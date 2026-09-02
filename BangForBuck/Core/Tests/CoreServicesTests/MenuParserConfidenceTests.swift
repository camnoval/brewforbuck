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

    // MARK: superscript-cent prices (the M/G menu prints cents as tiny superscripts; Vision mangles
    // them into "$8°5", "$10$5", "$1055", or bare "1025 1325 2825")

    func testGluedSuperscriptCentPriceTakesDollarsAndFreesTheName() {
        // "$10$5" used to read as $5 with a stranded "$10" polluting the name.
        let item = parser.parse(["High Noon Pineapple 12oz $10$5"]).first
        XCTAssertEqual(item?.price, Price(dollars: 10))
        XCTAssertEqual(item?.name, "High Noon Pineapple")   // clean name → resolves to the known brand
        XCTAssertEqual(parser.parse(["Miller Lite 16oz $8°5"]).first?.price, Price(dollars: 8))
    }

    func testFourDigitCentsAreDollarsAndCents() {
        XCTAssertEqual(parser.parse(["Surfside Iced Tea Lemonade Vodka $1055"]).first?.price,
                       Price(dollars: 10.55))
    }

    func testBareFourDigitMultiPriceTakesFirstServing() {
        // Guinness "Stout...1025 | 1325 | 2825" → $10.25 (not a literal $2825), name stays clean.
        let item = parser.parse(["Guinness Stout...1025 | 1325 | 2825"]).first
        XCTAssertEqual(item?.price, Price(dollars: 10.25))
        XCTAssertEqual(item?.name, "Guinness Stout")
    }

    func testRealThreeDigitPriceIsNotHalved() {
        // A genuine 3-digit price (champagne) must survive intact — only 4-digit runs are cents.
        XCTAssertEqual(parser.parse(["Moët Impérial Brut $150"]).first?.price, Price(dollars: 150))
    }

    // MARK: shared size/price grid → section price the listed drinks inherit

    func testBareSizePriceGridPricesTheDraftsBelow() {
        // The DRAFTS section: a nameless "16oz $7 | 22oz $12 | Pitcher $25" grid prices every draft
        // listed under it, none of which carries its own price.
        let items = parser.parse([
            "DRAFTS",
            "16oz $7 | 22oz $12 | Pitcher $25",
            "Pacifico Clara",
            "Stella Artois",
        ])
        let pacifico = items.first { $0.name.contains("Pacifico") }
        let stella = items.first { $0.name.contains("Stella") }
        XCTAssertEqual(pacifico?.price, Price(dollars: 7), "draft inherits the grid's single-serving price")
        XCTAssertEqual(stella?.price, Price(dollars: 7))
        XCTAssertEqual(pacifico?.category, .draftBeer)
        // The grid line itself is not emitted as a bogus "$7" drink.
        XCTAssertFalse(items.contains { $0.name.contains("16oz") || $0.name.contains("Pitcher") })
    }

    func testBareWineSubLabelDoesNotRankOnInheritedPrice() {
        // Under a "glass $14 | bottle $58" wine price, a stray "whites"/"reds" sub-label must not
        // rank as a $14 drink.
        let items = parser.parse([
            "Wine",
            "glass $14 | bottle $58",
            "whites",
            "Kim Crawford Sauv Blanc",
        ])
        XCTAssertNil(items.first { $0.name.lowercased() == "whites" }?.price)
        XCTAssertEqual(items.first { $0.name.contains("Kim Crawford") }?.price, Price(dollars: 14))
    }

    // MARK: name-then-price cocktails (price line FOLLOWS the name) vs grid-leads-list

    func testCocktailPriceLineBackfillsOntoPrecedingNameNotTheNext() {
        // The M/G Specialty layout: each cocktail is a name line then its own "glass|pitcher" price
        // line. The price must attach to the name above it — and must NOT leak onto the next cocktail.
        let items = parser.parse([
            "Specialty Cocktails",
            "Tito's Paloma",
            "glass $13 | pitchor $45",
            "Full Bloom",
            "glass $1s\"",                 // OCR'd $15 (superscript 5 read as 's')
            "Strawberry Fields",
            "glass $14 | pitcher $49",
        ])
        XCTAssertEqual(items.first { $0.name.contains("Paloma") }?.price, Price(dollars: 13))
        XCTAssertEqual(items.first { $0.name.contains("Full Bloom") }?.price, Price(dollars: 15))
        // The bug this guards: Strawberry Fields used to inherit the previous line's $1, not its $14.
        XCTAssertEqual(items.first { $0.name.contains("Strawberry Fields") }?.price, Price(dollars: 14))
        // "gloss"/"pitchor" (OCR vessel words) never rank as their own drink.
        XCTAssertFalse(items.contains { $0.name.lowercased().hasPrefix("gloss") || $0.name.lowercased() == "pitchor" })
    }

    func testGridLeadingAListStillForwardInherits() {
        // The opposite layout (grid first, then the priced-together list) must still forward-inherit.
        let items = parser.parse([
            "Happy Hour Cocktails",
            "glass $9 | pitcher $35",
            "Strawberry Fields",
            "Mission Margarita",
        ])
        XCTAssertEqual(items.first { $0.name.contains("Strawberry") }?.price, Price(dollars: 9))
        XCTAssertEqual(items.first { $0.name.contains("Mission") }?.price, Price(dollars: 9))
    }
}
