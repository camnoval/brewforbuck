//
//  BundledStoreCatalog.swift
//  BangForBuck
//
//  Created by Noval, Cameron on 9/5/26.
//

import Foundation
import CoreModel
import CoreContracts
import CoreServices

/// Loads the store catalog from a JSON file in the app bundle, falling back to the curated brand
/// list compiled into `CoreContracts` when the file isn't there. This is the impure shell (§7): the
/// file read lives here, the search behind it is the pure `InMemoryStoreCatalog`.
///
/// The fallback is the point. `store_catalog.json` is built by `Tooling/build_store_catalog.py` from
/// the PLCB wholesale catalogs and Open Food Facts, which needs a network and a few minutes; until
/// someone runs it the app still searches 655 curated products. Dropping the file into the bundle
/// later changes nothing else.
///
/// Why bundled JSON and not codegen'd Swift like `GeneratedBrandTable`: that table is the *menu*
/// brand matcher, where a small curated list is a feature (a 30,000-SKU list would match menu text
/// like "Chardonnay" against some specific winery's bottling). The store catalog is a different job
/// with different data, so it's a separate artifact, and thirty thousand `BrandEntry` literals would
/// be a miserable thing to compile besides.
enum BundledStoreCatalog {

    /// Everything the store search can find. Built once, lazily.
    ///
    /// `nonisolated` because this target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
    /// which would otherwise make it main-actor-isolated and unusable as a **default argument** in
    /// a view model's `init` (default arguments are evaluated in a nonisolated context). Safe to
    /// mark: it is an immutable `let` of a `Sendable` value, read once and never mutated.
    nonisolated static let shared: any StoreCatalog = load()

    nonisolated private static func load() -> any StoreCatalog {
        guard let url = Bundle.main.url(forResource: "store_catalog", withExtension: "json") else {
            return InMemoryStoreCatalog.curatedBrands
        }
        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(CatalogFile.self, from: data)
            let products = file.products.compactMap { $0.asCatalogProduct }
            guard !products.isEmpty else { return InMemoryStoreCatalog.curatedBrands }
            return InMemoryStoreCatalog(products: products)
        } catch {
            // A malformed catalog should degrade to the curated list, never crash a shopper's
            // session in an aisle.
            return InMemoryStoreCatalog.curatedBrands
        }
    }

    // MARK: - Wire format (matches Tooling/build_store_catalog.py)

    /// `nonisolated` for the same reason as `shared` above: under this target's default main-actor
    /// isolation, even a *conformance* is isolated, so decoding these from the nonisolated `load()`
    /// is rejected. Plain immutable data with no actor state, so there is nothing to protect.
    nonisolated private struct CatalogFile: Decodable {
        let products: [Entry]
    }

    nonisolated private struct Entry: Decodable {
        let name: String
        let category: String
        let abv: Double?
        let ml: Double?
        let units: Int?
        let upc: String?

        nonisolated var asCatalogProduct: CatalogProduct? {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return CatalogProduct(
                name: trimmed,
                category: BeverageCategory(rawValue: category) ?? .unknown,
                abv: abv,
                containerMilliliters: ml,
                unitsPerPackage: units,
                upc: upc
            )
        }
    }
}
