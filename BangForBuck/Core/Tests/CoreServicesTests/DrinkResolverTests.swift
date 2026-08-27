//
//  DrinkResolverTests.swift
//  Core
//
//  Created by Noval, Cameron on 8/27/26.
//


import XCTest
@testable import CoreServices
@testable import CoreModel
@testable import CoreContracts

/// Mirrors `DrinkResolver` (§8): one parsed item → an alcoholic `EditableDrink` or a
/// non-alcoholic exclusion, with ABV/size provenance resolved via the real knowledge layer.
final class DrinkResolverTests: XCTestCase {
    private let knowledge = StaticBeverageKnowledge()

    func testNonAlcoholicBrandIsExcludedEvenInABeerSection() {
        let item = MenuItem(name: "Heineken 0.0", price: Price(dollars: 6), category: .bottledBeer)
        let (drink, excluded) = DrinkResolver.resolve(item, id: 0, knowledge: knowledge)
        XCTAssertNil(drink)                       // Change B: never becomes editable/rankable
        XCTAssertEqual(excluded, "Heineken 0.0")
    }

    func testPrintedABVResolvesAsRead() {
        let item = MenuItem(name: "Hazy IPA", price: Price(dollars: 7), readABV: 6.8, category: .draftBeer)
        let (drink, excluded) = DrinkResolver.resolve(item, id: 0, knowledge: knowledge)
        XCTAssertNil(excluded)
        XCTAssertEqual(drink?.abv.value, 6.8)
        XCTAssertEqual(drink?.abv.isEstimated, false)   // menu printed it ⇒ .read
    }

    func testMissingABVResolvesAsEstimatedWithNote() {
        let item = MenuItem(name: "Cabernet", price: Price(dollars: 9), category: .wineGlass)
        let (drink, _) = DrinkResolver.resolve(item, id: 0, knowledge: knowledge)
        XCTAssertEqual(drink?.abv.value, 14.0)          // style-chart seed for Cabernet
        XCTAssertEqual(drink?.abv.isEstimated, true)
        XCTAssertNotNil(drink?.abv.note)                // the assumption is surfaced (§11)
    }

    func testPricelessItemIsKeptAsNeedsPriceNotExcluded() {
        let item = MenuItem(name: "Margarita", price: nil, category: .cocktail)
        let (drink, excluded) = DrinkResolver.resolve(item, id: 0, knowledge: knowledge)
        XCTAssertNil(excluded)
        XCTAssertEqual(drink?.needsPrice, true)
        XCTAssertNil(drink?.price)
    }
}