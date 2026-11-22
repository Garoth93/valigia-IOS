import XCTest
@testable import ValigiaCore

final class WeightTests: XCTestCase {
    func testBranchAndLuggageWeights() {
        let items = Synthetic.items()
        // pouch 50 + 100 + 2×30 + 200 = 410
        XCTAssertEqual(items[0].totalWeightGrams, 410)
        XCTAssertEqual(items[0].ownWeightGrams, 50)
        XCTAssertEqual(items[1].totalWeightGrams, 450)
        XCTAssertEqual(items.totalWeightGrams, 1360)
        let bag = Synthetic.luggage(max: 2000)
        XCTAssertEqual(bag.contentWeightGrams, 1360)
        XCTAssertEqual(bag.totalWeightGrams, 1660)
        XCTAssertFalse(bag.isOverweight)
        XCTAssertEqual(bag.weightLevel, .ok)
        XCTAssertEqual(Synthetic.luggage(max: 1700).weightLevel, .near)
        XCTAssertEqual(Synthetic.luggage(max: 1500).weightLevel, .over)
        XCTAssertTrue(Synthetic.luggage(max: 1500).isOverweight)
        XCTAssertEqual(Synthetic.luggage(max: nil).weightLevel, .unknown)
    }

    func testItemsWithoutWeight() {
        let item = Item(name: "x", children: [Item(name: "y")])
        XCTAssertFalse(item.hasWeight)
        XCTAssertEqual(item.totalWeightGrams, 0)
    }

    func testFormatting() {
        XCTAssertEqual(WeightFormat.string(850), "850 g")
        XCTAssertEqual(WeightFormat.string(1250), "1,25 kg")
        XCTAssertEqual(WeightFormat.string(1200), "1,2 kg")
        XCTAssertEqual(WeightFormat.string(7000), "7 kg")
        XCTAssertEqual(WeightFormat.string(12500), "12,5 kg")
        XCTAssertEqual(WeightFormat.ratio(3200, max: 7000), "3,2 kg / 7 kg")
        XCTAssertEqual(WeightFormat.parse("1,2 kg"), 1200)
        XCTAssertEqual(WeightFormat.parse("850"), 850)
        XCTAssertEqual(WeightFormat.parse("850 g"), 850)
        XCTAssertEqual(WeightFormat.parse("1.5kg"), 1500)
        XCTAssertNil(WeightFormat.parse("abc"))
        XCTAssertNil(WeightFormat.parse(""))
    }

    func testVolume() {
        let d = Dimensions(widthCm: 55, heightCm: 40, depthCm: 20)
        XCTAssertEqual(d.volumeLitres, 44)
        XCTAssertEqual(VolumeFormat.dimensions(d), "55 × 40 × 20 cm · 44 L")
        XCTAssertEqual(VolumeFormat.dimensions(Dimensions(litres: 38.5)), "38,5 L")
        XCTAssertNil(VolumeFormat.dimensions(Dimensions()))
    }
}
