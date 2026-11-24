import Foundation

/// Search and filters of a list. When any filter is active the tree is shown
/// fully expanded, keeping the parents of every match.
public struct ItemFilter: Equatable, Sendable {
    public var query: String
    /// All of these tags must apply (tags are inherited from parents).
    public var tags: Set<String>
    /// Only items not yet packed in the round.
    public var onlyMissing: Bool
    /// Only items not owned yet.
    public var onlyToBuy: Bool
    /// Only items with at least one attachment.
    public var onlyWithAttachments: Bool

    public init(query: String = "", tags: Set<String> = [], onlyMissing: Bool = false, onlyToBuy: Bool = false, onlyWithAttachments: Bool = false) {
        self.query = query
        self.tags = tags
        self.onlyMissing = onlyMissing
        self.onlyToBuy = onlyToBuy
        self.onlyWithAttachments = onlyWithAttachments
    }

    public var isActive: Bool {
        !TextKey.normalized(query).isEmpty || !tags.isEmpty || onlyMissing || onlyToBuy || onlyWithAttachments
    }

    /// Rows to show. `marks` is used by `onlyMissing` (empty for templates).
    public func rows(for items: [Item], marks: [UUID: ItemMark] = [:]) -> [TreeRow] {
        guard isActive else { return items.rows() }
        let q = TextKey.normalized(query)
        let wanted = Set(tags.map(TextKey.tag))

        func selfMatches(_ item: Item, inherited: Set<String>) -> Bool {
            if !q.isEmpty {
                let hay = TextKey.normalized(item.name + " " + item.note + " " + item.tags.joined(separator: " ") + " " + item.attachments.map(\.title).joined(separator: " "))
                if !hay.contains(q) { return false }
            }
            if !wanted.isEmpty, !wanted.isSubset(of: inherited) { return false }
            if onlyToBuy, item.owned { return false }
            if onlyWithAttachments, item.attachments.isEmpty { return false }
            if onlyMissing {
                if item.isLeaf {
                    if marks[item.id]?.status == .packed { return false }
                } else if item.checkState(marks: marks) == .done(.packed) {
                    return false
                }
            }
            return true
        }

        /// Returns the rows of the branch if it (or something below) matches.
        func walk(_ items: [Item], depth: Int, parentID: UUID?, inherited: Set<String>) -> [TreeRow] {
            var out: [TreeRow] = []
            for item in items {
                let tagsHere = inherited.union(item.tags.map(TextKey.tag))
                let below = walk(item.children, depth: depth + 1, parentID: item.id, inherited: tagsHere)
                let matches = selfMatches(item, inherited: tagsHere)
                // A matching leaf, or a parent with matching content. A parent that matches
                // the text alone shows all its content (searching "astuccio" shows its cables).
                if matches && item.isLeaf {
                    out.append(TreeRow(item: item, depth: depth, parentID: parentID, isExpanded: true))
                } else if !below.isEmpty {
                    out.append(TreeRow(item: item, depth: depth, parentID: parentID, isExpanded: true))
                    out += below
                } else if matches && !onlyMissing && !q.isEmpty {
                    out.append(TreeRow(item: item, depth: depth, parentID: parentID, isExpanded: true))
                    out += item.children.rows(depth: depth + 1, parentID: item.id).map {
                        TreeRow(item: $0.item, depth: $0.depth, parentID: $0.parentID, isExpanded: true)
                    }
                } else if matches && !item.isLeaf && q.isEmpty && !onlyMissing {
                    out.append(TreeRow(item: item, depth: depth, parentID: parentID, isExpanded: true))
                }
            }
            return out
        }
        return walk(items, depth: 0, parentID: nil, inherited: [])
    }
}

// MARK: - Shopping list

/// An item not owned yet, wherever it is.
public struct ShoppingEntry: Identifiable, Equatable, Sendable {
    public let itemID: UUID
    public let name: String
    public let emoji: String?
    public let quantity: Int
    public let note: String
    public let ref: ListRef
    /// "Weekend Roma › Zaino", "Template: Zaino scialpinismo", "Sempre presenti"
    public let sourceName: String
    /// Start date of the trip, for sorting (nil for templates).
    public let dueDate: Date?

    public var id: UUID { itemID }
}

public enum ShoppingList {
    /// Items marked as not owned, from active trips, templates and the "always" list.
    public static func entries(in data: ValigiaData) -> [ShoppingEntry] {
        var out: [ShoppingEntry] = []
        func collect(_ items: [Item], ref: ListRef, source: String, due: Date?) {
            for item in items.allItems where !item.owned {
                out.append(ShoppingEntry(itemID: item.id, name: item.name, emoji: item.emoji, quantity: item.quantity, note: item.note, ref: ref, sourceName: source, dueDate: due))
            }
        }
        for trip in data.trips where !trip.isArchived {
            for bag in trip.luggage {
                collect(bag.items, ref: .trip(tripID: trip.id, luggageID: bag.id), source: "\(trip.name) › \(bag.name)", due: trip.startDate)
            }
        }
        for t in data.templates {
            collect(t.luggage.items, ref: .template(t.id), source: "Template: \(t.name)", due: nil)
        }
        collect(data.alwaysItems, ref: .always, source: "Sempre presenti", due: nil)
        return out.sorted { a, b in
            switch (a.dueDate, b.dueDate) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
    }

    /// Marks items as bought (owned).
    public static func markBought(_ entries: [ShoppingEntry], in data: inout ValigiaData) {
        for e in entries {
            data.editItems(at: e.ref) { $0.update(e.itemID) { $0.owned = true } }
        }
    }

    /// Plain-text list to share.
    public static func text(_ entries: [ShoppingEntry]) -> String {
        guard !entries.isEmpty else { return "Da comprare: niente 🎉" }
        var lines = ["🛒 Da comprare"]
        for e in entries {
            var l = "☐ " + (e.emoji.map { $0 + " " } ?? "") + e.name
            if e.quantity > 1 { l += " ×\(e.quantity)" }
            if !e.note.isEmpty { l += " — \(e.note)" }
            lines.append(l)
        }
        return lines.joined(separator: "\n")
    }
}
