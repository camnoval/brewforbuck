//
//  SupporterPromptTests.swift
//  Core
//
//  Created by Noval, Cameron on 9/9/26.
//


import XCTest
@testable import CoreServices
@testable import CoreContracts
@testable import CoreModel

final class SupporterPromptTests: XCTestCase {

    /// What a fresh install starts at, so the first qualifying scan asks. The store persists this
    /// value; the tests state it explicitly rather than importing the default from the shell.
    private let neverAsked = SupporterPrompt.scansBetweenAsks

    // MARK: - When to ask

    func testItAsksAfterAGoodReadWhenNobodyHasAskedYet() {
        XCTAssertTrue(SupporterPrompt.shouldOffer(
            rankedCount: 12,
            isLowConfidence: false,
            status: .notSupporter,
            scansSinceLastAsk: neverAsked
        ))
    }

    /// The rule that makes the purchase one-time. A supporter is never asked again.
    func testItNeverAsksAnExistingSupporter() {
        XCTAssertFalse(SupporterPrompt.shouldOffer(
            rankedCount: 12,
            isLowConfidence: false,
            status: .supporter(productIdentifier: "supporter.pint"),
            scansSinceLastAsk: neverAsked
        ))
    }

    // MARK: - The cadence
    //
    // Replaced "never ask twice" on 2026-09-09. The ask now recurs, but it still has to be earned
    // by using the app rather than by opening it.

    /// Dismissing the sheet resets the counter, so the very next scan must not ask again.
    func testItDoesNotAskImmediatelyAfterAsking() {
        XCTAssertFalse(SupporterPrompt.shouldOffer(
            rankedCount: 12,
            isLowConfidence: false,
            status: .notSupporter,
            scansSinceLastAsk: 0
        ))
    }

    /// The whole interval, not just the first scan of it.
    func testItStaysQuietForTheWholeInterval() {
        for scans in 1..<SupporterPrompt.scansBetweenAsks {
            XCTAssertFalse(
                SupporterPrompt.shouldOffer(
                    rankedCount: 12,
                    isLowConfidence: false,
                    status: .notSupporter,
                    scansSinceLastAsk: scans
                ),
                "should still be quiet \(scans) scan(s) after asking"
            )
        }
    }

    func testItAsksAgainOnceEnoughScansHavePassed() {
        XCTAssertTrue(SupporterPrompt.shouldOffer(
            rankedCount: 12,
            isLowConfidence: false,
            status: .notSupporter,
            scansSinceLastAsk: SupporterPrompt.scansBetweenAsks
        ))
    }

    /// A run of thin reads still counts toward the interval, so the counter can overshoot. It must
    /// not wrap or go quiet again when it does.
    func testItStillAsksWhenMoreScansPassedThanNeeded() {
        XCTAssertTrue(SupporterPrompt.shouldOffer(
            rankedCount: 12,
            isLowConfidence: false,
            status: .notSupporter,
            scansSinceLastAsk: SupporterPrompt.scansBetweenAsks * 4
        ))
    }

    // MARK: - The other two rules

    /// The rule worth keeping above all the others: do not ask for money on a job the app is not
    /// confident it did well (C, R1).
    func testItNeverAsksOnAThinRead() {
        XCTAssertFalse(SupporterPrompt.shouldOffer(
            rankedCount: 12,
            isLowConfidence: true,
            status: .notSupporter,
            scansSinceLastAsk: neverAsked
        ))
    }

    /// And a thin read does not get a free pass just because plenty of scans have gone by.
    func testAThinReadNeverAsksHoweverManyScansHavePassed() {
        XCTAssertFalse(SupporterPrompt.shouldOffer(
            rankedCount: 12,
            isLowConfidence: true,
            status: .notSupporter,
            scansSinceLastAsk: SupporterPrompt.scansBetweenAsks * 10
        ))
    }

    func testItNeverAsksWithoutAComparison() {
        XCTAssertFalse(SupporterPrompt.shouldOffer(
            rankedCount: 1,
            isLowConfidence: false,
            status: .notSupporter,
            scansSinceLastAsk: neverAsked
        ))
    }

    func testItNeverAsksWithNothingRanked() {
        XCTAssertFalse(SupporterPrompt.shouldOffer(
            rankedCount: 0,
            isLowConfidence: false,
            status: .notSupporter,
            scansSinceLastAsk: neverAsked
        ))
    }

    func testTwoRankedDrinksIsEnough() {
        XCTAssertTrue(SupporterPrompt.shouldOffer(
            rankedCount: SupporterPrompt.minimumRankedDrinks,
            isLowConfidence: false,
            status: .notSupporter,
            scansSinceLastAsk: neverAsked
        ))
    }

    // MARK: - Whether the spread is worth saying

    func testAWideSpreadIsWorthMentioning() {
        let wide = MenuValueSpread(bestValue: 0.48, worstValue: 0.20, ratio: 2.4)

        XCTAssertTrue(SupporterPrompt.isWorthMentioning(wide))
    }

    /// A menu where it barely mattered what you ordered should not be dressed up as a saving.
    func testANarrowSpreadIsNotWorthMentioning() {
        let narrow = MenuValueSpread(bestValue: 0.42, worstValue: 0.40, ratio: 1.05)

        XCTAssertFalse(SupporterPrompt.isWorthMentioning(narrow))
    }

    func testNoSpreadIsNotWorthMentioning() {
        XCTAssertFalse(SupporterPrompt.isWorthMentioning(nil))
    }

    // MARK: - Naming what they bought

    func testKnownIdentifiersResolveToTheirTier() {
        XCTAssertEqual(SupporterTierKind.resolve(productIdentifier: "supporter.shot"), .shot)
        XCTAssertEqual(SupporterTierKind.resolve(productIdentifier: "supporter.pint"), .pint)
        XCTAssertEqual(SupporterTierKind.resolve(productIdentifier: "supporter.round"), .round)
    }

    /// Matching on suffix means the prefix can change without touching this.
    func testItMatchesOnSuffixSoThePrefixCanChange() {
        XCTAssertEqual(SupporterTierKind.resolve(productIdentifier: "abv.supporter.pint"), .pint)
    }

    /// A tier added in the dashboard but not in this build degrades to the plainer badge rather
    /// than to a wrong one.
    func testAnUnknownProductStillCountsAsSupport() {
        XCTAssertEqual(SupporterTierKind.resolve(productIdentifier: "supporter.magnum"), .unspecified)
    }

    func testStatusResolvesToATierKind() {
        let status = SupporterStatus.supporter(productIdentifier: "supporter.round")

        XCTAssertEqual(SupporterTierKind.resolve(status: status), .round)
    }

    /// No badge at all for someone who has not supported the app.
    func testNonSupportersResolveToNoTierKind() {
        XCTAssertNil(SupporterTierKind.resolve(status: .notSupporter))
    }
}
