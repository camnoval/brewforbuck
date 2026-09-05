//
//  QuickCompareViewModel.swift
//  BangForBuck
//
//  Created by Noval, Cameron on 9/5/26.
//

import Foundation
import Combine
import CoreModel
import CoreContracts
import CoreServices

/// What the quick-add row opens with. Same idea as `ProductPrefill` on the store side, sized for a
/// single serving instead of a package.
struct DrinkPrefill: Identifiable, Hashable {
    let id: String
    var name: String
    var abv: Double
    var abvIsEstimated: Bool
    var abvNote: String
    var pour: ContainerSize
}

/// The quick menu comparison: type two to five drinks off a menu, get them ranked by the same
/// standard-drinks-per-dollar metric as everything else.
///
/// It runs on the **same** pure `StoreSession` as the store calculator, because a priced volume of
/// alcohol is a priced volume of alcohol: `unitVolume × count × abv ÷ price` is the identical
/// computation whether the volume is a 12 oz can in a six pack or a 5 oz pour of wine. Sharing the
/// session means the two screens can't produce different rankings for the same numbers, and there's
/// one place where the price invariant lives (§10). What differs is the defaults (one serving, pour
/// sizes) and the wording, both of which are this file and the view.
@MainActor
final class QuickCompareViewModel: ObservableObject {
    /// Quick means quick. Past five drinks this stops being a glance and starts being the store
    /// calculator, which has no cap.
    static let maximumDrinks = 5

    @Published private(set) var session = StoreSession()

    private let catalog: any StoreCatalog
    private let knowledge: any BeverageKnowledge

    init(
        catalog: any StoreCatalog = InMemoryStoreCatalog.curatedBrands,
        knowledge: any BeverageKnowledge = StaticBeverageKnowledge()
    ) {
        self.catalog = catalog
        self.knowledge = knowledge
    }

    var ranked: [RankedEditableProduct] { session.rankedProducts }
    var needsPrice: [EditableProduct] { session.needsPriceProducts }
    var count: Int { session.products.count }
    var isEmpty: Bool { session.products.isEmpty }
    var isFull: Bool { count >= Self.maximumDrinks }
    var searchableProductCount: Int { catalog.productCount }

    // MARK: - Autofill

    /// Suggestions while typing. Capped short: this is a hint under a text field, not a browse list.
    func suggestions(for query: String) -> [CatalogProduct] {
        catalog.search(query, limit: 6)
    }

    /// Fill in a drink picked from the catalog: its label ABV, and a pour inferred from the name
    /// and category.
    func prefill(for product: CatalogProduct) -> DrinkPrefill {
        let profile = knowledge.profile(for: product.name, sectionCategory: product.category)
        let pour = PourDefaults.suggest(name: product.name,
                                        category: product.category,
                                        typicalSize: profile.typicalSize)
        if let abv = product.abv {
            return DrinkPrefill(
                id: product.id,
                name: product.name,
                abv: abv,
                abvIsEstimated: true,
                abvNote: "\(product.name) at its typical strength, not read off the menu",
                pour: pour
            )
        }
        return DrinkPrefill(
            id: product.id,
            name: product.name,
            abv: profile.typicalABV,
            abvIsEstimated: true,
            abvNote: profile.abvNote,
            pour: pour
        )
    }

    /// Fill in whatever the person typed, even when the catalog has never heard of it. This is the
    /// common case on a real menu: house cocktails aren't in any product database, but the style
    /// chart still has an opinion about a margarita, and it says so as an estimate (§11).
    func prefill(forTypedName name: String) -> DrinkPrefill {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let profile = knowledge.profile(for: trimmed, sectionCategory: nil)
        let pour = PourDefaults.suggest(name: trimmed,
                                        category: profile.category,
                                        typicalSize: profile.typicalSize)
        return DrinkPrefill(
            id: "typed:\(trimmed)",
            name: trimmed,
            abv: profile.typicalABV,
            abvIsEstimated: true,
            abvNote: profile.abvNote,
            pour: pour
        )
    }

    // MARK: - Edits (pass-through to the pure session)

    func addDrink(
        name: String,
        pourFluidOunces: Double,
        count: Int,
        abv: Double,
        abvIsEstimated: Bool,
        abvNote: String,
        priceDollars: Double?
    ) {
        guard !isFull else { return }

        let fallbackNote = "typical strength for this kind of drink, not read off the menu"
        let provenance: Provenance<Double> = abvIsEstimated
            ? .estimated(abv, note: abvNote.isEmpty ? fallbackNote : abvNote)
            : .read(abv)

        session.addProduct(
            name: name,
            unitVolume: Volume(fluidOunces: pourFluidOunces),
            count: count,
            abv: provenance,
            priceDollars: priceDollars
        )
    }

    func setPrice(id: Int, dollars: Double) { session.setPrice(id: id, dollars: dollars) }
    func correctABV(id: Int, to value: Double) { session.correctABV(id: id, to: value) }

    func setPour(id: Int, fluidOunces: Double, count: Int) {
        session.setPackage(id: id, unitVolume: Volume(fluidOunces: fluidOunces), count: count)
    }

    func removeDrink(id: Int) { session.removeProduct(id: id) }
    func removeAll() { session.removeAll() }
}
