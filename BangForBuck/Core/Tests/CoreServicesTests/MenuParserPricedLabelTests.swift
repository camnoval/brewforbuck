//
//  MenuParserPricedLabelTests.swift
//  Core
//
//  Created by Noval, Cameron on 9/7/26.
//

import XCTest
@testable import CoreServices
import CoreContracts
import CoreModel

/// A section label that carries its own prices sets a **section price**, it does not become drinks (D).
///
/// `WHITES - $9 GLASS / $82 BOTTLE` used to split into two ranked items called "WHITES (glass)" at
/// $9 and "WHITES (bottle)", while every wine underneath it stayed unpriced. Rullo's
/// `Red | $11/ $40` did the same. The parser was already inconsistent here: `Rosé | $10 / $35`
/// inherited correctly, because "rosé" was in the header vocabulary while `red` / `white` were not.
///
/// The fix is a **token-exact** pure-label path. Token-exact is load-bearing: `red` and `white` sit
/// inside `Allagash White`, `Fire Red Ale`, `White Claw` and `Wente Mt. Diablo Red Blend`, so as
/// substrings they would turn a beer list into wine sections. Both directions are pinned below.
final class MenuParserPricedLabelTests: XCTestCase {
    private let parser = MenuParser()

    // MARK: - The bug

    /// Menu 8. The label prices the section; the wines below inherit it.
    func testPricedWineLabelSetsTheSectionPrice() {
        let items = parser.parse([
            "WHITES - $9 GLASS / $82 BOTTLE",
            "Kim Crawford Sauvignon Blanc",
            "REDS - $9 GLASS / $82 BOTTLE",
            "Wente Mt. Diablo Red Blend",
        ])
        // The label is consumed, not ranked as a drink.
        XCTAssertFalse(items.contains { $0.name.contains("WHITES") || $0.name.contains("REDS") })
        for name in ["Kim Crawford Sauvignon Blanc", "Wente Mt. Diablo Red Blend"] {
            let wine = items.first { $0.name == name }
            XCTAssertEqual(wine?.price, Price(dollars: 9), "\(name) inherits the glass price")
            XCTAssertEqual(wine?.category, .wineGlass)
        }
    }

    /// Menu 3 (Rullo's). The single-serving price is the one that carries.
    func testPipedWineColourLabelSetsTheSectionPrice() {
        let items = parser.parse([
            "Red | $11/ $40",
            "Bogle Old Vine Zinfandel",
            "White | $12 / $44",
            "Placido Pinot Grigio",
        ])
        XCTAssertFalse(items.contains { $0.name == "Red" || $0.name == "White" })
        XCTAssertFalse(items.contains { $0.name.contains("(glass)") || $0.name.contains("(bottle)") })
        XCTAssertEqual(items.first { $0.name == "Bogle Old Vine Zinfandel" }?.price, Price(dollars: 11))
        XCTAssertEqual(items.first { $0.name == "Placido Pinot Grigio" }?.price, Price(dollars: 12))
    }

    /// `Rosé` already worked; it must keep working through the new path.
    func testRoseLabelStillInherits() {
        let items = parser.parse(["Rosé | $10 / $35", "Whispering Angel"])
        XCTAssertEqual(items.first { $0.name == "Whispering Angel" }?.price, Price(dollars: 10))
        XCTAssertEqual(items.first { $0.name == "Whispering Angel" }?.category, .wineGlass)
    }

    // MARK: - A vessel names how a section is served, not what it is

    /// Menu 5's wine grid. These rows carry a vessel and a number but no section word, so they are
    /// size/price rows — not a Bottled Beer section priced at $25.
    func testVesselOnlyRowsAreNotHeaders() {
        for line in ["Glass 12 Bottle 40", "Bottle 25", "Glass 14 Bottie 48"] {
            XCTAssertNil(MenuParser.sectionHeader(line), "\(line) is a size/price row")
            XCTAssertNil(MenuParser.pureLabelCategory(line), "a vessel names no category")
        }
    }
    
    /// A vessel beside a real section word is filler, which is what lets the menu-8 label parse.
    func testVesselIsFillerInsideARealLabel() {
        XCTAssertTrue(MenuParser.isPureSectionLabel("WHITES - $9 GLASS / $82 BOTTLE"))
        // `Glass 12 Bottle 40` also passes `isPureSectionLabel`, because "bottle" is a section word
        // in its own right. That is fine, and it is NOT what keeps the row out of the header path —
        // `pureLabelCategory` is, by omitting vessel singulars. Pinning that distinction here,
        // because conflating the two is the easy way to break D.
        XCTAssertTrue(MenuParser.isPureSectionLabel("Glass 12 Bottle 40"))
        XCTAssertNil(MenuParser.pureLabelCategory("Glass 12 Bottle 40"),
                     "a vessel names no category, so the row is a size grid")
    }

    // MARK: - Token-exact: a colour inside a name is not a label

    func testColourInsideADrinkNameIsNotASection() {
        for line in ["Allagash White", "Fire Red Ale", "Wente Mt. Diablo Red Blend",
                     "White Claw $8", "Strawberry Rose Sangria 3", "Westfalia Red Ale (5.6%) 8"] {
            XCTAssertNil(MenuParser.sectionHeader(line), "\(line) is a drink, not a section")
        }
    }

    func testWhiteClawStaysAPricedItem() {
        let items = parser.parse(["SELTZERS", "White Claw $8", "High Noon $9"])
        let claw = items.first { $0.name.contains("White Claw") }
        XCTAssertEqual(claw?.price, Price(dollars: 8))
        XCTAssertEqual(claw?.category, .seltzer)
    }

    // MARK: - Bare colour sub-labels

    /// Menu 7. `red` and `white` alone under WINE are sub-labels, not drinks — and being sub-labels
    /// they must not reset the shared by-the-glass price.
    func testBareColourSubLabelDoesNotResetTheSectionPrice() {
        let items = parser.parse([
            "Wine",
            "glass $14 | bottle $58",
            "red",
            "Cline Sonoma County Zinfandel",
            "white",
            "The Crossings Sauvignon Blanc",
        ])
        XCTAssertFalse(items.contains { $0.name == "red" || $0.name == "white" },
                       "a bare colour is a sub-label, never a ranked drink")
        for name in ["Cline Sonoma County Zinfandel", "The Crossings Sauvignon Blanc"] {
            XCTAssertEqual(items.first { $0.name == name }?.price, Price(dollars: 14),
                           "\(name) keeps the section's glass price")
        }
    }

    // MARK: - Priority is unchanged

    /// The token-exact path walks the same group order as `headerKeywords`, so multi-word labels
    /// resolve the way they always did.
    func testLabelPriorityMatchesTheKeywordOrder() {
        let expected: [(String, BeverageCategory)] = [
            ("BOTTLES CANS", .bottledBeer),   // bottles wins over cans
            ("CANS", .seltzer),
            ("DRAFT BEER", .draftBeer),
            ("SHOTS 4", .shot),
            ("WINE", .wineGlass),
            ("Cocktails | $10", .cocktail),
        ]
        for (line, category) in expected {
            XCTAssertEqual(MenuParser.sectionHeader(line)?.0, category, "\(line)")
        }
        XCTAssertEqual(MenuParser.sectionHeader("SHOTS 4")?.1, Price(dollars: 4))
    }
}
