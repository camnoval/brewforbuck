//
//  MenuParserHeaderProseTests.swift
//  Core
//
//  Created by Noval, Cameron on 9/7/26.
//


import XCTest
@testable import CoreServices
import CoreContracts
import CoreModel

/// A line that *mentions* a style is not the section header for that style (F).
///
/// The keyword match is a substring test, so any recipe or blurb naming a style used to reset the
/// category. Measured across all eight OCR dumps, 59 keyword matches drop to 43, removing 16
/// prose/item false positives on 7 of 8 menus and losing no real header. Every line below is taken
/// verbatim from a dump; the header-vs-prose call is the thing under test, so both directions are
/// pinned.
final class MenuParserHeaderProseTests: XCTestCase {
    private let parser = MenuParser()

    // MARK: - The damage the gate exists to stop

    /// Menu 4. `sparkling water, honey` is the tail of the BEE'S KNEES recipe. As a Wine header it
    /// re-categorized every cocktail below it, which is what ranked four cocktails as 12% wine.
    func testRecipeTailDoesNotRecategorizeTheCocktailsBelowIt() {
        let items = parser.parse([
            "COCKTAILS",
            "BEE'S KNEES 13",
            "peloton mezcal, herbal liquer, lemon,",
            "sparkling water, honey",
            "OLD FASHIONED 14",
            "MANHATTAN 14",
            "NERONI 14",
            "SCOTCH HIGHBALL 13",
        ])
        for name in ["OLD FASHIONED", "MANHATTAN", "NERONI", "SCOTCH HIGHBALL"] {
            let item = items.first { $0.name == name }
            XCTAssertEqual(item?.category, .cocktail, "\(name) is a cocktail, not wine")
        }
    }

    /// Menu 7. Four blurb lines under the beach-house list each mention "frozen"; as headers they
    /// put the whole list under `frozenCocktail`.
    func testBlurbLinesDoNotOpenAFrozenSection() {
        let items = parser.parse([
            "cocktails",
            "beach house cocktails reflect our love for",
            "coconut and 151, frozen and topped",
            "served on the rocks or frozen with pink",
            "PAINKILLER 14",
        ])
        XCTAssertEqual(items.first { $0.name == "PAINKILLER" }?.category, .cocktail)
    }

    /// Menu 3. A bulleted ingredient run ends in "Egg Whites", and "whites" is a wine sub-label.
    func testBulletedIngredientsDoNotOpenAWineSection() {
        let items = parser.parse([
            "Elixirs | $14",
            "Mr. Pink",
            "• Pineapple • Lime • Egg Whites",
            "I Choose Yuzu",
        ])
        XCTAssertEqual(items.first { $0.name == "I Choose Yuzu" }?.category, .cocktail)
    }

    /// Menus 5 and 8. A printed percentage is something an item says about itself.
    func testPrintedABVMeansItemNotHeader() {
        for line in ["Mighty Dry Cider (6%)", "Downeast Seasonal (Cider) - 5.0%ABV"] {
            XCTAssertNil(MenuParser.sectionHeader(line), "\(line) is an item, not a section header")
        }
    }

    /// Menu 8. A full sentence naming a style is a description.
    func testProseSentenceIsNotAHeader() {
        XCTAssertNil(MenuParser.sectionHeader("Rotating flavors of world class unfiltered ciders."))
    }

    // MARK: - Real headers must survive

    /// Every genuine header in the corpus, including the two that carry the maximum modifiers.
    func testRealHeadersStillClassify() {
        let expected: [(String, BeverageCategory)] = [
            ("CANS", .seltzer),
            ("CRAFT BOTTLES", .bottledBeer),
            ("BIG BREWERY BOTTLES", .bottledBeer),
            ("TALL BOY CANS", .bottledBeer),
            ("BOTTLES CANS", .bottledBeer),
            ("DOMESTICS", .bottledBeer),
            ("Imports", .bottledBeer),
            ("WINE", .wineGlass),
            ("house wine", .wineGlass),
            ("Sparkling", .wineGlass),
            ("CIDER/CIDRE", .cider),
            ("ON TAP", .draftBeer),
            ("DRAFT BEER", .draftBeer),
            ("house brews on tap", .draftBeer),
            ("bottles/cans", .bottledBeer),
            ("SELTZERS/", .seltzer),
            ("CANNED COCKTAILS", .seltzer),
            ("NON-ALCOHOLIC", .nonAlcoholic),
            ("mocktails", .nonAlcoholic),
            ("COCKTAILS", .cocktail),
            ("Elixirs", .cocktail),
        ]
        for (line, category) in expected {
            XCTAssertEqual(MenuParser.sectionHeader(line)?.0, category,
                           "\(line) is a real section header")
        }
    }

    /// A priced header carries a price and a pipe, neither of which may read as prose.
    func testPricedHeadersStillInheritTheirPrice() {
        let items = parser.parse([
            "Cocktails | $10",
            "The Jesuit",
            "Sparkling | $10 / $35",
            "Cantine Maschio Prosecco",
        ])
        XCTAssertEqual(items.first { $0.name == "The Jesuit" }?.price, Price(dollars: 10))
        XCTAssertEqual(items.first { $0.name == "The Jesuit" }?.category, .cocktail)
        XCTAssertEqual(items.first { $0.name == "Cantine Maschio Prosecco" }?.category, .wineGlass)
    }

    /// `SHOTS 4` is a bare section label plus a price; it reaches the keyword loop by a different
    /// route and must not be caught by the modifier count.
    func testBareSectionLabelWithPriceIsStillAHeader() {
        XCTAssertEqual(MenuParser.sectionHeader("SHOTS 4")?.0, .shot)
        XCTAssertEqual(MenuParser.sectionHeader("SHOTS $6 each")?.0, .shot)
    }

    // MARK: - Casing is deliberately not a signal (real bars lowercase their menus)

    func testGateIsCasingIndependent() {
        let headers = ["CRAFT BOTTLES", "BIG BREWERY BOTTLES", "ON TAP", "CIDER/CIDRE"]
        for line in headers {
            XCTAssertEqual(MenuParser.sectionHeader(line)?.0,
                           MenuParser.sectionHeader(line.lowercased())?.0,
                           "\(line) must classify the same lowercased")
        }
        let prose = ["sparkling water, honey", "Rotating flavors of world class unfiltered ciders."]
        for line in prose {
            XCTAssertNil(MenuParser.sectionHeader(line.uppercased()))
            XCTAssertNil(MenuParser.sectionHeader(line.lowercased()))
        }
    }

    // MARK: - The rule itself

    func testModifierCeilingIsTwo() {
        // Two qualifiers around the head noun is a label.
        XCTAssertTrue(MenuParser.isPlausibleHeader("BIG BREWERY BOTTLES", keyword: "bottles"))
        // Three is a phrase.
        XCTAssertFalse(MenuParser.isPlausibleHeader("Nutrl Vodka Seltzer 4.5ABV", keyword: "seltzer"))
    }

    func testCommaAndBulletAreNeverHeaders() {
        XCTAssertFalse(MenuParser.isPlausibleHeader("red sangria, and tresh limes", keyword: "sangria"))
        XCTAssertFalse(MenuParser.isPlausibleHeader("• Truly Hard Seltzer", keyword: "hard seltzer"))
    }
}
