//
//  PaywallFlow.swift
//  Core
//
//  Created by Noval, Cameron on 9/9/26.
//

import CoreContracts

/// What the paywall is showing right now.
///
/// Every state that carries tiers carries them explicitly, so backing out of a purchase returns to
/// the same list without re-fetching. There is no state that means "showing prices I do not have":
/// either the tiers are in hand or the state is `.loading` or `.unavailable` (§10).
public enum PaywallState: Equatable, Sendable {

    /// Fetching tiers. No prices on screen.
    case loading

    /// The store could not be reached or has no tiers configured. Shows a retry and **no prices**,
    /// rather than a plausible-looking guess.
    case unavailable

    /// Tiers in hand, waiting on a choice. `notice` carries the outcome of a previous attempt, if
    /// there was one.
    case ready(tiers: [SupporterTier], notice: PaywallNotice?)

    /// A purchase is in flight for `chosen`. Tiers are retained so a cancel lands back on the list.
    case purchasing(tiers: [SupporterTier], chosen: SupporterTier)

    /// A restore is in flight. Separate from `.ready` so the button can disable itself and the
    /// person is not left wondering whether the tap registered.
    case restoring(tiers: [SupporterTier])

    /// Ask to Buy or a bank challenge. Nothing is owed yet and the entitlement is not active, so
    /// this must not read as a thank-you.
    case pending

    /// Supported. `productIdentifier` is present when this state was reached by a purchase, and
    /// `nil` when reached by a restore, where the outcome does not say which product was found.
    /// In the `nil` case the caller re-reads `supporterStatus()` to name the tier.
    case thanks(productIdentifier: String?)
}

/// Something that happened on the previous attempt and needs saying once.
public enum PaywallNotice: Equatable, Sendable {

    /// The purchase failed for a reason that is not a cancel. Offer another go.
    case purchaseDidNotGoThrough

    /// The restore worked and this Apple Account owns nothing. Said plainly, because the
    /// alternative is thanking someone for a purchase they never made.
    case nothingToRestore

    /// The restore call itself failed. Different from `nothingToRestore`: the question of whether
    /// they own something is still unanswered.
    case restoreDidNotGoThrough
}

/// Things the view or the shell reports to the flow.
public enum PaywallEvent: Equatable, Sendable {
    case appeared
    case tiersLoaded([SupporterTier])
    case tiersFailed
    case retryRequested
    case tierChosen(SupporterTier)
    case purchaseFinished(PurchaseOutcome)
    case purchaseFailed
    case restoreRequested
    case restoreFinished(RestoreOutcome)
    case restoreFailed
}

/// The paywall's transitions, as one pure function.
///
/// No SwiftUI, no SDK, no clock. The view holds a `PaywallState`, hands events in, and renders
/// whatever comes back, which is what keeps the sheet free of business logic (house style) and makes
/// all six outcomes testable in milliseconds.
public enum PaywallFlow {

    /// Where a freshly presented paywall starts.
    public static let initial: PaywallState = .loading

    /// The next state, or the current one unchanged when the event does not apply.
    ///
    /// Ignoring inapplicable events on purpose: a late reply from a call the person already backed
    /// out of should not resurrect a dismissed sheet or move a finished purchase backwards.
    public static func next(from state: PaywallState, on event: PaywallEvent) -> PaywallState {
        switch (state, event) {

        // MARK: Loading the tiers

        case (.loading, .tiersLoaded(let tiers)):
            // An empty list is not something to show a paywall for.
            return tiers.isEmpty ? .unavailable : .ready(tiers: tiers, notice: nil)

        case (.loading, .tiersFailed):
            return .unavailable

        case (.unavailable, .retryRequested):
            return .loading

        // MARK: Choosing and buying

        case (.ready(let tiers, _), .tierChosen(let chosen)):
            return .purchasing(tiers: tiers, chosen: chosen)

        case (.purchasing(_, let chosen), .purchaseFinished(.purchased)):
            return .thanks(productIdentifier: chosen.productIdentifier)

        case (.purchasing(let tiers, _), .purchaseFinished(.cancelled)):
            // A cancel is not a failure, so no notice. Back to the list, silently.
            return .ready(tiers: tiers, notice: nil)

        case (.purchasing, .purchaseFinished(.pending)):
            return .pending

        case (.purchasing(let tiers, _), .purchaseFailed):
            return .ready(tiers: tiers, notice: .purchaseDidNotGoThrough)

        // MARK: Restoring

        case (.ready(let tiers, _), .restoreRequested):
            return .restoring(tiers: tiers)

        case (.restoring, .restoreFinished(.restored)):
            return .thanks(productIdentifier: nil)

        case (.restoring(let tiers), .restoreFinished(.nothingToRestore)):
            return .ready(tiers: tiers, notice: .nothingToRestore)

        case (.restoring(let tiers), .restoreFailed):
            return .ready(tiers: tiers, notice: .restoreDidNotGoThrough)

        // MARK: Everything else

        default:
            return state
        }
    }
}
