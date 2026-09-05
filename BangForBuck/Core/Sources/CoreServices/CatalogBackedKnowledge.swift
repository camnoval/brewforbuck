//
//  CatalogBackedKnowledge.swift
//  Core
//
//  Created by Noval, Cameron on 9/5/26.
//

import CoreModel
import CoreContracts

/// Match a *menu line* against the big store catalog, strictly.
///
/// The store search is tuned for a human typing a few letters: it ranks generously and returns
/// plenty of candidates. A menu line can't be treated that way. OCR gives us "Josh Cellars
/// Cabernet" or "House Red", and binding either to whatever the search ranked first would be worse
/// than the style chart: "Chardonnay" on a menu would inherit some specific winery's bottling and
/// vintage, and the app would state a false precision.
///
/// So a catalog match only counts when it is *specific*, which means all three of:
/// 1. **One name contains the other, whole.** Either the product name's words are all present in
///    the menu line, or the menu line is a shorter form of the product name ("Josh Cellars
///    Cabernet" inside "Josh Cellars Cabernet Sauvignon"). A partial overlap is not a match.
/// 2. **The menu line has at least two words.** A single word is a style, not a product.
/// 3. **They share at least one non-generic word.** "Cabernet Sauvignon", "House Red" and "Draft
///    IPA" are made entirely of style and vessel words, so a catalog hit on them adds nothing the
///    style chart doesn't already say, and risks being wrong about a producer. Those keep falling
///    through to the chart, which is honest about being a chart.
///
/// The effect: a menu that names a real product gets that product's real label ABV; a menu that
/// names a category keeps getting a category estimate. Both stay flagged as estimates (§11).
public enum CatalogMatcher {

    public static func specificMatch(for drinkName: String, in catalog: any StoreCatalog) -> CatalogProduct? {
        let menuWords = Set(InMemoryStoreCatalog.foldedWords(drinkName))
        guard menuWords.count >= 2 else { return nil }

        for candidate in catalog.search(drinkName, limit: 12) {
            let productWords = Set(InMemoryStoreCatalog.foldedWords(candidate.name))
            guard productWords.count >= 2 else { continue }

            let containsEitherWay = productWords.isSubset(of: menuWords)
                || menuWords.isSubset(of: productWords)
            guard containsEitherWay else { continue }

            let shared = productWords.intersection(menuWords)
            guard shared.contains(where: { !CatalogMatcher.genericWords.contains($0) }) else { continue }

            return candidate
        }
        return nil
    }

    /// Styles, varietals, colours, and vessels. A match made only of these is a category, not a
    /// product, and the style chart already has a sourced number for it.
    static let genericWords: Set<String> = [
        // beer and cider
        "beer", "ale", "lager", "ipa", "ipas", "pale", "hazy", "stout", "porter", "pilsner",
        "pils", "wheat", "hefeweizen", "witbier", "amber", "blonde", "golden", "kolsch", "bock",
        "double", "imperial", "session", "light", "lite", "dark", "draft", "draught", "cider",
        // wine
        "wine", "red", "white", "rose", "rosado", "blush", "blend", "reserve", "riserva",
        "cabernet", "sauvignon", "merlot", "pinot", "noir", "grigio", "gris", "blanc", "chardonnay",
        "riesling", "moscato", "muscat", "malbec", "shiraz", "syrah", "zinfandel", "sangiovese",
        "tempranillo", "prosecco", "champagne", "cava", "brut", "sparkling", "port", "sherry",
        "vermouth", "sangria", "house",
        // spirits and mixed
        "vodka", "gin", "rum", "tequila", "mezcal", "whiskey", "whisky", "bourbon", "scotch",
        "rye", "brandy", "cognac", "liqueur", "cocktail", "martini", "margarita", "seltzer",
        "shot", "well", "premium", "classic", "original", "spiced", "silver", "gold", "anejo",
        "reposado", "blanco", "single", "malt",
        // vessels and sizes
        "bottle", "bottles", "can", "cans", "glass", "pint", "pitcher", "pack", "oz", "ml",
    ]
}

/// `BeverageKnowledge` that consults the bundled store catalog before falling back to the style
/// chart, so the menu scanner and the store calculator draw on the same product library.
///
/// Tier order, most trustworthy first:
/// 1. **The curated brand table** (`StaticBeverageKnowledge`'s own brand tier). Hand-vetted, and it
///    encodes things the catalog can't, like "Heineken 0.0" being non-alcoholic. If it matched, it
///    wins, so no existing behaviour changes.
/// 2. **The store catalog**, via `CatalogMatcher`'s strict rule above. This is the new coverage:
///    thousands of real label ABVs instead of a varietal average.
/// 3. **Whatever the base said** (style chart, then category fallback).
///
/// One deliberate omission: the catalog's *container size* is not used. A catalog row's 750 mL is a
/// bottle on a shelf; a menu line means a pour. Size keeps coming from the category, which is what
/// `PourDefaults` and `SizeEstimator` already reason about.
public struct CatalogBackedKnowledge: BeverageKnowledge {
    private let base: any BeverageKnowledge
    private let catalog: any StoreCatalog

    public init(base: any BeverageKnowledge = StaticBeverageKnowledge(), catalog: any StoreCatalog) {
        self.base = base
        self.catalog = catalog
    }

    public func profile(for name: String, sectionCategory: BeverageCategory?) -> BeverageProfile {
        let baseProfile = base.profile(for: name, sectionCategory: sectionCategory)

        // The curated table is hand-checked and more specific than anything the catalog can say.
        if case .brandMatch = baseProfile.source { return baseProfile }

        guard let match = CatalogMatcher.specificMatch(for: name, in: catalog) else {
            return baseProfile
        }

        // A catalog product known to be non-alcoholic must win outright, so a menu's "Corona Cero"
        // is excluded before the metric runs rather than ranked as a 4.6% lager (Change B).
        if match.category == .nonAlcoholic {
            return BeverageProfile(
                category: .nonAlcoholic,
                typicalABV: 0,
                typicalSize: baseProfile.typicalSize,
                source: .brandMatch(matched: match.name)
            )
        }

        guard let abv = match.abv, abv > 0 else { return baseProfile }

        // Category: keep the section's read of it when there is one (a wine list means a pour), and
        // only take the catalog's when we had nothing.
        let category = baseProfile.category == .unknown ? match.category : baseProfile.category

        return BeverageProfile(
            category: category,
            typicalABV: abv,
            typicalSize: baseProfile.typicalSize,   // a pour, never the catalog's bottle size
            source: .brandMatch(matched: match.name)
        )
    }
}
