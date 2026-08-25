import XCTest
@testable import CoreServices
@testable import CoreModel

final class MenuPipelineTests: XCTestCase {
    private let pipeline = MenuPipeline()

    func testWineRanksWithEstimatedABV() {
        let a = pipeline.analyze(lines: ["WINE", "Cabernet $9"], metric: .standardDrinksPerDollar)
        XCTAssertEqual(a.ranked.count, 1)
        XCTAssertEqual(a.ranked[0].drink.name, "Cabernet")
        XCTAssertEqual(a.ranked[0].drink.abv.value, 14.0)          // style-chart estimate
        XCTAssertTrue(a.ranked[0].drink.abv.isEstimated)
        XCTAssertEqual(a.ranked[0].value, 0.1296, accuracy: 0.001) // (5oz*14%)/0.6/$9
    }

    func testPricelessGoesToNeedsPriceNotRanking() {
        let a = pipeline.analyze(lines: ["COCKTAILS", "Margarita"], metric: .standardDrinksPerDollar)
        XCTAssertTrue(a.ranked.isEmpty)
        XCTAssertEqual(a.needsPrice, ["Margarita"])
    }

    func testNonAlcoholicSectionExcluded() {
        let a = pipeline.analyze(lines: ["MOCKTAILS", "Virgin Mojito $7"], metric: .standardDrinksPerDollar)
        XCTAssertTrue(a.ranked.isEmpty)
        XCTAssertEqual(a.excludedNonAlcoholic, ["Virgin Mojito"])
    }

    // Change B via brand: a non-alcoholic brand is excluded even inside a regular beer section.
    func testNonAlcoholicBrandExcludedInBeerSection() {
        let a = pipeline.analyze(
            lines: ["BOTTLES", "Heineken 0.0 $6", "Heineken $6"],
            metric: .standardDrinksPerDollar
        )
        XCTAssertTrue(a.excludedNonAlcoholic.contains("Heineken 0.0"))
        XCTAssertEqual(a.ranked.count, 1)
        XCTAssertEqual(a.ranked[0].drink.name, "Heineken")
    }

    func testOrderingBestValueFirst() {
        let a = pipeline.analyze(
            lines: ["WINE", "Cabernet $9", "Moscato $6"],
            metric: .standardDrinksPerDollar
        )
        XCTAssertEqual(a.ranked.map { $0.drink.name }, ["Cabernet", "Moscato"])
        XCTAssertEqual(a.ranked[0].rank, 1)
    }
}
