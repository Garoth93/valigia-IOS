import Foundation

// MARK: - Attachment

public enum AttachmentKind: String, Codable, CaseIterable, Sendable {
    case image, pdf, other

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AttachmentKind(rawValue: raw) ?? .other
    }

    /// Kind from a file extension ("jpg", "PDF"…).
    public static func from(fileExtension ext: String) -> AttachmentKind {
        switch ext.lowercased() {
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp": return .image
        case "pdf": return .pdf
        default: return .other
        }
    }

    public var symbol: String {
        switch self {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .other: return "doc"
        }
    }

    public var label: String {
        switch self {
        case .image: return "Foto"
        case .pdf: return "PDF"
        case .other: return "File"
        }
    }
}

/// A file attached to an item or a trip. The file itself lives in the app's
/// Attachments folder under `fileName`; copies of templates / trips share the
/// same file (files are never modified, only added or deleted).
public struct Attachment: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: AttachmentKind
    /// Stored file name (unique, e.g. "<uuid>.pdf").
    public var fileName: String
    /// Title shown in the app ("Andata Milano–Roma").
    public var title: String
    /// Name of the file when it was added ("biglietto.pdf").
    public var originalName: String
    /// Size in bytes (0 = unknown, e.g. migrated photos).
    public var byteSize: Int
    public var createdAt: Date

    public init(id: UUID = UUID(), kind: AttachmentKind, fileName: String, title: String, originalName: String = "", byteSize: Int = 0, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.title = title
        self.originalName = originalName
        self.byteSize = max(0, byteSize)
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey { case id, kind, fileName, title, originalName, byteSize, createdAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        let ext = (fileName as NSString).pathExtension
        kind = try c.decodeIfPresent(AttachmentKind.self, forKey: .kind) ?? AttachmentKind.from(fileExtension: ext)
        originalName = try c.decodeIfPresent(String.self, forKey: .originalName) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? (originalName.isEmpty ? kind.label : originalName)
        byteSize = max(0, try c.decodeIfPresent(Int.self, forKey: .byteSize) ?? 0)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
    }

    /// The single photo of version 1 data, as an attachment.
    public static func legacyPhoto(fileName: String) -> Attachment {
        Attachment(kind: .image, fileName: fileName, title: "Foto", originalName: fileName, byteSize: 0, createdAt: Date(timeIntervalSince1970: 0))
    }

    /// A new stored name keeping the extension of the original ("x.PDF" → "<uuid>.pdf").
    public static func storedName(forOriginal original: String, id: UUID = UUID()) -> String {
        let ext = (original as NSString).pathExtension.lowercased()
        return ext.isEmpty ? id.uuidString : "\(id.uuidString).\(ext)"
    }

    /// Default title from an original file name: without extension.
    public static func defaultTitle(forOriginal original: String, kind: AttachmentKind) -> String {
        let base = (original as NSString).deletingPathExtension.trimmingCharacters(in: .whitespaces)
        return base.isEmpty ? kind.label : base
    }

    /// Same file, new id (copies of items keep sharing the file).
    public func copyWithNewID() -> Attachment {
        var c = self
        c.id = UUID()
        return c
    }
}

public extension Array where Element == Attachment {
    @discardableResult
    mutating func rename(_ id: UUID, to title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = firstIndex(where: { $0.id == id }) else { return false }
        self[i].title = t
        return true
    }

    @discardableResult
    mutating func remove(_ id: UUID) -> Attachment? {
        guard let i = firstIndex(where: { $0.id == id }) else { return nil }
        return remove(at: i)
    }

    /// Moves an attachment to a new position (clamped).
    @discardableResult
    mutating func move(_ id: UUID, to index: Int) -> Bool {
        guard let i = firstIndex(where: { $0.id == id }) else { return false }
        let a = remove(at: i)
        insert(a, at: Swift.min(Swift.max(0, index), count))
        return true
    }

    /// Moves one step earlier (-1) or later (+1).
    @discardableResult
    mutating func shift(_ id: UUID, by offset: Int) -> Bool {
        guard let i = firstIndex(where: { $0.id == id }) else { return false }
        let target = i + offset
        guard indices.contains(target) else { return false }
        swapAt(i, target)
        return true
    }

    /// First image, used as the row thumbnail.
    var firstImage: Attachment? { first { $0.kind == .image } }

    var fileNames: Set<String> { Set(map(\.fileName)) }
}

// MARK: - Items and trips

public extension Item {
    /// Attachments of this item and of everything below it.
    var allAttachments: [Attachment] { flattenedSelf.flatMap(\.attachments) }
    var hasAttachments: Bool { !attachments.isEmpty }
}

/// One document of a trip, with where it comes from.
public struct TripDocument: Identifiable, Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case trip
        case item(itemID: UUID, luggageID: UUID)
    }

    public let attachment: Attachment
    public let source: Source
    /// "Zaino › Astuccio documenti › Passaporto" (empty for the trip's own documents).
    public let path: [String]

    public var id: String {
        switch source {
        case .trip: return "trip-\(attachment.id.uuidString)"
        case .item(let i, _): return "\(i.uuidString)-\(attachment.id.uuidString)"
        }
    }

    public var location: String { path.joined(separator: " › ") }
}

public extension Trip {
    /// The trip's own documents first, then every item attachment in list order, with its path.
    var documents: [TripDocument] {
        var out = attachments.map { TripDocument(attachment: $0, source: .trip, path: []) }
        for bag in luggage {
            func walk(_ items: [Item], path: [String]) {
                for item in items {
                    let here = path + [item.name]
                    for a in item.attachments {
                        out.append(TripDocument(attachment: a, source: .item(itemID: item.id, luggageID: bag.id), path: here))
                    }
                    walk(item.children, path: here)
                }
            }
            walk(bag.items, path: [bag.name])
        }
        return out
    }

    /// Every attachment of the trip (own + items).
    var allAttachments: [Attachment] {
        attachments + luggage.flatMap { $0.items.flatMap(\.allAttachments) }
    }

    /// Space used by the trip's files (each shared file counted once).
    var attachmentsByteSize: Int {
        var seen = Set<String>()
        var total = 0
        for a in allAttachments where seen.insert(a.fileName).inserted { total += a.byteSize }
        return total
    }
}

public extension ValigiaData {
    /// Every stored file referenced anywhere (trips, templates, "always" list).
    var referencedFiles: Set<String> {
        var names = Set<String>()
        for t in trips { names.formUnion(t.allAttachments.fileNames) }
        for t in templates { names.formUnion(t.luggage.items.flatMap(\.allAttachments).fileNames) }
        names.formUnion(alwaysItems.flatMap(\.allAttachments).fileNames)
        return names
    }

    func isReferenced(_ fileName: String) -> Bool { referencedFiles.contains(fileName) }

    /// Files that a change made unused: they can be deleted from disk.
    static func releasedFiles(before: ValigiaData, after: ValigiaData) -> Set<String> {
        before.referencedFiles.subtracting(after.referencedFiles)
    }

    /// Edits the attachments of a trip (its own documents).
    @discardableResult
    mutating func editTripAttachments(_ tripID: UUID, _ change: (inout [Attachment]) -> Void) -> Bool {
        editTrip(tripID) { change(&$0.attachments) }
    }

    /// Edits the attachments of an item in any list.
    @discardableResult
    mutating func editItemAttachments(at ref: ListRef, itemID: UUID, _ change: (inout [Attachment]) -> Void) -> Bool {
        editItems(at: ref) { $0.update(itemID) { change(&$0.attachments) } } ?? false
    }
}

/// "850 KB", "1,2 MB"
public enum ByteFormat {
    public static func string(_ bytes: Int) -> String {
        let b = Double(max(0, bytes))
        if b < 1000 { return "\(Int(b)) B" }
        if b < 1_000_000 { return "\(Int((b / 1000).rounded())) KB" }
        if b < 1_000_000_000 {
            let mb = b / 1_000_000
            let s = mb < 10 ? String(format: "%.1f", mb) : String(format: "%.0f", mb)
            return s.replacingOccurrences(of: ".", with: ",") + " MB"
        }
        return String(format: "%.1f", b / 1_000_000_000).replacingOccurrences(of: ".", with: ",") + " GB"
    }
}
