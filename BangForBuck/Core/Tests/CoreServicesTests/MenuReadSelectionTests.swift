//
//  MenuReadSelectionTests.swift
//  Core
//

import XCTest
@testable import CoreServices
import CoreModel

/// `MenuReadSelection` picks between competing OCR readings of one photo. The cases below are the
/// ones that decide whether it earns its place: it must prefer the reading that actually yields
/// priced drinks, must not be fooled by a reading that is merely longer, and must leave the proven
/// reader in charge whenever the two are equivalent.
final class MenuReadSelectionTests: XCTestCase {

    /// The real failure: a tap list whose prices were torn into their own block by the column cut.
    /// Both readings contain every character on the page; only one connects a name to a price.
    func testAReadingThatKeepsPricesWithNamesWins() {
        let torn = [
            "1 - IC LIGHT 4.2% ABV",
            "2 - IRON CITY OLD GERMAN 4.7% ABV",
            "3 - YUENGLING TRADITIONAL LAGER 4.5% ABV",
            "4 - SAM ADAMS SEASONAL 6.0% ABV",
            "$5", "$5", "$5", "$5",
        ]
        let intact = [
            "1 - IC LIGHT 4.2% ABV $5",
            "2 - IRON CITY OLD GERMAN 4.7% ABV $5",
            "3 - YUENGLING TRADITIONAL LAGER 4.5% ABV $5",
            "4 - SAM ADAMS SEASONAL 6.0% ABV $5",
        ]
        XCTAssertEqual(MenuReadSelection.best(of: [torn, intact]), intact)
        XCTAssertEqual(MenuReadSelection.best(of: [intact, torn]), intact)
        XCTAssertGreaterThan(MenuReadSelection.score(intact).priced,
                             MenuReadSelection.score(torn).priced)
    }

    /// A longer reading is not a better one. At equal priced yield the leaner reading wins, because
    /// the surplus lines are junk bound for the "Not sure" bucket.
    func testAtEqualPricedYieldTheLeanerReadingWins() {
        let clean = ["Coors Light $5", "Guinness $9", "Yuengling $6"]
        let noisy = clean + ["VISIT US @", "FOLLOW US", "ASK YOUR SERVER"]
        XCTAssertEqual(MenuReadSelection.best(of: [noisy, clean]), clean)
    }

    /// A full tie must not reshuffle anything: callers pass the proven reader first and expect it to
    /// stay chosen.
    func testAFullTieKeepsTheFirstCandidate() {
        let a = ["Coors Light $5", "Guinness $9"]
        let b = ["Bud Light $5", "Stella $9"]
        XCTAssertEqual(MenuReadSelection.score(a), MenuReadSelection.score(b))
        XCTAssertEqual(MenuReadSelection.best(of: [a, b]), a)
        XCTAssertEqual(MenuReadSelection.best(of: [b, a]), b)
    }

    func testNoCandidatesIsEmptyRatherThanACrash() {
        XCTAssertEqual(MenuReadSelection.best(of: []), [])
    }

    /// Scoring runs through `PricePlausibility`, so a reading cannot win on prices the pipeline is
    /// going to withdraw anyway. Without that step this reading would score 4 priced drinks; with
    /// it, the absurd one is withheld and the score matches what the person will actually see.
    func testAnAbsurdPriceDoesNotCountTowardAReadingsScore() {
        let lines = ["Coors Light $5", "Guinness $6", "Yuengling $5", "7-Up 415"]
        XCTAssertEqual(MenuReadSelection.score(lines).priced, 3)
    }
}
