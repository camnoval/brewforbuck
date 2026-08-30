//
//  BrandCatalogTests.swift
//  Core
//
//  Created by Noval, Cameron on 8/30/26.
//


import XCTest
@testable import CoreContracts
@testable import CoreModel

/// The public brand projection used by the store calculator's picker.
final class BrandCatalogTests: XCTestCase {

    func testCatalogIsNonEmptyAndAlphabetical() {
        let all = BrandCatalog.all
        XCTAssertFalse(all.isEmpty)
        XCTAssertEqual(all, all.sorted { $0.label < $1.label })
    }

    func testLabelsAreUnique() {
        let labels = BrandCatalog.all.map(\.label)
        XCTAssertEqual(labels.count, Set(labels).count)
    }

    func testCarriesCategoryAndABV() {
        // A known domestic should be present with a plausible ABV and a beer category.
        guard let bud = BrandCatalog.all.first(where: { $0.label == "Bud Light" }) else {
            return XCTFail("expected Bud Light in the catalog")
        }
        XCTAssertGreaterThan(bud.abv, 0)
        XCTAssertTrue(bud.category.isAlcoholic)
    }
}