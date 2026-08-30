//
//  MenuParserSectionTests.swift
//  Core
//
//  Created by Noval, Cameron on 8/30/26.
//


import XCTest
@testable import CoreServices
import CoreContracts
import CoreModel

/// Section-header handling and non-alcoholic exclusion, driven by the real failing menus:
/// dotted section totals (Exclusive Drink Menu), singular headers + slash prices (the Reservoir),
/// and "N/A" beers that must never rank as alcohol.
final class MenuParserSectionTests: XCTestCase {
    private let parser = MenuParser()

    // MARK: - Dotted section totals ("COCKTAILS........$13")

    func testDotLeaderHeaderPriceIsInherited() {
        let items = parser.parse([
            "COCKTAILS...........$13",
            "House Old Fashion",
            "House Manhattan",
            "WINES.......$8",
            "Sean Minor Cabernet",
        ])
        // The header lines are consumed, not turned into items.
        XCTAssertFalse(items.contains { $0.name == "COCKTAILS" || $0.name == "WINES" })
        // Items inherit their section's price and category.
        let oldFashion = items.first { $0.name == "House Old Fashion" }
        XCTAssertEqual(oldFashion?.price, Price(dollars: 13))
        XCTAssertEqual(oldFashion?.category, .cocktail)
        let cabernet = items.first { $0.name == "Sean Minor Cabernet" }
        XCTAssertEqual(cabernet?.price, Price(dollars: 8))
        XCTAssertEqual(cabernet?.category, .wineGlass)
    }

    /// A priced item that merely contains a header keyword (and no dot leaders/pipe) is still an item.
    func testPricedKeywordItemIsNotMistakenForHeader() {
        let items = parser.parse(["Signature Margarita $13"])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "Signature Margarita")
        XCTAssertEqual(items[0].price, Price(dollars: 13))
    }

    // MARK: - Singular headers + slash prices (the Reservoir)

    func testSingularHeadersAndSlashPrices() {
        let items = parser.parse([
            "DOMESTIC",
            "Miller High Life 16oz / 6",
            "IMPORT",
            "Corona / 6",
        ])
        let miller = items.first { $0.name == "Miller High Life" }
        XCTAssertNotNil(miller, "name should be cleaned of size and slash")
        XCTAssertEqual(miller?.price, Price(dollars: 6))
        XCTAssertEqual(miller?.category, .bottledBeer)
        XCTAssertEqual(items.first { $0.name == "Corona" }?.category, .bottledBeer)
    }

    // MARK: - Non-alcoholic exclusion

    func testLooksNonAlcoholicMarkers() {
        XCTAssertTrue(MenuParser.looksNonAlcoholic("Gruvi IPA N/A beer / 7"))
        XCTAssertTrue(MenuParser.looksNonAlcoholic("Corona N/A"))
        XCTAssertTrue(MenuParser.looksNonAlcoholic("Athletic Brewing Non Alcoholic"))
        XCTAssertFalse(MenuParser.looksNonAlcoholic("Mike's Zero Sugar"))   // alcoholic seltzer
        XCTAssertFalse(MenuParser.looksNonAlcoholic("Coors Light"))
    }

    func testNAItemIsTaggedNonAlcoholicAndExcludedByResolver() {
        let items = parser.parse(["Gruvi IPA N/A beer / 7"])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].category, .nonAlcoholic)

        // Resolver must exclude it even though the name contains the alcoholic style "IPA".
        let (drink, excludedName) = DrinkResolver.resolve(items[0], id: 1, knowledge: StaticBeverageKnowledge())
        XCTAssertNil(drink)
        XCTAssertEqual(excludedName, items[0].name)
    }
}