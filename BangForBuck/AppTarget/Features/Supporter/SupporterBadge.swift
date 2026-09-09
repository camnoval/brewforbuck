//
//  SupporterBadge.swift
//  BangForBuck
//
//  Created by Noval, Cameron on 9/9/26.
//


import SwiftUI
import CoreServices

/// The quiet mark on the home screen saying this person bought a round.
///
/// Sits under the wordmark, in `Theme.glass` and `Theme.inkMuted`. **Never amber**: amber means
/// "this number is an estimate" and nothing else in this app, and a purchase badge wearing it would
/// quietly break that (§11).
struct SupporterBadge: View {
    let kind: SupporterTierKind

    var body: some View {
        HStack(spacing: Theme.Space.hair + 2) {
            Image(systemName: kind.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.glass)
            Text(kind.badgeText)
                .font(Theme.micro)
                .foregroundStyle(Theme.inkMuted)
        }
        .padding(.horizontal, Theme.Space.tight)
        .padding(.vertical, Theme.Space.hair)
        .background(Theme.wash(Theme.glass),
                    in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(kind.badgeText)
    }
}

/// Symbols and copy for each tier, in one place so the view never builds a string itself.
///
/// The symbol names are my best reading of what is available at your deployment target (18.6).
/// Verify them in the SF Symbols app and swap any that are missing: a bad `systemName` renders as
/// nothing rather than crashing, which is exactly the kind of silent gap that survives to the
/// App Store.
extension SupporterTierKind {

    var symbolName: String {
        switch self {
        case .shot: return "drop.fill"
        case .pint: return "mug.fill"
        case .round: return "wineglass.fill"
        case .unspecified: return "heart.fill"
        }
    }

    /// What the home-screen badge says. Warm and specific, because the point is to acknowledge a
    /// particular thing somebody did.
    var badgeText: String {
        switch self {
        case .shot: return "Thanks for the shot"
        case .pint: return "Thanks for the pint"
        case .round: return "Thanks for the round"
        case .unspecified: return "Thanks for the support"
        }
    }

    /// The heading on the paywall's thank-you state.
    var thanksHeadline: String {
        switch self {
        case .shot: return "Thanks for the shot"
        case .pint: return "Thanks for the pint"
        case .round: return "Thanks for the round"
        case .unspecified: return "Thanks for supporting ABV"
        }
    }
}

#Preview("Every tier") {
    VStack(alignment: .leading, spacing: Theme.Space.snug) {
        ForEach(SupporterTierKind.allCases, id: \.self) { kind in
            SupporterBadge(kind: kind)
        }
    }
    .padding(Theme.Space.loose)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.canvas)
}
