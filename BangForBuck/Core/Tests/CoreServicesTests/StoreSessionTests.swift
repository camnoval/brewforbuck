//
//  StoreSessionTests.swift
//  Core
//
//  Created by Noval, Cameron on 9/5/26.
//


import XCTest
@testable import CoreServices
import CoreModel

/// The interactive store calculator. These mirror `MenuSessionTests` on purpose — same invariants,
/// same edit semantics — plus a parity test pinning the session's ordering to the one-shot
/// `StoreComparison.rank`, since the two ranking paths are the thing most likely to drift.
final class StoreSessionTests: XCTestCase {

    private func session() -> StoreSession {
        var s = StoreSession()
        s.addProduct(name: "6pk 12oz lager", unitVolume: Volume(fluidOunces: 12), count: 6,
                     abv: .read(5), priceDollars: 10)
        s.addProduct(name: "750mL wine", unitVolume: Volume(milliliters: 750), count: 1,
                     abv: .read(13), priceDollars: 12)
        s.addProduct(name: "1.75L vodka", unitVolume: Volume(liters: 1.75), count: 1,
                     abv: .read(40), priceDollars: 20)
        s.addProduct(name: "4pk 16oz IPA", unitVolume: Volume(fluidOunces: 16), count: 4,
                     abv: .read(8), priceDollars: 13)
        return s
    }

    // MARK: - Ranking

    /// The classic shopper result, and the worked example: a 6-pack of 12 oz at 5% is 72 oz × 5%
    /// ÷ 0.6 = 6 standard drinks; at $10 that's 0.60/$ and $1.67 per standard drink.
    func testRanksBestValueFirstWithBothNumbers() {
        let ranked = session().rankedProducts
        XCTAssertEqual(ranked.first?.product.name, "1.75L vodka")
        XCTAssertEqual(ranked.last?.product.name, "750mL wine")
        XCTAssertEqual(ranked.map(\.rank), [1, 2, 3, 4])

        let sixpack = ranked.first { $0.product.name == "6pk 12oz lager" }!
        XCTAssertEqual(sixpack.product.totalStandardDrinks, 6, accuracy: 0.0001)
        XCTAssertEqual(sixpack.standardDrinksPerDollar, 0.6, accuracy: 0.0001)
        XCTAssertEqual(sixpack.pricePerStandardDrink, 10.0 / 6.0, accuracy: 0.0001)
    }

    /// The session and the one-shot ranker must agree on order and on both numbers — they share
    /// `StoreComparison.value` / `sortsBefore`, and this is what keeps that true.
    func testOrderingMatchesOneShotStoreComparison() {
        let s = session()
        let sessionOrder = s.rankedProducts.map(\.product.name)
        let oneShotOrder = StoreComparison()
            .rank(s.products.compactMap(\.storeProduct))
            .map(\.product.name)
        XCTAssertEqual(sessionOrder, oneShotOrder)

        for (a, b) in zip(s.rankedProducts, StoreComparison().rank(s.products.compactMap(\.storeProduct))) {
            XCTAssertEqual(a.standardDrinksPerDollar, b.standardDrinksPerDollar, accuracy: 0.0000001)
            XCTAssertEqual(a.pricePerStandardDrink, b.pricePerStandardDrink, accuracy: 0.0000001)
        }
    }

    /// Ties break by name so the list never reshuffles between reads.
    func testTiesBreakByName() {
        var s = StoreSession()
        s.addProduct(name: "Zeta", unitVolume: Volume(fluidOunces: 12), count: 6, abv: .read(5), priceDollars: 10)
        s.addProduct(name: "Alpha", unitVolume: Volume(fluidOunces: 12), count: 6, abv: .read(5), priceDollars: 10)
        XCTAssertEqual(s.rankedProducts.map(\.product.name), ["Alpha", "Zeta"])
    }

    /// Zero-alcohol can't divide by zero and sorts last.
    func testZeroAlcoholSortsLastWithInfinitePricePerDrink() {
        var s = StoreSession()
        s.addProduct(name: "NA 6pk", unitVolume: Volume(fluidOunces: 12), count: 6, abv: .read(0), priceDollars: 9)
        s.addProduct(name: "real 6pk", unitVolume: Volume(fluidOunces: 12), count: 6, abv: .read(5), priceDollars: 10)
        let ranked = s.rankedProducts
        XCTAssertEqual(ranked.first?.product.name, "real 6pk")
        XCTAssertEqual(ranked.last?.standardDrinksPerDollar, 0)
        XCTAssertTrue(ranked.last!.pricePerStandardDrink.isInfinite)
    }

    // MARK: - The price invariant (§10)

    /// A product with no price is visible in its own bucket but can never be ranked.
    func testPricelessProductIsBucketedNeverRanked() {
        var s = StoreSession()
        let id = s.addProduct(name: "unknown-price handle", unitVolume: Volume(liters: 1.75),
                              count: 1, abv: .read(40))!
        XCTAssertEqual(s.needsPriceProducts.map(\.id), [id])
        XCTAssertTrue(s.rankedProducts.isEmpty)
        XCTAssertNil(s.products[0].storeProduct)

        s.setPrice(id: id, dollars: 20)
        XCTAssertTrue(s.needsPriceProducts.isEmpty)
        XCTAssertEqual(s.rankedProducts.count, 1)
    }

    /// A zero or negative price is refused outright — `Price`'s failable init is the guard.
    func testNonPositivePriceIsRefused() {
        var s = StoreSession()
        let id = s.addProduct(name: "free beer?", unitVolume: Volume(fluidOunces: 12),
                              count: 6, abv: .read(5), priceDollars: 0)!
        XCTAssertTrue(s.products[0].needsPrice)

        s.setPrice(id: id, dollars: -5)
        XCTAssertTrue(s.products[0].needsPrice)
        XCTAssertTrue(s.rankedProducts.isEmpty)
    }

    // MARK: - Provenance (§11)

    /// A brand-seeded ABV is flagged as an estimate; typing the real one promotes it to `.read`.
    func testBrandSeededABVIsEstimatedUntilCorrected() {
        var s = StoreSession()
        let id = s.addProduct(name: "Bud Light 12pk", unitVolume: Volume(fluidOunces: 12), count: 12,
                              abv: .estimated(4.2, note: "Bud Light — typical label ABV"),
                              priceDollars: 14)!
        XCTAssertTrue(s.products[0].hasEstimate)
        XCTAssertEqual(s.products[0].abv.note, "Bud Light — typical label ABV")

        s.correctABV(id: id, to: 4.1)
        XCTAssertFalse(s.products[0].hasEstimate)
        XCTAssertEqual(s.products[0].abv.value, 4.1, accuracy: 0.0001)
    }

    // MARK: - Edits

    func testSetPackageRecomputesValue() {
        var s = StoreSession()
        let id = s.addProduct(name: "lager", unitVolume: Volume(fluidOunces: 12), count: 6,
                              abv: .read(5), priceDollars: 10)!
        let before = s.rankedProducts[0].standardDrinksPerDollar

        s.setPackage(id: id, unitVolume: Volume(fluidOunces: 12), count: 12)
        XCTAssertEqual(s.products[0].totalVolume.fluidOunces, 144, accuracy: 0.0001)
        XCTAssertGreaterThan(s.rankedProducts[0].standardDrinksPerDollar, before)
    }

    func testCountIsClampedToAtLeastOne() {
        var s = StoreSession()
        let id = s.addProduct(name: "single", unitVolume: Volume(fluidOunces: 12), count: 0,
                              abv: .read(5), priceDollars: 3)!
        XCTAssertEqual(s.products[0].count, 1)
        s.setPackage(id: id, unitVolume: Volume(fluidOunces: 12), count: -4)
        XCTAssertEqual(s.products[0].count, 1)
    }

    func testAddRejectsBlankNameAndIdsStayStableAcrossRemoval() {
        var s = StoreSession()
        XCTAssertNil(s.addProduct(name: "   ", unitVolume: Volume(fluidOunces: 12), count: 1, abv: .read(5)))
        XCTAssertTrue(s.products.isEmpty)

        let a = s.addProduct(name: "A", unitVolume: Volume(fluidOunces: 12), count: 1, abv: .read(5), priceDollars: 2)!
        let b = s.addProduct(name: "B", unitVolume: Volume(fluidOunces: 12), count: 1, abv: .read(5), priceDollars: 2)!
        s.removeProduct(id: a)
        let c = s.addProduct(name: "C", unitVolume: Volume(fluidOunces: 12), count: 1, abv: .read(5), priceDollars: 2)!
        XCTAssertEqual([b, c], [1, 2])          // ids never recycle, so a stale row can't be hijacked
        XCTAssertEqual(s.products.map(\.name), ["B", "C"])

        s.removeAll()
        XCTAssertTrue(s.products.isEmpty)
        XCTAssertNil(s.best)
    }

    func testStaleIdEditsAreNoOps() {
        var s = session()
        let before = s.products
        s.setPrice(id: 999, dollars: 5)
        s.correctABV(id: 999, to: 12)
        s.setPackage(id: 999, unitVolume: Volume(fluidOunces: 25), count: 4)
        s.removeProduct(id: 999)
        XCTAssertEqual(s.products, before)
    }

    /// A trimmed name is what gets stored (the form's text field leaves whitespace behind).
    func testNameIsTrimmed() {
        var s = StoreSession()
        s.addProduct(name: "  Modelo 12pk \n", unitVolume: Volume(fluidOunces: 12), count: 12,
                     abv: .read(4.4), priceDollars: 17)
        XCTAssertEqual(s.products[0].name, "Modelo 12pk")
    }
}
