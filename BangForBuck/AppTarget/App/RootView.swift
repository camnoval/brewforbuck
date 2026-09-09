//
//  RootView.swift
//  BangForBuck
//
//  Created by Noval, Cameron on 8/27/26.
//


import SwiftUI
import CoreContracts

/// App root: the 21+ gate (R3) guards first launch, then the capture flow. The confirmation is
/// persisted in `UserDefaults` via `@AppStorage`, so the gate shows once per install.
struct RootView: View {
    @ObservedObject var supporter: SupporterStore

    @AppStorage("hasConfirmedAge21") private var hasConfirmedAge21 = false

    var body: some View {
        if hasConfirmedAge21 {
            CaptureHomeView(supporter: supporter)
        } else {
            AgeGateView { hasConfirmedAge21 = true }
        }
    }
}

#Preview {
    RootView(supporter: SupporterStore(purchases: InMemoryPurchaseController()))
}
