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

    public init(ranked: [RankedDrink], needsPrice: [String], excludedNonAlcoholic: [String]) {
        self.ranked = ranked
        self.needsPrice = needsPrice
        self.excludedNonAlcoholic = excludedNonAlcoholic
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
        // Parse order gives each drink a stable id for inline correction.
        for (index, item) in parser.parse(lines).enumerated() {
            let (drink, excludedName) = DrinkResolver.resolve(item, id: index, knowledge: knowledge)
            if let drink { drinks.append(drink) }
            if let excludedName { excluded.append(excludedName) }
        }
        return MenuSession(drinks: drinks, excludedNonAlcoholic: excluded, metric: metric)
    }

    /// One-shot read-only analysis. Kept for the headless demo and existing tests; internally it's
    /// the initial snapshot of `makeSession`, so the two paths can never disagree.
    public func analyze(lines: [String], metric: ValueMetric) -> MenuAnalysis {
        let session = makeSession(lines: lines, metric: metric)
        let priced = session.drinks.compactMap { $0.pricedDrink }
        return MenuAnalysis(
            ranked: ranker.rank(priced, by: metric),
            needsPrice: session.needsPriceDrinks.map { $0.name },
            excludedNonAlcoholic: session.excludedNonAlcoholic
        )
    }
}
