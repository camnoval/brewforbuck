//
//  MenuParserConfidenceTests.swift
//  Core
//
//  Created by Noval, Cameron on 9/1/26.
//


import XCTest
@testable import CoreServices
import CoreModel

/// Real-world junk filtering (from the M/G and El Perrito dumps): a section label that grabbed a
/// price must stay a header, and lowercase recipe/promo/fragment lines must not rank — they lose
/// their price and fall to the visible "Not sure" bucket instead of polluting the ranking.
final class MenuParserConfidenceTests: XCTestCase {
    private let parser = MenuParser()

    // MARK: section labels

    func testSectionLabelWithTrailingNumberIsHeaderNotDrink() {
        // El Perrito: "SHOTS 4" was ranking as a $4 drink named SHOTS.
        let items = parser.parse(["SHOTS 4", "Mexican Candy Shot"])
        XCTAssertFalse(items.contains { $0.name.uppercased().contains("SHOTS") },
                       "a bare section label must not become a ranked item")
        let shot = items.first { $0.name == "Mexican Candy Shot" }
        XCTAssertEqual(shot?.price, Price(dollars: 4), "the label's price is inherited by its items")
        XCTAssertEqual(shot?.category, .shot)
    }

    func testSectionLabelWithPriceEachIsHeader() {
        let items = parser.parse(["SHOTS $6 each", "Tequila Slammer"])
        XCTAssertFalse(items.contains { $0.name.uppercased() == "SHOTS" })
        XCTAssertEqual(items.first { $0.name == "Tequila Slammer" }?.price, Price(dollars: 6))
    }

    func testTwoWordSectionLabelIsHeader() {
        let items = parser.parse(["Specialty Cocktails", "Mission Margarita $12"])
        XCTAssertFalse(items.contains { $0.name.lowercased().contains("specialty") })
        XCTAssertEqual(items.first { $0.name == "Mission Margarita" }?.price, Price(dollars: 12))
    }

    // MARK: name confidence

    func testLowercaseRecipeLineWithPriceRoutesToNeedsPrice() {
        // "fresh strawberry puree..." style ingredient line that happened to catch a price.
        let items = parser.parse(["fresh squeezed lime juice $5"])
        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items.first?.price, "a lowercase recipe line must not keep a price (→ needsPrice)")
    }

    func testImperativePromoLineIsNotRanked() {
        for line in ["make it spicy - 2", "For $19.95 get any burger", "add protein $6"] {
            let items = parser.parse([line])
            XCTAssertTrue(items.allSatisfy { $0.price == nil }, "promo line should not rank: \(line)")
        }
    }

    func testCapitalizedTitlesStillRank() {
        // Regression guard: the working menus' titles are all capitalized and must keep their price.
        let cases: [(String, Double)] = [
            ("Coors Light $5", 5), ("House Manhattan $13", 13),
            ("Mission Margarita $12", 12), ("Orange Crush $12", 12),
        ]
        for (line, dollars) in cases {
            let items = parser.parse([line])
            XCTAssertEqual(items.first?.price, Price(dollars: dollars), "should rank: \(line)")
        }
    }

    func testAllCapsBrandLineStillRanks() {
        let items = parser.parse(["COORS LIGHT 22oz. ABV 4.2% - 5"])
        XCTAssertEqual(items.first?.price, Price(dollars: 5))
        XCTAssertEqual(items.first?.name, "COORS LIGHT")
    }
}