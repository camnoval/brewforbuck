import XCTest
@testable import CoreContracts
@testable import CoreModel

final class ContractsSmokeTests: XCTestCase {
    func testFakeTextRecognizerReturnsCannedLines() async throws {
        let fake = FakeTextRecognizer(lines: ["Sunset Tea $8", "IPA 6"])
        let lines = try await fake.recognizeLines(in: CapturedImage(pngData: []))
        XCTAssertEqual(lines, ["Sunset Tea $8", "IPA 6"])
    }

    func testInMemoryPurchaseControllerTogglesEntitlement() async throws {
        let purchases = InMemoryPurchaseController()
        let before = await purchases.isRemoveAdsActive()
        XCTAssertFalse(before)
        try await purchases.purchaseRemoveAds()
        let after = await purchases.isRemoveAdsActive()
        XCTAssertTrue(after)
    }

    func testNoopAdPresenterDoesNothing() {
        let ads = NoopAdPresenter()
        ads.showBanner(); ads.maybeShowInterstitial(); ads.hideBanner()
        // No crash, no state — the point of the no-op double.
    }
}
