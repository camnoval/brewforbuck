/// The spine (Architecture §1): if you understand `DrinkOption`, you understand the app. A drink
/// with a real price and its two estimable axes wrapped in `Provenance`.
///
/// `price` is a **non-optional** `Price`. Because `Price` itself cannot be constructed from a
/// missing/zero/negative amount, a `DrinkOption` cannot exist without a real read price — this is
/// the price invariant (§10) enforced by the type, not by a comment. A `needsPrice` line stays a
/// `MenuItem` and never reaches this type.
public struct DrinkOption: Equatable, Hashable, Sendable {
    public let name: String
    public let price: Price
    /// Percent.
    public let abv: Provenance<Double>
    public let size: Provenance<Volume>
    public let category: BeverageCategory

    public init(
        name: String,
        price: Price,
        abv: Provenance<Double>,
        size: Provenance<Volume>,
        category: BeverageCategory
    ) {
        self.name = name
        self.price = price
        self.abv = abv
        self.size = size
        self.category = category
    }

    /// True when either axis is a guess — drives the honesty badge in Results (§11).
    public var hasEstimate: Bool { abv.isEstimated || size.isEstimated }
}
