import Foundation

/// Counts over the checkable units (leaves) of a list in one round.
public struct ProgressCount: Equatable, Sendable {
    public var packed: Int
    public var notFound: Int
    public var leftBehind: Int
    public var total: Int

    public init(packed: Int = 0, notFound: Int = 0, leftBehind: Int = 0, total: Int = 0) {
        self.packed = packed
        self.notFound = notFound
        self.leftBehind = leftBehind
        self.total = total
    }

    /// 0…1 (an empty list counts as 0).
    public var fraction: Double { total == 0 ? 0 : Double(packed) / Double(total) }
    /// Not packed yet (includes not found / left behind).
    public var missing: Int { total - packed }
    /// Nothing marked at all.
    public var unmarked: Int { total - packed - notFound - leftBehind }
    public var isComplete: Bool { total > 0 && packed == total }
    public var percent: Int { Int((fraction * 100).rounded()) }

    public static func + (a: ProgressCount, b: ProgressCount) -> ProgressCount {
        ProgressCount(packed: a.packed + b.packed, notFound: a.notFound + b.notFound, leftBehind: a.leftBehind + b.leftBehind, total: a.total + b.total)
    }
}

/// Aggregated state of an item (a parent mixes its children).
public enum CheckState: Equatable, Sendable {
    case none
    case partial
    case done(ItemStatus)
}

public extension ProgressCount {
    init(leafIDs: [UUID], marks: [UUID: ItemMark]) {
        var c = ProgressCount(total: leafIDs.count)
        for id in leafIDs {
            switch marks[id]?.status {
            case .packed: c.packed += 1
            case .notFound: c.notFound += 1
            case .leftBehind: c.leftBehind += 1
            case nil: break
            }
        }
        self = c
    }
}

public extension Item {
    /// State of the item in a round: leaves use their mark, parents summarise their leaves.
    func checkState(marks: [UUID: ItemMark]) -> CheckState {
        if isLeaf {
            return marks[id].map { .done($0.status) } ?? .none
        }
        let c = ProgressCount(leafIDs: leafIDs, marks: marks)
        if c.total > 0, c.packed == c.total { return .done(.packed) }
        if c.total > 0, c.leftBehind == c.total { return .done(.leftBehind) }
        if c.total > 0, c.notFound == c.total { return .done(.notFound) }
        if c.unmarked == c.total { return .none }
        return .partial
    }
}

// MARK: - Trip round operations

public extension Trip {
    func round(_ id: UUID?) -> CheckRound? {
        guard let id else { return activeRound }
        return rounds.first { $0.id == id }
    }

    /// Progress of the whole trip, or of one bag, in a round.
    func progress(round roundID: UUID? = nil, luggageID: UUID? = nil) -> ProgressCount {
        guard let r = round(roundID) else { return ProgressCount() }
        let marks = r.markIndex
        let bags = luggageID.map { id in luggage.filter { $0.id == id } } ?? luggage
        return bags.reduce(ProgressCount()) { $0 + ProgressCount(leafIDs: $1.items.leafIDs, marks: marks) }
    }

    /// Sets (or clears, with `nil`) the status of an item in a round.
    /// On a parent it applies to every leaf below it.
    mutating func setStatus(_ status: ItemStatus?, itemID: UUID, roundID: UUID? = nil, place: String = "", at date: Date = Date()) {
        guard let item = find(itemID),
              let ri = rounds.firstIndex(where: { $0.id == (roundID ?? activeRound?.id) }) else { return }
        let leaves = Set(item.leafIDs)
        rounds[ri].marks.removeAll { leaves.contains($0.itemID) }
        if let status {
            for leaf in item.leafIDs {
                rounds[ri].marks.append(ItemMark(itemID: leaf, status: status, place: status == .leftBehind ? place : "", date: date))
            }
        }
    }

    /// Tap on the check: packed ↔ nothing. A partially packed parent becomes fully packed.
    mutating func togglePacked(itemID: UUID, roundID: UUID? = nil, at date: Date = Date()) {
        guard let item = find(itemID), let r = round(roundID) else { return }
        let state = item.checkState(marks: r.markIndex)
        if state == .done(.packed) {
            setStatus(nil, itemID: itemID, roundID: r.id, at: date)
        } else {
            setStatus(.packed, itemID: itemID, roundID: r.id, at: date)
        }
    }

    /// Clears every tick of a round (to pack again from zero).
    mutating func resetRound(_ roundID: UUID) {
        guard let ri = rounds.firstIndex(where: { $0.id == roundID }) else { return }
        rounds[ri].marks = []
        rounds[ri].completedAt = nil
    }

    /// Clears the ticks of one bag only.
    mutating func resetLuggage(_ luggageID: UUID, roundID: UUID) {
        guard let ri = rounds.firstIndex(where: { $0.id == roundID }),
              let bag = luggage.first(where: { $0.id == luggageID }) else { return }
        let ids = bag.items.allIDs
        rounds[ri].marks.removeAll { ids.contains($0.itemID) }
    }

    @discardableResult
    mutating func addRound(name: String, kind: RoundKind = .custom, direction: PackDirection = .pack, at date: Date = Date(), activate: Bool = true) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = CheckRound(name: trimmed.isEmpty ? "Giro \(rounds.count + 1)" : trimmed, kind: kind, direction: direction, createdAt: date)
        rounds.append(r)
        if activate { activeRoundID = r.id }
        return r.id
    }

    mutating func removeRound(_ roundID: UUID) {
        guard rounds.count > 1 else { return }
        rounds.removeAll { $0.id == roundID }
        if activeRoundID == roundID { activeRoundID = rounds.first?.id }
    }

    mutating func completeRound(_ roundID: UUID, at date: Date = Date()) {
        guard let ri = rounds.firstIndex(where: { $0.id == roundID }) else { return }
        rounds[ri].completedAt = date
    }

    mutating func reopenRound(_ roundID: UUID) {
        guard let ri = rounds.firstIndex(where: { $0.id == roundID }) else { return }
        rounds[ri].completedAt = nil
    }

    mutating func editRound(_ roundID: UUID, _ change: (inout CheckRound) -> Void) {
        guard let ri = rounds.firstIndex(where: { $0.id == roundID }) else { return }
        change(&rounds[ri])
    }

    /// What is missing at the end of a round.
    func summary(round roundID: UUID? = nil) -> RoundSummary {
        guard let r = round(roundID) else { return RoundSummary(roundName: "", direction: .pack, progress: ProgressCount(), missing: [], notFound: [], leftBehind: []) }
        let marks = r.markIndex
        var missing: [RoundEntry] = [], notFound: [RoundEntry] = [], left: [RoundEntry] = []
        for bag in luggage {
            func walk(_ items: [Item], path: [String]) {
                for item in items {
                    if item.isLeaf {
                        let entry = RoundEntry(itemID: item.id, name: item.name, emoji: item.emoji, quantity: item.quantity, luggageID: bag.id, luggageName: bag.name, path: path, place: marks[item.id]?.place ?? "")
                        switch marks[item.id]?.status {
                        case .packed: break
                        case .notFound: notFound.append(entry); missing.append(entry)
                        case .leftBehind: left.append(entry); missing.append(entry)
                        case nil: missing.append(entry)
                        }
                    } else {
                        walk(item.children, path: path + [item.name])
                    }
                }
            }
            walk(bag.items, path: [])
        }
        return RoundSummary(roundName: r.name, direction: r.direction, progress: progress(round: r.id), missing: missing, notFound: notFound, leftBehind: left)
    }
}

public struct RoundEntry: Identifiable, Equatable, Sendable {
    public let itemID: UUID
    public let name: String
    public let emoji: String?
    public let quantity: Int
    public let luggageID: UUID
    public let luggageName: String
    /// Names of the parents ("Astuccio elettronica").
    public let path: [String]
    public let place: String

    public var id: UUID { itemID }

    /// "Zaino › Astuccio elettronica"
    public var location: String { ([luggageName] + path).joined(separator: " › ") }
}

public struct RoundSummary: Equatable, Sendable {
    public let roundName: String
    public let direction: PackDirection
    public let progress: ProgressCount
    /// Everything not packed (unmarked, not found, left behind).
    public let missing: [RoundEntry]
    public let notFound: [RoundEntry]
    public let leftBehind: [RoundEntry]

    public var unmarked: [RoundEntry] {
        let marked = Set(notFound.map(\.id) + leftBehind.map(\.id))
        return missing.filter { !marked.contains($0.id) }
    }
}
