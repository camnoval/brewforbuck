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

/// The thin shell over the pure `StoreSession` (§7, §4) — the store-calculator twin of
/// `ResultsViewModel`. It holds one session, republishes it to SwiftUI, and forwards edits straight
/// to Core. No business logic here: the ranking, the standard-drinks math, and both invariants live
/// in `StoreSession` / `StoreComparison` / `ValueRanker`.
@MainActor
final class CompareViewModel: ObservableObject {
    @Published private(set) var session = StoreSession()

    // Derived views for the UI.
    var ranked: [RankedEditableProduct] { session.rankedProducts }
    var needsPrice: [EditableProduct] { session.needsPriceProducts }
    var isEmpty: Bool { session.products.isEmpty }

    /// Brands the shopper can pick to pre-fill a typical ABV. This is the public projection of the
    /// generated brand table (655 products), so the picker doesn't reach into lookup internals.
    let brands: [KnownBeverage] = BrandCatalog.all

    // MARK: - Edits (pass-through to the pure session)

    /// `abvIsEstimated` is the honesty flag (§11): true when the ABV came from the brand catalog's
    /// label-typical figure, false when the shopper read it off the can.
    func addProduct(
        name: String,
        unitFluidOunces: Double,
        count: Int,
        abv: Double,
        abvIsEstimated: Bool,
        brandLabel: String? = nil,
        priceDollars: Double?
    ) {
        let provenance: Provenance<Double> = abvIsEstimated
            ? .estimated(abv, note: Self.estimateNote(brandLabel: brandLabel))
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

    /// The assumption the badge reveals — same phrasing style as the menu side's estimate notes.
    private static func estimateNote(brandLabel: String?) -> String {
        if let brandLabel {
            return "\(brandLabel) — typical label ABV, not read off this package"
        }
        return "typical ABV for this kind of drink, not read off this package"
    }
}
