/// The kind of drink. Used to (a) look up a typical ABV/pour when the menu doesn't print them
/// (`BeverageKnowledge`, Phase 3) and (b) decide what is rankable. The case set was drawn from the
/// section headers actually seen across 16 real menus — see
/// `Tooling/Fixtures/INSPECTION_FINDINGS.md` (§Finding 3).
public enum BeverageCategory: String, CaseIterable, Sendable, Codable {
    case draftBeer
    case bottledBeer
    case cider
    case wineGlass
    case sangria
    case cocktail
    case frozenCocktail
    case martini
    case shot
    case seltzer
    case nonAlcoholic
    /// A priced drink we couldn't classify. Treated as alcoholic (this is an alcohol menu) and
    /// flagged via estimation downstream — better to include-and-flag than silently drop.
    case unknown

    /// Change B (INSPECTION_FINDINGS §Finding 3): non-alcoholic items carry a real price, so the
    /// price invariant won't catch them — but a $7 mocktail ranked at "0 drinks per dollar" would
    /// pollute the list. Making this intrinsic lets `PricedDrink` refuse non-alcoholic items
    /// structurally, so they're dropped before the metric ever runs.
    public var isAlcoholic: Bool { self != .nonAlcoholic }
}
