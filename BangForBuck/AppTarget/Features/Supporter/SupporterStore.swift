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
/// Everything here is plumbing (§7): reading the entitlement, remembering that we asked once, and
/// forwarding to the injected `PurchaseController`. Every actual decision lives in
/// `SupporterPrompt` and `PaywallFlow`, in `Core`, with tests.
///
/// Matches `ResultsViewModel`'s shape on purpose: `ObservableObject` with `@Published`, not the
/// `@Observable` macro, so the two view models behave the same way.
@MainActor
final class SupporterStore: ObservableObject {

    /// Whether this person has supported the app, and with which tier. Read once at launch, then
    /// again after a purchase or a restore.
    @Published private(set) var status: SupporterStatus = .notSupporter

    /// Whether the prompt has already been shown once. Persisted, because declining is a real
    /// answer that should outlive the launch.
    @Published private(set) var hasAlreadyAsked: Bool

    let purchases: any PurchaseController

    private let askedKey = "hasAskedForSupport"

    init(purchases: any PurchaseController) {
        self.purchases = purchases
        self.hasAlreadyAsked = UserDefaults.standard.bool(forKey: askedKey)
    }

    /// Which badge to show, or `nil` for someone who has not supported the app.
    var tierKind: SupporterTierKind? {
        SupporterTierKind.resolve(status: status)
    }

    /// Re-read the entitlement. Cheap, and safe to call on every appearance.
    func refresh() async {
        status = await purchases.supporterStatus()
    }

    /// Whether to offer the prompt after a scan. Delegates the whole decision to `Core`.
    func shouldOffer(rankedCount: Int, isLowConfidence: Bool) -> Bool {
        SupporterPrompt.shouldOffer(
            rankedCount: rankedCount,
            isLowConfidence: isLowConfidence,
            status: status,
            hasAlreadyAsked: hasAlreadyAsked
        )
    }

    /// Record that the prompt has been shown, so it never appears again.
    ///
    /// Called when the prompt is *displayed*, not when it is accepted. Someone who scrolled past it
    /// has seen the ask, and asking again on the next scan would be nagging.
    func markAsked() {
        guard !hasAlreadyAsked else { return }
        hasAlreadyAsked = true
        UserDefaults.standard.set(true, forKey: askedKey)
    }
}
