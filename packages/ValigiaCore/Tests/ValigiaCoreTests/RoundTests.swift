import XCTest
@testable import ValigiaCore

final class RoundTests: XCTestCase {
    private func makeTrip() -> Trip {
        Trip(name: "V", luggage: [Synthetic.luggage("Zaino"), Luggage(name: "Borsa", items: [Item(name: "Scarpe TEST")])], createdAt: Synthetic.date(2026, 1, 1))
    }

    func testToggleLeafAndParent() {
        var trip = makeTrip()
        let pouch = trip.luggage[0].items[0]
        XCTAssertEqual(trip.progress().total, 6)
        trip.togglePacked(itemID: pouch.children[0].id)
        let marks = trip.activeRound!.markIndex
        XCTAssertEqual(pouch.checkState(marks: marks), .partial)
        // Parent toggle from partial → everything packed.
        trip.togglePacked(itemID: pouch.id)
        XCTAssertEqual(trip.progress().packed, 3)
        XCTAssertEqual(trip.find(pouch.id)!.checkState(marks: trip.activeRound!.markIndex), .done(.packed))
        // Again → cleared.
        trip.togglePacked(itemID: pouch.id)
        XCTAssertEqual(trip.progress().packed, 0)
    }

    func testRoundsAreIndependentAndResettable() {
        var trip = makeTrip()
        let dep = trip.rounds[0].id, ret = trip.rounds[1].id
        let shirt = trip.luggage[0].items[1].id
        trip.togglePacked(itemID: shirt, roundID: dep)
        XCTAssertEqual(trip.progress(round: dep).packed, 1)
        XCTAssertEqual(trip.progress(round: ret).packed, 0)
        let hotel = trip.addRound(name: "Cambio albergo", at: Synthetic.date(2026, 1, 3))
        XCTAssertEqual(trip.activeRoundID, hotel)
        XCTAssertEqual(trip.progress().packed, 0)
        trip.togglePacked(itemID: shirt)
        trip.resetRound(dep)
        XCTAssertEqual(trip.progress(round: dep).packed, 0)
        XCTAssertEqual(trip.progress(round: hotel).packed, 1, "history of other rounds kept")
        trip.removeRound(hotel)
        XCTAssertEqual(trip.rounds.count, 2)
        XCTAssertEqual(trip.activeRoundID, dep)
        trip.removeRound(ret)
        trip.removeRound(dep)
        XCTAssertEqual(trip.rounds.count, 1, "last round can't be removed")
    }

    func testStatusesAndSummary() {
        var trip = makeTrip()
        let items = trip.luggage[0].items
        trip.setStatus(.packed, itemID: items[0].id)
        trip.setStatus(.notFound, itemID: items[1].id)
        trip.setStatus(.leftBehind, itemID: items[2].id, place: "Hotel TEST")
        let s = trip.summary()
        XCTAssertEqual(s.progress, ProgressCount(packed: 3, notFound: 1, leftBehind: 1, total: 6))
        XCTAssertEqual(s.missing.map(\.name), ["Maglia TEST", "Giacca TEST", "Scarpe TEST"])
        XCTAssertEqual(s.notFound.map(\.name), ["Maglia TEST"])
        XCTAssertEqual(s.leftBehind.first?.place, "Hotel TEST")
        XCTAssertEqual(s.unmarked.map(\.name), ["Scarpe TEST"])
        XCTAssertEqual(s.missing.first?.location, "Zaino")
        // Place only kept for leftBehind.
        trip.setStatus(.packed, itemID: items[2].id, place: "ignored")
        XCTAssertEqual(trip.activeRound!.mark(for: items[2].id)?.place, "")
        // Nested location label.
        trip.setStatus(nil, itemID: items[0].children[1].id)
        XCTAssertEqual(trip.summary().missing.first?.location, "Zaino › Astuccio TEST")
    }

    func testCompleteAndReopen() {
        var trip = makeTrip()
        let id = trip.rounds[0].id
        trip.completeRound(id, at: Synthetic.date(2026, 1, 2))
        XCTAssertTrue(trip.rounds[0].isCompleted)
        trip.reopenRound(id)
        XCTAssertFalse(trip.rounds[0].isCompleted)
        trip.completeRound(id)
        trip.resetRound(id)
        XCTAssertFalse(trip.rounds[0].isCompleted)
    }

    func testMarksPrunedWhenItemsDisappear() {
        var data = ValigiaData()
        var trip = makeTrip()
        let shirt = trip.luggage[0].items[1].id
        trip.togglePacked(itemID: shirt)
        data.trips = [trip]
        data.editItems(at: .trip(tripID: trip.id, luggageID: trip.luggage[0].id)) { $0.remove(shirt) }
        XCTAssertTrue(data.trips[0].rounds[0].marks.isEmpty)
    }

    func testResetSingleLuggage() {
        var trip = makeTrip()
        let r = trip.rounds[0].id
        trip.setStatus(.packed, itemID: trip.luggage[0].items[1].id)
        trip.setStatus(.packed, itemID: trip.luggage[1].items[0].id)
        trip.resetLuggage(trip.luggage[0].id, roundID: r)
        XCTAssertEqual(trip.progress().packed, 1)
    }
}
