import XCTest
@testable import CoreModel

final class DrinkOptionTests: XCTestCase {
    func testAllReadHasNoEstimate() {
        let d = DrinkOption(
            name: "Guinness Draft", price: Price(dollars: 7)!,
            abv: .read(4.2), size: .read(Volume(fluidOunces: 16)), category: .draftBeer
        )
        XCTAssertFalse(d.hasEstimate)
    }

    func testAnyEstimatedAxisFlagsEstimate() {
        let d = DrinkOption(
            name: "House Red", price: Price(dollars: 9)!,
            abv: .estimated(12, note: "typical wine"),
            size: .read(Volume(fluidOunces: 5)), category: .wineGlass
        )
        XCTAssertTrue(d.hasEstimate)
    }
}
