//
//  ResultsViewModel.swift
//  BangForBuck
//
//  Created by Noval, Cameron on 8/27/26.
//

import Foundation
import Combine
import CoreModel
import CoreContracts
import CoreServices

/// The thin shell over the pure `MenuSession` (§7, §4): it holds one session, republishes it to
/// SwiftUI, and forwards edits straight to Core. No business logic lives here — correction,
/// add-a-price, re-ranking, and the invariants all live in `MenuSession`/`ValueRanker`. This is the
/// single seam the capture flow will reuse next: today `load(lines:)` is fed by `SampleMenus`; next
/// conversation it's fed by `VisionTextRecognizer` output. Nothing below changes.
@MainActor
final class ResultsViewModel: ObservableObject {
    @Published private(set) var session: MenuSession
    @Published var metric: ValueMetric {
        didSet { session.metric = metric }
    }

    private let pipeline: MenuPipeline

    /// The knowledge layer is injected so the menu scanner draws on the **same** product library as
    /// the store calculator: `CatalogBackedKnowledge` consults the bundled catalog (thousands of
    /// real label ABVs) before falling back to the style chart. The curated brand table still wins
    /// where it matches, and a menu line that names a category rather than a product still gets a
    /// chart estimate, so nothing gains false precision. See `CatalogMatcher` for that rule.
    init(
        lines: [String] = [],
        metric: ValueMetric = .standardDrinksPerDollar,
        knowledge: any BeverageKnowledge = CatalogBackedKnowledge(catalog: BundledStoreCatalog.shared)
    ) {
        let pipeline = MenuPipeline(knowledge: knowledge)
        self.pipeline = pipeline
        self.metric = metric
        self.session = pipeline.makeSession(lines: lines, metric: metric)
    }

    /// Load a freshly captured (or sampled) menu. Replaces the session — any prior edits are for the
    /// previous menu. This is the one call the capture flow will make with real OCR lines.
    func load(lines: [String]) {
        session = pipeline.makeSession(lines: lines, metric: metric)
    }

    // Derived views for the UI.
    var ranked: [RankedEditable] { session.rankedDrinks }
    var needsPrice: [EditableDrink] { session.needsPriceDrinks }
    var excluded: [String] { session.excludedNonAlcoholic }

    // Edits — pass-through to the pure session (each promotes an estimate to `.read` and re-ranks).
    func correctABV(id: Int, to value: Double) { session.correctABV(id: id, to: value) }
    func correctSize(id: Int, toFluidOunces value: Double) { session.correctSize(id: id, to: value) }
    func setPrice(id: Int, dollars: Double) { session.setPrice(id: id, dollars: dollars) }

    // Manual add / remove for drinks the scan missed or misread.
    func addDrink(name: String, abv: Double, sizeFluidOunces: Double, priceDollars: Double?) {
        session.addDrink(name: name, abv: abv, sizeFluidOunces: sizeFluidOunces, priceDollars: priceDollars)
    }
    func removeDrink(id: Int) { session.removeDrink(id: id) }
}
