/// A drink's price, and the single structural guard behind the price invariant (§10, R-invariant):
/// `Price` cannot represent a missing, zero, or negative amount. Its only initializers are failable
/// and reject non-positive values, so anything holding a `Price` provably had a real, positive price
/// read off the menu. A line with no readable price never produces a `Price`, so it can never be
/// assembled into a `DrinkOption`, so it can never reach the ranker.
///
/// Money is stored as integer **cents** — exact, no floating/decimal fuzz. Deliberately uses no
/// `Foundation` (no `Decimal`), which keeps `CoreModel` a zero-dependency module (§4) and also
/// side-steps a known explicit-modules toolchain bug that reports a bogus Foundation↔CoreModel
/// cycle. Currency itself is a UI/formatting concern and is applied at the edge with the locale.
public struct Price: Equatable, Hashable, Comparable, Sendable {
    /// The amount in whole cents. Always > 0.
    public let cents: Int

    /// Fails for non-positive amounts — the enforcement point.
    public init?(cents: Int) {
        guard cents > 0 else { return nil }
        self.cents = cents
    }

    /// Convenience for fixtures/tests written in dollars (rounds to the nearest cent).
    public init?(dollars: Double) {
        self.init(cents: Int((dollars * 100).rounded()))
    }

    /// The amount in dollars — used by the value formulas in `ValueRanker` (Phase 4).
    public var dollars: Double { Double(cents) / 100 }

    public static func < (lhs: Price, rhs: Price) -> Bool { lhs.cents < rhs.cents }
}
