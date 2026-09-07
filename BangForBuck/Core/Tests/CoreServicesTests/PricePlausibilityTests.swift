//
//  PricePlausibilityTests.swift
//  Core
//
//  Created by Noval, Cameron on 9/7/26.
//


import XCTest
import CoreModel
import CoreContracts
@testable import CoreServices

/// Withholding a price that doesn't fit the rest of its own menu (§10, §11).
///
/// Class: a misread price is worse than no price. `PABST BLUE RIBBON 1602.` ranked a
/// $3.50 beer at $16.02 and `7-Up 415` ranked at $415 — both real tokens off the page
/// attached to the wrong item, so "never fabricate a price" held while the displayed
/// number was still wrong. The price is withdrawn, never corrected, and the item
/// travels the `needsPrice` path.
///
/// Validated on the real OCR dumps: 7 bad prices caught, no correct price withdrawn,
/// stable for any multiple from 3.0 to 5.0.
final class PricePlausibilityTests: XCTestCase {

    private func item(_ name: String, _ dollars: Double?,
                      _ category: BeverageCategory = .bottledBeer) -> MenuItem {
        MenuItem(name: name,
                 price: dollars.flatMap { Price(dollars: $0) },
                 category: category)
    }

    // MARK: - Withdraws misreads

    func testAbsurdOutlierPriceIsWithdrawn() {
        let items = [
            item("Coors Light", 4.0), item("Bud Light", 4.0),
            item("Miller Lite", 4.5), item("Blue Moon", 4.5),
            item("Junk", 415.0),                   // ~100x the cheap end
        ]
        let out = PricePlausibility.withdrawingImplausiblePrices(items)
        XCTAssertNil(out.last?.price, "an absurd outlier must be withheld")
        XCTAssertTrue(out.last?.needsPrice ?? false)
        // Everything else is untouched.
        XCTAssertEqual(out.dropLast().compactMap { $0.price?.dollars }, [4.0, 4.0, 4.5, 4.5])
    }

    /// Deliberately NOT caught. `PABST BLUE RIBBON 1602.` is a real misread at only
    /// 4x the cheap end of its list, which is exactly where legitimate premium and
    /// large-format prices live. Reaching it costs real prices, so it stays. Pinned
    /// so nobody "fixes" this by tightening the multiple without reading why.
    func testMisreadInsideThePlausibleRangeIsDeliberatelyKept() {
        let items = [
            item("Coors Light", 4.0), item("Bud Light", 4.0),
            item("Miller Lite", 4.5), item("Blue Moon", 4.5),
            item("Pabst Blue Ribbon", 16.02),
        ]
        XCTAssertNotNil(PricePlausibility.withdrawingImplausiblePrices(items).last?.price)
    }

    /// The name and every other field survive: only the price is withheld, so the
    /// person sees the drink in `needsPrice` and can type the real number.
    func testWithdrawalKeepsTheRestOfTheItem() {
        let items = [
            item("A", 4.0), item("B", 4.0), item("C", 4.0), item("D", 4.0),
            MenuItem(name: "Junk", price: Price(dollars: 415), readABV: 5.0,
                     category: .bottledBeer, descriptionText: "a note"),
        ]
        let out = PricePlausibility.withdrawingImplausiblePrices(items)
        XCTAssertEqual(out.last?.name, "Junk")
        XCTAssertNil(out.last?.price)
        XCTAssertEqual(out.last?.readABV, 5.0)
        XCTAssertEqual(out.last?.descriptionText, "a note")
    }

    // MARK: - Leaves correct prices alone

    /// A menu priced in something other than present-day dollars must survive intact.
    /// The 1948 Roosevelt list runs $0.20–$1.60; an absolute floor would condemn all
    /// of it, which is exactly why the test is relative.
    func testHistoricPricedMenuIsNotCondemned() {
        let items = [
            item("Pink Lady", 1.05), item("Manhattan", 1.00),
            item("Old Fashioned", 0.95), item("Sidecar", 1.20),
            item("Bottle Beers", 0.30), item("Coca Cola", 0.15),
        ]
        let out = PricePlausibility.withdrawingImplausiblePrices(items)
        XCTAssertEqual(out.compactMap { $0.price?.dollars }.count, 6,
                       "no price on a cheap menu may be withdrawn")
    }

    /// ...and on that same menu the genuine misread still goes.
    func testMisreadOnACheapMenuIsStillCaught() {
        let items = [
            item("Pink Lady", 1.05), item("Manhattan", 1.00),
            item("Old Fashioned", 0.95), item("Sidecar", 1.20),
            item("7-Up", 415.0),                   // 339x the cheap end
        ]
        let out = PricePlausibility.withdrawingImplausiblePrices(items)
        XCTAssertNil(out.last?.price)
    }

    /// Expensive drinks are real, and these are the shapes that a tighter rule
    /// withdraws. Every one of these was a false positive at a 4x multiple.
    func testGenuinelyExpensiveDrinksAreKept() {
        let cases: [(String, [(String, Double)], BeverageCategory)] = [
            ("long-tail bourbon list", [("Evan Williams", 8), ("Bulleit", 9),
                                        ("Woodford", 10), ("Blantons", 12),
                                        ("Eagle Rare", 15), ("Pappy 15yr", 60)], .shot),
            ("one premium champagne", [("House Red", 9), ("House White", 9),
                                       ("Rose", 10), ("Pinot", 11),
                                       ("Malbec", 12), ("Dom Perignon", 120)], .wineGlass),
            ("750ml among cans", [("Lager", 5), ("IPA", 6), ("Pils", 6),
                                  ("Wheat", 6.5), ("Cantillon 750ml", 45)], .bottledBeer),
            ("pitchers beside pints", [("Pint A", 6), ("Pint B", 6), ("Pint C", 7),
                                       ("Pint D", 7), ("Pitcher A", 26),
                                       ("Pitcher B", 28)], .draftBeer),
            ("magnum among glasses", [("A", 10), ("B", 11), ("C", 12),
                                      ("D", 12), ("Magnum", 95)], .wineGlass),
            ("rare scotch", [("A", 12), ("B", 14), ("C", 16),
                             ("D", 18), ("Macallan 25", 150)], .shot),
        ]
        for (label, rows, category) in cases {
            let items = rows.map { item($0.0, $0.1, category) }
            let kept = PricePlausibility.withdrawingImplausiblePrices(items)
                .compactMap { $0.price?.dollars }.count
            XCTAssertEqual(kept, rows.count, "\(label): a real price was withdrawn")
        }
    }

    /// Wine by the bottle beside wine by the glass, both landing in `wineGlass`.
    func testBottlePricesBesideGlassPricesAreKept() {
        let items = [
            item("Chardonnay glass", 6.0, .wineGlass),
            item("Pinot glass", 6.5, .wineGlass),
            item("Cabernet glass", 7.0, .wineGlass),
            item("Sauv Blanc glass", 8.0, .wineGlass),
            item("Chardonnay bottle", 44.0, .wineGlass),
            item("Pinot bottle", 48.0, .wineGlass),
            item("Cabernet bottle", 48.0, .wineGlass),
        ]
        let out = PricePlausibility.withdrawingImplausiblePrices(items)
        XCTAssertEqual(out.compactMap { $0.price?.dollars }.count, 7,
                       "a second serving size must not be mistaken for misreads")
    }

    /// Scattered high values have no neighbours, so they are not a mode.
    /// The 1948 list: real prices near $1, misreads up to $415. Only the values far
    /// out are withdrawn; $15 at 15.8x stays, being inside the range where real
    /// premium prices live.
    func testOnlyTheFarOutValuesOnAWreckedMenuAreWithdrawn() {
        let items = [
            item("A", 0.95, .wineGlass), item("B", 0.95, .wineGlass),
            item("C", 1.2, .wineGlass), item("D", 1.5, .wineGlass),
            item("Coca Cola", 15.0, .wineGlass), item("White Rock", 30.0, .wineGlass),
            item("7-Up", 415.0, .wineGlass),
        ]
        let doubted = PricePlausibility.implausiblePriceIndices(items)
        XCTAssertTrue(doubted.contains(6), "415 must go")
        XCTAssertTrue(doubted.contains(5), "30 must go")
        XCTAssertFalse(doubted.contains(4), "15 is inside the premium range; kept")
    }

    /// Every decision is a ratio between prices on the same menu, so the rule is
    /// scale free: yen, pence or 1948 dollars all behave identically.
    func testDecisionsAreScaleInvariant() {
        let base = [
            item("A", 4.0), item("B", 4.0), item("C", 4.5),
            item("D", 4.5), item("Junk", 415.0),
        ]
        let expected = PricePlausibility.implausiblePriceIndices(base)
        for factor in [0.01, 0.7, 100.0, 1000.0] {
            let scaled = base.map { item($0.name, ($0.price?.dollars ?? 0) * factor) }
            XCTAssertEqual(PricePlausibility.implausiblePriceIndices(scaled), expected,
                           "scaling by \(factor) changed the outcome")
        }
    }

    /// Too few prices in a category means no evidence, so nothing is withdrawn —
    /// silence beats a guess. Two real wine-bottle prices beside nothing else.
    func testSmallSampleIsLeftAlone() {
        let items = [
            item("Cabernet", 25.0, .wineGlass),
            item("Malbec", 28.0, .wineGlass),
        ]
        XCTAssertTrue(PricePlausibility.implausiblePriceIndices(items).isEmpty)
    }

    /// Categories are judged separately: an $8 cocktail is not an outlier because
    /// beers cost $4.
    func testCategoriesAreJudgedIndependently() {
        let items = [
            item("Beer A", 4.0), item("Beer B", 4.0),
            item("Beer C", 4.0), item("Beer D", 4.5),
            item("Cocktail A", 8.0, .cocktail), item("Cocktail B", 8.0, .cocktail),
            item("Cocktail C", 8.0, .cocktail), item("Cocktail D", 15.0, .cocktail),
        ]
        XCTAssertTrue(PricePlausibility.implausiblePriceIndices(items).isEmpty)
    }

    func testLowerQuartileResistsJunkPiledAtTheTop() {
        // 6 of these 11 prices are misreads. The median is 15 — up among the junk,
        // which would condemn every real price. The lower quartile stays down with
        // the real ones. (With odd n the lower half includes the median index, so the
        // half is [0.95, 0.95, 1.0, 1.45, 1.6, 15] and its median is 1.225.)
        let values = [0.95, 0.95, 1.0, 1.45, 1.6, 15, 20, 30, 90, 100.45, 415]
        XCTAssertEqual(PricePlausibility.lowerQuartile(values), 1.225, accuracy: 0.001)
        XCTAssertLessThan(PricePlausibility.lowerQuartile(values), 2.0,
                          "the reference must sit with the real prices, not the junk")
    }

    func testEmptyAndUnpricedInputAreNoOps() {
        XCTAssertTrue(PricePlausibility.withdrawingImplausiblePrices([]).isEmpty)
        let unpriced = [item("A", nil), item("B", nil)]
        XCTAssertEqual(PricePlausibility.withdrawingImplausiblePrices(unpriced), unpriced)
    }
}

/// Discarding a printed ABV that can't be right for its category (§11).
///
/// Class: `(4.2%)` read as `(42%)` ranked a 20 oz Guinness at 42% ABV, ≈14 standard
/// drinks and 1.40 per dollar, badged "from menu" as though measured. An implausible
/// printed value is discarded and the knowledge estimate used instead — dividing by
/// ten would be a fabrication wearing a `.read` badge.
final class ABVPlausibilityTests: XCTestCase {

    private func profile(_ category: BeverageCategory, typical: Double) -> BeverageProfile {
        BeverageProfile(category: category, typicalABV: typical,
                        typicalSize: Volume(fluidOunces: 12),
                        source: .styleChart(matched: "test"))
    }

    func testDecimalMisreadIsDemotedToEstimated() {
        let item = MenuItem(name: "20 oz Guinness Stout (42%)", price: Price(dollars: 10),
                            readABV: 42.0, category: .draftBeer)
        let abv = ABVEstimator.estimate(item, profile: profile(.draftBeer, typical: 4.2))
        XCTAssertTrue(abv.isEstimated, "42% on a stout must not present as measured")
        XCTAssertEqual(abv.value, 4.2, accuracy: 0.001, "the estimate comes from knowledge")
    }

    func testPlausiblePrintedABVIsStillRead() {
        let credible: [(BeverageCategory, Double)] = [
            (.draftBeer, 4.2), (.draftBeer, 8.2), (.wineGlass, 13.5),
            (.cocktail, 30.0), (.shot, 40.0),
        ]
        for (category, printed) in credible {
            let item = MenuItem(name: "x", price: Price(dollars: 8),
                                readABV: printed, category: category)
            let abv = ABVEstimator.estimate(item, profile: profile(category, typical: 5))
            XCTAssertFalse(abv.isEstimated, "\(printed)% is credible for \(category)")
            XCTAssertEqual(abv.value, printed, accuracy: 0.001)
        }
    }

    /// The ceiling sits above the strongest thing anyone actually sells, so real
    /// products pass — including the extremes that a tighter ceiling demoted.
    func testStrongButRealDrinksAreAccepted() {
        let real: [(BeverageCategory, Double, String)] = [
            (.bottledBeer, 14.0, "imperial stout"),
            (.bottledBeer, 15.0, "barleywine"),
            (.bottledBeer, 28.0, "Samuel Adams Utopias"),
            (.wineGlass, 20.0, "fortified wine"),
            (.wineGlass, 24.0, "sherry"),
            (.martini, 32.0, "stirred martini"),
            (.shot, 60.0, "overproof rum"),
            (.shot, 95.0, "Everclear"),
        ]
        for (category, printed, label) in real {
            let item = MenuItem(name: label, price: Price(dollars: 10),
                                readABV: printed, category: category)
            XCTAssertFalse(
                ABVEstimator.estimate(item, profile: profile(category, typical: 5)).isEstimated,
                "\(label) at \(printed)% is real and must stay .read")
        }
    }

    /// A dropped decimal multiplies by ten, so every category catches one on
    /// anything it realistically contains.
    func testTenfoldMisreadsAreCaughtInEveryCategory() {
        let misreads: [(BeverageCategory, Double)] = [
            (.draftBeer, 42.0), (.draftBeer, 54.0), (.bottledBeer, 82.0),
            (.cider, 50.0), (.seltzer, 45.0), (.wineGlass, 55.0),
            (.cocktail, 50.0),
        ]
        for (category, printed) in misreads {
            let item = MenuItem(name: "x", price: Price(dollars: 8),
                                readABV: printed, category: category)
            XCTAssertTrue(
                ABVEstimator.estimate(item, profile: profile(category, typical: 5)).isEstimated,
                "\(printed)% in \(category) is a dropped decimal")
        }
    }

    func testUnknownCategoryHasNoBasisToJudge() {
        XCTAssertNil(ABVEstimator.abvCeiling(for: .unknown))
        let item = MenuItem(name: "?", price: Price(dollars: 8),
                            readABV: 42.0, category: .unknown)
        XCTAssertFalse(ABVEstimator.estimate(item, profile: profile(.unknown, typical: 5)).isEstimated,
                       "with no ceiling the printed value stands")
    }

    func testNonPositiveABVIsNotPlausible() {
        XCTAssertFalse(ABVEstimator.isPlausible(0, for: .draftBeer))
        XCTAssertFalse(ABVEstimator.isPlausible(-1, for: .draftBeer))
    }
}