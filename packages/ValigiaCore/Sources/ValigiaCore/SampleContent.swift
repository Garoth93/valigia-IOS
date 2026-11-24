import Foundation

/// Example templates installed at first launch. Generic content (no personal
/// data), every value is editable or deletable by the user.
public enum SampleContent {
    private static func i(_ name: String, _ emoji: String? = nil, g: Int? = nil, q: Int = 1, tags: [String] = [], note: String = "", _ children: [Item] = []) -> Item {
        Item(name: name, quantity: q, note: note, emoji: emoji, weightGrams: g, tags: tags, children: children)
    }

    static func electronicsPouch() -> Item {
        i("Astuccio elettronica", "🔌", g: 80, [
            i("Caricabatterie USB-C", "🔌", g: 120),
            i("Cavo USB-C", g: 30, q: 2),
            i("Cavo Lightning", g: 25),
            i("Power bank", "🔋", g: 210),
            i("Auricolari", "🎧", g: 60)
        ])
    }

    static func toiletry() -> Item {
        i("Beauty case", "🧴", g: 150, [
            i("Spazzolino", "🪥", g: 20),
            i("Dentifricio", g: 60),
            i("Deodorante", g: 80),
            i("Shampoo da viaggio", g: 100, tags: ["volo"], note: "max 100 ml nel bagaglio a mano"),
            i("Crema solare", "☀️", g: 120, tags: ["estate"])
        ])
    }

    public static func alwaysItems() -> [Item] {
        [
            i("Documento d'identità", "🪪", g: 10),
            i("Portafoglio", "👛", g: 120),
            i("Chiavi di casa", "🔑", g: 60),
            i("Telefono e caricabatterie", "📱", g: 250)
        ]
    }

    public static func templates(now: Date) -> [PackTemplate] {
        let skiTouring = Luggage(
            name: "Zaino scialpinismo", kind: .backpack, colorHex: "#e8604c",
            dimensions: Dimensions(litres: 30), maxWeightGrams: 8000, emptyWeightGrams: 1100,
            items: [
                i("Sicurezza", "⛑️", tags: ["inverno"], [
                    i("ARTVA", "📡", g: 210),
                    i("Pala", g: 650),
                    i("Sonda", g: 280)
                ]),
                i("Pelli di foca", g: 450, tags: ["inverno"]),
                i("Rampant", g: 300, tags: ["inverno"]),
                i("Abbigliamento", "🧥", [
                    i("Guscio", g: 400),
                    i("Piumino leggero", g: 300),
                    i("Guanti di ricambio", "🧤", g: 120),
                    i("Berretto", g: 60),
                    i("Buff", g: 40)
                ]),
                i("Maschera", "🥽", g: 180),
                i("Thermos", "🫖", g: 450),
                i("Barrette", "🍫", g: 40, q: 3),
                i("Kit primo soccorso", "🩹", g: 200),
                i("Frontale", "🔦", g: 90)
            ])

        let weekendTrolley = Luggage(
            name: "Trolley weekend", kind: .trolley, colorHex: "#1e6fd9",
            dimensions: Dimensions(widthCm: 55, heightCm: 40, depthCm: 20), maxWeightGrams: 10000, emptyWeightGrams: 2300,
            items: [
                i("Vestiti", "👕", [
                    i("Magliette", g: 150, q: 3),
                    i("Pantaloni", g: 450, q: 1),
                    i("Intimo", g: 60, q: 3),
                    i("Calze", "🧦", g: 50, q: 3),
                    i("Felpa", g: 500),
                    i("Pigiama", g: 300)
                ]),
                i("Scarpe comode", "👟", g: 700),
                toiletry(),
                electronicsPouch(),
                i("Ombrello pieghevole", "☂️", g: 250)
            ])

        let runningBag = Luggage(
            name: "Borsa corsa / gara", kind: .bag, colorHex: "#2e7d4f",
            dimensions: Dimensions(litres: 25), maxWeightGrams: 5000,
            items: [
                i("Scarpe da corsa", "👟", g: 520),
                i("Pettorale e spille", "🏷️", g: 15, tags: ["gara"]),
                i("Chip", g: 10, tags: ["gara"]),
                i("Maglia tecnica", "🎽", g: 120),
                i("Pantaloncini", "🩳", g: 100),
                i("Calze tecniche", "🧦", g: 40),
                i("Orologio GPS", "⌚", g: 50),
                i("Gel", g: 40, q: 2),
                i("Cambio post gara", "👕", [
                    i("Maglietta asciutta", g: 150),
                    i("Felpa", g: 450),
                    i("Ciabatte", "🩴", g: 250)
                ]),
                i("Asciugamano", g: 300)
            ])

        let bikeBackpack = Luggage(
            name: "Zaino bici giornata", kind: .backpack, colorHex: "#c58b2a",
            dimensions: Dimensions(litres: 12), maxWeightGrams: 4000, emptyWeightGrams: 600,
            items: [
                i("Kit riparazione", "🔧", [
                    i("Camera d'aria", g: 110),
                    i("Leve", g: 20),
                    i("Pompa / CO₂", g: 120),
                    i("Multitool", g: 150)
                ]),
                i("Borraccia", "🚰", g: 650, q: 2),
                i("Mantellina antivento", g: 120),
                i("Barrette", "🍫", g: 40, q: 2),
                i("Luci", "💡", g: 80)
            ])

        let weekSuitcase = Luggage(
            name: "Valigia settimana", kind: .suitcase, colorHex: "#7e57c2",
            dimensions: Dimensions(widthCm: 70, heightCm: 46, depthCm: 28), maxWeightGrams: 23000, emptyWeightGrams: 4000,
            items: [
                i("Vestiti", "👕", [
                    i("Magliette", g: 150, q: 7),
                    i("Pantaloni", g: 450, q: 2),
                    i("Pantaloncini", g: 200, q: 2, tags: ["estate"]),
                    i("Intimo", g: 60, q: 7),
                    i("Calze", "🧦", g: 50, q: 7),
                    i("Costume", "🩱", g: 120, tags: ["estate"]),
                    i("Maglione", g: 600, tags: ["inverno"])
                ]),
                i("Scarpe", "👟", [
                    i("Scarpe comode", g: 700),
                    i("Sandali", "🩴", g: 400, tags: ["estate"])
                ]),
                toiletry(),
                electronicsPouch(),
                i("Medicinali", "💊", g: 100),
                i("Adattatore prese", "🔌", g: 90, tags: ["estero"])
            ])

        return [skiTouring, weekendTrolley, runningBag, bikeBackpack, weekSuitcase].map {
            PackTemplate(luggage: $0, createdAt: now, isSample: true)
        }
    }
}
