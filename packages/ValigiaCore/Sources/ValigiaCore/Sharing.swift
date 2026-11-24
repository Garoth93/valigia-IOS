import Foundation

/// Plain-text list to share (Messages, WhatsApp, Notes…).
public enum TextExport {
    public struct Options: Equatable, Sendable {
        /// Show ticks of the round (☑/☐); without it, a plain list with "•".
        public var withChecks: Bool
        public var onlyMissing: Bool
        public var withWeights: Bool
        public var withNotes: Bool

        public init(withChecks: Bool = true, onlyMissing: Bool = false, withWeights: Bool = true, withNotes: Bool = true) {
            self.withChecks = withChecks
            self.onlyMissing = onlyMissing
            self.withWeights = withWeights
            self.withNotes = withNotes
        }
    }

    public static func trip(_ trip: Trip, roundID: UUID? = nil, options: Options = Options(), calendar: Calendar = .current) -> String {
        let round = trip.round(roundID)
        var lines: [String] = ["🧳 \(trip.name)"]
        var info: [String] = []
        if !trip.destination.isEmpty { info.append("📍 \(trip.destination)") }
        if let d = ItalianFormat.range(trip.startDate, trip.endDate, calendar: calendar) { info.append("🗓 \(d)") }
        if !info.isEmpty { lines.append(info.joined(separator: " · ")) }
        if options.withChecks, let round {
            let p = trip.progress(round: round.id)
            lines.append("Giro: \(round.name) — \(p.packed)/\(p.total)")
        }
        for bag in trip.luggage {
            lines.append("")
            lines.append(contentsOf: luggageLines(bag, round: options.withChecks ? round : nil, options: options))
        }
        return lines.joined(separator: "\n")
    }

    public static func luggage(_ bag: Luggage, round: CheckRound? = nil, options: Options = Options()) -> String {
        luggageLines(bag, round: round, options: options).joined(separator: "\n")
    }

    static func luggageLines(_ bag: Luggage, round: CheckRound?, options: Options) -> [String] {
        var header = "▸ \(bag.name)"
        if options.withWeights, bag.totalWeightGrams > 0 || bag.maxWeightGrams != nil {
            header += " (\(WeightFormat.ratio(bag.totalWeightGrams, max: bag.maxWeightGrams)))"
        }
        var lines = [header]
        let marks = round?.markIndex ?? [:]
        let filter = ItemFilter(onlyMissing: options.onlyMissing && round != nil)
        for row in filter.rows(for: bag.items.expandedCopy(), marks: marks) {
            let item = row.item
            let indent = String(repeating: "   ", count: row.depth)
            var symbol = "•"
            if round != nil {
                switch item.checkState(marks: marks) {
                case .done(.packed): symbol = "☑"
                case .done(.notFound): symbol = "❓"
                case .done(.leftBehind): symbol = "🏠"
                case .partial: symbol = "◐"
                case .none: symbol = "☐"
                }
            }
            var l = "\(indent)\(symbol) " + (item.emoji.map { $0 + " " } ?? "") + item.name
            if item.quantity > 1 { l += " ×\(item.quantity)" }
            if options.withWeights, item.hasWeight { l += " · \(WeightFormat.string(item.totalWeightGrams))" }
            if !item.owned { l += " 🛒" }
            if options.withNotes, !item.note.isEmpty { l += " — \(item.note)" }
            if let place = marks[item.id]?.place, !place.isEmpty { l += " (\(place))" }
            lines.append(l)
        }
        if bag.items.isEmpty { lines.append("   (vuoto)") }
        return lines
    }
}

extension Array where Element == Item {
    /// Same tree with every branch expanded (for exports).
    func expandedCopy() -> [Item] {
        var copy = self
        copy.setCollapsed(false)
        return copy
    }
}

// MARK: - Reminder the evening before departure

public struct ReminderPlan: Equatable, Sendable {
    public let tripID: UUID
    public let fireDate: Date
    public let title: String
    public let body: String
}

public enum ReminderPlanner {
    /// One notification per upcoming trip, the evening before departure at the chosen time.
    public static func plans(for data: ValigiaData, now: Date, calendar: Calendar = .current) -> [ReminderPlan] {
        let s = data.settings
        guard s.reminderEnabled else { return [] }
        var out: [ReminderPlan] = []
        for trip in data.trips where !trip.isArchived {
            guard let start = trip.startDate,
                  let dayBefore = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: start)),
                  let fire = calendar.date(bySettingHour: s.reminderHour, minute: s.reminderMinute, second: 0, of: dayBefore),
                  fire > now else { continue }
            out.append(plan(trip: trip, fireDate: fire))
        }
        return out.sorted { $0.fireDate < $1.fireDate }
    }

    public static func plan(trip: Trip, fireDate: Date) -> ReminderPlan {
        // The departure round: the first packing round.
        let round = trip.rounds.first { $0.kind == .departure } ?? trip.rounds.first { $0.direction == .pack } ?? trip.activeRound
        let summary = trip.summary(round: round?.id)
        let title = "Domani si parte: \(trip.name)"
        let body: String
        if summary.progress.total == 0 {
            body = "La lista è ancora vuota: aggiungi le cose da portare."
        } else if summary.missing.isEmpty {
            body = "Tutto pronto ✔ \(ItalianFormat.items(summary.progress.total)) preparate."
        } else {
            let names = summary.missing.prefix(3).map(\.name)
            let others = summary.missing.count - names.count
            var list = names.joined(separator: ", ")
            if others > 0 { list += " e altre \(others)" }
            let verb = summary.missing.count == 1 ? "Manca" : "Mancano"
            body = "\(verb) \(ItalianFormat.items(summary.missing.count)) da preparare: \(list)."
        }
        return ReminderPlan(tripID: trip.id, fireDate: fireDate, title: title, body: body)
    }
}

// MARK: - Widget snapshot

/// Small file written by the app and read by the widgets (App Group).
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct Bag: Codable, Equatable, Sendable, Identifiable {
        public let id: UUID
        public let name: String
        public let symbol: String
        public let colorHex: String
        public let packed: Int
        public let total: Int
        public let weightGrams: Int
        public let maxWeightGrams: Int?

        public var fraction: Double { total == 0 ? 0 : Double(packed) / Double(total) }
    }

    public struct TripInfo: Codable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let destination: String
        public let startDate: Date?
        public let endDate: Date?
        public let roundName: String
        public let direction: PackDirection
        public let packed: Int
        public let total: Int
        public let missingNames: [String]
        public let bags: [Bag]

        public var fraction: Double { total == 0 ? 0 : Double(packed) / Double(total) }
    }

    public var generatedAt: Date
    public var seedHex: String
    public var trip: TripInfo?

    public init(generatedAt: Date, seedHex: String, trip: TripInfo?) {
        self.generatedAt = generatedAt
        self.seedHex = seedHex
        self.trip = trip
    }

    public init(data: ValigiaData, now: Date, calendar: Calendar = .current) {
        generatedAt = now
        seedHex = data.settings.seedHex
        guard let t = data.nextTrip(now: now, calendar: calendar), let round = t.activeRound else {
            trip = nil
            return
        }
        let fill = TripFillState(trip: t, roundID: round.id)
        let summary = t.summary(round: round.id)
        trip = TripInfo(
            id: t.id, name: t.name, destination: t.destination, startDate: t.startDate, endDate: t.endDate,
            roundName: round.name, direction: round.direction,
            packed: fill.progress.packed, total: fill.progress.total,
            missingNames: Array(summary.missing.prefix(4).map(\.name)),
            bags: fill.luggage.map {
                Bag(id: $0.luggageID, name: $0.name, symbol: $0.kind.symbol, colorHex: $0.colorHex, packed: $0.progress.packed, total: $0.progress.total, weightGrams: $0.weightGrams, maxWeightGrams: $0.maxWeightGrams)
            }
        )
    }

    public static let placeholder = WidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 0),
        seedHex: Palette.defaultAccent,
        trip: TripInfo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Weekend al mare", destination: "Mare",
            startDate: nil, endDate: nil, roundName: "Partenza", direction: .pack,
            packed: 14, total: 20, missingNames: ["Costume", "Crema solare"],
            bags: [
                Bag(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Trolley", symbol: LuggageKind.trolley.symbol, colorHex: "#1e6fd9", packed: 10, total: 14, weightGrams: 7400, maxWeightGrams: 10000),
                Bag(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Zaino", symbol: LuggageKind.backpack.symbol, colorHex: "#e8604c", packed: 4, total: 6, weightGrams: 2100, maxWeightGrams: nil)
            ]
        )
    )
}
