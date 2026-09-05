//
//  StoreSession.swift
//  Core
//
//  Created by Noval, Cameron on 9/5/26.
//

import CoreModel

/// An identity-bearing, *mutable* packaged product — the unit the store-calculator UI edits. Same
/// role on the store side that `EditableDrink` plays on the menu side, and deliberately the same
/// shape, so `CompareView` can reuse the ranked-row/chip vocabulary from `ResultsView`.
///
/// Invariants preserved (§10, §11):
/// - **Price is never fabricated:** `price` is optional; `nil` means the shopper hasn't read the
///   shelf tag yet, and `storeProduct` returns `nil` until a real, positive `Price` exists, so the
///   product cannot be ranked on a guess.
/// - **Estimated never masquerades as measured:** `abv` carries `Provenance`. Picking a brand from
///   `BrandCatalog` seeds a *label-typical* ABV, which is an `.estimated` value with a note; typing
///   the ABV off the can promotes it to `.read`. Size and count are always user-entered, so they
///   need no provenance.
public struct EditableProduct: Identifiable, Equatable, Sendable {
    /// Stable within a session (assigned from add order), so a row stays addressable when two
    /// products share a name (two different 6-packs of "Lager", say).
    public let id: Int
    public var name: String
    /// Volume of ONE container.
    public var unitVolume: Volume
    /// Containers in the package (1 for a single bottle).
    public var count: Int
    /// Percent. `.estimated` when seeded from the brand catalog, `.read` when the shopper types it.
    public var abv: Provenance<Double>
    /// `nil` ⇒ this product still needs a price and cannot be ranked (§10).
    public var price: Price?

    public init(
        id: Int,
        name: String,
        unitVolume: Volume,
        count: Int,
        abv: Provenance<Double>,
        price: Price?
    ) {
        self.id = id
        self.name = name
        self.unitVolume = unitVolume
        self.count = max(1, count)
        self.abv = abv
        self.price = price
    }

    /// A product still missing the one thing we won't guess.
    public var needsPrice: Bool { price == nil }

    /// True when ABV is still a label-typical guess — drives the honesty badge (§11).
    public var hasEstimate: Bool { abv.isEstimated }

    /// Total liquid across the whole package.
    public var totalVolume: Volume {
        Volume(fluidOunces: unitVolume.fluidOunces * Double(count))
    }

    /// Standard drinks in the whole package — the shared NIAAA formula from `ValueRanker`.
    public var totalStandardDrinks: Double {
        ValueRanker.standardDrinks(sizeFloz: totalVolume.fluidOunces, abvPercent: abv.value)
    }

    /// The rankable value type, or `nil` while the price is still missing.
    public var storeProduct: StoreProduct? {
        guard let price else { return nil }
        return StoreProduct(name: name, unitVolume: unitVolume, count: count,
                            abv: abv.value, packagePrice: price)
    }
}

/// A ranked product that keeps its editable identity, so the UI can rank a row *and* still correct
/// it — `RankedProduct` carries no `id` and would be ambiguous when two products share a name.
public struct RankedEditableProduct: Identifiable, Equatable, Sendable {
    public let product: EditableProduct
    public let standardDrinksPerDollar: Double
    public let pricePerStandardDrink: Double
    /// 1 = best value.
    public let rank: Int

    public var id: Int { product.id }

    public init(product: EditableProduct, standardDrinksPerDollar: Double,
                pricePerStandardDrink: Double, rank: Int) {
        self.product = product
        self.standardDrinksPerDollar = standardDrinksPerDollar
        self.pricePerStandardDrink = pricePerStandardDrink
        self.rank = rank
    }
}

/// The interactive store calculator: hold the packages a shopper is weighing in the aisle and rank
/// them by the *same* NIAAA standard-drinks metric the menu ranker uses, applied to the whole
/// package (unit size × count) instead of a single pour.
///
/// All logic is pure and lives here in `CoreServices` (§7); `CompareViewModel` is a thin shell that
/// mutates this value and republishes it — exactly the `MenuSession` arrangement.
///
/// Scoring and ordering are delegated to `StoreComparison`'s shared statics rather than re-derived,
/// so this session and the one-shot `StoreComparison.rank` can't drift (there's a parity test).
public struct StoreSession: Equatable, Sendable {
    /// Every product the shopper added, in add order. Some may still be `needsPrice`.
    public private(set) var products: [EditableProduct]

    public init(products: [EditableProduct] = []) {
        self.products = products
    }

    // MARK: - Derived views (recomputed on read; cheap for aisle-sized inputs)

    /// Best value first, ranks assigned — mirrors `StoreComparison.rank`'s ordering exactly but
    /// preserves each product's `id` so a ranked row stays editable. Priceless products are absent
    /// by construction (§10).
    public var rankedProducts: [RankedEditableProduct] {
        let scored: [(product: EditableProduct, value: StoreValue)] = products.compactMap { product in
            guard let priced = product.storeProduct else { return nil }
            return (product, StoreComparison.value(totalStandardDrinks: priced.totalStandardDrinks,
                                                   dollars: priced.packagePrice.dollars))
        }
        let sorted = scored.sorted { a, b in
            StoreComparison.sortsBefore(
                lhsValue: a.value.standardDrinksPerDollar, lhsName: a.product.name,
                rhsValue: b.value.standardDrinksPerDollar, rhsName: b.product.name
            )
        }
        return sorted.enumerated().map { index, s in
            RankedEditableProduct(product: s.product,
                                  standardDrinksPerDollar: s.value.standardDrinksPerDollar,
                                  pricePerStandardDrink: s.value.pricePerStandardDrink,
                                  rank: index + 1)
        }
    }

    /// Products still missing a price — the "add a price" bucket, in add order.
    public var needsPriceProducts: [EditableProduct] { products.filter { $0.needsPrice } }

    /// The best deal on the shelf, if anything is priced yet.
    public var best: RankedEditableProduct? { rankedProducts.first }

    // MARK: - Edits

    /// Add a package the shopper is considering. `abv` is `.read` when they typed it off the can and
    /// `.estimated` when it came from the brand catalog — pass the provenance through rather than
    /// flattening it, or the honesty badge lies (§11). `priceDollars` is optional: omit it and the
    /// product waits in `needsPriceProducts` until the shelf tag is read (§10 — a non-positive price
    /// is rejected by `Price` and treated as none).
    /// Returns the new product's `id`, or `nil` if the name was blank.
    @discardableResult
    public mutating func addProduct(
        name: String,
        unitVolume: Volume,
        count: Int,
        abv: Provenance<Double>,
        priceDollars: Double? = nil
    ) -> Int? {
        let cleanName = StoreSession.trimmed(name)
        guard !cleanName.isEmpty else { return nil }

        let newId = (products.map { $0.id }.max() ?? -1) + 1
        products.append(
            EditableProduct(
                id: newId,
                name: cleanName,
                unitVolume: unitVolume,
                count: count,
                abv: abv,
                price: priceDollars.flatMap { Price(dollars: $0) }
            )
        )
        return newId
    }

    /// Supply (or change) a package price from cents. Non-positive input is ignored — `Price`'s
    /// failable init is the structural guard behind the price invariant (§10).
    public mutating func setPrice(id: Int, cents: Int) {
        guard let price = Price(cents: cents) else { return }
        update(id) { $0.price = price }
    }

    /// Convenience for a price typed in dollars (rounds to the nearest cent).
    public mutating func setPrice(id: Int, dollars: Double) {
        setPrice(id: id, cents: Int((dollars * 100).rounded()))
    }

    /// Correct a label-typical ABV with the real number off the can. Promotes it to `.read` (§11).
    public mutating func correctABV(id: Int, to newValue: Double) {
        update(id) { $0.abv = $0.abv.corrected(to: newValue) }
    }

    /// Change the package shape (a 12-pack instead of a 6-pack, a 16 oz can instead of 12 oz).
    /// Both axes are user-entered, so there's no provenance to disturb.
    public mutating func setPackage(id: Int, unitVolume: Volume, count: Int) {
        update(id) {
            $0.unitVolume = unitVolume
            $0.count = max(1, count)
        }
    }

    /// Remove a product — the shopper put it back on the shelf. No-op if `id` is stale.
    public mutating func removeProduct(id: Int) {
        products.removeAll { $0.id == id }
    }

    /// Clear the whole comparison (new store, new trip).
    public mutating func removeAll() { products.removeAll() }

    private mutating func update(_ id: Int, _ transform: (inout EditableProduct) -> Void) {
        guard let index = products.firstIndex(where: { $0.id == id }) else { return }
        transform(&products[index])
    }

    /// Foundation-free trim, matching `MenuSession`'s (CoreServices imports no Foundation).
    private static func trimmed(_ s: String) -> String {
        let whitespace: Set<Character> = [" ", "\t", "\n", "\r"]
        var chars = Array(s)
        while let first = chars.first, whitespace.contains(first) { chars.removeFirst() }
        while let last = chars.last, whitespace.contains(last) { chars.removeLast() }
        return String(chars)
    }
}
