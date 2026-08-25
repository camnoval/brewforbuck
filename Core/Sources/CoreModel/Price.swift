import Foundation

/// A drink's price, and the single structural guard behind the price invariant (§10, R-invariant):
/// `Price` cannot represent a missing, zero, or negative amount. Its only initializer is failable
/// and rejects non-positive values, so anything that ends up holding a `Price` provably had a real,
/// positive price read off the menu. A line with no readable price never produces a `Price`, so it
/// can never be assembled into a `DrinkOption`, so it can never reach the ranker.
///
/// Currency itself is a UI/formatting concern (a menu photo rarely states one reliably), so v1
/// models only the amount and formats with the device locale at the edge.
public struct Price: Equatable, Hashable, Comparable, Sendable {
    public let amount: Decimal

    /// Fails for non-positive amounts. This failable init is the enforcement point.
    public init?(_ amount: Decimal) {
        guard amount > 0 else { return nil }
        self.amount = amount
    }

    /// Convenience for fixtures/tests written in dollars.
    public init?(dollars: Double) {
        self.init(Decimal(dollars))
    }

    /// Convenience for exact cents (avoids Double rounding when precision matters).
    public init?(cents: Int) {
        self.init(Decimal(cents) / 100)
    }

    public static func < (lhs: Price, rhs: Price) -> Bool { lhs.amount < rhs.amount }
}
