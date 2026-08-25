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

    public func analyze(lines: [String], metric: ValueMetric) -> MenuAnalysis {
        var priced: [PricedDrink] = []
        var needsPrice: [String] = []
        var excluded: [String] = []

        for item in parser.parse(lines) {
            let sectionCat: BeverageCategory? = item.category == .unknown ? nil : item.category
            let profile = knowledge.profile(for: item.name, sectionCategory: sectionCat)

            // Non-alcoholic (by section or brand) never ranks (Change B).
            if profile.category == .nonAlcoholic {
                excluded.append(item.name)
                continue
            }
            // No readable price → the "add a price" bucket, never a guessed price (§10).
            guard let price = item.price else {
                needsPrice.append(item.name)
                continue
            }

            let option = DrinkOption(
                name: item.name, price: price,
                abv: ABVEstimator.estimate(item, profile: profile),
                size: SizeEstimator.estimate(item, profile: profile),
                category: profile.category
            )
            guard let pricedDrink = PricedDrink(option) else {
                excluded.append(item.name)   // defensive: category flipped non-alcoholic
                continue
            }
            priced.append(pricedDrink)
        }

        return MenuAnalysis(
            ranked: ranker.rank(priced, by: metric),
            needsPrice: needsPrice,
            excludedNonAlcoholic: excluded
        )
    }
}
