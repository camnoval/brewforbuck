//
//  PaywallFlowTests.swift
//  Core
//
//  Created by Noval, Cameron on 9/9/26.
//


import XCTest
@testable import CoreServices
@testable import CoreContracts

final class PaywallFlowTests: XCTestCase {

    private let tiers = InMemoryPurchaseController.sampleTiers

    private var pint: SupporterTier { tiers[1] }

    // MARK: - Loading

    func testItStartsLoading() {
        XCTAssertEqual(PaywallFlow.initial, .loading)
    }

    func testLoadedTiersBecomeTheList() {
        let state = PaywallFlow.next(from: .loading, on: .tiersLoaded(tiers))

        XCTAssertEqual(state, .ready(tiers: tiers, notice: nil))
    }

    /// The paywall never shows a price it does not have (§10), so a failed fetch offers a retry
    /// instead of a plausible-looking guess.
    func testAFailedFetchIsUnavailableRatherThanAGuess() {
        let state = PaywallFlow.next(from: .loading, on: .tiersFailed)

        XCTAssertEqual(state, .unavailable)
    }

    /// An empty offering is a misconfiguration, not a paywall.
    func testAnEmptyTierListIsAlsoUnavailable() {
        let state = PaywallFlow.next(from: .loading, on: .tiersLoaded([]))

        XCTAssertEqual(state, .unavailable)
    }

    func testRetryGoesBackToLoading() {
        let state = PaywallFlow.next(from: .unavailable, on: .retryRequested)

        XCTAssertEqual(state, .loading)
    }

    // MARK: - Buying

    func testChoosingATierStartsThePurchase() {
        let state = PaywallFlow.next(from: .ready(tiers: tiers, notice: nil), on: .tierChosen(pint))

        XCTAssertEqual(state, .purchasing(tiers: tiers, chosen: pint))
    }

    func testASuccessfulPurchaseNamesTheTierItThanksThemFor() {
        let purchasing = PaywallState.purchasing(tiers: tiers, chosen: pint)

        let state = PaywallFlow.next(from: purchasing, on: .purchaseFinished(.purchased))

        XCTAssertEqual(state, .thanks(productIdentifier: "supporter.pint"))
    }

    /// A cancel is not a failure. Back to the list with nothing said.
    func testACancelReturnsToTheListSilently() {
        let purchasing = PaywallState.purchasing(tiers: tiers, chosen: pint)

        let state = PaywallFlow.next(from: purchasing, on: .purchaseFinished(.cancelled))

        XCTAssertEqual(state, .ready(tiers: tiers, notice: nil))
    }

    /// Ask to Buy. Money may yet arrive, so this must not read as a thank-you.
    func testAPendingPurchaseIsNotAThankYou() {
        let purchasing = PaywallState.purchasing(tiers: tiers, chosen: pint)

        let state = PaywallFlow.next(from: purchasing, on: .purchaseFinished(.pending))

        XCTAssertEqual(state, .pending)
    }

    func testAFailedPurchaseReturnsToTheListAndSaysSo() {
        let purchasing = PaywallState.purchasing(tiers: tiers, chosen: pint)

        let state = PaywallFlow.next(from: purchasing, on: .purchaseFailed)

        XCTAssertEqual(state, .ready(tiers: tiers, notice: .purchaseDidNotGoThrough))
    }

    // MARK: - Restoring

    func testRestoringIsItsOwnStateSoTheButtonCanDisable() {
        let state = PaywallFlow.next(from: .ready(tiers: tiers, notice: nil), on: .restoreRequested)

        XCTAssertEqual(state, .restoring(tiers: tiers))
    }

    /// A restore does not report which product it found, so the caller re-reads the entitlement to
    /// name the tier.
    func testASuccessfulRestoreThanksThemWithoutNamingATier() {
        let state = PaywallFlow.next(from: .restoring(tiers: tiers), on: .restoreFinished(.restored))

        XCTAssertEqual(state, .thanks(productIdentifier: nil))
    }

    /// The case a `Void` return could not express. Owning nothing is said plainly rather than
    /// dressed up as success.
    func testARestoreThatFindsNothingSaysSo() {
        let state = PaywallFlow.next(
            from: .restoring(tiers: tiers),
            on: .restoreFinished(.nothingToRestore)
        )

        XCTAssertEqual(state, .ready(tiers: tiers, notice: .nothingToRestore))
    }

    /// Distinct from finding nothing: here the question is still unanswered.
    func testAFailedRestoreIsDistinctFromFindingNothing() {
        let state = PaywallFlow.next(from: .restoring(tiers: tiers), on: .restoreFailed)

        XCTAssertEqual(state, .ready(tiers: tiers, notice: .restoreDidNotGoThrough))
    }

    // MARK: - Events that do not apply

    /// A late reply from a call the person already backed out of must not move a finished purchase
    /// backwards.
    func testALateReplyDoesNotUndoAThankYou() {
        let thanked = PaywallState.thanks(productIdentifier: "supporter.pint")

        let state = PaywallFlow.next(from: thanked, on: .purchaseFinished(.cancelled))

        XCTAssertEqual(state, thanked)
    }

    func testTiersArrivingLateDoNotDisturbAPurchaseInFlight() {
        let purchasing = PaywallState.purchasing(tiers: tiers, chosen: pint)

        let state = PaywallFlow.next(from: purchasing, on: .tiersLoaded(tiers))

        XCTAssertEqual(state, purchasing)
    }

    func testARetryTapWhileLoadingChangesNothing() {
        let state = PaywallFlow.next(from: .loading, on: .retryRequested)

        XCTAssertEqual(state, .loading)
    }

    /// The notice from a previous attempt survives until something else happens, so it gets read
    /// once rather than flashing away.
    func testAppearingAgainDoesNotClearAPreviousNotice() {
        let withNotice = PaywallState.ready(tiers: tiers, notice: .nothingToRestore)

        let state = PaywallFlow.next(from: withNotice, on: .appeared)

        XCTAssertEqual(state, withNotice)
    }
}