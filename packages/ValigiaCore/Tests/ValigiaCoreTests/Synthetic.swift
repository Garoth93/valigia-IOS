import Foundation
@testable import ValigiaCore

/// Synthetic data built in code only (no real data in the repo).
enum Synthetic {
    static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// Pouch (charger 100 g, cable 30 g ×2, power bank 200 g) + shirt 150 g ×3 + jacket 500 g.
    static func items() -> [Item] {
        [
            Item(name: "Astuccio TEST", emoji: "🔌", weightGrams: 50, tags: ["volo"], children: [
                Item(name: "Caricatore TEST", weightGrams: 100),
                Item(name: "Cavo TEST", quantity: 2, weightGrams: 30),
                Item(name: "Batteria TEST", weightGrams: 200, owned: false)
            ]),
            Item(name: "Maglia TEST", quantity: 3, weightGrams: 150, tags: ["estate"]),
            Item(name: "Giacca TEST", note: "quella blu", weightGrams: 500, tags: ["inverno"])
        ]
    }

    static func luggage(_ name: String = "Zaino TEST", max: Int? = 2000) -> Luggage {
        Luggage(name: name, kind: .backpack, maxWeightGrams: max, emptyWeightGrams: 300, items: items())
    }

    static func data() -> ValigiaData {
        var d = ValigiaData()
        d.templates = [PackTemplate(luggage: luggage("Template A"), createdAt: date(2026, 1, 1)),
                       PackTemplate(luggage: Luggage(name: "Template B", kind: .trolley, items: [Item(name: "Scarpe TEST", weightGrams: 700)]), createdAt: date(2026, 1, 1))]
        d.alwaysItems = [Item(name: "Documento TEST"), Item(name: "maglia test")]
        return d
    }

    static func names(_ rows: [TreeRow]) -> [String] { rows.map { String(repeating: "-", count: $0.depth) + $0.item.name } }
}
