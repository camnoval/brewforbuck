//
//  AgeGateView.swift
//  ABV
//
//  Created by Noval, Cameron on 8/27/26.
//


import SwiftUI

/// The 21+ gate shown on first launch (R3). The framing is strictly informational — a
/// price-comparison tool, not an encouragement to drink — which is the defensible posture for App
/// Review and ad-network alcohol policies. Confirmation is remembered so the gate appears once
/// (see `RootView`).
///
/// Left-aligned on purpose. A centred hero paragraph is the default treatment for a screen like
/// this, and it makes a legal notice read like marketing; ranged left, it reads as a statement the
/// person is being asked to agree with.
struct AgeGateView: View {
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: Theme.Space.wide)

            Wordmark(size: 52)

            Text("Ranks the drinks on a menu by how much alcohol you get for your money.")
                .font(Theme.title)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.loose)

            Text("An informational price-comparison tool, not an encouragement to drink. Anything it has to estimate is labelled as an estimate, and you can correct it.")
                .font(Theme.callout)
                .foregroundStyle(Theme.inkMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.snug)

            Spacer()

            Text("Continuing confirms you are of legal drinking age, 21 or over in the US.")
                .font(Theme.label)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Theme.Space.snug)

            Button("I am 21 or older", action: onConfirm)
                .buttonStyle(PourButtonStyle())
        }
        .padding(.horizontal, Theme.Space.loose)
        .padding(.bottom, Theme.Space.loose)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.canvas.ignoresSafeArea())
    }
}

#Preview { AgeGateView {} }
