import Foundation

/// Italian dates and plurals, computed by hand so they are identical on Linux and iOS.
public enum ItalianFormat {
    static let monthsShort = ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"]
    static let monthsLong = ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre"]
    static let weekdays = ["domenica", "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato"]

    /// "12 dic 2026"
    public static func day(_ date: Date, calendar: Calendar = .current, year: Bool = true) -> String {
        let c = calendar.dateComponents([.day, .month, .year], from: date)
        var s = "\(c.day ?? 1) \(monthsShort[(c.month ?? 1) - 1])"
        if year { s += " \(c.year ?? 2000)" }
        return s
    }

    /// "sabato 12 dicembre"
    public static func longDay(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.day, .month, .weekday], from: date)
        return "\(weekdays[(c.weekday ?? 1) - 1]) \(c.day ?? 1) \(monthsLong[(c.month ?? 1) - 1])"
    }

    /// "12–14 dic 2026", "30 dic 2026 – 2 gen 2027", "12 dic 2026"
    public static func range(_ start: Date?, _ end: Date?, calendar: Calendar = .current) -> String? {
        guard let start else { return end.map { day($0, calendar: calendar) } }
        guard let end, !calendar.isDate(start, inSameDayAs: end) else { return day(start, calendar: calendar) }
        let a = calendar.dateComponents([.day, .month, .year], from: start)
        let b = calendar.dateComponents([.day, .month, .year], from: end)
        if a.year == b.year, a.month == b.month {
            return "\(a.day ?? 1)–\(day(end, calendar: calendar))"
        }
        if a.year == b.year {
            return "\(day(start, calendar: calendar, year: false)) – \(day(end, calendar: calendar))"
        }
        return "\(day(start, calendar: calendar)) – \(day(end, calendar: calendar))"
    }

    /// Whole days from `now`'s day to `date`'s day (negative = past).
    public static func daysBetween(_ now: Date, _ date: Date, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: now), b = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// "oggi", "domani", "tra 5 giorni", "ieri", "3 giorni fa"
    public static func relative(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let d = daysBetween(now, date, calendar: calendar)
        switch d {
        case 0: return "oggi"
        case 1: return "domani"
        case 2: return "dopodomani"
        case -1: return "ieri"
        case let x where x > 0: return "tra \(x) giorni"
        default: return "\(-d) giorni fa"
        }
    }

    /// "1 voce", "3 voci"
    public static func items(_ n: Int) -> String { n == 1 ? "1 voce" : "\(n) voci" }

    public static func plural(_ n: Int, _ one: String, _ many: String) -> String {
        n == 1 ? "1 \(one)" : "\(n) \(many)"
    }

    /// "A, B e C"
    public static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " e " + names.last!
        }
    }
}

/// Where a trip is in time.
public enum TripPhase: Equatable, Sendable {
    case noDates
    case upcoming(days: Int)
    case ongoing
    case past
}

public extension Trip {
    func phase(now: Date, calendar: Calendar = .current) -> TripPhase {
        guard let start = startDate else {
            if let end = endDate, ItalianFormat.daysBetween(now, end, calendar: calendar) < 0 { return .past }
            return .noDates
        }
        let toStart = ItalianFormat.daysBetween(now, start, calendar: calendar)
        if toStart > 0 { return .upcoming(days: toStart) }
        let end = endDate ?? start
        if ItalianFormat.daysBetween(now, end, calendar: calendar) >= 0 { return .ongoing }
        return .past
    }

    /// Days from start to end, inclusive.
    func durationDays(calendar: Calendar = .current) -> Int? {
        guard let s = startDate else { return nil }
        return ItalianFormat.daysBetween(s, endDate ?? s, calendar: calendar) + 1
    }

    var dateLabel: String? { ItalianFormat.range(startDate, endDate) }
}

public extension ValigiaData {
    /// The trip the widget and the reminder care about: ongoing first, then the
    /// closest upcoming one, then the most recent without dates.
    func nextTrip(now: Date, calendar: Calendar = .current) -> Trip? {
        let active = trips.filter { !$0.isArchived }
        let ongoing = active.filter { $0.phase(now: now, calendar: calendar) == .ongoing }
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
        if let t = ongoing.first { return t }
        let upcoming = active.filter {
            if case .upcoming = $0.phase(now: now, calendar: calendar) { return true }
            return false
        }.sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        if let t = upcoming.first { return t }
        return active.filter { $0.phase(now: now, calendar: calendar) == .noDates }
            .max { $0.createdAt < $1.createdAt }
    }

    /// Trips grouped for the main list.
    func tripSections(now: Date, calendar: Calendar = .current) -> (current: [Trip], past: [Trip], archived: [Trip]) {
        var current: [Trip] = [], past: [Trip] = [], archived: [Trip] = []
        for t in trips {
            if t.isArchived { archived.append(t); continue }
            if t.phase(now: now, calendar: calendar) == .past { past.append(t) } else { current.append(t) }
        }
        current.sort { ($0.startDate ?? .distantFuture, $0.createdAt) < ($1.startDate ?? .distantFuture, $1.createdAt) }
        past.sort { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
        archived.sort { ($0.startDate ?? $0.createdAt) > ($1.startDate ?? $1.createdAt) }
        return (current, past, archived)
    }
}
