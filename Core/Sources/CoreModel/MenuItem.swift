/// The raw output of `MenuParser` (Phase 5): one parsed menu line before enrichment. `price` is
/// optional here — `nil` is the `needsPrice` signal (§7, §10). `readABV`/`readSize` are populated
/// only when the menu actually printed them (INSPECTION_FINDINGS §Finding 2), which is what lets
/// the estimators return `.read` rather than `.estimated` for those lines.
public struct MenuItem: Equatable, Hashable, Sendable {
    public let name: String
    /// `nil` ⇒ no readable price ⇒ this item travels the `needsPrice` path, never the ranker (§10).
    public let price: Price?
    /// Percent, e.g. `6.5`. Present only if the menu printed an ABV.
    public let readABV: Double?
    /// Present only if the menu printed a serving size.
    public let readSize: Volume?
    public let category: BeverageCategory
    /// Ingredient/description line(s) captured under the item (Finding 4) — kept so they don't get
    /// mistaken for priceless drinks and flood the `needsPrice` bucket.
    public let descriptionText: String?

    public init(
        name: String,
        price: Price?,
        readABV: Double? = nil,
        readSize: Volume? = nil,
        category: BeverageCategory = .unknown,
        descriptionText: String? = nil
    ) {
        self.name = name
        self.price = price
        self.readABV = readABV
        self.readSize = readSize
        self.category = category
        self.descriptionText = descriptionText
    }

    /// A parsed line with no price to rank on.
    public var needsPrice: Bool { price == nil }
}
