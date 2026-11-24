import Foundation

// MARK: - Item (one line of a packing list, with unlimited sub-items)

/// One thing to pack. Any item can contain other items (an electronics pouch
/// holding chargers and cables), with no depth limit.
public struct Item: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Always ≥ 1.
    public var quantity: Int
    public var note: String
    /// Emoji shown instead of the generic dot (optional).
    public var emoji: String?
    /// Weight of ONE unit, in grams (optional).
    public var weightGrams: Int?
    public var tags: [String]
    /// Photos, PDFs and other files (the first image is the row thumbnail).
    public var attachments: [Attachment]
    /// `false` = not owned yet: the item appears in the shopping list.
    public var owned: Bool
    /// UI state of the tree, saved so the list reopens as it was left.
    public var isCollapsed: Bool
    /// Link to an item of another app (gear catalog), not used yet.
    public var externalRef: ExternalRef?
    public var children: [Item]

    public init(
        id: UUID = UUID(),
        name: String,
        quantity: Int = 1,
        note: String = "",
        emoji: String? = nil,
        weightGrams: Int? = nil,
        tags: [String] = [],
        attachments: [Attachment] = [],
        owned: Bool = true,
        isCollapsed: Bool = false,
        externalRef: ExternalRef? = nil,
        children: [Item] = []
    ) {
        self.id = id
        self.name = name
        self.quantity = max(1, quantity)
        self.note = note
        self.emoji = emoji
        self.weightGrams = weightGrams
        self.tags = tags
        self.attachments = attachments
        self.owned = owned
        self.isCollapsed = isCollapsed
        self.externalRef = externalRef
        self.children = children
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, quantity, note, emoji, weightGrams, tags, attachments, owned, isCollapsed, externalRef, children
        /// Version 1 had a single photo: read only, migrated to the first attachment.
        case photoFile
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(quantity, forKey: .quantity)
        try c.encode(note, forKey: .note)
        try c.encodeIfPresent(emoji, forKey: .emoji)
        try c.encodeIfPresent(weightGrams, forKey: .weightGrams)
        try c.encode(tags, forKey: .tags)
        try c.encode(attachments, forKey: .attachments)
        try c.encode(owned, forKey: .owned)
        try c.encode(isCollapsed, forKey: .isCollapsed)
        try c.encodeIfPresent(externalRef, forKey: .externalRef)
        try c.encode(children, forKey: .children)
    }

    /// Tolerant decoding: missing fields take their default (older backups keep working).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        quantity = max(1, try c.decodeIfPresent(Int.self, forKey: .quantity) ?? 1)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji)
        weightGrams = try c.decodeIfPresent(Int.self, forKey: .weightGrams)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        var files = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        if let legacy = try c.decodeIfPresent(String.self, forKey: .photoFile), !legacy.isEmpty,
           !files.contains(where: { $0.fileName == legacy }) {
            files.insert(Attachment.legacyPhoto(fileName: legacy), at: 0)
        }
        attachments = files
        owned = try c.decodeIfPresent(Bool.self, forKey: .owned) ?? true
        isCollapsed = try c.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        externalRef = try c.decodeIfPresent(ExternalRef.self, forKey: .externalRef)
        children = try c.decodeIfPresent([Item].self, forKey: .children) ?? []
    }

    public var isLeaf: Bool { children.isEmpty }
}

// MARK: - Luggage (backpack, suitcase, trolley…)

public enum LuggageKind: String, Codable, CaseIterable, Sendable {
    case backpack, suitcase, trolley, bag, duffel, pouch, waistPack, other

    public var label: String {
        switch self {
        case .backpack: return "Zaino"
        case .suitcase: return "Valigia"
        case .trolley: return "Trolley"
        case .bag: return "Borsa"
        case .duffel: return "Borsone"
        case .pouch: return "Astuccio"
        case .waistPack: return "Marsupio"
        case .other: return "Altro"
        }
    }

    /// SF Symbol.
    public var symbol: String {
        switch self {
        case .backpack: return "backpack.fill"
        case .suitcase: return "suitcase.fill"
        case .trolley: return "suitcase.rolling.fill"
        case .bag: return "bag.fill"
        case .duffel: return "duffle.bag.fill"
        case .pouch: return "case.fill"
        case .waistPack: return "figure.run"
        case .other: return "shippingbox.fill"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LuggageKind(rawValue: raw) ?? .other
    }
}

/// Outer size of a bag: either width × height × depth in cm, or litres, or both.
public struct Dimensions: Codable, Equatable, Hashable, Sendable {
    public var widthCm: Double?
    public var heightCm: Double?
    public var depthCm: Double?
    public var litres: Double?

    public init(widthCm: Double? = nil, heightCm: Double? = nil, depthCm: Double? = nil, litres: Double? = nil) {
        self.widthCm = widthCm
        self.heightCm = heightCm
        self.depthCm = depthCm
        self.litres = litres
    }

    public var hasCentimetres: Bool { widthCm != nil && heightCm != nil && depthCm != nil }

    /// Declared litres, else computed from the centimetres.
    public var volumeLitres: Double? {
        if let litres { return litres }
        guard let w = widthCm, let h = heightCm, let d = depthCm else { return nil }
        return w * h * d / 1000
    }

    public var isEmpty: Bool { widthCm == nil && heightCm == nil && depthCm == nil && litres == nil }
}

/// A container: backpack, suitcase, trolley, bag… with its list of items.
public struct Luggage: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: LuggageKind
    public var colorHex: String
    public var dimensions: Dimensions
    public var maxWeightGrams: Int?
    /// Weight of the empty container (optional): counted in the total.
    public var emptyWeightGrams: Int?
    public var note: String
    public var items: [Item]

    public init(
        id: UUID = UUID(),
        name: String,
        kind: LuggageKind = .suitcase,
        colorHex: String = Palette.defaultAccent,
        dimensions: Dimensions = Dimensions(),
        maxWeightGrams: Int? = nil,
        emptyWeightGrams: Int? = nil,
        note: String = "",
        items: [Item] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.colorHex = colorHex
        self.dimensions = dimensions
        self.maxWeightGrams = maxWeightGrams
        self.emptyWeightGrams = emptyWeightGrams
        self.note = note
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, colorHex, dimensions, maxWeightGrams, emptyWeightGrams, note, items
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = try c.decodeIfPresent(LuggageKind.self, forKey: .kind) ?? .other
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? Palette.defaultAccent
        dimensions = try c.decodeIfPresent(Dimensions.self, forKey: .dimensions) ?? Dimensions()
        maxWeightGrams = try c.decodeIfPresent(Int.self, forKey: .maxWeightGrams)
        emptyWeightGrams = try c.decodeIfPresent(Int.self, forKey: .emptyWeightGrams)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
    }
}

// MARK: - Template

/// A reusable bag with its list ("Zaino scialpinismo", "Trolley weekend").
/// Trips copy it: later changes on either side never touch the other.
public struct PackTemplate: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var luggage: Luggage
    public var createdAt: Date
    public var updatedAt: Date
    /// Installed by the app as an example (still fully editable).
    public var isSample: Bool
    /// How many trips started from it.
    public var usageCount: Int

    public var name: String {
        get { luggage.name }
        set { luggage.name = newValue }
    }

    public init(id: UUID = UUID(), luggage: Luggage, createdAt: Date = Date(), updatedAt: Date? = nil, isSample: Bool = false, usageCount: Int = 0) {
        self.id = id
        self.luggage = luggage
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.isSample = isSample
        self.usageCount = usageCount
    }

    private enum CodingKeys: String, CodingKey {
        case id, luggage, createdAt, updatedAt, isSample, usageCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        luggage = try c.decodeIfPresent(Luggage.self, forKey: .luggage) ?? Luggage(name: "Template")
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        isSample = try c.decodeIfPresent(Bool.self, forKey: .isSample) ?? false
        usageCount = try c.decodeIfPresent(Int.self, forKey: .usageCount) ?? 0
    }
}

// MARK: - Check rounds

/// State of one item in one round.
public enum ItemStatus: String, Codable, CaseIterable, Sendable {
    /// In the bag (or, in an unpacking round, taken out).
    case packed
    /// Searched for and not found.
    case notFound
    /// Deliberately left somewhere (home, hotel…).
    case leftBehind

    public var label: String {
        switch self {
        case .packed: return "Preparata"
        case .notFound: return "Non trovata"
        case .leftBehind: return "Lasciata"
        }
    }

    public var symbol: String {
        switch self {
        case .packed: return "checkmark.circle.fill"
        case .notFound: return "questionmark.circle.fill"
        case .leftBehind: return "house.circle.fill"
        }
    }
}

public struct ItemMark: Codable, Equatable, Hashable, Sendable {
    public var itemID: UUID
    public var status: ItemStatus
    /// Where it was left ("a casa", "hotel Milano"), for `leftBehind`.
    public var place: String
    public var date: Date

    public init(itemID: UUID, status: ItemStatus, place: String = "", date: Date) {
        self.itemID = itemID
        self.status = status
        self.place = place
        self.date = date
    }
}

public enum RoundKind: String, Codable, CaseIterable, Sendable {
    case departure, returnTrip, custom

    public var defaultName: String {
        switch self {
        case .departure: return "Partenza"
        case .returnTrip: return "Ritorno"
        case .custom: return "Giro"
        }
    }

    public var symbol: String {
        switch self {
        case .departure: return "airplane.departure"
        case .returnTrip: return "airplane.arrival"
        case .custom: return "arrow.triangle.2.circlepath"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RoundKind(rawValue: raw) ?? .custom
    }
}

/// Whether ticking an item puts it IN the bag or takes it OUT.
public enum PackDirection: String, Codable, CaseIterable, Sendable {
    /// Ticking = it's in the bag. The bag fills up.
    case pack
    /// Ticking = taken out and back home. The bag empties.
    case unpack

    public var label: String {
        switch self {
        case .pack: return "Riempi"
        case .unpack: return "Svuota"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PackDirection(rawValue: raw) ?? .pack
    }
}

/// One full check of the trip's list: Departure, Return, hotel change…
/// Every round has its own independent ticks.
public struct CheckRound: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: RoundKind
    public var direction: PackDirection
    public var createdAt: Date
    public var completedAt: Date?
    public var marks: [ItemMark]

    public init(id: UUID = UUID(), name: String, kind: RoundKind = .custom, direction: PackDirection = .pack, createdAt: Date = Date(), completedAt: Date? = nil, marks: [ItemMark] = []) {
        self.id = id
        self.name = name
        self.kind = kind
        self.direction = direction
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.marks = marks
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, direction, createdAt, completedAt, marks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(RoundKind.self, forKey: .kind) ?? .custom
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? kind.defaultName
        direction = try c.decodeIfPresent(PackDirection.self, forKey: .direction) ?? .pack
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        marks = try c.decodeIfPresent([ItemMark].self, forKey: .marks) ?? []
    }

    public var isCompleted: Bool { completedAt != nil }

    /// Marks by item, for fast lookups.
    public var markIndex: [UUID: ItemMark] {
        var d: [UUID: ItemMark] = [:]
        for m in marks { d[m.itemID] = m }
        return d
    }

    public func mark(for itemID: UUID) -> ItemMark? {
        marks.first { $0.itemID == itemID }
    }

    public static func departure(at date: Date) -> CheckRound {
        CheckRound(name: RoundKind.departure.defaultName, kind: .departure, direction: .pack, createdAt: date)
    }

    /// The return round starts from the same list; ticking means "it's back home".
    public static func returnTrip(at date: Date) -> CheckRound {
        CheckRound(name: RoundKind.returnTrip.defaultName, kind: .returnTrip, direction: .unpack, createdAt: date)
    }
}

// MARK: - Trip

public struct Trip: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var destination: String
    public var startDate: Date?
    public var endDate: Date?
    public var note: String
    public var luggage: [Luggage]
    public var rounds: [CheckRound]
    public var activeRoundID: UUID?
    public var createdAt: Date
    public var isArchived: Bool
    /// Templates this trip was created from (statistics only).
    public var templateIDs: [UUID]
    /// Documents of the trip itself (tickets, bookings, insurance…).
    public var attachments: [Attachment]

    public init(
        id: UUID = UUID(),
        name: String,
        destination: String = "",
        startDate: Date? = nil,
        endDate: Date? = nil,
        note: String = "",
        luggage: [Luggage] = [],
        rounds: [CheckRound]? = nil,
        activeRoundID: UUID? = nil,
        createdAt: Date = Date(),
        isArchived: Bool = false,
        templateIDs: [UUID] = [],
        attachments: [Attachment] = []
    ) {
        self.id = id
        self.name = name
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.note = note
        self.luggage = luggage
        let r = rounds ?? [.departure(at: createdAt), .returnTrip(at: createdAt)]
        self.rounds = r
        self.activeRoundID = activeRoundID ?? r.first?.id
        self.createdAt = createdAt
        self.isArchived = isArchived
        self.templateIDs = templateIDs
        self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, destination, startDate, endDate, note, luggage, rounds, activeRoundID, createdAt, isArchived, templateIDs, attachments
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        destination = try c.decodeIfPresent(String.self, forKey: .destination) ?? ""
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(Date.self, forKey: .endDate)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        luggage = try c.decodeIfPresent([Luggage].self, forKey: .luggage) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        rounds = try c.decodeIfPresent([CheckRound].self, forKey: .rounds) ?? [.departure(at: createdAt)]
        activeRoundID = try c.decodeIfPresent(UUID.self, forKey: .activeRoundID) ?? rounds.first?.id
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        templateIDs = try c.decodeIfPresent([UUID].self, forKey: .templateIDs) ?? []
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
    }

    /// Round currently being checked (falls back to the first).
    public var activeRound: CheckRound? {
        rounds.first { $0.id == activeRoundID } ?? rounds.first
    }
}

// MARK: - Settings and root data

public enum Appearance: String, Codable, CaseIterable, Sendable {
    case system, light, dark

    public var label: String {
        switch self {
        case .system: return "Automatico"
        case .light: return "Chiaro"
        case .dark: return "Scuro"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Appearance(rawValue: raw) ?? .system
    }
}

/// How the bag is drawn: simple icon, 3D suitcase (RealityKit, generated in code)
/// and, in a later phase, the illustrated SwiftUI suitcase.
public enum LuggageVisualStyle: String, Codable, CaseIterable, Sendable {
    case simple, illustrated, threeD

    public var label: String {
        switch self {
        case .simple: return "Semplice"
        case .illustrated: return "Illustrata"
        case .threeD: return "3D"
        }
    }

    public var isAvailable: Bool { self != .illustrated }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LuggageVisualStyle(rawValue: raw) ?? .simple
    }
}

public struct ValigiaSettings: Codable, Equatable, Sendable {
    public var appearance: Appearance
    /// Seed of the Material scheme.
    public var seedHex: String
    /// Inside a bag, the theme follows the bag's color.
    public var tintWithLuggageColor: Bool
    public var reminderEnabled: Bool
    public var reminderHour: Int
    public var reminderMinute: Int
    public var haptics: Bool
    public var visualStyle: LuggageVisualStyle
    /// Face ID (or passcode) before opening or showing attachments.
    public var lockDocuments: Bool
    /// Automatic backup in iCloud Drive (shared "Backup" container, folder "Valigia").
    public var cloudBackup: Bool
    /// Put attachments (possibly identity documents) in the iCloud backup too.
    public var cloudIncludeAttachments: Bool

    public init(
        appearance: Appearance = .system,
        seedHex: String = Palette.defaultAccent,
        tintWithLuggageColor: Bool = true,
        reminderEnabled: Bool = true,
        reminderHour: Int = 20,
        reminderMinute: Int = 0,
        haptics: Bool = true,
        visualStyle: LuggageVisualStyle = .simple,
        lockDocuments: Bool = false,
        cloudBackup: Bool = true,
        cloudIncludeAttachments: Bool = false
    ) {
        self.appearance = appearance
        self.seedHex = seedHex
        self.tintWithLuggageColor = tintWithLuggageColor
        self.reminderEnabled = reminderEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.haptics = haptics
        self.visualStyle = visualStyle
        self.lockDocuments = lockDocuments
        self.cloudBackup = cloudBackup
        self.cloudIncludeAttachments = cloudIncludeAttachments
    }

    private enum CodingKeys: String, CodingKey {
        case appearance, seedHex, tintWithLuggageColor, reminderEnabled, reminderHour, reminderMinute, haptics, visualStyle, lockDocuments, cloudBackup, cloudIncludeAttachments
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ValigiaSettings()
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? d.appearance
        seedHex = try c.decodeIfPresent(String.self, forKey: .seedHex) ?? d.seedHex
        tintWithLuggageColor = try c.decodeIfPresent(Bool.self, forKey: .tintWithLuggageColor) ?? d.tintWithLuggageColor
        reminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? d.reminderEnabled
        reminderHour = try c.decodeIfPresent(Int.self, forKey: .reminderHour) ?? d.reminderHour
        reminderMinute = try c.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? d.reminderMinute
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? d.haptics
        visualStyle = try c.decodeIfPresent(LuggageVisualStyle.self, forKey: .visualStyle) ?? d.visualStyle
        lockDocuments = try c.decodeIfPresent(Bool.self, forKey: .lockDocuments) ?? d.lockDocuments
        cloudBackup = try c.decodeIfPresent(Bool.self, forKey: .cloudBackup) ?? d.cloudBackup
        cloudIncludeAttachments = try c.decodeIfPresent(Bool.self, forKey: .cloudIncludeAttachments) ?? d.cloudIncludeAttachments
    }
}

/// Everything the app saves.
public struct ValigiaData: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var trips: [Trip]
    public var templates: [PackTemplate]
    /// "Always" items: copied into every new trip.
    public var alwaysItems: [Item]
    public var settings: ValigiaSettings
    /// Example templates were installed once (never reinstalled automatically).
    public var samplesInstalled: Bool

    public init(version: Int = ValigiaData.currentVersion, trips: [Trip] = [], templates: [PackTemplate] = [], alwaysItems: [Item] = [], settings: ValigiaSettings = ValigiaSettings(), samplesInstalled: Bool = false) {
        self.version = version
        self.trips = trips
        self.templates = templates
        self.alwaysItems = alwaysItems
        self.settings = settings
        self.samplesInstalled = samplesInstalled
    }

    private enum CodingKeys: String, CodingKey {
        case version, trips, templates, alwaysItems, settings, samplesInstalled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? ValigiaData.currentVersion
        trips = try c.decodeIfPresent([Trip].self, forKey: .trips) ?? []
        templates = try c.decodeIfPresent([PackTemplate].self, forKey: .templates) ?? []
        alwaysItems = try c.decodeIfPresent([Item].self, forKey: .alwaysItems) ?? []
        settings = try c.decodeIfPresent(ValigiaSettings.self, forKey: .settings) ?? ValigiaSettings()
        samplesInstalled = try c.decodeIfPresent(Bool.self, forKey: .samplesInstalled) ?? false
    }

    public func trip(_ id: UUID) -> Trip? { trips.first { $0.id == id } }
    public func template(_ id: UUID) -> PackTemplate? { templates.first { $0.id == id } }
}
