//
//  ABVApp.swift
//  BangForBuck
//
//  Created by Noval, Cameron on 8/25/26.
//


import SwiftUI

@main
struct ABVApp: App {

    /// The `supporter` entitlement, owned here so one read at launch serves the whole app (§A).
    @StateObject private var supporter: SupporterStore

    /// Configure the SDK before anything can call it, then build the store around the real
    /// conformer.
    ///
    /// Done in `init` rather than as a property default so the ordering is visible: a property
    /// initializer runs *before* the init body, and "configure before any other SDK call" is a
    /// documented requirement rather than a preference. Nothing in `SupporterStore.init` touches
    /// the SDK today, so the property-default form happened to work; this one cannot stop working
    /// if that changes.
    init() {
        RevenueCatPurchases.configure()
        _supporter = StateObject(wrappedValue: SupporterStore(purchases: RevenueCatPurchases()))
    }

    var body: some Scene {
        WindowGroup {
            RootView(supporter: supporter)
                .tint(Theme.glass)
        }
    }
}
