import CoreModel

/// The value engine's payoff (§7): turn priced, alcoholic drinks into a ranking, best value first.
/// Pure math — no I/O, no framework — so the whole thing is fixture-testable in milliseconds.
///
/// Takes `[PricedDrink]`, which structurally cannot contain a nil price (§10) or a non-alcoholic
/// item (Change B). So a menu line with no readable price never had the type required to reach this
/// function — the price invariant is enforced upstream by construction, not re-checked here.
public struct ValueRanker {
    public init() {}

    /// Rank best value first. Ties break by name for deterministic output.
    public func rank(_ drinks: [PricedDrink], by metric: ValueMetric) -> [RankedDrink] {
        let scored = drinks.map { (drink: $0, value: Self.value(of: $0, metric: metric)) }
        let sorted = scored.sorted { a, b in
            if a.value != b.value {
                return metric.higherIsBetter ? a.value > b.value : a.value < b.value
            }
            return a.drink.name < b.drink.name
        }
        return sorted.enumerated().map { index, item in
            RankedDrink(drink: item.drink, metric: metric, value: item.value, rank: index + 1)
        }
    }

    // MARK: - The metric

    /// 0.6 fl oz of pure ethanol = 1 US standard drink (NIAAA).
    static let ethanolFlozPerStandardDrink = 0.6
    /// 1 US fl oz = 29.5735 mL; ethanol density ≈ 0.789 g/mL ⇒ ≈ 23.34 g ethanol per fl oz.
    static let ethanolGramsPerFloz = 29.5735 * 0.789
    /// Ethanol yields ≈ 7.1 kcal/g.
    static let kcalPerGramEthanol = 7.1

    /// Pure ethanol in the serving, in fluid ounces: size × (ABV / 100).
    static func pureEthanolFloz(_ d: PricedDrink) -> Double {
        pureEthanolFloz(sizeFloz: d.size.value.fluidOunces, abvPercent: d.abv.value)
    }

    /// US standard drinks in the serving.
    static func standardDrinks(_ d: PricedDrink) -> Double {
        standardDrinks(sizeFloz: d.size.value.fluidOunces, abvPercent: d.abv.value)
    }

    // MARK: - Shared primitive (menu ranker AND store comparison)

    /// Pure ethanol (fl oz) from size and ABV alone. The one place the size×ABV rule lives.
    public static func pureEthanolFloz(sizeFloz: Double, abvPercent: Double) -> Double {
        max(0, sizeFloz) * (max(0, abvPercent) / 100.0)
    }

    /// US standard drinks from size and ABV alone — reused by `StoreComparison` for whole packages
    /// (size × count) so both features score alcohol on the identical NIAAA definition.
    public static func standardDrinks(sizeFloz: Double, abvPercent: Double) -> Double {
        pureEthanolFloz(sizeFloz: sizeFloz, abvPercent: abvPercent) / ethanolFlozPerStandardDrink
    }

    /// The metric value for a drink. Higher = better value for both current metrics.
    static func value(of d: PricedDrink, metric: ValueMetric) -> Double {
        let dollars = d.price.dollars
        guard dollars > 0 else { return 0 }   // Price already guarantees > 0; belt and suspenders.
        switch metric {
        case .standardDrinksPerDollar:
            return standardDrinks(d) / dollars
        case .caloriesPerDollar:
            // v2, alcohol-only kcal lower bound (R4): sugars/mixers not modeled.
            let kcal = pureEthanolFloz(d) * ethanolGramsPerFloz * kcalPerGramEthanol
            return kcal / dollars
        }
    }
}
