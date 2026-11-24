import XCTest
@testable import ValigiaCore

final class TripTests: XCTestCase {
    func testCreateTripCopiesTemplatesIndependently() {
        var data = Synthetic.data()
        let tA = data.templates[0].id, tB = data.templates[1].id
        let tripID = data.createTrip(TripDraft(name: "Viaggio TEST", templateIDs: [tA, tB]), now: Synthetic.date(2026, 3, 1))
        let trip = data.trip(tripID)!
        XCTAssertEqual(trip.luggage.map(\.name), ["Template A", "Template B"])
        XCTAssertEqual(data.templates[0].usageCount, 1)
        // New ids everywhere.
        XCTAssertNotEqual(trip.luggage[0].id, data.templates[0].luggage.id)
        XCTAssertTrue(trip.luggage[0].items.allIDs.isDisjoint(with: data.templates[0].luggage.items.allIDs))
        // "Always" items: the one with a name already present ("maglia test") is skipped.
        XCTAssertEqual(trip.luggage[0].items.map(\.name).suffix(1), ["Documento TEST"])
        XCTAssertEqual(trip.luggage[0].items.count, 4)
        // Default rounds.
        XCTAssertEqual(trip.rounds.map(\.kind), [.departure, .returnTrip])
        XCTAssertEqual(trip.rounds.map(\.direction), [.pack, .unpack])
        XCTAssertEqual(trip.activeRound?.kind, .departure)

        // Editing the trip does not touch the template and vice versa.
        let ref = ListRef.trip(tripID: tripID, luggageID: trip.luggage[0].id)
        data.editItems(at: ref) { $0.removeAll() }
        XCTAssertEqual(data.templates[0].luggage.items.count, 3)
        data.editItems(at: .template(tA)) { $0.append(Item(name: "Solo template")) }
        XCTAssertTrue(data.items(at: ref)!.isEmpty)
    }

    func testTripWithoutTemplatesGetsABagForAlwaysItems() {
        var data = Synthetic.data()
        let id = data.createTrip(TripDraft(name: "", includeAlwaysItems: true))
        let trip = data.trip(id)!
        XCTAssertEqual(trip.name, "Nuovo viaggio")
        XCTAssertEqual(trip.luggage.count, 1)
        XCTAssertEqual(trip.luggage[0].items.map(\.name), ["Documento TEST", "maglia test"])
        let id2 = data.createTrip(TripDraft(name: "Vuoto", includeAlwaysItems: false))
        XCTAssertTrue(data.trip(id2)!.luggage.isEmpty)
    }

    func testSaveAsTemplateAndAddLuggage() {
        var data = Synthetic.data()
        let tripID = data.createTrip(TripDraft(name: "V", templateIDs: [data.templates[0].id], includeAlwaysItems: false))
        let bag = data.trip(tripID)!.luggage[0]
        let newT = data.saveAsTemplate(tripID: tripID, luggageID: bag.id, name: "Mio zaino")!
        let t = data.template(newT)!
        XCTAssertEqual(t.name, "Mio zaino")
        XCTAssertEqual(t.luggage.items.map(\.name), bag.items.map(\.name))
        XCTAssertTrue(t.luggage.items.allIDs.isDisjoint(with: bag.items.allIDs))

        let added = data.addLuggage(toTrip: tripID, fromTemplate: data.templates[1].id)!
        XCTAssertEqual(data.trip(tripID)!.luggage.count, 2)
        XCTAssertEqual(data.trip(tripID)!.luggage.last?.id, added)
        let blank = data.addLuggage(toTrip: tripID, fromTemplate: nil)!
        XCTAssertEqual(data.luggage(at: .trip(tripID: tripID, luggageID: blank))?.name, "Nuovo contenitore")
        XCTAssertNotNil(data.removeLuggage(blank, fromTrip: tripID))
        XCTAssertEqual(data.trip(tripID)!.luggage.count, 2)
    }

    func testMoveItemBetweenBagsKeepsTicks() {
        var data = Synthetic.data()
        let tripID = data.createTrip(TripDraft(name: "V", templateIDs: data.templates.map(\.id), includeAlwaysItems: false))
        var trip = data.trip(tripID)!
        let pouch = trip.luggage[0].items[0]
        trip.togglePacked(itemID: pouch.id)
        data.editTrip(tripID) { $0 = trip }
        let a = ListRef.trip(tripID: tripID, luggageID: trip.luggage[0].id)
        let b = ListRef.trip(tripID: tripID, luggageID: trip.luggage[1].id)
        XCTAssertTrue(data.moveItem(pouch.id, from: a, to: b, parentID: nil))
        let after = data.trip(tripID)!
        XCTAssertNil(after.luggage[0].items.find(pouch.id))
        XCTAssertNotNil(after.luggage[1].items.find(pouch.id))
        XCTAssertEqual(after.progress(luggageID: after.luggage[1].id).packed, 3)
        // Copy to a template: new ids.
        let copied = data.copyItem(pouch.id, from: b, to: .template(data.templates[1].id))!
        XCTAssertNotEqual(copied, pouch.id)
    }

    func testDuplicateAndDeleteTrip() {
        var data = Synthetic.data()
        let id = data.createTrip(TripDraft(name: "V", templateIDs: [data.templates[0].id]))
        data.editTrip(id) { $0.togglePacked(itemID: $0.luggage[0].items[1].id) }
        let copy = data.duplicateTrip(id)!
        XCTAssertEqual(data.trip(copy)!.name, "V (copia)")
        XCTAssertEqual(data.trip(copy)!.progress().packed, 0)
        XCTAssertEqual(data.trip(copy)!.itemCount, data.trip(id)!.itemCount)
        XCTAssertNotNil(data.deleteTrip(id))
        XCTAssertEqual(data.trips.count, 1)
    }

    func testTemplatesDuplicateDeleteAndSamples() {
        var data = ValigiaData()
        data.installSamplesIfNeeded()
        XCTAssertEqual(data.templates.count, 5)
        XCTAssertTrue(data.templates.allSatisfy(\.isSample))
        XCTAssertFalse(data.alwaysItems.isEmpty)
        data.installSamplesIfNeeded()
        XCTAssertEqual(data.templates.count, 5, "installed only once")
        let all = data.templates.flatMap { $0.luggage.items.allIDs }
        XCTAssertEqual(Set(all).count, all.count, "sample ids unique")
        let dup = data.duplicateTemplate(data.templates[0].id)!
        XCTAssertTrue(data.template(dup)!.name.hasSuffix("(copia)"))
        XCTAssertNotNil(data.deleteTemplate(dup))
        XCTAssertEqual(data.templates.count, 5)
    }

    func testPhasesAndNextTrip() {
        let cal = Synthetic.calendar
        let now = Synthetic.date(2026, 6, 10)
        var data = ValigiaData()
        let past = Trip(name: "Passato", startDate: Synthetic.date(2026, 5, 1), endDate: Synthetic.date(2026, 5, 3))
        let soon = Trip(name: "Presto", startDate: Synthetic.date(2026, 6, 12), endDate: Synthetic.date(2026, 6, 14))
        let later = Trip(name: "Dopo", startDate: Synthetic.date(2026, 7, 1))
        data.trips = [past, later, soon]
        XCTAssertEqual(past.phase(now: now, calendar: cal), .past)
        XCTAssertEqual(soon.phase(now: now, calendar: cal), .upcoming(days: 2))
        XCTAssertEqual(data.nextTrip(now: now, calendar: cal)?.name, "Presto")
        let ongoing = Trip(name: "Ora", startDate: Synthetic.date(2026, 6, 9), endDate: Synthetic.date(2026, 6, 11))
        data.trips.append(ongoing)
        XCTAssertEqual(data.nextTrip(now: now, calendar: cal)?.name, "Ora")
        let s = data.tripSections(now: now, calendar: cal)
        XCTAssertEqual(s.current.map(\.name), ["Ora", "Presto", "Dopo"])
        XCTAssertEqual(s.past.map(\.name), ["Passato"])
        XCTAssertEqual(ongoing.durationDays(calendar: cal), 3)
    }

    func testItalianDates() {
        let cal = Synthetic.calendar
        XCTAssertEqual(ItalianFormat.range(Synthetic.date(2026, 12, 12), Synthetic.date(2026, 12, 14), calendar: cal), "12–14 dic 2026")
        XCTAssertEqual(ItalianFormat.range(Synthetic.date(2026, 11, 28), Synthetic.date(2026, 12, 2), calendar: cal), "28 nov – 2 dic 2026")
        XCTAssertEqual(ItalianFormat.range(Synthetic.date(2026, 12, 30), Synthetic.date(2027, 1, 2), calendar: cal), "30 dic 2026 – 2 gen 2027")
        XCTAssertEqual(ItalianFormat.range(Synthetic.date(2026, 12, 12), nil, calendar: cal), "12 dic 2026")
        XCTAssertNil(ItalianFormat.range(nil, nil, calendar: cal))
        let now = Synthetic.date(2026, 6, 10, 23, 30)
        XCTAssertEqual(ItalianFormat.relative(Synthetic.date(2026, 6, 11, 1), now: now, calendar: cal), "domani")
        XCTAssertEqual(ItalianFormat.relative(Synthetic.date(2026, 6, 15), now: now, calendar: cal), "tra 5 giorni")
        XCTAssertEqual(ItalianFormat.longDay(Synthetic.date(2026, 12, 12), calendar: cal), "sabato 12 dicembre")
        XCTAssertEqual(ItalianFormat.list(["a", "b", "c"]), "a, b e c")
    }
}
