//
//  SupporterStore.swift
//  BangForBuck
//
//  Created by Noval, Cameron on 9/9/26.
//

import Combine
import SwiftUI
import CoreContracts
import CoreServices

/// Holds the `supporter` entitlement for the whole app, and the one persisted bit the pure layer
/// cannot hold for itself.
///
/// Everything here is plumbing (§7): reading the entitlement, counting scans, and forwarding to the
/// injected `PurchaseController`. Every actual decision lives in `SupporterPrompt` and
/// `PaywallFlow`, in `Core`, with tests.
///
/// Matches `ResultsViewModel`'s shape on purpose: `ObservableObject` with `@Published`, not the
/// `@Observable` macro, so the two view models behave the same way.
@MainActor
final class SupporterStore: ObservableObject {

    /// Whether this person has supported the app, and with which tier. Read once at launch, then
    /// again after a purchase or a restore.
    @Published private(set) var status: SupporterStatus = .notSupporter

    /// How many scans have finished since the prompt was last shown. Persisted, because the cadence
    /// has to outlive the launch to mean anything.
    @Published private(set) var scansSinceLastAsk: Int

    let purchases: any PurchaseController

    private let scansKey = "scansSinceLastAsk"

    init(purchases: any PurchaseController) {
        self.purchases = purchases
        // A fresh install starts at the interval, so the first scan that earns an ask gets one
        // rather than making somebody scan three menus before the app mentions it exists.
        let stored = UserDefaults.standard.object(forKey: scansKey) as? Int
        self.scansSinceLastAsk = stored ?? SupporterPrompt.scansBetweenAsks
    }

    /// Which badge to show, or `nil` for someone who has not supported the app.
    var tierKind: SupporterTierKind? {
        SupporterTierKind.resolve(status: status)
    }

    /// Re-read the entitlement. Cheap, and safe to call on every appearance.
    func refresh() async {
        status = await purchases.supporterStatus()
    }

    /// Count a finished scan.
    ///
    /// Called once per results screen, **including for a thin read that will not ask**. The counter
    /// measures how much use the app has had, not how many times it has asked, so a run of bad
    /// photos still earns the next good one an ask.
    func recordScan() {
        scansSinceLastAsk += 1
        UserDefaults.standard.set(scansSinceLastAsk, forKey: scansKey)
    }

    /// Whether to offer the prompt after a scan. Delegates the whole decision to `Core`.
    func shouldOffer(rankedCount: Int, isLowConfidence: Bool) -> Bool {
        SupporterPrompt.shouldOffer(
            rankedCount: rankedCount,
            isLowConfidence: isLowConfidence,
            status: status,
            scansSinceLastAsk: scansSinceLastAsk
        )
    }

    /// Record that the prompt has been shown, restarting the interval.
    ///
    /// Called when the prompt is *displayed*, not when it is accepted. Someone who dismissed it has
    /// seen the ask, and showing it again on the next scan would be nagging. What changed on
    /// 2026-09-09 is only that the interval restarts rather than closing forever.
    func markAsked() {
        scansSinceLastAsk = 0
        UserDefaults.standard.set(0, forKey: scansKey)
    }
}
