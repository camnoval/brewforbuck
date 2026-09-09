import CoreModel

/// Lightweight reference/test doubles for the shell-facing contracts. Public so any test target (or
/// a SwiftUI preview) can use them without a separate support module. The *real* implementations
/// live in the app's Infrastructure layer.

/// Returns canned OCR lines, ignoring the image. This is how the whole pure pipeline is exercised
/// without a camera: feed it transcribed fixture lines (Tooling/Fixtures).
public struct FakeTextRecognizer: TextRecognizer {
    public let lines: [String]
    public init(lines: [String]) { self.lines = lines }
    public func recognizeLines(in image: CapturedImage) async throws -> [String] { lines }
}

/// In-memory entitlement. An actor so its mutable state is concurrency-safe.
///
/// Every branch a paywall has to handle is reachable from here without a store: no tiers, a
/// cancelled purchase, an Ask-to-Buy hold, a thrown failure, and a restore that finds nothing. That
/// is the point of the double. The pure paywall logic gets tested against all of those, not just
/// the one where everything works.
///
/// It is also what SwiftUI previews use, so the paywall and the supporter badge can be designed
/// without a sandbox account or a device.
public actor InMemoryPurchaseController: PurchaseController {

    /// What the next `purchase(_:)` should do.
    public enum PurchaseBehaviour: Sendable {
        case succeeds
        case cancels
        case pends
        case fails
    }

    /// Thrown by `.fails`, and by `supporterTiers()` when `tiers` is empty.
    public struct StoreUnavailable: Error, Sendable {
        public init() {}
    }

    /// The three tiers the shipping app configures, for tests and previews that just need
    /// something realistic.
    public static let sampleTiers: [SupporterTier] = [
        SupporterTier(productIdentifier: "supporter.shot", displayName: "Buy me a well shot", displayPrice: "$1.99"),
        SupporterTier(productIdentifier: "supporter.pint", displayName: "Buy me a pint", displayPrice: "$4.99"),
        SupporterTier(productIdentifier: "supporter.round", displayName: "Buy me a round", displayPrice: "$9.99")
    ]

    private var status: SupporterStatus
    /// The product a `restorePurchases()` would find on this account, if any.
    private var priorPurchase: String?
    private let tiers: [SupporterTier]
    private let behaviour: PurchaseBehaviour

    /// The tier the last successful purchase was made at, so tests can confirm the app charged the
    /// tier it displayed rather than whichever one it felt like.
    public private(set) var lastPurchasedTier: SupporterTier?

    public init(
        status: SupporterStatus = .notSupporter,
        priorPurchase: String? = nil,
        tiers: [SupporterTier] = InMemoryPurchaseController.sampleTiers,
        behaviour: PurchaseBehaviour = .succeeds
    ) {
        self.status = status
        self.priorPurchase = priorPurchase
        self.tiers = tiers
        self.behaviour = behaviour
    }

    public func supporterTiers() async throws -> [SupporterTier] {
        guard !tiers.isEmpty else { throw StoreUnavailable() }
        return tiers
    }

    public func purchase(_ tier: SupporterTier) async throws -> PurchaseOutcome {
        switch behaviour {
        case .succeeds:
            status = .supporter(productIdentifier: tier.productIdentifier)
            priorPurchase = tier.productIdentifier
            lastPurchasedTier = tier
            return .purchased
        case .cancels:
            return .cancelled
        case .pends:
            return .pending
        case .fails:
            throw StoreUnavailable()
        }
    }

    public func restorePurchases() async throws -> RestoreOutcome {
        guard let priorPurchase else { return .nothingToRestore }
        status = .supporter(productIdentifier: priorPurchase)
        return .restored
    }

    public func supporterStatus() async -> SupporterStatus { status }
}
