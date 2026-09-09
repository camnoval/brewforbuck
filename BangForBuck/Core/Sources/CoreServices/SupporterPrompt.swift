//
//  SupporterPrompt.swift
//  Core
//
//  Created by Noval, Cameron on 9/9/26.
//


import CoreContracts
import CoreModel

/// When the app is allowed to ask for support, and how it refers to what was bought.
///
/// The rules are here rather than in the view because they are the product decision, not a layout
/// detail, and because each one is worth a test.
public enum SupporterPrompt {

    /// A ranking of one drink is not a comparison, so the app has not yet demonstrated anything
    /// worth paying for.
    public static let minimumRankedDrinks = 2

    /// Below this multiple the spread is not worth stating out loud. A menu where the best option
    /// is 1.05x the worst is a menu where it did not matter much what you ordered, and saying so
    /// with a flourish would be overselling.
    public static let minimumRatioWorthMentioning = 1.25

    /// Whether to offer the supporter prompt after a scan.
    ///
    /// Four rules, in order of how much they matter:
    ///
    /// 1. **Never ask a supporter.** They already paid. This is what makes it one-time.
    /// 2. **Never ask twice.** Declining is a real answer, and the caller persists that.
    /// 3. **Never ask on a thin read.** If `isLowConfidence` fired, the app is not confident in the
    ///    ranking it just produced, and asking for money on a job it may have done badly is the
    ///    wrong instinct. This is the rule most worth keeping when something has to give.
    /// 4. **Never ask without a real result.** Fewer than two ranked drinks means there is no
    ///    comparison to have been useful about.
    public static func shouldOffer(
        rankedCount: Int,
        isLowConfidence: Bool,
        status: SupporterStatus,
        hasAlreadyAsked: Bool
    ) -> Bool {
        guard !status.isActive else { return false }
        guard !hasAlreadyAsked else { return false }
        guard !isLowConfidence else { return false }
        guard rankedCount >= minimumRankedDrinks else { return false }
        return true
    }

    /// Whether the spread is worth putting in front of someone as a reason to support the app.
    public static func isWorthMentioning(_ spread: MenuValueSpread?) -> Bool {
        guard let spread else { return false }
        return spread.ratio >= minimumRatioWorthMentioning
    }
}

/// Which tier someone supported at, for the badge.
///
/// A closed set of kinds rather than a raw string, so the view picks a symbol and a word by
/// exhaustive switch and cannot be handed something it has no case for.
public enum SupporterTierKind: Sendable, Equatable, CaseIterable {

    case shot
    case pint
    case round

    /// Supported, but at a product this build does not recognize.
    ///
    /// Reached when a tier is added in the RevenueCat dashboard without a matching case here. The
    /// badge then says simply "Supporter", which stays true for any product that grants the
    /// entitlement. That is the point of having this case: a new tier degrades to a plainer badge
    /// rather than to a wrong one or a crash.
    case unspecified

    /// Resolve from the product identifier that granted the entitlement.
    ///
    /// Matches on suffix so the identifier prefix can change (`supporter.pint`, `abv.supporter.pint`)
    /// without touching this. Uses `hasSuffix`, which is Swift standard library, so `CoreServices`
    /// stays Foundation-free and keeps building on Linux (§7).
    public static func resolve(productIdentifier: String) -> SupporterTierKind {
        if productIdentifier.hasSuffix(".shot") { return .shot }
        if productIdentifier.hasSuffix(".pint") { return .pint }
        if productIdentifier.hasSuffix(".round") { return .round }
        return .unspecified
    }

    /// Resolve straight from an entitlement read. `nil` when this person is not a supporter, which
    /// is the case where no badge should appear at all.
    public static func resolve(status: SupporterStatus) -> SupporterTierKind? {
        switch status {
        case .notSupporter:
            return nil
        case .supporter(let productIdentifier):
            return resolve(productIdentifier: productIdentifier)
        }
    }
}
