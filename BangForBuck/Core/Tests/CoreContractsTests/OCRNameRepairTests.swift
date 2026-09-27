//
//  OCRNameRepairTests.swift
//  Core
//

import XCTest
@testable import CoreContracts
import CoreModel

/// Every "should repair" case below is a real name from the 09-27 device dump, and every "should
/// not" case is a real line from the same two menus. The false-positive half matters more than the
/// other: a wrong brand match states a specific product's ABV with false confidence, which is worse
/// than the category estimate it replaced.
final class OCRNameRepairTests: XCTestCase {

    private func repaired(_ name: String) -> String? {
        OCRNameRepair.match(for: name)?.label
    }

    func testGlyphConfusionsAreRepaired() {
        XCTAssertEqual(repaired("MICHELOS ULTRA SE"), "Michelob Ultra")        // S for B
        XCTAssertEqual(repaired("GUINESS"), "Guinness")                        // dropped letter
        XCTAssertEqual(repaired("TRUEY WILD BERRY SS"), "Truly")               // L for E
    }

    /// The load-bearing ones: two capitals read as a single glyph. These fold to distance zero, so
    /// they need no fuzziness at all — which is why they're worth folding rather than just
    /// widening an edit-distance threshold.
    func testLigatureConfusionsFoldExactly() {
        XCTAssertEqual(repaired("BUSCHUGHT SE"), "Busch Light")                // LI → U, space lost
        XCTAssertEqual(repaired("DOGRSH HEAD 60 MIN"), "Dogfish Head 60 Minute")  // FI → R
    }

    func testCleanNamesStillMatchExactlyAsBefore() {
        XCTAssertEqual(repaired("ANGRY ORCHARD CRISP APPLE"), "Angry Orchard Crisp Apple")
        XCTAssertEqual(repaired("KONA BIG WAVE"), "Kona Big Wave")
        XCTAssertEqual(repaired("CORONA PREMIER"), "Corona Premier")
        XCTAssertEqual(repaired("BELL'S TWO HEARTED"), "Bell's Two Hearted")
    }

    /// `BUO LIGHT` off a 574 px menu. `LIGHT` folds exactly, so the one edit in `BUO`→`BUD` is
    /// affordable even though a three-letter word normally gets no edits — and that exact anchor is
    /// what keeps the relaxation honest.
    func testAnExactWordPaysForAnEditInItsNeighbour() {
        XCTAssertEqual(repaired("BUO LIGHT"), "Bud Light")
        XCTAssertEqual(repaired("STELLA AXTOIS 3P"), "Stella Artois")
        XCTAssertEqual(repaired("QUINNESS"), "Guinness")
    }

    /// The relaxation must not let a beer become a different beer. Two edits in `BUD`→`BUSCH` is
    /// over the budget however exact the rest of the window is, and a window with no exact word
    /// anywhere is refused rather than assembled out of guesses.
    func testTheRelaxationCannotCrossBetweenBrands() {
        XCTAssertEqual(repaired("BUD LIGHT"), "Bud Light")
        XCTAssertEqual(repaired("BUSCH LIGHT"), "Busch Light")
        XCTAssertNil(repaired("SEIALAMHCAD LLTRA"))   // Michelob Ultra, but far past recognition
    }

    /// A leading word must not be treated as an abbreviation of a longer one, or every light beer
    /// becomes its full-strength sibling. Bud Light is 4.2%; Budweiser is 5%.
    func testALeadingWordIsNotAnAbbreviation() {
        XCTAssertEqual(repaired("BUD LIGHT"), "Bud Light")
        XCTAssertNil(repaired("HOUSE RED"))          // would otherwise reach Redd's
        XCTAssertNil(repaired("BEER TOWER"))         // would otherwise reach Beerlao
    }

    /// Word alignment, not a floating character window. `press` really is inside `PRESSURE` and
    /// `beck's` is two edits from `BUCKSHORT`; neither starts a word.
    func testMatchingIsAnchoredToWordBoundaries() {
        XCTAssertNil(repaired("MARG UNDER PRESSURE"))
        XCTAssertNil(repaired("NORTH COUNTRY BUCKSHORT STOUT"))
        XCTAssertNil(repaired("EVERGRAIN JOOSE JUICY"))
    }

    /// One word is a style, and the style chart has a sourced number for it. Binding it to a
    /// specific bottling would invent precision.
    func testASingleStyleWordIsNotBoundToAProduct() {
        XCTAssertNil(repaired("PROSECCO"))
        XCTAssertNil(repaired("PINOT GRIGIO"))
    }

    func testCocktailsAndIngredientListsAreLeftAlone() {
        for line in ["GUMMY WORM", "GREEN TEA", "SIMPLE SYRUP", "COLD BREW MARTINI", "SHOR TEA",
                     "LA FLAMA BLANCA", "MIMOSA YOWER", "VODKA COFFEE COMFEE LIQUEUR",
                     "SPARKLING WINE ORANGE JUICE", "ANGOSTURA BITTERS ORANGE RANG",
                     "IRISH WHISKY PEACH SCHNAPPS", "LEMON"] {
            XCTAssertNil(repaired(line), "wrongly repaired \(line)")
        }
    }

    /// Beers that genuinely aren't in the table must stay unmatched. `SREWDOG ELVIS AF` is the
    /// important one: the nearest entry is Brewdog Elvis Juice at 6.5%, but Elvis AF is the
    /// alcohol-free version, so a confident partial match would be actively wrong. When the table
    /// is missing a beer the fix is the table, not a looser threshold.
    func testBeersAbsentFromTheTableStayUnmatched() {
        XCTAssertNil(repaired("SREWDOG ELVIS AF"))
        XCTAssertNil(repaired("VICTORY SOUR MONKEY"))
        XCTAssertNil(repaired("PLATFORM HAZE JUDE"))
        XCTAssertNil(repaired("PRAIRIE BREWING RAINBOW SHERBERT"))
        XCTAssertNil(repaired("PENN BREWERY WEIZEN"))
    }

    /// End to end: the repair has to actually change the ABV the ranking uses, and say so.
    func testARepairedNameResolvesToTheBrandsABV() {
        let profile = StaticBeverageKnowledge().profile(for: "BUSCHUGHT SE", sectionCategory: .draftBeer)
        XCTAssertEqual(profile.typicalABV, 4.1, accuracy: 0.01)
        XCTAssertEqual(profile.source, .brandMatch(matched: "Busch Light"))
        XCTAssertTrue(profile.abvNote.contains("Busch Light"))
    }

    func testFoldingCollapsesTheConfusableGlyphs() {
        XCTAssertEqual(String(OCRNameRepair.fold(word: "LIGHT")), "ught")
        XCTAssertEqual(String(OCRNameRepair.fold(word: "DOGFISH")), "dogrsh")
        XCTAssertEqual(String(OCRNameRepair.fold(word: "$5")), "s")
        XCTAssertEqual(String(OCRNameRepair.fold(word: "Bell's")), "beiis")
    }
}
