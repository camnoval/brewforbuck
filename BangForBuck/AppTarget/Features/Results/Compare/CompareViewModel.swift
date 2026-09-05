//
//  CompareViewModel.swift
//  BangForBuck
//
//  Created by Noval, Cameron on 9/5/26.
//

import Foundation
import Combine
import CoreModel
import CoreContracts
import CoreServices

/// What the add form opens with once the shopper picks a product. Everything here is a starting
/// point they can overtype. The one field with no default is the price, which is the single value
/// the app never supplies (§10).
struct ProductPrefill: Identifiable, Hashable {
    let id: String
    var name: String
    var abv: Double
    /// True while `abv` is still a catalog or style-chart figure rather than a number read off the
    /// package. Drives the honesty badge and the estimate note (§11).
    var abvIsEstimated: Bool
    var abvNote: String
    var container: ContainerSize
    var count: Int
}

/// The thin shell over the pure `StoreSession` (§7, §4), plus the product search the add flow now
/// opens with. No business logic lives here: value ranking is in `StoreSession`/`StoreComparison`,
/// search ranking in `InMemoryStoreCatalog`, package inference in `PackageDefaults`, and the ABV
/// fallback in `BeverageKnowledge`. This type forwards and nothing else.
@MainActor
final class CompareViewModel: ObservableObject {
    @Published private(set) var session = StoreSession()

    private let catalog: any StoreCatalog
    private let knowledge: any BeverageKnowledge

    /// Injected behind the contracts (§6). Swapping the curated brand list for a bundled PLCB plus
    /// Open Food Facts catalog, or adding a barcode lookup, happens here and nowhere else.
    init(
        catalog: any StoreCatalog = InMemoryStoreCatalog.curatedBrands,
        knowledge: any BeverageKnowledge = StaticBeverageKnowledge()
    ) {
        self.catalog = catalog
        self.knowledge = knowledge
    }

    // Derived views for the UI.
    var ranked: [RankedEditableProduct] { session.rankedProducts }
    var needsPrice: [EditableProduct] { session.needsPriceProducts }
    var isEmpty: Bool { session.products.isEmpty }
    var searchableProductCount: Int { catalog.productCount }

    // MARK: - Search

    func search(_ query: String) -> [CatalogProduct] {
        catalog.search(query, limit: 40)
    }

    /// Turn a picked catalog product into a filled-in form. Three things get resolved, all by Core:
    /// the ABV (the catalog's if it stated one, else the style chart's), the container, and the
    /// pack count.
    func prefill(for product: CatalogProduct) -> ProductPrefill {
        let package = PackageDefaults.suggest(
            name: product.name,
            category: product.category,
            containerMilliliters: product.containerMilliliters,
            unitsPerPackage: product.unitsPerPackage
        )

        if let abv = product.abv {
            return ProductPrefill(
                id: product.id,
                name: product.name,
                abv: abv,
                abvIsEstimated: true,
                abvNote: "\(product.name) at its typical label strength, not read off this package",
                container: package.container,
                count: package.count
            )
        }

        // The catalog stated no strength, so fall back to the same style chart the menu scanner
        // uses. Still an estimate, and the note says which tier it came from.
        let profile = knowledge.profile(for: product.name, sectionCategory: product.category)
        return ProductPrefill(
            id: product.id,
            name: product.name,
            abv: profile.typicalABV,
            abvIsEstimated: true,
            abvNote: profile.abvNote,
            container: package.container,
            count: package.count
        )
    }

    /// A product the catalog doesn't carry. Nothing is estimated because nothing was looked up: the
    /// shopper supplies every axis, so the ABV is `.read` as soon as they type it.
    func blankPrefill(named name: String) -> ProductPrefill {
        ProductPrefill(
            id: "manual",
            name: name,
            abv: 0,
            abvIsEstimated: false,
            abvNote: "",
            container: .can12,
            count: 1
        )
    }

    // MARK: - Edits (pass-through to the pure session)

    func addProduct(
        name: String,
        unitFluidOunces: Double,
        count: Int,
        abv: Double,
        abvIsEstimated: Bool,
        abvNote: String,
        priceDollars: Double?
    ) {
        let fallbackNote = "typical strength, not read off this package"
        let provenance: Provenance<Double> = abvIsEstimated
            ? .estimated(abv, note: abvNote.isEmpty ? fallbackNote : abvNote)
            : .read(abv)

        session.addProduct(
            name: name,
            unitVolume: Volume(fluidOunces: unitFluidOunces),
            count: count,
            abv: provenance,
            priceDollars: priceDollars
        )
    }

    func setPrice(id: Int, dollars: Double) { session.setPrice(id: id, dollars: dollars) }
    func correctABV(id: Int, to value: Double) { session.correctABV(id: id, to: value) }

    func setPackage(id: Int, unitFluidOunces: Double, count: Int) {
        session.setPackage(id: id, unitVolume: Volume(fluidOunces: unitFluidOunces), count: count)
    }

    func removeProduct(id: Int) { session.removeProduct(id: id) }
    func removeAll() { session.removeAll() }
}
