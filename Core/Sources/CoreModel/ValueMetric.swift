/// Which value metric to rank by. v1 ships `.standardDrinksPerDollar`; `.caloriesPerDollar` is the
/// v2 metric that runs on the *same* pipeline — adding it is the localized recipe in §14. The
/// formulas live in `ValueRanker` (CoreServices, Phase 4), not here, so the model carries no
/// business math (§4, §7).
public enum ValueMetric: String, CaseIterable, Sendable, Codable {
    case standardDrinksPerDollar
    /// v2 — alcohol-only kcal lower bound, heavily flagged (R4). Not shipped in v1.
    case caloriesPerDollar

    public var displayName: String {
        switch self {
        case .standardDrinksPerDollar: return "Drinks / $"
        case .caloriesPerDollar: return "Calories / $"
        }
    }

    /// Higher = better value for both current metrics.
    public var higherIsBetter: Bool { true }
}
