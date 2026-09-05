//
//  CatalogBackedKnowledgeTests.swift
//  Core
//
//  Created by Noval, Cameron on 9/5/26.
//


import XCTest
@testable import CoreServices
import CoreContracts
import CoreModel

/// The menu scanner drawing on the same product library as the store calculator. The interesting
/// cases are all negative: a menu line that names a *category* must keep falling through to the
/// style chart, or the app states a false precision about a producer it only guessed at.
final class CatalogBackedKnowledgeTests: XCTestCase {

    private let catalog = InMemoryStoreCatalog(products: [
        CatalogProduct(name: "Josh Cellars Cabernet Sauvignon",
                       category: .wineGlass, abv: 13.5, containerMilliliters: 750),
        CatalogProduct(name: "Tito's Handmade Vodka", category: .shot, abv: 40,
                       containerMilliliters: 1750),
        CatalogProduct(name: "Yuengling Traditional Lager", category: .bottledBeer, abv: 4.5),
        CatalogProduct(name: "Moët & Chandon - Brut Impérial", category: .wineGlass, abv: 12),
        // Deliberately awkward: a catalog entry whose name is nothing but a varietal.
        CatalogProduct(name: "Chardonnay - Caviste", category: .wineGlass, abv: 13.5),
        CatalogProduct(name: "House Red Blend", category: .wineGlass, abv: 13.9),
        // A non-alcoholic product that must never rank.
        CatalogProduct(name: "Corona Cero Alcohol Free", category: .nonAlcoholic, abv: 0),
        // No percentage in the catalog: must fall through rather than assert 0%.
        CatalogProduct(name: "Mystery Craft Saison", category: .draftBeer, abv: nil),
    ])

    private var knowledge: CatalogBackedKnowledge {
        CatalogBackedKnowledge(catalog: catalog)
    }

    // MARK: - The uplift

    /// A menu that names a real product gets that product's real label ABV, not a varietal average.
    func testNamedProductGetsItsLabelABV() {
        let profile = knowledge.profile(for: "Josh Cellars Cabernet Sauvignon", sectionCategory: .wineGlass)
        XCTAssertEqual(profile.typicalABV, 13.5)
        guard case .brandMatch(let matched) = profile.source else {
            return XCTFail("expected a catalog brand match, got \(profile.source)")
        }
        XCTAssertEqual(matched, "Josh Cellars Cabernet Sauvignon")
    }

    /// A menu line is usually a shortened form of the shelf name, which still counts.
    func testShortenedMenuNameStillMatches() {
        XCTAssertEqual(knowledge.profile(for: "Josh Cellars Cabernet", sectionCategory: .wineGlass).typicalABV, 13.5)
        XCTAssertEqual(knowledge.profile(for: "Yuengling Lager", sectionCategory: .bottledBeer).typicalABV, 4.5)
        XCTAssertEqual(knowledge.profile(for: "Tito's Vodka", sectionCategory: .shot).typicalABV, 40)
    }

    func testFoldingAppliesToMenuLinesToo() {
        // OCR gives the accent or doesn't; both must land on the same product.
        XCTAssertEqual(knowledge.profile(for: "Moet Imperial", sectionCategory: .wineGlass).typicalABV, 12)
        XCTAssertEqual(knowledge.profile(for: "Moët Impérial", sectionCategory: .wineGlass).typicalABV, 12)
    }

    // MARK: - The guards that keep it honest

    /// "Chardonnay" is a varietal. Binding it to one winery's bottling would be a false precision,
    /// so it keeps using the sourced style chart (13.5% for Chardonnay) via the base knowledge.
    func testSingleWordVarietalDoesNotBindToAProduct() {
        let profile = knowledge.profile(for: "Chardonnay", sectionCategory: .wineGlass)
        guard case .styleChart = profile.source else {
            return XCTFail("expected the style chart for a bare varietal, got \(profile.source)")
        }
    }

    /// Every word here is a style or colour word, so a catalog hit adds nothing the chart doesn't
    /// already say and risks being wrong about the producer.
    func testCategoryLikeNamesFallThroughToTheChartOrFallback() {
        for name in ["Cabernet Sauvignon", "House Red", "Draft IPA", "Red Blend"] {
            let profile = knowledge.profile(for: name, sectionCategory: .wineGlass)
            if case .brandMatch = profile.source {
                XCTFail("\(name) should not bind to a catalog product")
            }
        }
    }

    /// A catalog row with no percentage must not assert one.
    func testCatalogProductWithoutABVFallsThrough() {
        let profile = knowledge.profile(for: "Mystery Craft Saison", sectionCategory: .draftBeer)
        if case .brandMatch = profile.source {
            XCTFail("a product with no ABV should not present as a brand match")
        }
        XCTAssertGreaterThan(profile.typicalABV, 0)   // still estimated by the chart/fallback
    }

    // MARK: - Ordering and invariants

    /// The curated brand table is hand-vetted and encodes things the catalog can't. It wins.
    func testCuratedBrandTableStillWins() {
        let profile = knowledge.profile(for: "Bud Light", sectionCategory: nil)
        XCTAssertEqual(profile.typicalABV, 4.2)
        guard case .brandMatch(let matched) = profile.source else {
            return XCTFail("expected the curated brand tier")
        }
        XCTAssertEqual(matched, "Bud Light")
    }

    /// Change B: a non-alcoholic catalog product is reported as non-alcoholic so `DrinkResolver`
    /// excludes it before the metric runs.
    func testNonAlcoholicCatalogProductIsExcluded() {
        let profile = knowledge.profile(for: "Corona Cero Alcohol Free", sectionCategory: .bottledBeer)
        XCTAssertEqual(profile.category, .nonAlcoholic)
        XCTAssertEqual(profile.typicalABV, 0)
    }

    /// A catalog row's size is a bottle on a shelf. A menu line means a pour, so the size must keep
    /// coming from the category and never from the catalog.
    func testCatalogSizeIsNeverUsedForAMenuPour() {
        let plain = StaticBeverageKnowledge()
            .profile(for: "Josh Cellars Cabernet Sauvignon", sectionCategory: .wineGlass)
        let enriched = knowledge.profile(for: "Josh Cellars Cabernet Sauvignon", sectionCategory: .wineGlass)

        XCTAssertEqual(enriched.typicalSize, plain.typicalSize)
        // Emphatically not the 750 mL bottle the catalog row carries.
        XCTAssertLessThan(enriched.typicalSize.fluidOunces, 12)
    }

    /// An empty catalog changes nothing, which is what makes this safe to ship before the bundled
    /// file exists.
    func testEmptyCatalogIsANoOp() {
        let empty = CatalogBackedKnowledge(catalog: InMemoryStoreCatalog(products: []))
        let base = StaticBeverageKnowledge()
        for name in ["Hazy IPA", "Pinot Noir", "Bud Light", "The Popular Delusion"] {
            XCTAssertEqual(empty.profile(for: name, sectionCategory: nil),
                           base.profile(for: name, sectionCategory: nil),
                           "\(name) should be untouched by an empty catalog")
        }
    }
}
