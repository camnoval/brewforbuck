//
//  MenuValueSpreadTests.swift
//  Core
//
//  Created by Noval, Cameron on 9/9/26.
//


import XCTest
@testable import CoreServices
@testable import CoreModel

final class MenuValueSpreadTests: XCTestCase {

    // MARK: - The ratio

    func testRatioIsBestOverWorst() {
        let spread = MenuValueSpread.of(rankedValues: [0.48, 0.31, 0.20])

        XCTAssertEqual(spread?.bestValue ?? 0, 0.48, accuracy: 0.0001)
        XCTAssertEqual(spread?.worstValue ?? 0, 0.20, accuracy: 0.0001)
        XCTAssertEqual(spread?.ratio ?? 0, 2.4, accuracy: 0.0001)
    }

    /// A menu where everything is the same value gets a ratio of exactly 1, not nil. It is a true
    /// answer; it is just not one to brag about.
    func testAFlatMenuHasARatioOfOne() {
        let spread = MenuValueSpread.of(rankedValues: [0.33, 0.33, 0.33])

        XCTAssertEqual(spread?.ratio ?? 0, 1.0, accuracy: 0.0001)
    }

    /// Takes values already in ranked order, so it reads position 0 as best and never reasons about
    /// the metric's direction. Given a descending list it must not silently re-sort.
    func testItTrustsTheGivenOrderRatherThanResorting() {
        let spread = MenuValueSpread.of(rankedValues: [0.10, 0.50])

        XCTAssertEqual(spread?.bestValue ?? 0, 0.10, accuracy: 0.0001)
        XCTAssertEqual(spread?.worstValue ?? 0, 0.50, accuracy: 0.0001)
    }

    // MARK: - When there is nothing to compare

    func testOneDrinkIsNotAComparison() {
        XCTAssertNil(MenuValueSpread.of(rankedValues: [0.42]))
    }

    func testNoDrinksIsNotAComparison() {
        XCTAssertNil(MenuValueSpread.of(rankedValues: []))
    }

    /// A zero worst value would make the ratio undefined, so there is no spread to report.
    func testAZeroWorstValueYieldsNoSpread() {
        XCTAssertNil(MenuValueSpread.of(rankedValues: [0.42, 0.0]))
    }

    func testANegativeValueYieldsNoSpread() {
        XCTAssertNil(MenuValueSpread.of(rankedValues: [0.42, -0.1]))
    }

    // MARK: - The session convenience

    func testSessionWithTwoPricedDrinksReportsASpread() {
        // A $4 pint and an $8 pint of identical strength: the cheap one is exactly twice the value.
        let session = MenuSession(
            drinks: [
                Self.pint(id: 1, name: "Cheap Lager", dollars: 4),
                Self.pint(id: 2, name: "Dear Lager", dollars: 8)
            ],
            excludedNonAlcoholic: [],
            metric: .standardDrinksPerDollar
        )

        let spread = session.valueSpread

        XCTAssertNotNil(spread)
        XCTAssertEqual(spread?.ratio ?? 0, 2.0, accuracy: 0.0001)
    }

    func testSessionWithNoPricedDrinksReportsNoSpread() {
        let session = MenuSession(
            drinks: [Self.pint(id: 1, name: "No Price Here", dollars: nil)],
            excludedNonAlcoholic: [],
            metric: .standardDrinksPerDollar
        )

        XCTAssertNil(session.valueSpread)
    }

    // MARK: - Fixture

    /// A 16 oz, 5% draft beer at the given price. `nil` dollars means the line has no price yet, so
    /// it never reaches the ranking (§10).
    private static func pint(id: Int, name: String, dollars: Double?) -> EditableDrink {
        EditableDrink(
            id: id,
            name: name,
            category: .draftBeer,
            price: dollars.flatMap { Price(dollars: $0) },
            abv: .read(5.0),
            size: .read(Volume(fluidOunces: 16))
        )
    }
}
