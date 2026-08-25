/// The ranker's output (§7): a `PricedDrink` plus its computed value under the chosen metric and
/// its position. A pure data holder — the computation itself lives in `ValueRanker` (Phase 4).
public struct RankedDrink: Equatable, Sendable {
    public let drink: PricedDrink
    public let metric: ValueMetric
    /// The metric value, e.g. standard drinks per dollar. Higher = better for current metrics.
    public let value: Double
    /// 1 = best value.
    public let rank: Int

    public init(drink: PricedDrink, metric: ValueMetric, value: Double, rank: Int) {
        self.drink = drink
        self.metric = metric
        self.value = value
        self.rank = rank
    }
}
