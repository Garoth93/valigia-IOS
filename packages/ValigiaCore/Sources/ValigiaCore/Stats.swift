import Foundation

/// The statistics page.
public struct PackingStats: Equatable, Sendable {
    public struct Forgotten: Identifiable, Equatable, Sendable {
        public let name: String
        public let emoji: String?
        /// Rounds in which it was not found / left behind / missing at the end.
        public let count: Int
        public let notFound: Int
        public let leftBehind: Int
        public let lastTripName: String
        public var id: String { TextKey.normalized(name) }
    }

    public struct KindWeight: Identifiable, Equatable, Sendable {
        public let kind: LuggageKind
        public let averageGrams: Int
        public let maxGrams: Int
        public let samples: Int
        public var id: String { kind.rawValue }
    }

    public struct TemplateUse: Identifiable, Equatable, Sendable {
        public let name: String
        public let count: Int
        public var id: String { name }
    }

    public let tripsTotal: Int
    /// Trips already over.
    public let tripsDone: Int
    public let daysAway: Int
    public let roundsCompleted: Int
    public let itemsPacked: Int
    public let forgotten: [Forgotten]
    public let weightByKind: [KindWeight]
    public let templateUse: [TemplateUse]
    public let topDestinations: [String]

    public static let empty = PackingStats(tripsTotal: 0, tripsDone: 0, daysAway: 0, roundsCompleted: 0, itemsPacked: 0, forgotten: [], weightByKind: [], templateUse: [], topDestinations: [])

    public init(tripsTotal: Int, tripsDone: Int, daysAway: Int, roundsCompleted: Int, itemsPacked: Int, forgotten: [Forgotten], weightByKind: [KindWeight], templateUse: [TemplateUse], topDestinations: [String]) {
        self.tripsTotal = tripsTotal
        self.tripsDone = tripsDone
        self.daysAway = daysAway
        self.roundsCompleted = roundsCompleted
        self.itemsPacked = itemsPacked
        self.forgotten = forgotten
        self.weightByKind = weightByKind
        self.templateUse = templateUse
        self.topDestinations = topDestinations
    }

    public init(data: ValigiaData, now: Date, calendar: Calendar = .current) {
        let trips = data.trips
        var done = 0, days = 0, rounds = 0, packed = 0
        struct Acc { var name: String; var emoji: String?; var count = 0; var notFound = 0; var left = 0; var last: String; var lastDate: Date }
        var forgotten: [String: Acc] = [:]
        var weights: [LuggageKind: [Int]] = [:]
        var destinations: [String: (name: String, count: Int)] = [:]

        for trip in trips {
            let phase = trip.phase(now: now, calendar: calendar)
            if phase == .past { done += 1 }
            if phase == .past || phase == .ongoing, let d = trip.durationDays(calendar: calendar) {
                days += phase == .past ? d : max(0, ItalianFormat.daysBetween(trip.startDate ?? now, now, calendar: calendar) + 1)
            }
            let dest = trip.destination.trimmingCharacters(in: .whitespaces)
            if !dest.isEmpty {
                let key = TextKey.normalized(dest)
                destinations[key] = (destinations[key]?.name ?? dest, (destinations[key]?.count ?? 0) + 1)
            }
            for bag in trip.luggage where bag.totalWeightGrams > 0 {
                weights[bag.kind, default: []].append(bag.totalWeightGrams)
            }
            let tripDate = trip.startDate ?? trip.createdAt
            for round in trip.rounds {
                if round.isCompleted { rounds += 1 }
                let marks = round.markIndex
                for bag in trip.luggage {
                    for leaf in bag.items.leaves {
                        let status = marks[leaf.id]?.status
                        if status == .packed { packed += 1 }
                        let isForgotten = status == .notFound || status == .leftBehind || (round.isCompleted && status == nil)
                        guard isForgotten else { continue }
                        let key = TextKey.normalized(leaf.name)
                        guard !key.isEmpty else { continue }
                        var acc = forgotten[key] ?? Acc(name: leaf.name, emoji: leaf.emoji, last: trip.name, lastDate: tripDate)
                        acc.count += 1
                        if status == .notFound { acc.notFound += 1 }
                        if status == .leftBehind { acc.left += 1 }
                        if tripDate >= acc.lastDate {
                            acc.lastDate = tripDate
                            acc.last = trip.name
                            acc.name = leaf.name
                            acc.emoji = leaf.emoji ?? acc.emoji
                        }
                        forgotten[key] = acc
                    }
                }
            }
        }

        tripsTotal = trips.count
        tripsDone = done
        daysAway = days
        roundsCompleted = rounds
        itemsPacked = packed
        self.forgotten = forgotten.values
            .map { Forgotten(name: $0.name, emoji: $0.emoji, count: $0.count, notFound: $0.notFound, leftBehind: $0.left, lastTripName: $0.last) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        weightByKind = weights.map { kind, list in
            KindWeight(kind: kind, averageGrams: list.reduce(0, +) / max(1, list.count), maxGrams: list.max() ?? 0, samples: list.count)
        }.sorted { $0.samples != $1.samples ? $0.samples > $1.samples : $0.kind.rawValue < $1.kind.rawValue }
        templateUse = data.templates.filter { $0.usageCount > 0 }
            .map { TemplateUse(name: $0.name, count: $0.usageCount) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
        topDestinations = destinations.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }.map(\.name)
    }
}
