//
//  ABVApp.swift
//  ABV
//
//  Created by Noval, Cameron on 8/25/26.
//


import SwiftUI
import CoreContracts

@main
struct ABVApp: App {

    /// The `supporter` entitlement, owned here so one read at launch serves the whole app (§A).
    ///
    /// **This is the one line that changes when the RevenueCat SDK lands.** Swap
    /// `InMemoryPurchaseController()` for `RevenueCatPurchases()`. Until then purchases are
    /// simulated: the paywall lays out and previews correctly, but nothing is charged and nothing
    /// is entitled, so this must not ship as is.
    @StateObject private var supporter = SupporterStore(purchases: InMemoryPurchaseController())

    var body: some Scene {
        WindowGroup {
            RootView(supporter: supporter)
                .tint(Theme.glass)
        }
    }
}
