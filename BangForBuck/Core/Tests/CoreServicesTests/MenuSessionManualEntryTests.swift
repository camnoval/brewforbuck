//
//  MenuSessionManualEntryTests.swift
//  Core
//
//  Created by Noval, Cameron on 8/27/26.
//


import XCTest
@testable import CoreServices
@testable import CoreModel

/// Manual add/remove on `MenuSession` (§8): the user adds a beer the scan missed or removes a line
/// that wasn't really a drink. Proves the ranking updates and the invariants (§10, Change B) hold.
final class MenuSessionManualEntryTests: XCTestCase {
    private let pipeline = MenuPipeline()

    private func session(_ lines: [String]) -> MenuSession {
        pipeline.makeSession(lines: lines, metric: .standardDrinksPerDollar)
    }

    func testAddDrinkWithPriceEntersRanking() {
        var s = session(["WINE", "Cabernet $9"])
        let baseline = s.rankedDrinks.count

        let id = s.addDrink(name: "Manual IPA", abv: 7, sizeFluidOunces: 16, priceDollars: 6)
        XCTAssertNotNil(id)
        XCTAssertEqual(s.rankedDrinks.count, baseline + 1)

        let added = s.rankedDrinks.first { $0.drink.name == "Manual IPA" }
        XCTAssertNotNil(added)
        XCTAssertEqual(added?.value ?? 0, 0.31111, accuracy: 0.0005)   // (16×7%)/0.6/6
        XCTAssertFalse(added?.drink.hasEstimate ?? true)              // user-supplied ⇒ all .read
    }

    func testAddDrinkWithoutPriceGoesToNeedsPrice() {
        var s = session(["WINE", "Cabernet $9"])
        let id = s.addDrink(name: "Mystery Lager", abv: 5, sizeFluidOunces: 12, priceDollars: nil)
        XCTAssertNotNil(id)
        XCTAssertTrue(s.needsPriceDrinks.contains { $0.name == "Mystery Lager" })
        XCTAssertFalse(s.rankedDrinks.contains { $0.drink.name == "Mystery Lager" })
    }

    func testBlankNameIsRejected() {
        var s = session(["WINE", "Cabernet $9"])
        let before = s.drinks.count
        XCTAssertNil(s.addDrink(name: "   ", abv: 5, sizeFluidOunces: 12, priceDollars: 6))
        XCTAssertEqual(s.drinks.count, before)
    }

    func testManualAddGetsUniqueIdAndIsRemovable() {
        var s = session(["WINE", "Cabernet $9"])
        let id = s.addDrink(name: "Manual IPA", abv: 7, sizeFluidOunces: 16, priceDollars: 6)!
        XCTAssertFalse(s.drinks.contains { $0.id == 0 && $0.name == "Manual IPA" }) // id 0 is Cabernet
        s.removeDrink(id: id)
        XCTAssertFalse(s.drinks.contains { $0.id == id })
        XCTAssertFalse(s.rankedDrinks.contains { $0.drink.name == "Manual IPA" })
    }

    func testRemovingAParsedDrinkDropsItFromRanking() {
        var s = session(["WINE", "Cabernet $9"])
        XCTAssertTrue(s.rankedDrinks.contains { $0.drink.name == "Cabernet" })
        s.removeDrink(id: 0)
        XCTAssertFalse(s.rankedDrinks.contains { $0.drink.name == "Cabernet" })
    }

    // Change B: a manual add can't smuggle a non-alcoholic item into the ranking — the category is
    // coerced to alcoholic, so the drink ranks rather than being silently dropped.
    func testNonAlcoholicCategoryIsCoercedSoManualAddStillRanks() {
        var s = session(["WINE", "Cabernet $9"])
        let id = s.addDrink(name: "Added", abv: 5, sizeFluidOunces: 12, priceDollars: 6,
                            category: .nonAlcoholic)!
        let added = s.drinks.first { $0.id == id }
        XCTAssertEqual(added?.category, .unknown)
        XCTAssertTrue(s.rankedDrinks.contains { $0.drink.id == id })
    }
}