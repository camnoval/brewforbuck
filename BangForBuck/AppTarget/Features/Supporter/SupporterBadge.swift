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

    /// The rank the tier earns, in the same metals as the podium.
    ///
    /// Cheapest tier is bronze and the dearest is gold, which is the obvious reading and the same
    /// order `RankMedal` uses. `.unspecified` gets bottle green rather than a metal, because a tier
    /// this build does not recognize has no place in the ordering and guessing one would be a
    /// fabricated rank.
    var metal: Color {
        switch self {
        case .shot: return Theme.bronze
        case .pint: return Theme.silver
        case .round: return Theme.gold
        case .unspecified: return Theme.glass
        }
    }

    /// The line under the thank-you, in that tier's metal.
    var contributorTitle: String {
        switch self {
        case .shot: return "Shot Contributor"
        case .pint: return "Pint Contributor"
        case .round: return "Round Contributor"
        case .unspecified: return "Contributor"
        }
    }
}

/// The big mark on the thank-you screen.
///
/// Separate from `symbolName` because **a round is not one drink.** SF Symbols has no clinking-mugs
/// glyph (searched 2026-09-09; the 🍻 emoji exists but cannot be tinted, so it could not be gold),
/// so the round is composed from two `mug.fill` leaning into each other. That gives the tiers an
/// honest progression: a drop, a mug, two mugs.
///
/// `symbolName` is still the single glyph, and the small badge and toolbar button keep using it: two
/// overlapped mugs at 11pt would be mush, and the round needs to stay distinguishable from the pint
/// at that size.
struct ContributorMark: View {
    let kind: SupporterTierKind
    var size: CGFloat = 68

    var body: some View {
        Group {
            if kind == .round {
                HStack(spacing: -size * 0.13) {
                    Image(systemName: "mug.fill")
                        // The **left** mug is the mirrored one. `mug.fill` draws its handle on the
                        // right, so flipping the right mug put both handles in the middle, facing
                        // each other; flipping the left one puts them on the outside where a pair
                        // of mugs actually has them.
                        .scaleEffect(x: -1)
                        .rotationEffect(.degrees(12))
                    Image(systemName: "mug.fill")
                        .rotationEffect(.degrees(-12))
                }
                .font(.system(size: size * 0.76, weight: .semibold))
            } else {
                Image(systemName: kind.symbolName)
                    .font(.system(size: size, weight: .semibold))
            }
        }
        .foregroundStyle(kind.metal)
        // The surrounding text already says the tier and the thanks, so this is decoration to a
        // screen reader.
        .accessibilityHidden(true)
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

#Preview("Every contributor mark") {
    VStack(spacing: Theme.Space.wide) {
        ForEach(SupporterTierKind.allCases, id: \.self) { kind in
            VStack(spacing: Theme.Space.tight) {
                ContributorMark(kind: kind, size: 56)
                Text(kind.contributorTitle)
                    .font(Theme.display(19, .heavy))
                    .foregroundStyle(kind.metal)
            }
        }
    }
    .padding(Theme.Space.loose)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.canvas)
}
