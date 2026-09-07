import CoreModel

/// A ranked drink that keeps its editable identity, so the UI can rank a row *and* still correct it
/// (unlike `RankedDrink`, whose `PricedDrink` carries no `id` and would be ambiguous when two drinks
/// share a name). Value/rank semantics match `ValueRanker` exactly (see `rankedDrinks`).
public struct RankedEditable: Identifiable, Equatable, Sendable {
    public let drink: EditableDrink
    /// The metric value (higher = better for current metrics).
    public let value: Double
    /// 1 = best value.
    public let rank: Int

    public var id: Int { drink.id }

    public init(drink: EditableDrink, value: Double, rank: Int) {
        self.drink = drink
        self.value = value
        self.rank = rank
    }
}

/// The interactive value engine (Week 1). Holds the enriched drinks for one captured menu and
/// exposes pure edit operations — correct an estimate, or supply a missing price — that promote a
/// guess to `.read` (§11) and re-rank on the next read. All logic is pure and lives here in
/// `CoreServices` (§7); the ViewModel is a thin shell that mutates this value and republishes it.
///
/// The two load-bearing invariants survive editing:
/// - **Price is never fabricated (§10):** a drink with no price simply doesn't produce a
///   `PricedDrink`, so it can't be ranked; `setPrice` refuses non-positive input via `Price`'s guard.
/// - **Non-alcoholic never ranks (Change B):** non-alcoholic items never become `EditableDrink`s
///   (they're excluded at resolve time), so there's no edit that can promote one into the ranking.
public struct MenuSession: Equatable, Sendable {
    /// Every alcoholic drink from the menu, in parse order. Some may still be `needsPrice`.
    public private(set) var drinks: [EditableDrink]
    /// Non-alcoholic items, by name — shown as "excluded", not editable into the ranking.
    public let excludedNonAlcoholic: [String]
    /// Which metric to rank by. Mutable so the UI's segmented toggle just sets it and re-reads.
    public var metric: ValueMetric
    /// How well the menu was read (C). Advisory only — the ranking is always produced; when
    /// `quality.isLowConfidence` is true the UI should say the read was thin. Defaults to
    /// `.trusted`, so a hand-built session (manual entry, tests) is unaffected.
    public let quality: MenuQuality

    public init(
        drinks: [EditableDrink],
        excludedNonAlcoholic: [String],
        metric: ValueMetric,
        quality: MenuQuality = .trusted
    ) {
        self.drinks = drinks
        self.excludedNonAlcoholic = excludedNonAlcoholic
        self.metric = metric
        self.quality = quality
    }

    /// Whether to warn the person that the read was thin (C). Never suppresses the ranking.
    public var isLowConfidence: Bool { quality.isLowConfidence }

    // MARK: - Derived views (recomputed on read; cheap for menu-sized inputs)

    /// Best value first, ranks assigned. Mirrors `ValueRanker.rank`'s ordering and tiebreak
    /// (value, then name) exactly — it reuses the same internal metric function — but preserves
    /// each drink's `id` so a ranked row stays correctable.
    public var rankedDrinks: [RankedEditable] {
        let scored: [(EditableDrink, Double)] = drinks.compactMap { drink in
            guard let priced = drink.pricedDrink else { return nil }
            return (drink, ValueRanker.value(of: priced, metric: metric))
        }
        let sorted = scored.sorted { a, b in
            if a.1 != b.1 { return metric.higherIsBetter ? a.1 > b.1 : a.1 < b.1 }
            return a.0.name < b.0.name
        }
        return sorted.enumerated().map { index, item in
            RankedEditable(drink: item.0, value: item.1, rank: index + 1)
        }
    }

    /// Alcoholic drinks still missing a price — the "add a price" bucket (R1), in parse order.
    public var needsPriceDrinks: [EditableDrink] { drinks.filter { $0.needsPrice } }

    // MARK: - Edits (each promotes the touched estimate to `.read` and thus re-ranks)

    /// Correct an estimated ABV inline. Promotes that axis to `.read` (§11); no-op if `id` is stale.
    public mutating func correctABV(id: Int, to newValue: Double) {
        update(id) { $0.abv = $0.abv.corrected(to: newValue) }
    }

    /// Correct an estimated serving size inline. Promotes that axis to `.read` (§11).
    public mutating func correctSize(id: Int, to newFluidOunces: Double) {
        update(id) { $0.size = $0.size.corrected(to: Volume(fluidOunces: newFluidOunces)) }
    }

    /// Supply (or change) a price for a drink from cents. Non-positive input is ignored — `Price`'s
    /// failable init is the structural guard behind the price invariant (§10), so a fabricated or
    /// zero price can never take hold here.
    public mutating func setPrice(id: Int, cents: Int) {
        guard let price = Price(cents: cents) else { return }
        update(id) { $0.price = price }
    }

    /// Convenience for a price typed in dollars (rounds to the nearest cent).
    public mutating func setPrice(id: Int, dollars: Double) {
        setPrice(id: id, cents: Int((dollars * 100).rounded()))
    }

    // MARK: - Manual add / remove (user fixes what OCR missed)

    /// Add a drink the scan didn't pick up. Every axis is user-supplied, so ABV and size are `.read`
    /// (never flagged as a guess). Category defaults to `.unknown` — alcoholic, since this is an
    /// alcohol menu, so the drink is rankable without pretending we classified it; a non-alcoholic
    /// category is coerced to `.unknown` so a manual add can never smuggle a non-alcoholic item past
    /// Change B. `priceDollars` is optional: omit it and the drink lands in `needsPriceDrinks` until
    /// the user supplies one (§10 — a non-positive price is rejected by `Price` and treated as none).
    /// Returns the new drink's `id`, or `nil` if the name was blank.
    @discardableResult
    public mutating func addDrink(
        name: String,
        abv: Double,
        sizeFluidOunces: Double,
        priceDollars: Double? = nil,
        category: BeverageCategory = .unknown
    ) -> Int? {
        let cleanName = MenuSession.trimmed(name)
        guard !cleanName.isEmpty else { return nil }

        let newId = (drinks.map { $0.id }.max() ?? -1) + 1
        let drink = EditableDrink(
            id: newId,
            name: cleanName,
            category: category.isAlcoholic ? category : .unknown,
            price: priceDollars.flatMap { Price(dollars: $0) },
            abv: .read(abv),
            size: .read(Volume(fluidOunces: sizeFluidOunces))
        )
        drinks.append(drink)
        return newId
    }

    /// Remove a drink entirely — a misread line that isn't actually a drink, or a manual add made in
    /// error. No-op if `id` is stale.
    public mutating func removeDrink(id: Int) {
        drinks.removeAll { $0.id == id }
    }

    private mutating func update(_ id: Int, _ transform: (inout EditableDrink) -> Void) {
        guard let index = drinks.firstIndex(where: { $0.id == id }) else { return }
        transform(&drinks[index])
    }

    private static func trimmed(_ s: String) -> String {
        let whitespace: Set<Character> = [" ", "\t", "\n", "\r"]
        var chars = Array(s)
        while let first = chars.first, whitespace.contains(first) { chars.removeFirst() }
        while let last = chars.last, whitespace.contains(last) { chars.removeLast() }
        return String(chars)
    }
}
