import XCTest
@testable import CoreServices
@testable import CoreModel

final class ValueRankerTests: XCTestCase {
    private let ranker = ValueRanker()

    private func drink(_ name: String, price: Double, abv: Double, ozFloz: Double,
                       category: BeverageCategory = .cocktail) -> PricedDrink {
        PricedDrink(DrinkOption(
            name: name, price: Price(dollars: price)!,
            abv: .read(abv), size: .read(Volume(fluidOunces: ozFloz)), category: category
        ))!
    }

    // The worked example from Architecture §8:
    //   16 oz / 6.5% draft @ $7  → 1.733 std drinks → 0.248 /$   (should WIN)
    //   3 oz / 40% well double @ $10 → 2.0 std drinks → 0.200 /$
    func testWorkedExampleOrderingAndValues() {
        let draft = drink("Draft", price: 7, abv: 6.5, ozFloz: 16, category: .draftBeer)
        let wellDouble = drink("Well Double", price: 10, abv: 40, ozFloz: 3, category: .cocktail)

        let ranked = ranker.rank([wellDouble, draft], by: .standardDrinksPerDollar)

        XCTAssertEqual(ranked.count, 2)
        XCTAssertEqual(ranked[0].drink.name, "Draft")
        XCTAssertEqual(ranked[0].rank, 1)
        XCTAssertEqual(ranked[0].value, 0.2476, accuracy: 0.001)
        XCTAssertEqual(ranked[1].drink.name, "Well Double")
        XCTAssertEqual(ranked[1].rank, 2)
        XCTAssertEqual(ranked[1].value, 0.20, accuracy: 0.001)
    }

    func testStandardDrinksMath() {
        // 5 oz of 12% wine = 0.6 fl oz ethanol = exactly one standard drink.
        let wine = drink("House Red", price: 5, abv: 12, ozFloz: 5, category: .wineGlass)
        XCTAssertEqual(ValueRanker.standardDrinks(wine), 1.0, accuracy: 0.0001)
        // Value = 1 standard drink / $5 = 0.2 per dollar.
        XCTAssertEqual(ValueRanker.value(of: wine, metric: .standardDrinksPerDollar), 0.2, accuracy: 0.0001)
    }

    func testCaloriesMetricIsPositiveAndOrders() {
        // v2 sanity: alcohol-only kcal lower bound; a stronger-per-dollar drink also wins on kcal here.
        let a = drink("Draft", price: 7, abv: 6.5, ozFloz: 16, category: .draftBeer)
        let b = drink("Well Double", price: 10, abv: 40, ozFloz: 3, category: .cocktail)
        let ranked = ranker.rank([b, a], by: .caloriesPerDollar)
        XCTAssertGreaterThan(ranked[0].value, 0)
        XCTAssertEqual(ranked[0].drink.name, "Draft")   // ~24.6 kcal/$ vs ~19.9 kcal/$
    }

    func testEstimatedValuesStillRank() {
        // Provenance doesn't change the math — the ranker uses .value regardless of read/estimated.
        let estimated = PricedDrink(DrinkOption(
            name: "Mystery IPA", price: Price(dollars: 6)!,
            abv: .estimated(6.5, note: "style chart"), size: .estimated(Volume(fluidOunces: 16), note: "assumed pint"),
            category: .draftBeer))!
        let ranked = ranker.rank([estimated], by: .standardDrinksPerDollar)
        XCTAssertEqual(ranked.count, 1)
        XCTAssertGreaterThan(ranked[0].value, 0)
    }

    func testEmptyInputIsEmptyOutput() {
        XCTAssertTrue(ranker.rank([], by: .standardDrinksPerDollar).isEmpty)
    }

    // §8/§10 at the ranker boundary: the ranker ranks exactly the priced drinks it is given —
    // nothing is injected, nothing is dropped. (Priceless/non-alcoholic items can't be PricedDrinks.)
    func testRanksExactlyItsInput() {
        let items = [
            drink("A", price: 8, abv: 5, ozFloz: 12, category: .bottledBeer),
            drink("B", price: 9, abv: 12, ozFloz: 5, category: .wineGlass),
            drink("C", price: 12, abv: 40, ozFloz: 1.5, category: .shot),
        ]
        let ranked = ranker.rank(items, by: .standardDrinksPerDollar)
        XCTAssertEqual(ranked.count, items.count)
        XCTAssertEqual(Set(ranked.map { $0.drink.name }), ["A", "B", "C"])
        // Ranks are a clean 1...n.
        XCTAssertEqual(ranked.map { $0.rank }, [1, 2, 3])
    }
}
