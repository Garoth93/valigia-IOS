import Foundation

/// Where an item sits in a tree: its parent (`nil` = top level) and index among siblings.
public struct TreeLocation: Equatable, Sendable {
    public var parentID: UUID?
    public var index: Int

    public init(parentID: UUID?, index: Int) {
        self.parentID = parentID
        self.index = index
    }
}

/// One visible line of a tree flattened for a list.
public struct TreeRow: Identifiable, Equatable, Sendable {
    public let item: Item
    public let depth: Int
    public let parentID: UUID?
    /// Shown expanded (children follow). Always true while a filter is active.
    public let isExpanded: Bool

    public var id: UUID { item.id }
    public var hasChildren: Bool { !item.children.isEmpty }
}

// MARK: - Item helpers

public extension Item {
    /// Same content with brand-new ids everywhere (templates → trips, duplicates).
    func copyWithNewIDs() -> Item {
        var copy = self
        copy.id = UUID()
        copy.attachments = attachments.map { $0.copyWithNewID() }
        copy.children = children.map { $0.copyWithNewIDs() }
        return copy
    }

    /// Self and all descendants, depth-first.
    var flattenedSelf: [Item] {
        [self] + children.flatMap { $0.flattenedSelf }
    }

    /// Ids of the "checkable" units below (or equal to) this item: the leaves.
    var leafIDs: [UUID] {
        isLeaf ? [id] : children.flatMap { $0.leafIDs }
    }

    var descendantCount: Int {
        children.reduce(0) { $0 + 1 + $1.descendantCount }
    }

    func contains(_ id: UUID) -> Bool {
        self.id == id || children.contains { $0.contains(id) }
    }
}

// MARK: - Tree operations

public extension Array where Element == Item {
    func find(_ id: UUID) -> Item? {
        for item in self {
            if item.id == id { return item }
            if let found = item.children.find(id) { return found }
        }
        return nil
    }

    /// Ancestors followed by the item itself.
    func path(to id: UUID) -> [Item]? {
        for item in self {
            if item.id == id { return [item] }
            if let sub = item.children.path(to: id) { return [item] + sub }
        }
        return nil
    }

    func location(of id: UUID, parentID: UUID? = nil) -> TreeLocation? {
        for (i, item) in enumerated() {
            if item.id == id { return TreeLocation(parentID: parentID, index: i) }
            if let loc = item.children.location(of: id, parentID: item.id) { return loc }
        }
        return nil
    }

    /// Every item, depth-first.
    var allItems: [Item] { flatMap { $0.flattenedSelf } }

    var allIDs: Set<UUID> { Set(allItems.map(\.id)) }

    var leafIDs: [UUID] { flatMap { $0.leafIDs } }

    var leaves: [Item] { allItems.filter(\.isLeaf) }

    var itemCount: Int { allItems.count }

    /// Applies `change` to the item with this id. Returns false if not found.
    @discardableResult
    mutating func update(_ id: UUID, _ change: (inout Item) -> Void) -> Bool {
        for i in indices {
            if self[i].id == id {
                change(&self[i])
                self[i].quantity = Swift.max(1, self[i].quantity)
                return true
            }
            if self[i].children.update(id, change) { return true }
        }
        return false
    }

    /// Removes and returns the item (with its whole branch).
    @discardableResult
    mutating func remove(_ id: UUID) -> Item? {
        if let i = firstIndex(where: { $0.id == id }) {
            return self.remove(at: i)
        }
        for i in indices {
            if let removed = self[i].children.remove(id) { return removed }
        }
        return nil
    }

    /// Inserts under `parentID` (`nil` = top level) at `index` (`nil` or too large = at the end).
    /// Returns false when the parent does not exist.
    @discardableResult
    mutating func insert(_ item: Item, into parentID: UUID?, at index: Int? = nil) -> Bool {
        guard let parentID else {
            let i = Swift.min(Swift.max(0, index ?? count), count)
            self.insert(item, at: i)
            return true
        }
        return update(parentID) { parent in
            let i = Swift.min(Swift.max(0, index ?? parent.children.count), parent.children.count)
            parent.children.insert(item, at: i)
            parent.isCollapsed = false
        }
    }

    /// Moves a branch under another parent. Refuses to move an item into itself
    /// or into one of its own descendants. `index` refers to the destination
    /// list after the item has been taken out.
    @discardableResult
    mutating func move(_ id: UUID, into parentID: UUID?, at index: Int? = nil) -> Bool {
        guard let item = find(id) else { return false }
        if let parentID {
            if item.contains(parentID) { return false }
            guard find(parentID) != nil else { return false }
        }
        var copy = self
        guard let removed = copy.remove(id) else { return false }
        guard copy.insert(removed, into: parentID, at: index) else { return false }
        self = copy
        return true
    }

    /// Moves the item just before `anchorID` (same parent as the anchor).
    /// `anchorID == nil` moves it to the end of the top level.
    /// This is what a drag in the flattened list means.
    @discardableResult
    mutating func move(_ id: UUID, before anchorID: UUID?) -> Bool {
        guard id != anchorID, let item = find(id) else { return false }
        guard let anchorID else { return move(id, into: nil, at: nil) }
        if item.contains(anchorID) { return false }
        var copy = self
        guard let removed = copy.remove(id), let loc = copy.location(of: anchorID) else { return false }
        guard copy.insert(removed, into: loc.parentID, at: loc.index) else { return false }
        self = copy
        return true
    }

    /// SwiftUI `onMove` on the flattened rows: `source` row goes before row `destination`
    /// (`destination == rows.count` = at the end).
    @discardableResult
    mutating func moveRow(from source: Int, to destination: Int, in rows: [TreeRow]) -> Bool {
        guard rows.indices.contains(source), destination != source, destination != source + 1 else { return false }
        let moving = rows[source].id
        var anchorIndex = destination
        // Skip the moving item's own descendants: dropping right below its own
        // children means "after them", i.e. before the next row outside the branch.
        let branch = rows[source].item
        while anchorIndex < rows.count, branch.contains(rows[anchorIndex].id) { anchorIndex += 1 }
        if anchorIndex >= rows.count {
            // Dropped at the very end: become the last sibling of the last row's top-level ancestor.
            return move(moving, before: nil)
        }
        return move(moving, before: rows[anchorIndex].id)
    }

    /// Duplicates a whole branch (new ids) right after the original. Returns the new id.
    @discardableResult
    mutating func duplicate(_ id: UUID, nameSuffix: String = "") -> UUID? {
        guard let item = find(id), let loc = location(of: id) else { return nil }
        var copy = item.copyWithNewIDs()
        if !nameSuffix.isEmpty { copy.name += nameSuffix }
        insert(copy, into: loc.parentID, at: loc.index + 1)
        return copy.id
    }

    /// Makes the item the last child of its previous sibling.
    @discardableResult
    mutating func indent(_ id: UUID) -> Bool {
        guard let loc = location(of: id), loc.index > 0 else { return false }
        let siblings = loc.parentID.flatMap { find($0)?.children } ?? self
        let newParent = siblings[loc.index - 1].id
        return move(id, into: newParent, at: nil)
    }

    /// Moves the item out of its parent, right after it.
    @discardableResult
    mutating func outdent(_ id: UUID) -> Bool {
        guard let loc = location(of: id), let parentID = loc.parentID,
              let parentLoc = location(of: parentID) else { return false }
        return move(id, into: parentLoc.parentID, at: parentLoc.index + 1)
    }

    /// Expands or collapses every branch.
    mutating func setCollapsed(_ collapsed: Bool) {
        for i in indices {
            if !self[i].children.isEmpty { self[i].isCollapsed = collapsed }
            self[i].children.setCollapsed(collapsed)
        }
    }

    /// Visible rows, honouring each item's `isCollapsed`.
    func rows(depth: Int = 0, parentID: UUID? = nil) -> [TreeRow] {
        var out: [TreeRow] = []
        for item in self {
            let expanded = !item.isCollapsed
            out.append(TreeRow(item: item, depth: depth, parentID: parentID, isExpanded: expanded))
            if expanded {
                out += item.children.rows(depth: depth + 1, parentID: item.id)
            }
        }
        return out
    }

    /// Every tag used in the tree, sorted.
    var allTags: [String] {
        [String](Set(allItems.flatMap(\.tags))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Possible destinations for moving `id`: every item that is not the item itself or below it.
    func moveTargets(excluding id: UUID) -> [TreeRow] {
        func walk(_ items: [Item], depth: Int, parent: UUID?) -> [TreeRow] {
            var out: [TreeRow] = []
            for item in items where item.id != id {
                out.append(TreeRow(item: item, depth: depth, parentID: parent, isExpanded: true))
                out += walk(item.children, depth: depth + 1, parent: item.id)
            }
            return out
        }
        return walk(self, depth: 0, parent: nil)
    }
}

// MARK: - Text normalisation

public enum TextKey {
    /// Case and accent insensitive key, trimmed.
    public static func normalized(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Clean tag: trimmed, no leading "#", lowercase, single spaces.
    public static func tag(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasPrefix("#") { t.removeFirst() }
        return t.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
