import XCTest
@testable import ValigiaCore

final class FillStateTests: XCTestCase {
    private func trip() -> Trip {
        Trip(name: "V", luggage: [
            Luggage(name: "A", maxWeightGrams: 500, items: [Item(name: "a1", weightGrams: 300), Item(name: "a2", weightGrams: 300)]),
            Luggage(name: "B", items: [Item(name: "b1")])
        ])
    }

    func testFillLevelPackAndUnpack() {
        var t = trip()
        let a1 = t.luggage[0].items[0].id
        t.togglePacked(itemID: a1)
        let fill = TripFillState(trip: t)
        let a = fill.luggage(t.luggage[0].id)!
        XCTAssertEqual(a.fillLevel, 0.5)
        XCTAssertTrue(a.isOverweight)
        XCTAssertEqual(a.weightFraction!, 1.2, accuracy: 0.001)
        XCTAssertFalse(a.isClosed)
        XCTAssertEqual(fill.progress.packed, 1)

        let ret = t.rounds[1].id
        t.activeRoundID = ret
        t.togglePacked(itemID: a1)
        let back = TripFillState(trip: t).luggage(t.luggage[0].id)!
        XCTAssertEqual(back.direction, .unpack)
        XCTAssertEqual(back.fillLevel, 0.5, "unpacking: one of two taken out")
        t.togglePacked(itemID: t.luggage[0].items[1].id)
        XCTAssertTrue(TripFillState(trip: t).luggage(t.luggage[0].id)!.isEmptied)
        XCTAssertEqual(TripFillState(trip: t).luggage(t.luggage[0].id)!.fillLevel, 0)
    }

    func testEventsForPackingRound() {
        let t0 = trip()
        var t1 = t0
        t1.togglePacked(itemID: t0.luggage[0].items[0].id)
        XCTAssertEqual(PackingEvents.diff(before: t0, after: t1), [.itemChecked(itemID: t0.luggage[0].items[0].id, luggageID: t0.luggage[0].id, direction: .pack)])
        var t2 = t1
        t2.togglePacked(itemID: t0.luggage[0].items[1].id)
        let e2 = PackingEvents.diff(before: t1, after: t2)
        XCTAssertTrue(e2.contains(.luggageClosed(luggageID: t0.luggage[0].id)))
        XCTAssertFalse(e2.contains(.roundCompleted(roundID: t0.rounds[0].id)))
        var t3 = t2
        t3.togglePacked(itemID: t0.luggage[1].items[0].id)
        let e3 = PackingEvents.diff(before: t2, after: t3)
        XCTAssertEqual(e3.suffix(2), [.luggageClosed(luggageID: t0.luggage[1].id), .roundCompleted(roundID: t0.rounds[0].id)])
        var t4 = t3
        t4.togglePacked(itemID: t0.luggage[1].items[0].id)
        XCTAssertEqual(PackingEvents.diff(before: t3, after: t4), [.itemUnchecked(itemID: t0.luggage[1].items[0].id, luggageID: t0.luggage[1].id, direction: .pack)])
        var t5 = t4
        t5.setStatus(.leftBehind, itemID: t0.luggage[1].items[0].id, place: "casa")
        XCTAssertEqual(PackingEvents.diff(before: t4, after: t5), [.itemFlagged(itemID: t0.luggage[1].items[0].id, luggageID: t0.luggage[1].id, status: .leftBehind)])
    }

    func testReturnRoundEmptied() {
        var t0 = trip()
        let ret = t0.rounds[1].id
        t0.activeRoundID = ret
        var t1 = t0
        for bag in t0.luggage { for id in bag.items.leafIDs { t1.togglePacked(itemID: id) } }
        let events = PackingEvents.diff(before: t0, after: t1)
        XCTAssertTrue(events.contains(.luggageEmptied(luggageID: t0.luggage[0].id)))
        XCTAssertTrue(events.contains(.roundCompleted(roundID: ret)))
        XCTAssertEqual(events.last, .returnRoundEmptied(roundID: ret))
    }

    func testMotionAndLuggageOfEvents() {
        let i = UUID(), l = UUID(), r = UUID()
        XCTAssertEqual(PackingEvent.itemChecked(itemID: i, luggageID: l, direction: .pack).motion, .enter)
        XCTAssertEqual(PackingEvent.itemChecked(itemID: i, luggageID: l, direction: .unpack).motion, .exit)
        XCTAssertEqual(PackingEvent.itemUnchecked(itemID: i, luggageID: l, direction: .pack).motion, .exit)
        XCTAssertEqual(PackingEvent.itemUnchecked(itemID: i, luggageID: l, direction: .unpack).motion, .enter)
        XCTAssertNil(PackingEvent.luggageClosed(luggageID: l).motion)
        XCTAssertEqual(PackingEvent.itemFlagged(itemID: i, luggageID: l, status: .notFound).luggageID, l)
        XCTAssertNil(PackingEvent.roundCompleted(roundID: r).luggageID)
        XCTAssertTrue(LuggageVisualStyle.threeD.isAvailable)
        XCTAssertFalse(LuggageVisualStyle.illustrated.isAvailable)
    }
}
