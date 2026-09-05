//
//  StoreCatalog.swift
//  Core
//
//  Created by Noval, Cameron on 9/5/26.
//

import CoreModel

/// One product as a *store catalog* knows it: what the shelf tag says, before the shopper adds
/// anything of their own. Every field except the name is optional because real catalogs are ragged:
/// the PLCB wholesale catalogs carry a UPC and a bottle size but not always an ABV, Open Food Facts
/// carries an ABV and a UPC but not always a clean size, and a curated list may carry neither.
///
/// A missing `abv` is not a problem: `BeverageKnowledge` fills it from the style chart and the value
/// stays flagged as an estimate (§11). What we never invent is the price, which no catalog supplies
/// here on purpose (shelf prices are local and change weekly, so the shopper always types it).
public struct CatalogProduct: Equatable, Sendable, Identifiable {
    /// Display name as the catalog spells it.
    public let name: String
    public let category: BeverageCategory
    /// Percent. `nil` when the source didn't say.
    public let abv: Double?
    /// Volume of ONE container in millilitres. `nil` when the source didn't say.
    public let containerMilliliters: Double?
    /// Containers in the package when the catalog states it (a 12-pack). `nil` when it doesn't.
    public let unitsPerPackage: Int?
    /// 12 or 14 digit barcode, when known. Unused today; this is the hook the barcode scanner
    /// needs later, and it costs nothing to carry now.
    public let upc: String?

    public var id: String { upc ?? name }

    public init(
        name: String,
        category: BeverageCategory,
        abv: Double? = nil,
        containerMilliliters: Double? = nil,
        unitsPerPackage: Int? = nil,
        upc: String? = nil
    ) {
        self.name = name
        self.category = category
        self.abv = abv
        self.containerMilliliters = containerMilliliters
        self.unitsPerPackage = unitsPerPackage
        self.upc = upc
    }
}

/// The fifth contract (§6): where the store calculator's product search comes from. Behind a
/// protocol because the *source* is expected to change while the screen doesn't. Today it's the
/// curated 655-brand list compiled into the app; next it's a much larger bundled catalog built from
/// the PLCB wholesale catalogs and Open Food Facts; later, possibly, a barcode lookup. Swapping any
/// of those is one new conforming type, no change to `CompareView` (§6, §14).
///
/// Implementations must be usable from a keystroke-by-keystroke search, so `search` is synchronous
/// and expected to be fast on a bundled in-memory catalog.
public protocol StoreCatalog: Sendable {
    /// How many products are searchable. Shown in the search prompt so the shopper knows the size
    /// of what they're searching.
    var productCount: Int { get }

    /// Best matches for a partial name, best first, capped at `limit`. An empty or whitespace-only
    /// query returns an empty array rather than the whole catalog.
    func search(_ query: String, limit: Int) -> [CatalogProduct]

    /// Exact barcode lookup. The barcode feature isn't built yet; this is the seam it will use.
    func product(withUPC upc: String) -> CatalogProduct?
}
