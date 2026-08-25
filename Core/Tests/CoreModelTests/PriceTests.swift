import XCTest
import Foundation
@testable import CoreModel

final class PriceTests: XCTestCase {
    func testRejectsZeroAndNegative() {
        XCTAssertNil(Price(Decimal(0)))
        XCTAssertNil(Price(Decimal(-5)))
        XCTAssertNil(Price(dollars: 0))
    }

    func testAcceptsPositive() {
        XCTAssertNotNil(Price(dollars: 8))
        XCTAssertEqual(Price(cents: 739)?.amount, Decimal(739) / 100)
    }

    func testComparable() {
        XCTAssertTrue(Price(dollars: 5)! < Price(dollars: 8)!)
    }

    // §10, model level: a parsed line with no amount yields no Price, so it can never build a
    // DrinkOption. This is the first link in the structural price invariant.
    func testAbsentAmountCannotBecomePrice() {
        let parsedAmount: Decimal? = nil
        XCTAssertNil(parsedAmount.flatMap(Price.init))
    }
}
