/// Queries and mutates the `remove_ads` entitlement (§6, §A). Real impl: RevenueCat (Week 2).
/// Test impl: `InMemoryPurchaseController`. On launch the app checks the entitlement; if active,
/// it never initializes ads at all.
public protocol PurchaseController: Sendable {
    func isRemoveAdsActive() async -> Bool
    func purchaseRemoveAds() async throws
    func restorePurchases() async throws
}
