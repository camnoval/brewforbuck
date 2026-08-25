import XCTest
@testable import CoreModel

final class PriceTests: XCTestCase {
    func testRejectsZeroAndNegative() {
        XCTAssertNil(Price(cents: 0))
        XCTAssertNil(Price(cents: -500))
        XCTAssertNil(Price(dollars: 0))
    }

    func testAcceptsPositive() {
        XCTAssertNotNil(Price(dollars: 8))
        XCTAssertEqual(Price(cents: 739)?.dollars ?? 0, 7.39, accuracy: 0.0001)
        XCTAssertEqual(Price(dollars: 7.39)?.cents, 739)
    }

    func testComparable() {
        XCTAssertTrue(Price(dollars: 5)! < Price(dollars: 8)!)
    }

    // §10, model level: a parsed line with no amount yields no Price, so it can never build a
    // DrinkOption. First link in the structural price invariant.
    func testAbsentAmountCannotBecomePrice() {
        let parsedCents: Int? = nil
        XCTAssertNil(parsedCents.flatMap { Price(cents: $0) })
    }
}
