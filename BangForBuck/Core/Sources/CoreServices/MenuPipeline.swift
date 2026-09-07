import CoreModel
import CoreContracts

/// The end-to-end value engine (§7), still headless: OCR lines → parse → enrich → rank.
/// One call turns `[String]` into a ranked list plus the two honest side-buckets:
/// `needsPrice` (couldn't read a price — never guessed, §10) and `excludedNonAlcoholic`
/// (had a price but isn't alcohol — dropped before ranking, Change B).
public struct MenuAnalysis: Equatable {
    public let ranked: [RankedDrink]
    public let needsPrice: [String]
    public let excludedNonAlcoholic: [String]
    /// How well the menu was read (C). Advisory: when `quality.isLowConfidence` is true the caller
    /// should say the read was thin, but the ranking is still populated.
    public let quality: MenuQuality

    public init(ranked: [RankedDrink], needsPrice: [String], excludedNonAlcoholic: [String],
                quality: MenuQuality = .trusted) {
        self.ranked = ranked
        self.needsPrice = needsPrice
        self.excludedNonAlcoholic = excludedNonAlcoholic
        self.quality = quality
    }
}

public struct MenuPipeline {
    private let knowledge: BeverageKnowledge
    private let parser = MenuParser()
    private let ranker = ValueRanker()

    public init(knowledge: BeverageKnowledge = StaticBeverageKnowledge()) {
        self.knowledge = knowledge
    }

    /// Editable capture-flow entry point (Week 1): the same parse+enrich as `analyze`, but returns a
    /// mutable `MenuSession` the UI can correct and add prices to, then re-rank. `analyze` is the
    /// read-only snapshot over the same data.
    public func makeSession(lines: [String], metric: ValueMetric) -> MenuSession {
        var drinks: [EditableDrink] = []
        var excluded: [String] = []
        // A price that doesn't fit the rest of this menu is withdrawn before enrichment, so the item
        // travels the `needsPrice` path instead of ranking on a misread ("7-Up 415" at $415). Applied
        // here rather than in either caller because `analyze` delegates to this method, so both paths
        // see identical data by construction (§10).
        let items = PricePlausibility.withdrawingImplausiblePrices(parser.parse(lines))
        // Parse order gives each drink a stable id for inline correction.
        for (index, item) in items.enumerated() {
            let (drink, excludedName) = DrinkResolver.resolve(item, id: index, knowledge: knowledge)
            if let drink { drinks.append(drink) }
            if let excludedName { excluded.append(excludedName) }
        }
        // C — judged on the parser's own output, which is what was measured, and before enrichment
        // drops the non-alcoholic items, so the denominator is "lines that parsed as a drink".
        return MenuSession(drinks: drinks, excludedNonAlcoholic: excluded, metric: metric,
                           quality: MenuQualityGate.assess(items))
    }

    /// One-shot read-only analysis. Kept for the headless demo and existing tests; internally it's
    /// the initial snapshot of `makeSession`, so the two paths can never disagree.
    public func analyze(lines: [String], metric: ValueMetric) -> MenuAnalysis {
        let session = makeSession(lines: lines, metric: metric)
        let priced = session.drinks.compactMap { $0.pricedDrink }
        return MenuAnalysis(
            ranked: ranker.rank(priced, by: metric),
            needsPrice: session.needsPriceDrinks.map { $0.name },
            excludedNonAlcoholic: session.excludedNonAlcoholic,
            quality: session.quality
        )
    }
}
