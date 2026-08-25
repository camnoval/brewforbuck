/// The ranker's input type (§10): a `DrinkOption` that is *also* rankable. Priced-ness is already
/// guaranteed by `DrinkOption` (its `price` is a non-optional `Price`); this type adds the second
/// gate — the drink must be alcoholic. The failable init refuses `.nonAlcoholic` (Change B), so
/// `ValueRanker` structurally cannot be handed a mocktail. Non-alcoholic items are dropped here,
/// which is distinct from the `needsPrice` bucket: they *have* a price, they're just not alcohol.
public struct PricedDrink: Equatable, Hashable, Sendable {
    public let option: DrinkOption

    /// Fails for non-alcoholic drinks.
    public init?(_ option: DrinkOption) {
        guard option.category.isAlcoholic else { return nil }
        self.option = option
    }

    public var name: String { option.name }
    public var price: Price { option.price }
    public var abv: Provenance<Double> { option.abv }
    public var size: Provenance<Volume> { option.size }
    public var category: BeverageCategory { option.category }
    public var hasEstimate: Bool { option.hasEstimate }
}
