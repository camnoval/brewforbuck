//
//  AgeGateView.swift
//  BangForBuck
//
//  Created by Noval, Cameron on 8/27/26.
//


import SwiftUI

/// The 21+ age gate shown on first launch (R3). The framing is strictly informational — a
/// price-comparison tool, not an encouragement to drink — which is the defensible posture for App
/// Review and ad-network alcohol policies. Confirmation is remembered so the gate appears once
/// (see `RootView`).
struct AgeGateView: View {
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.seal")
                .font(.system(size: 52))
                .foregroundStyle(.tint)

            Text("For adults 21 and over")
                .font(.title2).bold()
                .multilineTextAlignment(.center)

            Text("Bang-for-Buck is an informational price-comparison tool for weighing the value of drinks on a menu. It is not an encouragement to drink. By continuing, you confirm you are of legal drinking age (21+ in the US).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Button(action: onConfirm) {
                Text("I’m 21 or older").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .padding(24)
    }
}