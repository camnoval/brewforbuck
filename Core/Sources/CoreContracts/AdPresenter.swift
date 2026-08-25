/// Shows/hides the banner and the occasional interstitial (§6, §A). Real impl: RevenueCat Ads
/// (Week 2). Test impl: `NoopAdPresenter`. Gated: if `remove_ads` is active, the app never
/// constructs a real `AdPresenter` at all.
public protocol AdPresenter: Sendable {
    func showBanner()
    func hideBanner()
    func maybeShowInterstitial()
}
