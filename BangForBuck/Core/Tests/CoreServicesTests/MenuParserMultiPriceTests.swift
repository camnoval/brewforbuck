//
//  MenuParserMultiPriceTests.swift
//  Core
//
//  Created by Noval, Cameron on 8/30/26.
//


import XCTest
@testable import CoreServices
import CoreModel

/// Multi-price lines (Decision: one ranked row per size). A single OCR line that lists several
/// size/price pairs must become one `MenuItem` per size, each with its own price and volume, so the
/// ranker can score a glass and a bottle separately. Single-price lines must be untouched.
final class MenuParserMultiPriceTests: XCTestCase {
    private let parser = MenuParser()

    private func floz(_ v: Volume?) -> Double { v?.fluidOunces ?? -1 }

    func testWineGlassBottleByKeyword() {
        let items = parser.parse(["House Cabernet glass $9 bottle $32"])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].name, "House Cabernet (glass)")
        XCTAssertEqual(items[0].price, Price(dollars: 9))
        XCTAssertEqual(floz(items[0].readSize), 5.0, accuracy: 0.001)
        XCTAssertEqual(items[1].name, "House Cabernet (bottle)")
        XCTAssertEqual(items[1].price, Price(dollars: 32))
        XCTAssertEqual(floz(items[1].readSize), 25.36, accuracy: 0.001)
    }

    /// Two prices, no size words: smaller is a glass, larger is a bottle.
    func testWineTwoPricesNoCuesFallsBackToGlassBottle() {
        let items = parser.parse(["Pinot Noir $11 $40"])
        XCTAssertEqual(items.map(\.name), ["Pinot Noir (glass)", "Pinot Noir (bottle)"])
        XCTAssertEqual(items[0].price, Price(dollars: 11))
        XCTAssertEqual(items[1].price, Price(dollars: 40))
        XCTAssertEqual(floz(items[0].readSize), 5.0, accuracy: 0.001)
        XCTAssertEqual(floz(items[1].readSize), 25.36, accuracy: 0.001)
    }

    /// The size word can trail its price ("$9 glass"), not only lead it.
    func testLabelAfterPrice() {
        let items = parser.parse(["Chardonnay $9 glass $32 bottle"])
        XCTAssertEqual(items.map(\.name), ["Chardonnay (glass)", "Chardonnay (bottle)"])
        XCTAssertEqual(items[0].price, Price(dollars: 9))
        XCTAssertEqual(items[1].price, Price(dollars: 32))
    }

    func testBeerSizeGridWithExplicitOunces() {
        let items = parser.parse(["Bud Light 12oz $4 16oz $6 22oz $8"])
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.map(\.name), ["Bud Light (12 oz)", "Bud Light (16 oz)", "Bud Light (22 oz)"])
        XCTAssertEqual(floz(items[0].readSize), 12, accuracy: 0.001)
        XCTAssertEqual(floz(items[1].readSize), 16, accuracy: 0.001)
        XCTAssertEqual(floz(items[2].readSize), 22, accuracy: 0.001)
        XCTAssertEqual(items[2].price, Price(dollars: 8))
    }

    /// A normal single-price line is unaffected: exactly one item, no size suffix.
    func testSinglePriceLineIsUnchanged() {
        let items = parser.parse(["The Best Margarita $13"])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "The Best Margarita")
        XCTAssertEqual(items[0].price, Price(dollars: 13))
    }

    /// A priceless ingredient line is not mistaken for a multi-price drink.
    func testNoPriceLineProducesNoMultiSplit() {
        let split = MenuParser.splitMultiPrice("Sauza blanco, Cointreau, fresh lime")
        XCTAssertTrue(split.isEmpty)
    }
}