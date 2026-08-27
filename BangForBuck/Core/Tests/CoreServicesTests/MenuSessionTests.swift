//
//  MenuSessionTests.swift
//  Core
//
//  Created by Noval, Cameron on 8/27/26.
//


import XCTest
@testable import CoreServices
@testable import CoreModel

/// Mirrors `MenuSession` (§8): the editable capture-flow engine. Proves that correcting an estimate
/// promotes it to `.read` and re-ranks, that the add-a-price path brings a priceless line into the
/// ranking, and that both load-bearing invariants (§10, Change B) survive editing.
final class MenuSessionTests: XCTestCase {
    private let pipeline = MenuPipeline()

    private func session(_ lines: [String]) -> MenuSession {
        pipeline.makeSession(lines: lines, metric: .standardDrinksPerDollar)
    }

    // MARK: - Correction (§11)

    func testCorrectingABVPromotesToReadAndRerecomputes() {
        var s = session(["WINE", "Cabernet $9"])
        // Baseline: estimated 14% ⇒ (5oz × 14%)/0.6 / $9.
        XCTAssertEqual(s.drinks[0].abv.isEstimated, true)
        XCTAssertEqual(s.rankedDrinks[0].value, 0.12963, accuracy: 0.0005)

        s.correctABV(id: 0, to: 20)
        XCTAssertEqual(s.drinks[0].abv.isEstimated, false)              // now .read
        XCTAssertEqual(s.drinks[0].abv.value, 20)
        XCTAssertEqual(s.rankedDrinks[0].value, 0.18519, accuracy: 0.0005) // (5×20%)/0.6/9
    }

    func testCorrectingSizePromotesToReadAndRerecomputes() {
        var s = session(["WINE", "Cabernet $9"])
        s.correctSize(id: 0, to: 10)                                   // a double pour
        XCTAssertEqual(s.drinks[0].size.isEstimated, false)
        XCTAssertEqual(s.drinks[0].size.value.fluidOunces, 10)
        XCTAssertEqual(s.rankedDrinks[0].value, 0.25926, accuracy: 0.0005) // (10×14%)/0.6/9
    }

    // MARK: - Add-a-price (R1)

    func testAddingPriceMovesItemFromNeedsPriceIntoRanking() {
        var s = session(["COCKTAILS", "Margarita"])
        XCTAssertTrue(s.rankedDrinks.isEmpty)
        XCTAssertEqual(s.needsPriceDrinks.map { $0.name }, ["Margarita"])

        s.setPrice(id: 0, dollars: 10)
        XCTAssertTrue(s.needsPriceDrinks.isEmpty)
        XCTAssertEqual(s.rankedDrinks.count, 1)
        XCTAssertEqual(s.rankedDrinks[0].drink.name, "Margarita")
        XCTAssertGreaterThan(s.rankedDrinks[0].value, 0)
    }

    // MARK: - Invariants survive editing (§10, Change B)

    func testSetPriceRejectsNonPositiveInput() {
        var s = session(["COCKTAILS", "Margarita"])
        s.setPrice(id: 0, cents: 0)
        s.setPrice(id: 0, dollars: -5)
        XCTAssertEqual(s.needsPriceDrinks.map { $0.name }, ["Margarita"])   // still unpriced
        XCTAssertTrue(s.rankedDrinks.isEmpty)                               // never fabricated
    }

    func testNonAlcoholicNeverEntersTheEditableSet() {
        let s = session(["MOCKTAILS", "Virgin Mojito $7"])
        XCTAssertTrue(s.drinks.isEmpty)                        // no id exists to price it
        XCTAssertEqual(s.excludedNonAlcoholic, ["Virgin Mojito"])
    }

    // MARK: - Parity with ValueRanker ordering

    func testRankingOrderMatchesPipeline() {
        let s = session(["WINE", "Cabernet $9", "Moscato $6"])
        XCTAssertEqual(s.rankedDrinks.map { $0.drink.name }, ["Cabernet", "Moscato"])
        XCTAssertEqual(s.rankedDrinks[0].rank, 1)
        XCTAssertEqual(s.rankedDrinks[1].rank, 2)
    }

    func testMetricSwitchRecomputesValues() {
        var s = session(["WINE", "Cabernet $9"])
        let drinksPerDollar = s.rankedDrinks[0].value
        s.metric = .caloriesPerDollar
        let caloriesPerDollar = s.rankedDrinks[0].value
        XCTAssertNotEqual(drinksPerDollar, caloriesPerDollar)
        XCTAssertGreaterThan(caloriesPerDollar, 0)
    }
}