import XCTest
@testable import CoreServices
import CoreModel

/// Real-world junk filtering (from the M/G and El Perrito dumps): a section label that grabbed a
/// price stays a header, and promo/recipe/fragment lines don't rank — they lose their price and fall
/// to the visible "Not sure" bucket. The gate is deliberately **casing-independent**: a bar that
/// lowercases its menu must still rank (capitalization is not a signal).
final class MenuParserConfidenceTests: XCTestCase {
    private let parser = MenuParser()

    // MARK: casing independence (the reason we dropped the capitalization gate)

    func testLowercaseStyledMenuStillRanks() {
        for line in ["modelo $6", "coors light $5", "sierra nevada hazy little thing ipa $7"] {
            let items = parser.parse([line])
            XCTAssertNotNil(items.first?.price, "lowercase-styled drink must still rank: \(line)")
        }
    }

    func testSizeOnlyPriceRowDoesNotRank() {
        // "glass $13 | pitcher $45" style stray price row with no drink title on the line.
        let items = parser.parse(["glass $13"])
        XCTAssertTrue(items.allSatisfy { $0.price == nil })
    }

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

    // MARK: food & URLs are dropped entirely

    func testFoodSectionIsDroppedButDrinksResume() {
        let items = parser.parse([
            "FOOD", "Parmesan Fries $8", "Chicken Bites $12",
            "COCKTAILS", "Mission Margarita $12",
        ])
        XCTAssertFalse(items.contains { $0.name.lowercased().contains("fries") })
        XCTAssertFalse(items.contains { $0.name.lowercased().contains("bites") })
        XCTAssertEqual(items.first { $0.name == "Mission Margarita" }?.price, Price(dollars: 12),
                       "a drink section after FOOD must resume ranking")
    }

    func testStrayFoodLineDropped() {
        for line in ["Buffalo Wings $12", "Loaded Tots $9", "Cheeseburger Sliders (3) $13"] {
            XCTAssertTrue(parser.parse([line]).isEmpty, "food should be dropped: \(line)")
        }
    }

    func testURLDropped() {
        XCTAssertTrue(parser.parse(["WWW.ELFERRITOATX.COM"]).isEmpty)
    }

    func testBeerNamedForTacosIsNotDroppedAsFood() {
        // Real beer: Off Color "Beer for Tacos" — must survive (we exclude taco/beer from food words).
        let items = parser.parse(["Off Color Beer for Tacos / 7"])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.price, Price(dollars: 7))
        XCTAssertTrue(items.first?.name.contains("Tacos") ?? false)
    }
}
