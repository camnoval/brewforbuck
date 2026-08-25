import XCTest
@testable import CoreModel

/// Load-bearing invariant (§8, §10, Change B): the ranker's input can only ever be a priced,
/// alcoholic drink. Non-alcoholic items are barred at the type boundary.
final class PricedDrinkInvariantTests: XCTestCase {
    private func option(_ category: BeverageCategory) -> DrinkOption {
        DrinkOption(
            name: "x", price: Price(dollars: 7)!,
            abv: .estimated(5, note: "n"),
            size: .estimated(Volume(fluidOunces: 12), note: "n"),
            category: category
        )
    }

    func testAlcoholicDrinkBecomesPricedDrink() {
        XCTAssertNotNil(PricedDrink(option(.cocktail)))
        XCTAssertNotNil(PricedDrink(option(.unknown)))
    }

    // Change B: a priced non-alcoholic item can NEVER become a PricedDrink, so it can never be
    // ranked — it's dropped before the metric runs.
    func testNonAlcoholicCannotBecomePricedDrink() {
        XCTAssertNil(PricedDrink(option(.nonAlcoholic)))
    }
}
