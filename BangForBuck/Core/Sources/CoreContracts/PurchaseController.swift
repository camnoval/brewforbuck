/// The `supporter` entitlement (§6, §A): read it, buy it, restore it.
///
/// One entitlement, bought at any of several price tiers, and it does two things:
///
/// 1. Marks the customer as a supporter, so the app stops asking and can show a quiet badge.
/// 2. Turns off the ad banner, once the banner exists (v1.1).
///
/// The second point is why the entitlement is called `supporter` and not `remove_ads`. In v1 there
/// is no banner to remove, so the App Store listing must not claim to remove one; selling a feature
/// the build does not have is a rejection risk. When the banner ships in v1.1 the ad gate checks
/// this same entitlement, and everyone who already bought a tier is already covered. No second
/// product, no migration.
///
/// Real implementation: `RevenueCatPurchases` in `AppTarget/Infrastructure`. Test implementation:
/// `InMemoryPurchaseController`.
///
/// **Foundation-free on purpose.** Everything here is `String`, `Bool`, arrays and enums, so
/// `CoreContracts` keeps building on Linux and the SDK stays behind the seam (§7).
public protocol PurchaseController: Sendable {

    /// The tiers the customer can choose from, in the order the store returned them.
    ///
    /// Order is the store's, not ours, so the tiers can be reordered or repriced from the
    /// RevenueCat dashboard without a new build.
    ///
    /// Throws when the store can't be reached or no tiers are configured. The paywall then shows a
    /// retry and **no prices**, rather than made-up ones.
    func supporterTiers() async throws -> [SupporterTier]

    /// Buy the tier that was displayed.
    ///
    /// Takes the tier rather than re-resolving the product internally, so the thing charged is
    /// provably the thing shown. See `SupporterTier.displayPrice`.
    func purchase(_ tier: SupporterTier) async throws -> PurchaseOutcome

    /// Re-apply a purchase made on another device or a previous install.
    ///
    /// Required by App Review for a non-consumable, and it **must report whether anything was
    /// actually found**: a restore that turns up nothing has to say so rather than implying success.
    func restorePurchases() async throws -> RestoreOutcome

    /// Whether `supporter` is active, and if so which product granted it. Read at launch, and
    /// re-read after a purchase or a restore.
    ///
    /// Reports the granting product identifier so the app can name what was bought, not just that
    /// something was. This works offline, because the identifier comes from the locally cached
    /// entitlement rather than from a fresh product lookup.
    ///
    /// Deliberately non-throwing, and the real implementation **answers `.notSupporter` when it
    /// cannot tell**. Claiming support on an error would give the product away and would silently
    /// disable the v1.1 ad gate through an error path, which is not a state anyone would think to
    /// test. Answering `.notSupporter` costs a paying customer a banner in the one case it can
    /// happen, which is a fresh install, offline, before Restore has run.
    func supporterStatus() async -> SupporterStatus
}

/// Whether this customer has supported the app, and with which product.
public enum SupporterStatus: Sendable, Equatable {

    case notSupporter

    /// Supported. `productIdentifier` is the product that granted the entitlement, e.g.
    /// `"supporter.pint"`.
    ///
    /// An identifier and not a display name, because this has to answer offline and a display name
    /// would require a live product lookup. The app maps known identifiers to a short label for the
    /// badge; anything unrecognized falls back to the generic "Supporter", which is always true.
    case supporter(productIdentifier: String)

    /// Convenience for the many places that only care yes or no, such as the v1.1 ad gate.
    public var isActive: Bool {
        self != .notSupporter
    }
}

/// One price tier, as the store describes it.
///
/// The app's tiers are named after drinks (a well shot, a pint, a round) because the whole product
/// is denominated in drinks. The names live in App Store Connect rather than in code, so they are
/// localizable and editable without a build.
public struct SupporterTier: Sendable, Equatable, Identifiable {

    /// The store's product identifier, e.g. `supporter.pint`. Opaque to `Core`; the shell uses it to
    /// find the package again at purchase time, and to match against `SupporterStatus`.
    public let productIdentifier: String

    /// Stable identity for lists and SwiftUI.
    public var id: String { productIdentifier }

    /// The store's localized product name, e.g. "Buy me a pint".
    ///
    /// Comes from the store rather than from a string constant, so the copy is translated by the
    /// same system that translates everything else on the product page.
    public let displayName: String

    /// The store's own localized price string: `"$1.99"`, `"1,99 €"`, `"￥300"`.
    ///
    /// **A String, never a number, and this is load-bearing.** The store is the only authority on
    /// what this costs in the customer's currency and locale. Handing `Core` a `Double` invites
    /// somebody to format it, and a hand-formatted price is a fabricated price shown to a real
    /// person about to be charged. §10 says a price is never fabricated; that applies with more
    /// force to our own price than to a menu's.
    public let displayPrice: String

    public init(productIdentifier: String, displayName: String, displayPrice: String) {
        self.productIdentifier = productIdentifier
        self.displayName = displayName
        self.displayPrice = displayPrice
    }
}

/// How a purchase attempt ended, for the cases that are not errors.
///
/// Cancelling and failing need different behaviour, which the old `throws`-only signature could not
/// express: a cancel should close the sheet quietly, a failure should apologize and offer a retry.
public enum PurchaseOutcome: Sendable, Equatable {

    /// Paid, and the entitlement is active.
    case purchased

    /// The customer backed out. Not an error. Say nothing, dismiss.
    case cancelled

    /// Awaiting someone else's approval (Ask to Buy) or a bank challenge. Nothing is owed and the
    /// entitlement is **not** active yet, so the app must not thank them or hide the banner.
    case pending
}

/// What a restore turned up.
public enum RestoreOutcome: Sendable, Equatable {

    /// A prior purchase was found and the entitlement is now active.
    case restored

    /// The call succeeded and this Apple Account owns nothing. The app says exactly that.
    case nothingToRestore
}
