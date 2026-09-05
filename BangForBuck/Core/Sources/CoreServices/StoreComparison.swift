//
//  StoreComparison.swift
//  Core
//
//  Created by Noval, Cameron on 8/30/26.
//

import CoreModel

/// The liquor-store side of the app (Goal 2): compare packaged products by the *same* value metric
/// as the menu ranker — US standard drinks per dollar — but on a whole package (a 6-pack, a 750 mL
/// bottle, a 1.75 L handle) instead of a single pour. Per the design decision this is a **separate**
/// pure type that shares only `ValueRanker`'s ethanol formula; the pack-count × container-size math
/// the store side needs (and the menu side never does) lives here and doesn't leak into `MenuSession`.
///
/// Pure and Foundation-free, so it's fixture-testable in milliseconds like the rest of the core.

/// One packaged product the shopper is weighing: `count` containers of `unitVolume` at `abv`, for
/// `packagePrice` total. Holding a `Price` means the price was real and positive (§10 invariant); a
/// product with no valid price can't be constructed and so can't be ranked.
public struct StoreProduct: Equatable, Sendable {
    public let name: String
    public let unitVolume: Volume     // volume of ONE container
    public let count: Int             // containers in the package (1 for a single bottle)
    public let abv: Double            // percent, e.g. 40 for spirits
    public let packagePrice: Price    // price for the whole package

    public init(name: String, unitVolume: Volume, count: Int, abv: Double, packagePrice: Price) {
        self.name = name
        self.unitVolume = unitVolume
        self.count = max(1, count)
        self.abv = abv
        self.packagePrice = packagePrice
    }

    /// Total liquid across the whole package.
    public var totalVolume: Volume {
        Volume(fluidOunces: unitVolume.fluidOunces * Double(count))
    }

    /// US standard drinks in the whole package — the shared NIAAA formula from `ValueRanker`.
    public var totalStandardDrinks: Double {
        ValueRanker.standardDrinks(sizeFloz: totalVolume.fluidOunces, abvPercent: abv)
    }
}

/// A product placed in the ranking, carrying both the headline metric (standard drinks per dollar,
/// higher is better) and the shopper-friendly inverse ($ per standard drink) surfaced in the UI.
public struct RankedProduct: Equatable, Sendable {
    public let product: StoreProduct
    public let standardDrinksPerDollar: Double
    public let pricePerStandardDrink: Double
    public let rank: Int

    public init(product: StoreProduct, standardDrinksPerDollar: Double,
                pricePerStandardDrink: Double, rank: Int) {
        self.product = product
        self.standardDrinksPerDollar = standardDrinksPerDollar
        self.pricePerStandardDrink = pricePerStandardDrink
        self.rank = rank
    }
}

/// The two numbers a shopper compares, computed once so the one-shot ranker and the interactive
/// `StoreSession` can never disagree about what a package is worth.
public struct StoreValue: Equatable, Sendable {
    /// Standard drinks per dollar — the headline metric, higher is better.
    public let standardDrinksPerDollar: Double
    /// The shopper-friendly inverse. `.infinity` for a zero-alcohol package (never a divide-by-zero).
    public let pricePerStandardDrink: Double

    public init(standardDrinksPerDollar: Double, pricePerStandardDrink: Double) {
        self.standardDrinksPerDollar = standardDrinksPerDollar
        self.pricePerStandardDrink = pricePerStandardDrink
    }
}

public struct StoreComparison {
    public init() {}

    // MARK: - Shared scoring (one-shot ranker AND `StoreSession`)

    /// Score one package. A product with zero standard drinks (0% ABV or 0 volume) scores 0 per
    /// dollar and reports an infinite price-per-drink rather than dividing by zero.
    public static func value(totalStandardDrinks: Double, dollars: Double) -> StoreValue {
        StoreValue(
            standardDrinksPerDollar: dollars > 0 ? totalStandardDrinks / dollars : 0,
            pricePerStandardDrink: totalStandardDrinks > 0 ? dollars / totalStandardDrinks : Double.infinity
        )
    }

    /// The one ordering rule: best value first, ties broken by name so output is deterministic.
    /// Both ranking paths call this, which is what makes the parity test meaningful.
    static func sortsBefore(
        lhsValue: Double, lhsName: String,
        rhsValue: Double, rhsName: String
    ) -> Bool {
        if lhsValue != rhsValue { return lhsValue > rhsValue }
        return lhsName < rhsName
    }

    /// Rank best value first (most standard drinks per dollar). Ties break by name for determinism.
    public func rank(_ products: [StoreProduct]) -> [RankedProduct] {
        let scored: [(product: StoreProduct, value: StoreValue)] = products.map { product in
            (product: product,
             value: Self.value(totalStandardDrinks: product.totalStandardDrinks,
                               dollars: product.packagePrice.dollars))
        }
        let sorted = scored.sorted { a, b in
            Self.sortsBefore(lhsValue: a.value.standardDrinksPerDollar, lhsName: a.product.name,
                             rhsValue: b.value.standardDrinksPerDollar, rhsName: b.product.name)
        }
        return sorted.enumerated().map { index, s in
            RankedProduct(product: s.product,
                          standardDrinksPerDollar: s.value.standardDrinksPerDollar,
                          pricePerStandardDrink: s.value.pricePerStandardDrink,
                          rank: index + 1)
        }
    }
}

/// Common container sizes for the store-calculator pickers (UI convenience — not domain defaults, so
/// it lives here in the store feature rather than on `Volume`). Labels are what a shopper reads off a
/// shelf tag; values are exact.
public struct ContainerSize: Equatable, Hashable, Sendable, Identifiable {
    public let label: String
    public let volume: Volume
    public init(label: String, volume: Volume) { self.label = label; self.volume = volume }

    /// `Hashable`/`Identifiable` so a SwiftUI `Picker` can select one and a `ForEach` can list them
    /// without the app declaring a retroactive conformance on a Core type.
    public var id: String { label }

    /// Cans / bottles by fluid ounce.
    public static let can12 = ContainerSize(label: "12 oz", volume: Volume(fluidOunces: 12))
    public static let can16 = ContainerSize(label: "16 oz", volume: Volume(fluidOunces: 16))
    public static let can192 = ContainerSize(label: "19.2 oz", volume: Volume(fluidOunces: 19.2))
    public static let can24 = ContainerSize(label: "24 oz", volume: Volume(fluidOunces: 24))
    public static let can25 = ContainerSize(label: "25 oz", volume: Volume(fluidOunces: 25))

    /// Wine / spirits bottles by metric size.
    public static let ml187 = ContainerSize(label: "187 mL (split)", volume: Volume(milliliters: 187))
    public static let ml375 = ContainerSize(label: "375 mL (half)", volume: Volume(milliliters: 375))
    public static let ml500 = ContainerSize(label: "500 mL", volume: Volume(milliliters: 500))
    public static let ml750 = ContainerSize(label: "750 mL", volume: Volume(milliliters: 750))
    public static let liter1 = ContainerSize(label: "1 L", volume: Volume(liters: 1))
    public static let liter15 = ContainerSize(label: "1.5 L (magnum)", volume: Volume(liters: 1.5))
    public static let liter175 = ContainerSize(label: "1.75 L (handle)", volume: Volume(liters: 1.75))

    /// Ordered for a picker: beer/seltzer cans first, then wine/spirits bottles ascending.
    public static let presets: [ContainerSize] = [
        can12, can16, can192, can24, can25,
        ml187, ml375, ml500, ml750, liter1, liter15, liter175,
    ]
}
