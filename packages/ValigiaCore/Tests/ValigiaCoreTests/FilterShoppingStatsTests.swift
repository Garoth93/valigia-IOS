import XCTest
@testable import ValigiaCore

final class FilterTests: XCTestCase {
    func testSearchKeepsParentsAndIgnoresAccents() {
        let items = Synthetic.items()
        let rows = ItemFilter(query: "cavo").rows(for: items)
        XCTAssertEqual(Synthetic.names(rows), ["Astuccio TEST", "-Cavo TEST"])
        XCTAssertEqual(Synthetic.names(ItemFilter(query: "BLU").rows(for: items)), ["Giacca TEST"], "searches notes")
        var withAccent = items
        withAccent.append(Item(name: "Caffè"))
        XCTAssertEqual(Synthetic.names(ItemFilter(query: "caffe").rows(for: withAccent)), ["Caffè"])
        // A matching parent shows its whole content.
        XCTAssertEqual(ItemFilter(query: "astuccio").rows(for: items).count, 4)
    }

    func testTagsAreInherited() {
        let rows = ItemFilter(tags: ["volo"]).rows(for: Synthetic.items())
        XCTAssertEqual(Synthetic.names(rows), ["Astuccio TEST", "-Caricatore TEST", "-Cavo TEST", "-Batteria TEST"])
        XCTAssertEqual(Synthetic.names(ItemFilter(tags: ["volo", "estate"]).rows(for: Synthetic.items())), [])
        XCTAssertEqual(Synthetic.names(ItemFilter(tags: ["#Inverno"]).rows(for: Synthetic.items())), ["Giacca TEST"])
    }

    func testOnlyMissingAndToBuy() {
        var trip = Trip(name: "V", luggage: [Synthetic.luggage()])
        let items = trip.luggage[0].items
        trip.togglePacked(itemID: items[0].children[0].id)
        trip.togglePacked(itemID: items[1].id)
        let rows = ItemFilter(onlyMissing: true).rows(for: items, marks: trip.activeRound!.markIndex)
        XCTAssertEqual(Synthetic.names(rows), ["Astuccio TEST", "-Cavo TEST", "-Batteria TEST", "Giacca TEST"])
        XCTAssertEqual(Synthetic.names(ItemFilter(onlyToBuy: true).rows(for: items)), ["Astuccio TEST", "-Batteria TEST"])
        XCTAssertFalse(ItemFilter(query: "  ").isActive)
    }

    func testCollapsedIgnoredWhileFiltering() {
        var items = Synthetic.items()
        items.update(items[0].id) { $0.isCollapsed = true }
        XCTAssertEqual(ItemFilter(query: "cavo").rows(for: items).count, 2)
        XCTAssertEqual(ItemFilter().rows(for: items).count, 3)
    }
}

final class ShoppingTests: XCTestCase {
    func testCollectsNotOwnedAndMarksBought() {
        var data = Synthetic.data()
        let tripID = data.createTrip(TripDraft(name: "Viaggio", startDate: Synthetic.date(2026, 5, 1), templateIDs: [data.templates[0].id]))
        data.alwaysItems.append(Item(name: "Zzz TEST", owned: false))
        let entries = ShoppingList.entries(in: data)
        XCTAssertEqual(entries.map(\.name), ["Batteria TEST", "Batteria TEST", "Zzz TEST"])
        XCTAssertEqual(entries.first?.sourceName, "Viaggio › Template A")
        XCTAssertEqual(entries.first?.ref.tripID, tripID)
        ShoppingList.markBought([entries[0]], in: &data)
        XCTAssertEqual(ShoppingList.entries(in: data).count, 2)
        XCTAssertTrue(ShoppingList.text(ShoppingList.entries(in: data)).contains("☐ Batteria TEST"))
        data.trips[0].isArchived = true
        ShoppingList.markBought(ShoppingList.entries(in: data), in: &data)
        XCTAssertTrue(ShoppingList.entries(in: data).isEmpty)
        XCTAssertEqual(ShoppingList.text([]), "Da comprare: niente 🎉")
    }
}

final class StatsTests: XCTestCase {
    func testStats() {
        let cal = Synthetic.calendar
        var data = Synthetic.data()
        let t1 = data.createTrip(TripDraft(name: "Uno", destination: "Mare TEST", startDate: Synthetic.date(2026, 5, 1), endDate: Synthetic.date(2026, 5, 3), templateIDs: [data.templates[0].id], includeAlwaysItems: false))
        let t2 = data.createTrip(TripDraft(name: "Due", destination: "mare test", startDate: Synthetic.date(2026, 5, 10), endDate: Synthetic.date(2026, 5, 11), templateIDs: [data.templates[0].id, data.templates[1].id], includeAlwaysItems: false))
        _ = data.createTrip(TripDraft(name: "Futuro", startDate: Synthetic.date(2026, 9, 1)))
        // Trip 1: jacket not found; round completed with the shirt unticked.
        data.editTrip(t1) { t in
            let items = t.luggage[0].items
            t.setStatus(.packed, itemID: items[0].id)
            t.setStatus(.notFound, itemID: items[2].id)
            t.completeRound(t.rounds[0].id)
        }
        // Trip 2: jacket left at the hotel.
        data.editTrip(t2) { t in
            t.setStatus(.leftBehind, itemID: t.luggage[0].items[2].id, place: "Hotel")
        }
        let s = PackingStats(data: data, now: Synthetic.date(2026, 6, 1), calendar: cal)
        XCTAssertEqual(s.tripsTotal, 3)
        XCTAssertEqual(s.tripsDone, 2)
        XCTAssertEqual(s.daysAway, 5)
        XCTAssertEqual(s.roundsCompleted, 1)
        XCTAssertEqual(s.itemsPacked, 3)
        XCTAssertEqual(s.forgotten.first?.name, "Giacca TEST")
        XCTAssertEqual(s.forgotten.first?.count, 2)
        XCTAssertEqual(s.forgotten.first?.notFound, 1)
        XCTAssertEqual(s.forgotten.first?.leftBehind, 1)
        XCTAssertEqual(s.forgotten.first?.lastTripName, "Due")
        XCTAssertEqual(s.forgotten.map(\.name).sorted(), ["Giacca TEST", "Maglia TEST"])
        let backpack = s.weightByKind.first { $0.kind == .backpack }
        XCTAssertEqual(backpack?.samples, 2)
        XCTAssertEqual(backpack?.averageGrams, 1660)
        XCTAssertEqual(s.templateUse.first?.name, "Template A")
        XCTAssertEqual(s.templateUse.first?.count, 2)
        XCTAssertEqual(s.topDestinations, ["Mare TEST"])
        XCTAssertEqual(PackingStats(data: ValigiaData(), now: Date()), .empty)
    }
}
