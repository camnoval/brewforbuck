import XCTest
@testable import CoreContracts
@testable import CoreModel

final class StaticBeverageKnowledgeTests: XCTestCase {
    private let bk = StaticBeverageKnowledge()

    // --- Chart tier: style / varietal matches use the sourced ABV and are flagged .styleChart ---

    func testBeerStylesMatchChart() {
        XCTAssertEqual(bk.profile(for: "Hazy IPA", sectionCategory: nil).typicalABV, 6.5)
        XCTAssertEqual(bk.profile(for: "Space Hopper Double IPA", sectionCategory: nil).typicalABV, 8.5)
        // Guinness is only ~4.2% despite being a stout — the specific rule must beat the generic "stout".
        XCTAssertEqual(bk.profile(for: "Guinness Draught", sectionCategory: nil).typicalABV, 4.2)
        XCTAssertEqual(bk.profile(for: "Weihenstephan (Hefeweizen)", sectionCategory: nil).typicalABV, 5.4)
    }

    func testWineVarietalsMatchChart() {
        XCTAssertEqual(bk.profile(for: "Cabernet Sauvignon", sectionCategory: nil).typicalABV, 14.0)
        XCTAssertEqual(bk.profile(for: "Prosecco", sectionCategory: nil).typicalABV, 11.0)
        XCTAssertEqual(bk.profile(for: "Moscato d'Asti", sectionCategory: nil).typicalABV, 6.0)
    }

    func testChartMatchIsFlaggedAsStyleChart() {
        let p = bk.profile(for: "Pinot Noir", sectionCategory: nil)
        guard case .styleChart(let matched) = p.source else {
            return XCTFail("expected a style-chart match, got \(p.source)")
        }
        XCTAssertEqual(matched, "Pinot Noir")
        XCTAssertEqual(p.category, .wineGlass)
    }

    func testSectionRefinesCategoryButChartKeepsABV() {
        // A *generic* IPA in a BOTTLES section: chart ABV (6.5) wins, section sets category/size
        // (bottled, 12 oz). The name here must not exist in `beverages.json` — a real brand would
        // legitimately be matched by the brand tier first, which is a different behaviour. Asserting
        // the source below makes that failure mode obvious instead of looking like a wrong ABV.
        let p = bk.profile(for: "Nonesuch Placeholder IPA", sectionCategory: .bottledBeer)
        guard case .styleChart = p.source else {
            return XCTFail("expected the style-chart tier, got \(p.source) — has this name been added to beverages.json?")
        }
        XCTAssertEqual(p.typicalABV, 6.5)
        XCTAssertEqual(p.category, .bottledBeer)
        XCTAssertEqual(p.typicalSize, Volume(fluidOunces: 12))
    }

    // --- Fallback tier: no style match → category default, flagged .categoryFallback ---

    func testUnknownNameFallsBackToSectionCategory() {
        let p = bk.profile(for: "The Popular Delusion", sectionCategory: .cocktail)
        XCTAssertEqual(p.typicalABV, 12.0)              // cocktail default ≈ 1 standard drink
        XCTAssertEqual(p.category, .cocktail)
        XCTAssertEqual(p.source, .categoryFallback)     // <- the app can say it fell back
        XCTAssertTrue(p.abvNote.contains("no style match"))
    }

    func testNoStyleNoSectionIsUnclassifiedFallback() {
        let p = bk.profile(for: "Bartender's Whim", sectionCategory: nil)
        XCTAssertEqual(p.source, .unclassifiedFallback)
        XCTAssertEqual(p.category, .unknown)
    }

    func testNonAlcoholicSectionIsZeroABV() {
        let p = bk.profile(for: "Non-Stop Pop", sectionCategory: .nonAlcoholic)
        XCTAssertEqual(p.typicalABV, 0)
        XCTAssertEqual(p.category, .nonAlcoholic)
    }

    func testShotSectionUsesSpiritStrength() {
        let p = bk.profile(for: "Lemon Drop", sectionCategory: .shot)
        XCTAssertEqual(p.typicalABV, 40.0)
        XCTAssertEqual(p.typicalSize, Volume(fluidOunces: 1.5))
    }
}
