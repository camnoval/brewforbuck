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

    // MARK: - When to ask

    func testItAsksAfterAGoodReadWhenNobodyHasAskedYet() {
        XCTAssertTrue(SupporterPrompt.shouldOffer(
            rankedCount: 12,
            isLowConfidence: false,
            status: .notSupporter,
            hasAlreadyAsked: false
        ))
    }

    /// The rule that makes it one-time. A supporter is never asked again.
    func testItNeverAsksAnExistingSupporter() {
        XCTAssertFalse(SupporterPrompt.shouldOffer(
            rankedCount: 12,
            isLowConfidence: false,
            status: .supporter(productIdentifier: "supporter.pint"),
            hasAlreadyAsked: false
        ))
    }

    /// Declining is a real answer.
    func testItNeverAsksTwice() {
        XCTAssertFalse(SupporterPrompt.shouldOffer(
            rankedCount: 12,
            isLowConfidence: false,
            status: .notSupporter,
            hasAlreadyAsked: true
        ))
    }

    /// The rule worth keeping above all the others: do not ask for money on a job the app is not
    /// confident it did well (C, R1).
    func testItNeverAsksOnAThinRead() {
        XCTAssertFalse(SupporterPrompt.shouldOffer(
            rankedCount: 12,
            isLowConfidence: true,
            status: .notSupporter,
            hasAlreadyAsked: false
        ))
    }

    func testItNeverAsksWithoutAComparison() {
        XCTAssertFalse(SupporterPrompt.shouldOffer(
            rankedCount: 1,
            isLowConfidence: false,
            status: .notSupporter,
            hasAlreadyAsked: false
        ))
    }

    func testItNeverAsksWithNothingRanked() {
        XCTAssertFalse(SupporterPrompt.shouldOffer(
            rankedCount: 0,
            isLowConfidence: false,
            status: .notSupporter,
            hasAlreadyAsked: false
        ))
    }

    func testTwoRankedDrinksIsEnough() {
        XCTAssertTrue(SupporterPrompt.shouldOffer(
            rankedCount: SupporterPrompt.minimumRankedDrinks,
            isLowConfidence: false,
            status: .notSupporter,
            hasAlreadyAsked: false
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