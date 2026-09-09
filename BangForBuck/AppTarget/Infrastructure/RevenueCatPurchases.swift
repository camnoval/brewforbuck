//
//  RevenueCatPurchases.swift
//  BangForBuck
//
//  Created by Noval, Cameron on 9/9/26.
//

import CoreContracts
import RevenueCat

/// The `supporter` entitlement, against the real store. **The only file in the project that may
/// import RevenueCat** (§6, §7): everything above this line speaks in `SupporterTier`,
/// `PurchaseOutcome` and `SupporterStatus`, and knows nothing about offerings, packages or
/// `CustomerInfo`.
///
/// Deliberately blunt and all in one file. `ProjectConventions.md` §5 is explicit that the contract
/// above this was designed before anybody had used this SDK, so this is where the two shapes get
/// reconciled and where the surprises get written down rather than smoothed over.
///
/// **An `actor`, and that is not a style choice.** This target builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so a `struct` or `final class` declared here is
/// implicitly main-actor-isolated and cannot satisfy `PurchaseController`'s nonisolated
/// requirements. An actor is never main-actor-isolated, is `Sendable` by construction, and may
/// satisfy `async` requirements from an isolated context. `InMemoryPurchaseController` is an actor
/// for the same reason, so the real and the fake conformer have the same isolation shape.
///
/// Verified against RevenueCat's current documentation on 2026-09-09, SDK 5.88.x. Three findings
/// worth keeping:
///
/// 1. **`.pending` and `.cancelled` arrive by `throw`, not in the result.** Ask to Buy throws
///    `ErrorCode.paymentPendingError`; a dismissed sheet throws `ErrorCode.purchaseCancelledError`.
///    The contract already had both cases; they come out of the `catch`, not the tuple.
/// 2. **`userCancelled` is a hint, never the truth.** RevenueCat documents it as a convenience over
///    the error, and it has a history of reading `true` on successful production purchases
///    (purchases-ios issue #4903: ~22% of transactions on 5.17.0, since closed, resolution not
///    publicly visible). Per `ProjectConventions.md` §8 the entitlement is the state and the flag is
///    the hint, so the flag is consulted **only** when the entitlement is inactive. That ordering
///    prevents the expensive failure: somebody pays and gets the paywall back.
/// 3. **`Purchases.shared` traps when the SDK is not configured**, so every method guards on
///    `isConfigured` rather than trusting call order.
actor RevenueCatPurchases: PurchaseController {

    /// The RevenueCat entitlement all three tiers grant (`MonetizationPlan.md` §3). If a purchase
    /// succeeds and this does not activate, the dashboard is misconfigured, not the code.
    private let entitlementIdentifier = "supporter"

    /// The packages behind the tiers this instance last displayed, keyed by product identifier.
    ///
    /// **This is §10, not a cache for speed.** `purchase(_:)` must charge for the thing that was
    /// shown, so it buys the exact `Package` whose `localizedPriceString` went on screen rather
    /// than re-resolving the product by identifier and trusting the price to still match.
    private var displayedPackages: [String: Package] = [:]

    /// The store could not be reached, or the Current Offering has no packages. Surfaces as
    /// `.unavailable` with a retry and no prices (§10).
    struct StoreUnavailable: Error {}

    /// A purchase arrived for a tier this instance never displayed. Only reachable if a caller
    /// invented a `SupporterTier`, so it fails loudly rather than quietly re-resolving a product.
    struct TierWasNotDisplayed: Error {
        let productIdentifier: String
    }

    /// The store reported a finished purchase that was not a cancel, and `supporter` is still
    /// inactive. Almost always a dashboard problem: entitlement missing, or products not attached
    /// to it. Reported as a failure rather than a thank-you, because thanking somebody for an
    /// entitlement they do not hold is the one outcome worse than an error message.
    struct EntitlementNotGranted: Error {}

    /// Start the SDK. Call once, as early as possible, before any other SDK call.
    ///
    /// `nonisolated` so `ABVApp.init()` can call it without an `await`. Idempotent via
    /// `isConfigured`, because RevenueCat documents configuring more than once as unsupported.
    ///
    /// **The Debug key is a Test Store key and must never ship.** RevenueCat's own documentation is
    /// unambiguous about this, and R7 says the same. That is what `#if DEBUG` is doing here, and it
    /// is the reason not to collapse these into one shared constant.
    nonisolated static func configure() {
        guard !Purchases.isConfigured else { return }

        #if DEBUG
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: "test_bSeRWXdKYmXqGZNHSkkAGBiPWQM") //they're public API keys don't worry lol
        #else
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: "appl_IbfewZePfNsCxQRCgNdFbyNeuMo")
        #endif
    }

    func supporterTiers() async throws -> [SupporterTier] {
        guard Purchases.isConfigured else { throw StoreUnavailable() }

        let offerings = try await Purchases.shared.offerings()
        guard let current = offerings.current, !current.availablePackages.isEmpty else {
            throw StoreUnavailable()
        }

        var tiers: [SupporterTier] = []
        var packages: [String: Package] = [:]

        // Dashboard order, not ours, so the tiers can be repriced or reordered without a build.
        for package in current.availablePackages {
            let product = package.storeProduct
            packages[product.productIdentifier] = package
            tiers.append(
                SupporterTier(
                    productIdentifier: product.productIdentifier,
                    displayName: product.localizedTitle,
                    // The store's own localized string. Never a number, never formatted here (§10).
                    displayPrice: product.localizedPriceString
                )
            )
        }

        displayedPackages = packages
        return tiers
    }

    func purchase(_ tier: SupporterTier) async throws -> PurchaseOutcome {
        guard Purchases.isConfigured else { throw StoreUnavailable() }
        guard let package = displayedPackages[tier.productIdentifier] else {
            throw TierWasNotDisplayed(productIdentifier: tier.productIdentifier)
        }

        let result: PurchaseResultData
        do {
            result = try await Purchases.shared.purchase(package: package)
        } catch let error as ErrorCode {
            switch error {
            case .paymentPendingError:
                // Ask to Buy or a bank challenge. Nothing owed, entitlement inactive.
                return .pending
            case .purchaseCancelledError:
                return .cancelled
            default:
                throw error
            }
        }

        // Entitlement first, flag second. See note 2 on the type.
        if isSupporter(result.customerInfo) { return .purchased }
        if result.userCancelled { return .cancelled }
        throw EntitlementNotGranted()
    }

    func restorePurchases() async throws -> RestoreOutcome {
        guard Purchases.isConfigured else { throw StoreUnavailable() }

        let info = try await Purchases.shared.restorePurchases()
        return isSupporter(info) ? .restored : .nothingToRestore
    }

    /// Fails closed to `.notSupporter`, per the contract. RevenueCat caches the entitlement
    /// locally, so a device that has already bought answers correctly offline.
    func supporterStatus() async -> SupporterStatus {
        guard Purchases.isConfigured else { return .notSupporter }

        do {
            let info = try await Purchases.shared.customerInfo()
            guard let entitlement = activeEntitlement(info) else { return .notSupporter }
            return .supporter(productIdentifier: entitlement.productIdentifier)
        } catch {
            return .notSupporter
        }
    }

    private func activeEntitlement(_ info: CustomerInfo) -> EntitlementInfo? {
        guard let entitlement = info.entitlements[entitlementIdentifier],
              entitlement.isActive else { return nil }
        return entitlement
    }

    private func isSupporter(_ info: CustomerInfo) -> Bool {
        activeEntitlement(info) != nil
    }
}
