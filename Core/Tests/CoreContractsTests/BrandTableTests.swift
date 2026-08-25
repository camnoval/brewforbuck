import XCTest
@testable import CoreContracts
@testable import CoreModel

/// The brand tier (from Tooling/Data/beverages.json → GeneratedBrandTable.swift) runs ahead of the
/// style chart and the category fallback.
final class BrandTableTests: XCTestCase {
    private let bk = StaticBeverageKnowledge()

    func testDomesticBrandMatch() {
        let p = bk.profile(for: "Bud Light", sectionCategory: nil)
        XCTAssertEqual(p.typicalABV, 4.2)
        guard case .brandMatch(let matched) = p.source else { return XCTFail("expected brandMatch, got \(p.source)") }
        XCTAssertEqual(matched, "Bud Light")
    }

    func testMoreSpecificBrandWins() {
        // "Corona Light" (4.0) must beat bare "Corona" (4.6) via descending-length ordering.
        XCTAssertEqual(bk.profile(for: "Corona Light", sectionCategory: nil).typicalABV, 4.0)
        XCTAssertEqual(bk.profile(for: "Corona Extra", sectionCategory: nil).typicalABV, 4.6)
        XCTAssertEqual(bk.profile(for: "Corona", sectionCategory: nil).typicalABV, 4.6)
    }

    func testSeltzerBrandBeatsGenericSeltzerStyle() {
        // High Noon is 4.5% (brand) rather than the generic seltzer style default of 5.0%.
        let p = bk.profile(for: "High Noon Peach", sectionCategory: nil)
        XCTAssertEqual(p.typicalABV, 4.5)
        XCTAssertEqual(p.category, .seltzer)
    }

    // Change B robustness: a non-alcoholic brand is caught even in a regular beer section.
    func testNonAlcoholicBrandDetectedWithoutNASection() {
        let p = bk.profile(for: "Athletic Run Wild", sectionCategory: .draftBeer)
        XCTAssertEqual(p.typicalABV, 0)
        XCTAssertEqual(p.category, .nonAlcoholic)
    }

    func testZeroVariantBeatsRegularBrand() {
        // "Heineken 0.0" must resolve non-alcoholic, not to regular Heineken (5.0%).
        let p = bk.profile(for: "Heineken 0.0", sectionCategory: nil)
        XCTAssertEqual(p.typicalABV, 0)
        XCTAssertEqual(p.category, .nonAlcoholic)
    }

    func testSectionRefinesBrandCategory() {
        // "Modelo Especial" on tap: brand ABV (4.4) kept, section makes it draft (16 oz).
        let p = bk.profile(for: "Modelo Especial", sectionCategory: .draftBeer)
        XCTAssertEqual(p.typicalABV, 4.4)
        XCTAssertEqual(p.category, .draftBeer)
        XCTAssertEqual(p.typicalSize, Volume(fluidOunces: 16))
    }
}
