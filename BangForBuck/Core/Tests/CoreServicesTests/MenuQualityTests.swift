//
//  MenuQualityTests.swift
//  Core
//
//  Created by Noval, Cameron on 9/7/26.
//


import XCTest
@testable import CoreServices
import CoreContracts
import CoreModel

/// A menu read too thinly to describe itself is **flagged, not withheld** (C).
///
/// The two menus this exists for are the 1948 Roosevelt list and the Thirsty Duck menu, which prints
/// no beer prices at all. Both read at near-perfect OCR confidence, which is why the measure is
/// built on the **priced fraction** and not on confidence — see the `MenuQuality` doc comment for
/// the table that kills the confidence idea.
///
/// The ranking is always produced. On the 1948 list that is the right answer: once
/// `PricePlausibility` withdraws its absurd prices, the podium is led by a real $1.00 line. A
/// flagged imperfect ranking beats silence, and the person can see and fix what is wrong.
final class MenuQualityTests: XCTestCase {
    private let pipeline = MenuPipeline()

    private func item(_ name: String, _ dollars: Double?) -> MenuItem {
        MenuItem(name: name, price: dollars.flatMap { Price(dollars: $0) }, category: .draftBeer)
    }

    private func menu(priced: Int, unpriced: Int) -> [MenuItem] {
        (0..<priced).map { item("Priced \($0)", 6) } + (0..<unpriced).map { item("Bare \($0)", nil) }
    }

    // MARK: - The measured corpus

    /// The exact ratios measured on the eight dumps. The gap between the worst good menu (36.1%) and
    /// the best bad one (11.3%) is 3.2× with nothing inside it, so these verdicts are not close
    /// calls — that is the point of pinning them.
    func testCorpusRatiosGetTheRightVerdict() {
        // menu 8 (Thirsty Duck): 4 priced of 76.
        XCTAssertTrue(MenuQualityGate.assess(menu(priced: 4, unpriced: 72)).isLowConfidence)
        // menu 2 (1948 list): 11 priced of 97.
        XCTAssertTrue(MenuQualityGate.assess(menu(priced: 11, unpriced: 86)).isLowConfidence)
        // menu 7, the thinnest menu that must NOT be flagged: 30 priced of 83.
        XCTAssertFalse(MenuQualityGate.assess(menu(priced: 30, unpriced: 53)).isLowConfidence)
        // menu 3 (Rullo's), the lowest-confidence menu on the corpus, parses fine.
        XCTAssertFalse(MenuQualityGate.assess(menu(priced: 21, unpriced: 37)).isLowConfidence)
    }

    func testPricedFractionIsReported() {
        let q = MenuQualityGate.assess(menu(priced: 4, unpriced: 76))
        XCTAssertEqual(q.itemCount, 80)
        XCTAssertEqual(q.pricedCount, 4)
        XCTAssertEqual(q.pricedFraction, 0.05, accuracy: 0.0001)
    }

    // MARK: - Not enough evidence to condemn

    /// Below the sample floor the ratio is one or two lines wide, so nothing is flagged.
    func testShortMenusAreNeverFlagged() {
        for unpriced in 0..<MenuQualityGate.minimumItemsToJudge {
            let q = MenuQualityGate.assess(menu(priced: 0, unpriced: unpriced))
            XCTAssertFalse(q.isLowConfidence, "\(unpriced) items is not evidence of a bad read")
        }
        // One more item and there is.
        XCTAssertTrue(MenuQualityGate.assess(menu(priced: 0, unpriced: 8)).isLowConfidence)
    }

    func testEmptyMenuIsNotFlaggedAndHasNoFraction() {
        let q = MenuQualityGate.assess([])
        XCTAssertFalse(q.isLowConfidence)
        XCTAssertEqual(q.pricedFraction, 0)
    }

    // MARK: - End to end through the session

    private func thinMenu() -> [String] {
        // No trailing digits: a bare number at the end of a line is read as a price.
        let suffixes = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot",
                        "Golf", "Hotel", "India", "Juliet", "Kilo", "Lima"]
        return ["DRAFTS", "Lager $6"] + suffixes.map { "Mystery Ale \($0)" }
    }

    /// The whole point of the change: a thin read is flagged, and still ranks what it could read.
    func testThinReadIsFlaggedButStillRanks() {
        let session = pipeline.makeSession(lines: thinMenu(), metric: .standardDrinksPerDollar)
        XCTAssertTrue(session.isLowConfidence, "one priced line in thirteen is a thin read")
        XCTAssertEqual(session.rankedDrinks.count, 1, "the one priced drink still ranks")
        // And nothing is lost — the rest are there for review and correction.
        XCTAssertEqual(session.drinks.count, 13)
        XCTAssertEqual(session.needsPriceDrinks.count, 12)
    }

    /// `analyze` delegates to the session, so the two paths must agree.
    func testAnalyzeAgreesWithTheSession() {
        let analysis = pipeline.analyze(lines: thinMenu(), metric: .standardDrinksPerDollar)
        XCTAssertEqual(analysis.ranked.count, 1)
        XCTAssertTrue(analysis.quality.isLowConfidence)
        XCTAssertEqual(analysis.needsPrice.count, 12)
    }

    /// Manual prices flow straight into the ranking; the flag is a verdict on the **OCR read**, so
    /// it deliberately stays set. It describes how the menu was scanned, not the state of the list
    /// after editing. If that ever needs to change, recompute `quality` from the live drinks rather
    /// than special-casing manual entry.
    func testManualPricesRankAndTheFlagDescribesTheOriginalRead() {
        var session = pipeline.makeSession(lines: thinMenu(), metric: .standardDrinksPerDollar)
        XCTAssertTrue(session.isLowConfidence)
        for drink in session.needsPriceDrinks {
            session.setPrice(id: drink.id, dollars: 7)
        }
        XCTAssertEqual(session.rankedDrinks.count, 13, "every priced drink ranks")
        XCTAssertTrue(session.isLowConfidence, "the read was still thin")
    }

    /// A healthy menu is untouched.
    func testHealthyMenuStillRanks() {
        let session = pipeline.makeSession(
            lines: ["DRAFTS", "Lager $6", "IPA $7", "Stout $8", "Pils $6",
                    "Wheat $7", "Porter $7", "Amber $6", "Saison $8"],
            metric: .standardDrinksPerDollar
        )
        XCTAssertFalse(session.isLowConfidence)
        XCTAssertEqual(session.rankedDrinks.count, 8)
    }

    /// A hand-built session is trusted: the gate judges an OCR read, and there isn't one here.
    func testHandBuiltSessionIsTrusted() {
        let session = MenuSession(drinks: [], excludedNonAlcoholic: [],
                                  metric: .standardDrinksPerDollar)
        XCTAssertFalse(session.quality.isLowConfidence)
        XCTAssertFalse(session.isLowConfidence)
    }
}
