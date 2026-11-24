import Foundation

/// JSON backup: all data plus (optionally) the item photos as base64.
public struct BackupFile: Codable, Equatable, Sendable {
    public static let formatID = "valigia-backup"

    public var format: String
    public var version: Int
    public var exportedAt: Date
    public var data: ValigiaData
    /// Photo file name → base64 JPEG.
    public var photos: [String: String]

    public init(data: ValigiaData, photos: [String: Data] = [:], exportedAt: Date = Date()) {
        format = Self.formatID
        version = ValigiaData.currentVersion
        self.exportedAt = exportedAt
        self.data = data
        self.photos = photos.mapValues { $0.base64EncodedString() }
    }

    private enum CodingKeys: String, CodingKey { case format, version, exportedAt, data, photos }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? Self.formatID
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date(timeIntervalSince1970: 0)
        data = try c.decode(ValigiaData.self, forKey: .data)
        photos = try c.decodeIfPresent([String: String].self, forKey: .photos) ?? [:]
    }

    public var photoData: [String: Data] {
        photos.compactMapValues { Data(base64Encoded: $0) }
    }

    /// Photo files referenced by items (only these go into a backup).
    public static func referencedPhotos(in data: ValigiaData) -> Set<String> {
        var names = Set<String>()
        func add(_ items: [Item]) { for i in items.allItems { if let p = i.photoFile { names.insert(p) } } }
        for t in data.trips { for b in t.luggage { add(b.items) } }
        for t in data.templates { add(t.luggage.items) }
        add(data.alwaysItems)
        return names
    }

    public func encoded() throws -> Data {
        try JSONFileStore<BackupFile>.encoder(compact: false).encode(self)
    }

    public enum ReadError: Error, LocalizedError, Equatable {
        case notJSON
        case notValigia
        case newerVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .notJSON: return "Il file non è un JSON leggibile."
            case .notValigia: return "Il file non è un backup di Valigia."
            case .newerVersion(let v): return "Il backup è di una versione più recente dell'app (v\(v)). Aggiorna Valigia e riprova."
            }
        }
    }

    /// Reads a backup; also accepts a bare data file (`valigia-data.json`).
    public static func decode(_ raw: Data) throws -> BackupFile {
        guard (try? JSONSerialization.jsonObject(with: raw)) != nil else { throw ReadError.notJSON }
        let decoder = JSONFileStore<BackupFile>.decoder
        if let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] {
            if obj["data"] != nil {
                if let f = obj["format"] as? String, f != formatID { throw ReadError.notValigia }
                if let v = obj["version"] as? Int, v > ValigiaData.currentVersion { throw ReadError.newerVersion(v) }
                guard let b = try? decoder.decode(BackupFile.self, from: raw) else { throw ReadError.notValigia }
                return b
            }
            if obj["trips"] != nil || obj["templates"] != nil {
                guard let d = try? decoder.decode(ValigiaData.self, from: raw) else { throw ReadError.notValigia }
                return BackupFile(data: d)
            }
        }
        throw ReadError.notValigia
    }
}

// MARK: - Integration with other apps (gear catalogs) — protocol only

/// Link from an item to an entry of another app (e.g. a gear / equipment app).
public struct ExternalRef: Codable, Hashable, Sendable {
    /// Identifier of the other app ("gear-catalog").
    public var source: String
    /// Id of the entry in that app.
    public var externalID: String

    public init(source: String, externalID: String) {
        self.source = source
        self.externalID = externalID
    }
}

/// A piece of equipment offered by another app.
public struct GearItem: Equatable, Hashable, Sendable, Identifiable {
    public var ref: ExternalRef
    public var name: String
    public var weightGrams: Int?
    public var category: String
    public var tags: [String]
    public var emoji: String?
    public var note: String

    public var id: ExternalRef { ref }

    public init(ref: ExternalRef, name: String, weightGrams: Int? = nil, category: String = "", tags: [String] = [], emoji: String? = nil, note: String = "") {
        self.ref = ref
        self.name = name
        self.weightGrams = weightGrams
        self.category = category
        self.tags = tags
        self.emoji = emoji
        self.note = note
    }

    /// The packing-list item made from this gear (linked through `externalRef`).
    public func makeItem() -> Item {
        Item(name: name, note: note, emoji: emoji, weightGrams: weightGrams, tags: tags, externalRef: ref)
    }
}

/// A source of gear, implemented in the future by an adapter to the user's
/// equipment apps (shared App Group file, URL scheme, App Intents…).
/// Nothing implements it yet: Valigia works fully without it.
public protocol GearCatalogProvider: Sendable {
    var sourceID: String { get }
    var displayName: String { get }
    /// True when the other app is installed / its data is reachable.
    func isAvailable() async -> Bool
    func fetchGear() async throws -> [GearItem]
    /// Latest data for already-linked items (weights may have changed).
    func refresh(_ refs: [ExternalRef]) async throws -> [GearItem]
}

public extension Array where Element == Item {
    /// Updates name/weight of items linked to refreshed gear. Returns how many changed.
    @discardableResult
    mutating func applyGearUpdates(_ gear: [GearItem]) -> Int {
        let byRef = Dictionary(gear.map { ($0.ref, $0) }, uniquingKeysWith: { a, _ in a })
        var changed = 0
        for item in allItems {
            guard let ref = item.externalRef, let g = byRef[ref] else { continue }
            if item.name != g.name || item.weightGrams != g.weightGrams {
                update(item.id) {
                    $0.name = g.name
                    $0.weightGrams = g.weightGrams
                }
                changed += 1
            }
        }
        return changed
    }
}
