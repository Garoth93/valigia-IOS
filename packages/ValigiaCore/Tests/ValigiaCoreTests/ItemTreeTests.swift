import XCTest
@testable import ValigiaCore

final class ItemTreeTests: XCTestCase {
    func testFindPathAndLocation() {
        let items = Synthetic.items()
        let cable = items[0].children[1]
        XCTAssertEqual(items.find(cable.id)?.name, "Cavo TEST")
        XCTAssertEqual(items.path(to: cable.id)?.map(\.name), ["Astuccio TEST", "Cavo TEST"])
        XCTAssertEqual(items.location(of: cable.id), TreeLocation(parentID: items[0].id, index: 1))
        XCTAssertEqual(items.itemCount, 6)
        XCTAssertEqual(items.leafIDs.count, 5)
    }

    func testDeepNestingWithoutLimit() {
        var items: [Item] = [Item(name: "L0")]
        var parent = items[0].id
        for depth in 1...30 {
            let child = Item(name: "L\(depth)")
            XCTAssertTrue(items.insert(child, into: parent))
            parent = child.id
        }
        XCTAssertEqual(items.path(to: parent)?.count, 31)
        XCTAssertEqual(items.rows().last?.depth, 30)
    }

    func testInsertRemoveUpdate() {
        var items = Synthetic.items()
        let new = Item(name: "Nuovo")
        XCTAssertTrue(items.insert(new, into: items[0].id, at: 0))
        XCTAssertEqual(items[0].children.first?.name, "Nuovo")
        XCTAssertFalse(items.insert(Item(name: "x"), into: UUID()))
        XCTAssertTrue(items.update(new.id) { $0.quantity = 0; $0.name = "Rinominato" })
        XCTAssertEqual(items.find(new.id)?.quantity, 1, "quantity never below 1")
        XCTAssertEqual(items.remove(items[0].id)?.children.count, 4)
        XCTAssertNil(items.find(new.id))
    }

    func testMoveRefusesCycles() {
        var items = Synthetic.items()
        let pouch = items[0].id, cable = items[0].children[1].id
        XCTAssertFalse(items.move(pouch, into: cable))
        XCTAssertFalse(items.move(pouch, into: pouch))
        XCTAssertTrue(items.move(items[1].id, into: pouch, at: 0))
        XCTAssertEqual(items[0].children.first?.name, "Maglia TEST")
        XCTAssertEqual(items.count, 2)
    }

    func testMoveBeforeAnchorAndRowMove() {
        var items = Synthetic.items()
        // Rows: Astuccio, -Caricatore, -Cavo, -Batteria, Maglia, Giacca
        let rows = items.rows()
        XCTAssertEqual(Synthetic.names(rows), ["Astuccio TEST", "-Caricatore TEST", "-Cavo TEST", "-Batteria TEST", "Maglia TEST", "Giacca TEST"])
        // Drag "Giacca" before "Cavo": it enters the pouch.
        XCTAssertTrue(items.moveRow(from: 5, to: 2, in: rows))
        XCTAssertEqual(items[0].children.map(\.name), ["Caricatore TEST", "Giacca TEST", "Cavo TEST", "Batteria TEST"])
        // Drag the pouch to the end: whole branch moves.
        let rows2 = items.rows()
        XCTAssertTrue(items.moveRow(from: 0, to: rows2.count, in: rows2))
        XCTAssertEqual(items.map(\.name), ["Maglia TEST", "Astuccio TEST"])
        XCTAssertEqual(items[1].children.count, 4)
        // Dropping right after itself is a no-op.
        let rows3 = items.rows()
        XCTAssertFalse(items.moveRow(from: 0, to: 1, in: rows3))
    }

    func testDraggingParentBelowItsOwnChildren() {
        var items = Synthetic.items()
        let rows = items.rows()
        // Pouch (row 0) dropped before row 3 (its own child) → goes before "Maglia".
        items.moveRow(from: 0, to: 3, in: rows)
        XCTAssertEqual(items.map(\.name), ["Astuccio TEST", "Maglia TEST", "Giacca TEST"])
        XCTAssertEqual(items[0].children.count, 3)
    }

    func testDuplicateBranchGetsNewIDs() {
        var items = Synthetic.items()
        let newID = items.duplicate(items[0].id)
        XCTAssertNotNil(newID)
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items[1].id, newID)
        XCTAssertEqual(items[1].children.map(\.name), items[0].children.map(\.name))
        XCTAssertTrue(Set(items[1].children.map(\.id)).isDisjoint(with: Set(items[0].children.map(\.id))))
        XCTAssertEqual(items.allIDs.count, items.itemCount, "all ids unique")
    }

    func testIndentOutdent() {
        var items = Synthetic.items()
        let shirt = items[1].id
        XCTAssertTrue(items.indent(shirt))
        XCTAssertEqual(items[0].children.last?.id, shirt)
        XCTAssertTrue(items.outdent(shirt))
        XCTAssertEqual(items.map(\.name), ["Astuccio TEST", "Maglia TEST", "Giacca TEST"])
        XCTAssertFalse(items.indent(items[0].id), "first item has no previous sibling")
        XCTAssertFalse(items.outdent(items[0].id), "already top level")
    }

    func testCollapseHidesChildren() {
        var items = Synthetic.items()
        items.update(items[0].id) { $0.isCollapsed = true }
        XCTAssertEqual(items.rows().count, 3)
        items.setCollapsed(false)
        XCTAssertEqual(items.rows().count, 6)
    }

    func testMoveTargetsExcludeBranch() {
        let items = Synthetic.items()
        let targets = items.moveTargets(excluding: items[0].id)
        XCTAssertEqual(targets.map(\.item.name), ["Maglia TEST", "Giacca TEST"])
    }

    func testTagsAndNormalisation() {
        XCTAssertEqual(Synthetic.items().allTags, ["estate", "inverno", "volo"])
        XCTAssertEqual(TextKey.tag("  #Solo  Bagaglio a Mano "), "solo bagaglio a mano")
        XCTAssertEqual(TextKey.normalized(" Città "), "citta")
    }
}
