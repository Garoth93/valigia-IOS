import Foundation

/// Address of an editable list of items: a bag of a trip, a template, or the "always" list.
public enum ListRef: Hashable, Codable, Sendable {
    case trip(tripID: UUID, luggageID: UUID)
    case template(UUID)
    case always

    public var tripID: UUID? {
        if case .trip(let t, _) = self { return t }
        return nil
    }
}

/// What the user fills in to create a trip.
public struct TripDraft: Equatable, Sendable {
    public var name: String
    public var destination: String
    public var startDate: Date?
    public var endDate: Date?
    public var note: String
    /// One bag per template, in this order.
    public var templateIDs: [UUID]
    /// Copy the "always" items into the first bag.
    public var includeAlwaysItems: Bool

    public init(name: String, destination: String = "", startDate: Date? = nil, endDate: Date? = nil, note: String = "", templateIDs: [UUID] = [], includeAlwaysItems: Bool = true) {
        self.name = name
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.note = note
        self.templateIDs = templateIDs
        self.includeAlwaysItems = includeAlwaysItems
    }
}

public extension Luggage {
    /// Independent copy: new bag id and new item ids.
    func copyWithNewIDs() -> Luggage {
        var copy = self
        copy.id = UUID()
        copy.items = items.map { $0.copyWithNewIDs() }
        return copy
    }
}

public extension ValigiaData {
    // MARK: Lists by reference

    func luggage(at ref: ListRef) -> Luggage? {
        switch ref {
        case .trip(let tripID, let luggageID):
            return trip(tripID)?.luggage.first { $0.id == luggageID }
        case .template(let id):
            return template(id)?.luggage
        case .always:
            return nil
        }
    }

    func items(at ref: ListRef) -> [Item]? {
        if case .always = ref { return alwaysItems }
        return luggage(at: ref)?.items
    }

    /// Edits the items of a list in place. Returns nil when the list does not exist.
    @discardableResult
    mutating func editItems<R>(at ref: ListRef, now: Date = Date(), _ change: (inout [Item]) -> R) -> R? {
        switch ref {
        case .always:
            return change(&alwaysItems)
        case .template(let id):
            guard let ti = templates.firstIndex(where: { $0.id == id }) else { return nil }
            let r = change(&templates[ti].luggage.items)
            templates[ti].updatedAt = now
            return r
        case .trip(let tripID, let luggageID):
            guard let ti = trips.firstIndex(where: { $0.id == tripID }),
                  let li = trips[ti].luggage.firstIndex(where: { $0.id == luggageID }) else { return nil }
            let r = change(&trips[ti].luggage[li].items)
            trips[ti].pruneMarks()
            return r
        }
    }

    /// Edits the bag (name, kind, limits…) of a trip or template.
    @discardableResult
    mutating func editLuggage(at ref: ListRef, now: Date = Date(), _ change: (inout Luggage) -> Void) -> Bool {
        switch ref {
        case .always:
            return false
        case .template(let id):
            guard let ti = templates.firstIndex(where: { $0.id == id }) else { return false }
            change(&templates[ti].luggage)
            templates[ti].updatedAt = now
            return true
        case .trip(let tripID, let luggageID):
            guard let ti = trips.firstIndex(where: { $0.id == tripID }),
                  let li = trips[ti].luggage.firstIndex(where: { $0.id == luggageID }) else { return false }
            change(&trips[ti].luggage[li])
            trips[ti].pruneMarks()
            return true
        }
    }

    @discardableResult
    mutating func editTrip(_ id: UUID, _ change: (inout Trip) -> Void) -> Bool {
        guard let i = trips.firstIndex(where: { $0.id == id }) else { return false }
        change(&trips[i])
        return true
    }

    // MARK: Trips

    /// Creates a trip: one independent bag per template, plus the "always" items.
    @discardableResult
    mutating func createTrip(_ draft: TripDraft, now: Date = Date()) -> UUID {
        var bags: [Luggage] = []
        for tid in draft.templateIDs {
            guard let ti = templates.firstIndex(where: { $0.id == tid }) else { continue }
            bags.append(templates[ti].luggage.copyWithNewIDs())
            templates[ti].usageCount += 1
        }
        var trip = Trip(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Nuovo viaggio" : draft.name,
            destination: draft.destination,
            startDate: draft.startDate,
            endDate: draft.endDate,
            note: draft.note,
            luggage: bags,
            createdAt: now,
            templateIDs: draft.templateIDs
        )
        if draft.includeAlwaysItems, !alwaysItems.isEmpty {
            if trip.luggage.isEmpty {
                trip.luggage.append(Luggage(name: "Valigia", kind: .suitcase))
            }
            trip.addAlwaysItems(alwaysItems)
        }
        trips.append(trip)
        return trip.id
    }

    /// Adds a bag to a trip: a copy of a template, or an empty one.
    @discardableResult
    mutating func addLuggage(toTrip tripID: UUID, fromTemplate templateID: UUID?, blank: Luggage? = nil) -> UUID? {
        guard let ti = trips.firstIndex(where: { $0.id == tripID }) else { return nil }
        let bag: Luggage
        if let templateID, let k = templates.firstIndex(where: { $0.id == templateID }) {
            bag = templates[k].luggage.copyWithNewIDs()
            templates[k].usageCount += 1
            trips[ti].templateIDs.append(templateID)
        } else {
            bag = blank ?? Luggage(name: "Nuovo contenitore")
        }
        trips[ti].luggage.append(bag)
        return bag.id
    }

    @discardableResult
    mutating func removeLuggage(_ luggageID: UUID, fromTrip tripID: UUID) -> Luggage? {
        guard let ti = trips.firstIndex(where: { $0.id == tripID }),
              let li = trips[ti].luggage.firstIndex(where: { $0.id == luggageID }) else { return nil }
        let removed = trips[ti].luggage.remove(at: li)
        trips[ti].pruneMarks()
        return removed
    }

    /// Same trip again (new dates to be set): same bags and items, fresh rounds.
    @discardableResult
    mutating func duplicateTrip(_ id: UUID, now: Date = Date()) -> UUID? {
        guard let t = trip(id) else { return nil }
        let copy = Trip(
            name: t.name + " (copia)",
            destination: t.destination,
            note: t.note,
            luggage: t.luggage.map { $0.copyWithNewIDs() },
            createdAt: now,
            templateIDs: t.templateIDs
        )
        trips.append(copy)
        return copy.id
    }

    @discardableResult
    mutating func deleteTrip(_ id: UUID) -> Trip? {
        guard let i = trips.firstIndex(where: { $0.id == id }) else { return nil }
        return trips.remove(at: i)
    }

    // MARK: Templates

    /// "Save as template": independent copy of a trip's bag.
    @discardableResult
    mutating func saveAsTemplate(tripID: UUID, luggageID: UUID, name: String? = nil, now: Date = Date()) -> UUID? {
        guard let bag = luggage(at: .trip(tripID: tripID, luggageID: luggageID)) else { return nil }
        var copy = bag.copyWithNewIDs()
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { copy.name = name }
        let t = PackTemplate(luggage: copy, createdAt: now)
        templates.append(t)
        return t.id
    }

    @discardableResult
    mutating func addTemplate(_ luggage: Luggage, now: Date = Date()) -> UUID {
        let t = PackTemplate(luggage: luggage, createdAt: now)
        templates.append(t)
        return t.id
    }

    @discardableResult
    mutating func duplicateTemplate(_ id: UUID, now: Date = Date()) -> UUID? {
        guard let t = template(id) else { return nil }
        var bag = t.luggage.copyWithNewIDs()
        bag.name += " (copia)"
        let copy = PackTemplate(luggage: bag, createdAt: now)
        templates.append(copy)
        return copy.id
    }

    @discardableResult
    mutating func deleteTemplate(_ id: UUID) -> PackTemplate? {
        guard let i = templates.firstIndex(where: { $0.id == id }) else { return nil }
        return templates.remove(at: i)
    }

    /// Installs the example templates and "always" items once.
    mutating func installSamplesIfNeeded(now: Date = Date()) {
        guard !samplesInstalled else { return }
        samplesInstalled = true
        templates += SampleContent.templates(now: now)
        if alwaysItems.isEmpty { alwaysItems = SampleContent.alwaysItems() }
    }

    // MARK: Moving between bags

    /// Moves a branch from one list to another (e.g. from the backpack to the suitcase of the same trip).
    @discardableResult
    mutating func moveItem(_ itemID: UUID, from source: ListRef, to destination: ListRef, parentID: UUID?, now: Date = Date()) -> Bool {
        if source == destination {
            return editItems(at: source, now: now) { $0.move(itemID, into: parentID, at: nil) } ?? false
        }
        guard let item = items(at: source)?.find(itemID), items(at: destination) != nil else { return false }
        if let parentID, items(at: destination)?.find(parentID) == nil { return false }
        // Moving inside the same trip keeps the ticks of the round (same ids).
        let sameTrip = source.tripID != nil && source.tripID == destination.tripID
        let moved = sameTrip ? item : item.copyWithNewIDs()
        editItems(at: destination, now: now) { $0.insert(moved, into: parentID, at: nil) }
        editItems(at: source, now: now) { $0.remove(itemID) }
        return true
    }

    /// Copies a branch to another list (new ids), leaving the original.
    @discardableResult
    mutating func copyItem(_ itemID: UUID, from source: ListRef, to destination: ListRef, now: Date = Date()) -> UUID? {
        guard let item = items(at: source)?.find(itemID) else { return nil }
        let copy = item.copyWithNewIDs()
        return editItems(at: destination, now: now) { items -> UUID in
            items.append(copy)
            return copy.id
        }
    }
}

public extension Trip {
    /// Appends copies of the "always" items to the first bag, skipping names
    /// already present anywhere in the trip.
    mutating func addAlwaysItems(_ always: [Item]) {
        guard !luggage.isEmpty else { return }
        let existing = Set(luggage.flatMap { $0.items.allItems }.map { TextKey.normalized($0.name) })
        for item in always where !existing.contains(TextKey.normalized(item.name)) {
            luggage[0].items.append(item.copyWithNewIDs())
        }
    }

    /// Every item of every bag.
    var allItems: [Item] { luggage.flatMap { $0.items.allItems } }

    /// The bag that holds an item.
    func luggageID(containing itemID: UUID) -> UUID? {
        luggage.first { $0.items.find(itemID) != nil }?.id
    }

    func find(_ itemID: UUID) -> Item? {
        for bag in luggage { if let i = bag.items.find(itemID) { return i } }
        return nil
    }

    /// Drops marks of items that no longer exist.
    mutating func pruneMarks() {
        let ids = Set(luggage.flatMap { $0.items.allIDs })
        for r in rounds.indices {
            rounds[r].marks.removeAll { !ids.contains($0.itemID) }
        }
    }
}
