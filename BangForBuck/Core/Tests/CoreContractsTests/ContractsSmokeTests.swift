import XCTest
@testable import CoreContracts
@testable import CoreModel

/// Note on style: every `await` is hoisted into a local before the assertion. The `XCTAssert*`
/// family takes a non-async autoclosure, so `XCTAssertEqual(await thing(), x)` does not compile.
final class ContractsSmokeTests: XCTestCase {

    func testFakeTextRecognizerReturnsCannedLines() async throws {
        let fake = FakeTextRecognizer(lines: ["Sunset Tea $8", "IPA 6"])
        let lines = try await fake.recognizeLines(in: CapturedImage(pngData: []))
        XCTAssertEqual(lines, ["Sunset Tea $8", "IPA 6"])
    }

    // MARK: - The tiers

    func testTiersComeBackInTheStoresOrder() async throws {
        let purchases = InMemoryPurchaseController()

        let tiers = try await purchases.supporterTiers()

        XCTAssertEqual(tiers.map(\.productIdentifier), ["supporter.shot", "supporter.pint", "supporter.round"])
    }

    /// The paywall must be able to tell "no prices available" from "prices are these". The honest
    /// response to the first is a retry, not a guess (§10).
    func testNoTiersThrowsRatherThanReturningPlaceholderPrices() async {
        let purchases = InMemoryPurchaseController(tiers: [])

        do {
            _ = try await purchases.supporterTiers()
            XCTFail("Expected an empty tier list to throw")
        } catch {
            // Expected: there are no fallback prices to hand back.
        }
    }

    func testTiersCarryTheStoresOwnPriceAndNameStrings() async throws {
        let euro = SupporterTier(
            productIdentifier: "supporter.pint",
            displayName: "Offre-moi une pinte",
            displayPrice: "4,99 €"
        )
        let purchases = InMemoryPurchaseController(tiers: [euro])

        let tier = try await purchases.supporterTiers()[0]

        XCTAssertEqual(tier.displayName, "Offre-moi une pinte")
        XCTAssertEqual(tier.displayPrice, "4,99 €")
    }

    // MARK: - Buying

    func testPurchaseActivatesTheEntitlement() async throws {
        let purchases = InMemoryPurchaseController()
        let before = await purchases.supporterStatus()
        XCTAssertFalse(before.isActive)

        let tiers = try await purchases.supporterTiers()
        let outcome = try await purchases.purchase(tiers[1])
        let after = await purchases.supporterStatus()

        XCTAssertEqual(outcome, .purchased)
        XCTAssertTrue(after.isActive)
    }

    /// The badge has to be able to name what was bought, which is the whole reason status carries
    /// an identifier instead of being a Bool.
    func testStatusReportsWhichProductGrantedSupport() async throws {
        let purchases = InMemoryPurchaseController()
        let tiers = try await purchases.supporterTiers()

        _ = try await purchases.purchase(tiers[1])
        let status = await purchases.supporterStatus()

        XCTAssertEqual(status, .supporter(productIdentifier: "supporter.pint"))
    }

    /// Any tier grants the same entitlement, so a $1.99 shot removes the v1.1 banner exactly as a
    /// $9.99 round does. The tiers are how much you choose to give, not how much you get.
    func testEveryTierGrantsTheSameEntitlement() async throws {
        for index in 0..<InMemoryPurchaseController.sampleTiers.count {
            let purchases = InMemoryPurchaseController()
            let tiers = try await purchases.supporterTiers()

            let outcome = try await purchases.purchase(tiers[index])
            let status = await purchases.supporterStatus()

            XCTAssertEqual(outcome, .purchased)
            XCTAssertTrue(status.isActive, "Tier \(tiers[index].productIdentifier) did not grant support")
        }
    }

    /// The charge has to match the thing displayed, which is why `purchase` takes a tier at all.
    func testThePurchasedTierIsTheOneThatWasPassedIn() async throws {
        let purchases = InMemoryPurchaseController()
        let tiers = try await purchases.supporterTiers()

        _ = try await purchases.purchase(tiers[2])
        let charged = await purchases.lastPurchasedTier

        XCTAssertEqual(charged, tiers[2])
    }

    /// A cancel is not a failure and must not grant the entitlement. This is the distinction the
    /// old `purchaseRemoveAds() async throws` could not express.
    func testCancelLeavesTheEntitlementInactive() async throws {
        let purchases = InMemoryPurchaseController(behaviour: .cancels)
        let tiers = try await purchases.supporterTiers()

        let outcome = try await purchases.purchase(tiers[0])
        let status = await purchases.supporterStatus()

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(status, .notSupporter)
    }

    /// Ask to Buy: money may yet arrive, but nothing is owed now, so the banner stays and the badge
    /// does not appear.
    func testPendingLeavesTheEntitlementInactive() async throws {
        let purchases = InMemoryPurchaseController(behaviour: .pends)
        let tiers = try await purchases.supporterTiers()

        let outcome = try await purchases.purchase(tiers[0])
        let status = await purchases.supporterStatus()

        XCTAssertEqual(outcome, .pending)
        XCTAssertEqual(status, .notSupporter)
    }

    func testAFailedPurchaseThrowsAndGrantsNothing() async throws {
        let purchases = InMemoryPurchaseController(behaviour: .fails)
        let tiers = try await purchases.supporterTiers()

        do {
            _ = try await purchases.purchase(tiers[0])
            XCTFail("Expected the purchase to throw")
        } catch {
            let status = await purchases.supporterStatus()
            XCTAssertEqual(status, .notSupporter)
        }
    }

    // MARK: - Restore

    func testRestoreFindsAPriorPurchaseAndKnowsWhichOne() async throws {
        let purchases = InMemoryPurchaseController(priorPurchase: "supporter.round")

        let outcome = try await purchases.restorePurchases()
        let status = await purchases.supporterStatus()

        XCTAssertEqual(outcome, .restored)
        XCTAssertEqual(status, .supporter(productIdentifier: "supporter.round"))
    }

    /// The case the old `Void` return could not report. A restore that finds nothing has to be
    /// distinguishable from one that succeeds, or the app thanks people for nothing.
    func testRestoreWithNothingToFindSaysSo() async throws {
        let purchases = InMemoryPurchaseController(priorPurchase: nil)

        let outcome = try await purchases.restorePurchases()
        let status = await purchases.supporterStatus()

        XCTAssertEqual(outcome, .nothingToRestore)
        XCTAssertEqual(status, .notSupporter)
    }
}
