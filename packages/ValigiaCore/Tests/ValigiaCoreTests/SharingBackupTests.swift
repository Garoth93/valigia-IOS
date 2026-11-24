import XCTest
@testable import ValigiaCore

final class SharingTests: XCTestCase {
    func testTextExport() {
        var trip = Trip(name: "Weekend TEST", destination: "Lago TEST", startDate: Synthetic.date(2026, 12, 12), endDate: Synthetic.date(2026, 12, 14), luggage: [Synthetic.luggage("Zaino")])
        let items = trip.luggage[0].items
        trip.togglePacked(itemID: items[0].children[0].id)
        trip.setStatus(.leftBehind, itemID: items[2].id, place: "casa")
        let text = TextExport.trip(trip, calendar: Synthetic.calendar)
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "🧳 Weekend TEST")
        XCTAssertEqual(lines[1], "📍 Lago TEST · 🗓 12–14 dic 2026")
        XCTAssertEqual(lines[2], "Giro: Partenza — 1/5")
        XCTAssertEqual(lines[4], "▸ Zaino (1,66 kg / 2 kg)")
        XCTAssertEqual(lines[5], "◐ 🔌 Astuccio TEST · 410 g")
        XCTAssertEqual(lines[6], "   ☑ Caricatore TEST · 100 g")
        XCTAssertEqual(lines[7], "   ☐ Cavo TEST ×2 · 60 g")
        XCTAssertEqual(lines[8], "   ☐ Batteria TEST · 200 g 🛒")
        XCTAssertEqual(lines.last, "🏠 Giacca TEST · 500 g — quella blu (casa)")

        let missing = TextExport.trip(trip, options: .init(onlyMissing: true, withWeights: false), calendar: Synthetic.calendar)
        XCTAssertFalse(missing.contains("Caricatore"))
        XCTAssertTrue(missing.contains("☐ Cavo TEST ×2"))
        let plain = TextExport.luggage(trip.luggage[0], options: .init(withChecks: false, withWeights: false, withNotes: false))
        XCTAssertTrue(plain.contains("• Giacca TEST\n") || plain.hasSuffix("• Giacca TEST"))
    }

    func testReminder() {
        let cal = Synthetic.calendar
        var data = ValigiaData()
        var trip = Trip(name: "Mare TEST", startDate: Synthetic.date(2026, 7, 10, 8), luggage: [Synthetic.luggage()])
        trip.setStatus(.packed, itemID: trip.luggage[0].items[0].id)
        data.trips = [trip, Trip(name: "Passato", startDate: Synthetic.date(2026, 1, 1))]
        let plans = ReminderPlanner.plans(for: data, now: Synthetic.date(2026, 7, 1), calendar: cal)
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].fireDate, Synthetic.date(2026, 7, 9, 20, 0))
        XCTAssertEqual(plans[0].title, "Domani si parte: Mare TEST")
        XCTAssertEqual(plans[0].body, "Mancano 2 voci da preparare: Maglia TEST, Giacca TEST.")
        // Past the reminder time: nothing.
        XCTAssertTrue(ReminderPlanner.plans(for: data, now: Synthetic.date(2026, 7, 9, 21), calendar: cal).isEmpty)
        data.settings.reminderEnabled = false
        XCTAssertTrue(ReminderPlanner.plans(for: data, now: Synthetic.date(2026, 7, 1), calendar: cal).isEmpty)
        // All done.
        trip.setStatus(.packed, itemID: trip.luggage[0].items[1].id)
        trip.setStatus(.packed, itemID: trip.luggage[0].items[2].id)
        XCTAssertTrue(ReminderPlanner.plan(trip: trip, fireDate: Date()).body.hasPrefix("Tutto pronto"))
        XCTAssertTrue(ReminderPlanner.plan(trip: Trip(name: "x"), fireDate: Date()).body.contains("vuota"))
    }

    func testWidgetSnapshot() {
        let cal = Synthetic.calendar
        var data = ValigiaData()
        var trip = Trip(name: "Prossimo", startDate: Synthetic.date(2026, 7, 10), luggage: [Synthetic.luggage(), Luggage(name: "B", items: [Item(name: "x")])])
        trip.setStatus(.packed, itemID: trip.luggage[1].items[0].id)
        data.trips = [trip]
        let snap = WidgetSnapshot(data: data, now: Synthetic.date(2026, 7, 1), calendar: cal)
        XCTAssertEqual(snap.trip?.name, "Prossimo")
        XCTAssertEqual(snap.trip?.packed, 1)
        XCTAssertEqual(snap.trip?.total, 6)
        XCTAssertEqual(snap.trip?.bags.count, 2)
        XCTAssertEqual(snap.trip?.bags[1].fraction, 1)
        XCTAssertEqual(snap.trip?.missingNames.count, 4)
        XCTAssertNil(WidgetSnapshot(data: data, now: Synthetic.date(2026, 8, 1), calendar: cal).trip)
        // Round-trips through JSON.
        let encoded = try! JSONFileStore<WidgetSnapshot>.encoder().encode(snap)
        XCTAssertEqual(try! JSONFileStore<WidgetSnapshot>.decoder.decode(WidgetSnapshot.self, from: encoded), snap)
    }
}

final class BackupTests: XCTestCase {
    func testRoundTripWithPhotos() throws {
        var data = Synthetic.data()
        data.createTrip(TripDraft(name: "V", templateIDs: [data.templates[0].id]), now: Synthetic.date(2026, 2, 1))
        data.editItems(at: .always) { $0.update($0[0].id) { $0.photoFile = "p1.jpg" } }
        XCTAssertEqual(BackupFile.referencedPhotos(in: data), ["p1.jpg"])
        let backup = BackupFile(data: data, photos: ["p1.jpg": Data([1, 2, 3])], exportedAt: Synthetic.date(2026, 1, 1))
        let raw = try backup.encoded()
        let read = try BackupFile.decode(raw)
        XCTAssertEqual(read.data, data)
        XCTAssertEqual(read.photoData["p1.jpg"], Data([1, 2, 3]))
    }

    func testAcceptsBareDataAndRejectsOthers() throws {
        let data = Synthetic.data()
        let raw = try JSONFileStore<ValigiaData>.encoder().encode(data)
        XCTAssertEqual(try BackupFile.decode(raw).data, data)
        XCTAssertThrowsError(try BackupFile.decode(Data("ciao".utf8))) { XCTAssertEqual($0 as? BackupFile.ReadError, .notJSON) }
        XCTAssertThrowsError(try BackupFile.decode(Data("{\"a\":1}".utf8))) { XCTAssertEqual($0 as? BackupFile.ReadError, .notValigia) }
        XCTAssertThrowsError(try BackupFile.decode(Data("{\"format\":\"valigia-backup\",\"version\":99,\"data\":{}}".utf8))) {
            XCTAssertEqual($0 as? BackupFile.ReadError, .newerVersion(99))
        }
    }

    func testTolerantDecodingOfOldFiles() throws {
        let json = """
        {"trips":[{"name":"Vecchio","luggage":[{"name":"Zaino","kind":"jetpack","items":[{"name":"Cosa","quantity":0}]}],"rounds":[{"kind":"strano"}]}]}
        """
        let d = try JSONFileStore<ValigiaData>.decoder.decode(ValigiaData.self, from: Data(json.utf8))
        XCTAssertEqual(d.trips[0].luggage[0].kind, .other)
        XCTAssertEqual(d.trips[0].luggage[0].items[0].quantity, 1)
        XCTAssertEqual(d.trips[0].rounds[0].kind, .custom)
        XCTAssertEqual(d.trips[0].activeRound?.id, d.trips[0].rounds[0].id)
        XCTAssertEqual(d.settings, ValigiaSettings())
    }

    func testFileStoreKeepsBackupCopy() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("valigia-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFileStore<ValigiaData>(url: dir.appendingPathComponent("data.json"), compact: true)
        XCTAssertNil(try store.load())
        var d = ValigiaData()
        d.trips = [Trip(name: "Primo")]
        try store.save(d, keepBackup: true)
        d.trips.append(Trip(name: "Secondo"))
        try store.save(d, keepBackup: true)
        XCTAssertEqual(try store.load()?.trips.count, 2)
        XCTAssertEqual(try store.loadBackup()?.trips.count, 1)
    }

    func testGearIntegrationHelpers() {
        let ref = ExternalRef(source: "gear-test", externalID: "42")
        var items = [GearItem(ref: ref, name: "Frontale TEST", weightGrams: 90).makeItem(), Item(name: "Altro")]
        XCTAssertEqual(items[0].externalRef, ref)
        let changed = items.applyGearUpdates([GearItem(ref: ref, name: "Frontale TEST v2", weightGrams: 80)])
        XCTAssertEqual(changed, 1)
        XCTAssertEqual(items[0].name, "Frontale TEST v2")
        XCTAssertEqual(items[0].weightGrams, 80)
    }
}
