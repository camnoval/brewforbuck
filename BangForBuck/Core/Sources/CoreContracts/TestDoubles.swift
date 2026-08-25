import CoreModel

/// Lightweight reference/test doubles for the shell-facing contracts. Public so any test target (or
/// a SwiftUI preview) can use them without a separate support module. The *real* implementations
/// live in the app's Infrastructure layer (Weeks 1–2).

/// Returns canned OCR lines, ignoring the image. This is how the whole pure pipeline is exercised
/// without a camera — feed it transcribed fixture lines (Tooling/Fixtures).
public struct FakeTextRecognizer: TextRecognizer {
    public let lines: [String]
    public init(lines: [String]) { self.lines = lines }
    public func recognizeLines(in image: CapturedImage) async throws -> [String] { lines }
}

/// In-memory entitlement, toggled by a fake purchase. An actor so its mutable state is concurrency-safe.
public actor InMemoryPurchaseController: PurchaseController {
    private var active: Bool
    public init(removeAdsActive: Bool = false) { self.active = removeAdsActive }
    public func isRemoveAdsActive() async -> Bool { active }
    public func purchaseRemoveAds() async throws { active = true }
    public func restorePurchases() async throws { /* keeps current state */ }
}

/// Does nothing — used in tests and whenever ads are gated off.
public struct NoopAdPresenter: AdPresenter {
    public init() {}
    public func showBanner() {}
    public func hideBanner() {}
    public func maybeShowInterstitial() {}
}
