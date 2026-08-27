//
//  EditableDrink.swift
//  Core
//
//  Created by Noval, Cameron on 8/27/26.
//

import CoreModel

/// An identity-bearing, *mutable* view of a parsed-and-enriched drink — the unit the capture-flow
/// UI edits (Week 1). It's the bridge between the pure one-shot pipeline (`[String] → MenuAnalysis`)
/// and an interactive session where the user corrects estimates and supplies missing prices.
///
/// Why this exists (see Handoff design note): `MenuAnalysis` is a display-only snapshot whose
/// `needsPrice` bucket is just `[String]`. That's fine for showing a ranking, but it can't support
/// *editing* — a correction re-parsed from scratch would be wiped, and a priceless line carries no
/// category/read-values to turn into a `DrinkOption` once the user types a price. `EditableDrink`
/// carries all of that forward, keyed by a stable `id`.
///
/// Invariants preserved (§10, Change B):
/// - Only **alcoholic** items ever become an `EditableDrink` — non-alcoholic items are excluded at
///   resolve time (`DrinkResolver`), so a mocktail can never gain a price and sneak into the rank.
/// - `price` is still the one axis that is never fabricated: a `nil` price means `needsPrice`, and
///   `pricedDrink` returns `nil` until the user supplies a real, positive `Price`.
public struct EditableDrink: Identifiable, Equatable, Sendable {
    /// Stable within a session (assigned from parse order). Lets the UI address a specific drink
    /// for correction even when two drinks share a name.
    public let id: Int
    public let name: String
    public let category: BeverageCategory
    /// `nil` ⇒ this drink still needs a price and cannot be ranked (§10).
    public var price: Price?
    /// Percent. `.read` if the menu printed it or the user corrected it; else `.estimated`.
    public var abv: Provenance<Double>
    public var size: Provenance<Volume>

    public init(
        id: Int,
        name: String,
        category: BeverageCategory,
        price: Price?,
        abv: Provenance<Double>,
        size: Provenance<Volume>
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.price = price
        self.abv = abv
        self.size = size
    }

    /// A parsed line still missing the one thing we won't guess.
    public var needsPrice: Bool { price == nil }

    /// True when either estimable axis is still a guess — drives the honesty badge (§11).
    public var hasEstimate: Bool { abv.isEstimated || size.isEstimated }

    /// Build the rankable type, or `nil` if there's still no price. Alcoholic-ness is guaranteed at
    /// session-build time, so `PricedDrink(_:)` here fails only in the impossible non-alcoholic case.
    public var pricedDrink: PricedDrink? {
        guard let price else { return nil }
        let option = DrinkOption(
            name: name, price: price, abv: abv, size: size, category: category
        )
        return PricedDrink(option)
    }
}
