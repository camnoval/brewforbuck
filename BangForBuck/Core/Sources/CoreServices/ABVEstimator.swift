import CoreModel
import CoreContracts

/// Resolve a drink's ABV with provenance (§7, §11): the menu's printed value is `.read`; otherwise
/// the profile's typical value is `.estimated`, carrying the profile's note (brand / style / fallback).
///
/// **A printed value that can't be right for its category is discarded, not corrected.** `(4.2%)`
/// read as `(42%)` ranked a 20 oz Guinness at 42% ABV — roughly 14 standard drinks, 1.40 per dollar,
/// badged "from menu" as though somebody had measured it. That is precisely the §11 violation the
/// invariant exists to prevent, so the read is dropped and the knowledge estimate used in its place,
/// badged `.estimated`. Dividing by ten instead would be a fabrication wearing a `.read` badge: we
/// cannot tell a misplaced decimal from a genuinely strong pour, and guessing which is a guess.
public enum ABVEstimator {
    public static func estimate(_ item: MenuItem, profile: BeverageProfile) -> Provenance<Double> {
        if let printed = item.readABV, isPlausible(printed, for: item.category) {
            return .read(printed)
        }
        return .estimated(profile.typicalABV, note: profile.abvNote)
    }

    /// Whether a printed percentage is credible for this category. Non-positive is never credible;
    /// otherwise it must sit at or below the category's ceiling. A category with no ceiling has no
    /// basis to judge, so the printed value stands.
    public static func isPlausible(_ abv: Double, for category: BeverageCategory) -> Bool {
        guard abv > 0 else { return false }
        guard let ceiling = abvCeiling(for: category) else { return true }
        return abv <= ceiling
    }

    /// The strongest percentage this category can credibly print.
    ///
    /// **These are derived, not tuned.** The error being caught is a lost decimal point, which
    /// always multiplies by exactly ten, so a ceiling works as long as it sits above the strongest
    /// product really sold and below ten times the weakest. Both bounds come from real products:
    ///
    /// | Category | Strongest real | 10× weakest real | Ceiling |
    /// |---|---|---|---|
    /// | draft / bottled beer | Samuel Adams Utopias 28% | 3.0% → 30% | 30 |
    /// | cider | ice cider ~12% | 4.0% → 40% | 20 |
    /// | seltzer | ~8% | 4.0% → 40% | 20 |
    /// | wine / sangria | sherry 24%, fortified 20% | 5.5% → 55% | 30 |
    /// | frozen cocktail | frozen daiquiri ~15% | 5.0% → 50% | 40 |
    /// | cocktail | spirit-forward ~35% | 8.0% → 80% | 45 |
    /// | martini | stirred, barely diluted ~35% | — | 50 |
    /// | shot | Everclear 95%, Spirytus 96% | — | 96 |
    /// | non-alcoholic | 0.5% by law | — | 1 |
    ///
    /// The spirit-forward three sit high on purpose: a Zombie, a Sazerac or a barely-diluted stirred
    /// martini really is most of the way to neat spirit, and demoting a printed 38% would throw away
    /// a read value to protect against an error a cocktail menu almost never makes (printed ABVs are
    /// rare outside beer). **45 is the ceiling for `cocktail`, not a preference** — anything higher
    /// stops catching the 50% case, which is the tenfold misread of a 5% highball.
    ///
    /// Beer is the tight one: Utopias at 28% leaves only a 2-point margin, so the ceiling catches a
    /// dropped decimal on anything at or above 3.0% and lets one on a 2.8% session beer through.
    /// That is the right way round — a wrongly kept 28% is one item, a wrongly discarded 28% is a
    /// real Utopias silently demoted to the style chart.
    ///
    /// `.unknown` deliberately has **no** ceiling: it is the category we assigned because we could
    /// not classify the line, so it carries no expectation to violate. Judging against a guess would
    /// be inventing evidence.
    public static func abvCeiling(for category: BeverageCategory) -> Double? {
        switch category {
        case .draftBeer, .bottledBeer: return 30
        case .cider, .seltzer: return 20
        case .wineGlass, .sangria: return 30
        case .cocktail: return 45
        case .frozenCocktail: return 40
        case .martini: return 50
        case .shot: return 96
        case .nonAlcoholic: return 1
        case .unknown: return nil
        }
    }
}
