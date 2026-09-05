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
    static let shared: any StoreCatalog = load()

    private static func load() -> any StoreCatalog {
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

    private struct CatalogFile: Decodable {
        let products: [Entry]
    }

    private struct Entry: Decodable {
        let name: String
        let category: String
        let abv: Double?
        let ml: Double?
        let units: Int?
        let upc: String?

        var asCatalogProduct: CatalogProduct? {
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
