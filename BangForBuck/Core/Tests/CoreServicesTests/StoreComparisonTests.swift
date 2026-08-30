import XCTest
@testable import CoreServices
import CoreModel

/// The store calculator ranks packaged products by standard drinks per dollar using the same NIAAA
/// formula as the menu ranker, applied to the whole package (unit size × count).
final class StoreComparisonTests: XCTestCase {

    private func product(_ name: String, _ size: Volume, _ count: Int, _ abv: Double, _ price: Double) -> StoreProduct {
        StoreProduct(name: name, unitVolume: size, count: count, abv: abv, packagePrice: Price(dollars: price)!)
    }

    /// A 6-pack of 12 oz cans at 5% = 72 oz × 5% ÷ 0.6 = 6 standard drinks; at $10 that's 0.6/$.
    func testPackageStandardDrinksAndValue() {
        let sixpack = product("Lager 6pk", Volume(fluidOunces: 12), 6, 5, 10)
        XCTAssertEqual(sixpack.totalVolume.fluidOunces, 72, accuracy: 0.0001)
        XCTAssertEqual(sixpack.totalStandardDrinks, 6, accuracy: 0.0001)

        let ranked = StoreComparison().rank([sixpack])
        XCTAssertEqual(ranked[0].standardDrinksPerDollar, 0.6, accuracy: 0.0001)
        XCTAssertEqual(ranked[0].pricePerStandardDrink, 10.0 / 6.0, accuracy: 0.0001)
    }

    /// The classic shopper result: a 1.75 L handle of spirits beats wine and beer per dollar.
    func testHandleBeatsBeerAndWinePerDollar() {
        let products = [
            product("6pk 12oz lager", Volume(fluidOunces: 12), 6, 5, 10),
            product("750mL wine", Volume(milliliters: 750), 1, 13, 12),
            product("1.75L vodka", Volume(liters: 1.75), 1, 40, 20),
            product("4pk 16oz IPA", Volume(fluidOunces: 16), 4, 8, 13),
        ]
        let ranked = StoreComparison().rank(products)
        XCTAssertEqual(ranked.first?.product.name, "1.75L vodka")
        XCTAssertEqual(ranked.last?.product.name, "750mL wine")
        // Ranks are 1...n in order.
        XCTAssertEqual(ranked.map(\.rank), [1, 2, 3, 4])
        // Monotonic non-increasing value.
        for i in 1..<ranked.count {
            XCTAssertGreaterThanOrEqual(ranked[i - 1].standardDrinksPerDollar,
                                        ranked[i].standardDrinksPerDollar)
        }
    }

    /// Shares the exact menu formula: package of one 5 oz pour at 12% equals the menu ranker's count.
    func testSharesValueRankerFormula() {
        let oneGlass = product("single pour", Volume(fluidOunces: 5), 1, 12, 8)
        XCTAssertEqual(oneGlass.totalStandardDrinks,
                       ValueRanker.standardDrinks(sizeFloz: 5, abvPercent: 12),
                       accuracy: 0.0000001)
    }

    /// A zero-alcohol product can't divide by zero and sorts last.
    func testZeroAlcoholSortsLastWithoutDividingByZero() {
        let products = [
            product("NA beer 6pk", Volume(fluidOunces: 12), 6, 0, 9),
            product("real beer 6pk", Volume(fluidOunces: 12), 6, 5, 10),
        ]
        let ranked = StoreComparison().rank(products)
        XCTAssertEqual(ranked.first?.product.name, "real beer 6pk")
        XCTAssertEqual(ranked.last?.product.name, "NA beer 6pk")
        XCTAssertEqual(ranked.last!.standardDrinksPerDollar, 0, accuracy: 0.0)
        XCTAssertTrue(ranked.last!.pricePerStandardDrink.isInfinite)
    }

    func testContainerPresetsCoverCommonSizes() {
        XCTAssertEqual(ContainerSize.ml750.volume.milliliters, 750, accuracy: 0.001)
        XCTAssertEqual(ContainerSize.liter175.volume.liters, 1.75, accuracy: 0.0001)
        XCTAssertEqual(ContainerSize.can12.volume.fluidOunces, 12, accuracy: 0.0001)
        XCTAssertFalse(ContainerSize.presets.isEmpty)
    }
}
