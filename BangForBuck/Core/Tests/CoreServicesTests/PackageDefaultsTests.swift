//
//  PackageDefaultsTests.swift
//  Core
//
//  Created by Noval, Cameron on 9/5/26.
//


import XCTest
@testable import CoreServices
import CoreModel

/// Package inference: the shopper picks a product and the form is already the right shape. Every
/// case below is a real shelf-name pattern, and the negative cases matter as much as the positive
/// ones (a vintage year is not a bottle size).
final class PackageDefaultsTests: XCTestCase {

    private func suggest(_ name: String, _ category: BeverageCategory,
                         milliliters: Double? = nil, units: Int? = nil) -> PackageSuggestion {
        PackageDefaults.suggest(name: name, category: category,
                                containerMilliliters: milliliters, unitsPerPackage: units)
    }

    // MARK: - Category fallback (tier 3)

    func testWineDefaultsTo750MillilitreSingleBottle() {
        let s = suggest("Josh Cellars Cabernet", .wineGlass)
        XCTAssertEqual(s.container, .ml750)
        XCTAssertEqual(s.count, 1)
    }

    func testSpiritsDefaultToA750MillilitreBottle() {
        XCTAssertEqual(suggest("House Bourbon", .shot).container, .ml750)
        XCTAssertEqual(suggest("Some Gin", .martini).count, 1)
    }

    func testBeerDefaultsToATwelveOunceSixPack() {
        let s = suggest("Coors Light", .bottledBeer)
        XCTAssertEqual(s.container, .can12)
        XCTAssertEqual(s.count, 6)
    }

    /// Hard seltzer is sold as a variety pack far more often than as a six-pack.
    func testSeltzerDefaultsToTwelve() {
        XCTAssertEqual(suggest("White Claw Variety", .seltzer).count, 12)
    }

    // MARK: - Read it off the name (tier 2)

    func testSizeIsReadFromTheName() {
        XCTAssertEqual(suggest("Josh Cellars Cabernet Sauvignon 750ml", .wineGlass).container, .ml750)
        XCTAssertEqual(suggest("Barefoot Pinot Grigio 1.5 L", .wineGlass).container, .liter15)
        XCTAssertEqual(suggest("Tito's Handmade Vodka 1.75 L", .shot).container, .liter175)
        XCTAssertEqual(suggest("Jameson Irish Whiskey 375ml", .shot).container, .ml375)
        XCTAssertEqual(suggest("Modelo Especial 24oz", .bottledBeer).container, .can24)
    }

    /// Generic on purpose: an enumerated list of sizes misses the ones actually on the shelf.
    func testUnlistedRealSizesAreHandledNotRoundedAway() {
        let guinness = suggest("Guinness Draught 14.9oz 8pk", .draftBeer)
        XCTAssertEqual(guinness.container.volume.fluidOunces, 14.9, accuracy: 0.001)
        XCTAssertEqual(guinness.container.label, "14.9 oz")
        XCTAssertEqual(guinness.count, 8)

        let peroni = suggest("Peroni 11.2oz 6pk", .bottledBeer)
        XCTAssertEqual(peroni.container.volume.fluidOunces, 11.2, accuracy: 0.001)

        let box = suggest("Franzia Chillable Red 5 L", .wineGlass)
        XCTAssertEqual(box.container.volume.liters, 5, accuracy: 0.001)
        XCTAssertEqual(box.container.label, "5 L")     // not "5000 mL"
    }

    func testUnitsAreGluedToTheirNumberHoweverSpelled() {
        XCTAssertEqual(suggest("Whiskey 1.75 Liter", .shot).container, .liter175)
        XCTAssertEqual(suggest("Whiskey 1.75L", .shot).container, .liter175)
        XCTAssertEqual(suggest("Whiskey 1.75 L.", .shot).container, .liter175)
        XCTAssertEqual(suggest("Lager 16 OZ", .bottledBeer).container, .can16)
    }

    func testPackCountsInEveryCommonSpelling() {
        XCTAssertEqual(suggest("Coors Light 16 oz 12pk", .bottledBeer).count, 12)
        XCTAssertEqual(suggest("Yuengling Lager 12oz 24 pack", .bottledBeer).count, 24)
        XCTAssertEqual(suggest("Something 4-pack", .draftBeer).count, 4)
        XCTAssertEqual(suggest("Natural Light 30 Rack", .bottledBeer).count, 30)
    }

    func testTradeWordsNameASizeWithoutANumber() {
        XCTAssertEqual(suggest("Jim Beam Handle", .shot).container, .liter175)
        XCTAssertEqual(suggest("Yellow Tail Magnum", .wineGlass).container, .liter15)
        XCTAssertEqual(suggest("Fireball Nip", .shot).container, .ml50)
        XCTAssertEqual(suggest("Founders All Day Tallboy", .draftBeer).container, .can16)
        XCTAssertEqual(suggest("Bell's Two Hearted Stovepipe", .draftBeer).container, .can192)
    }

    /// A spirits pint is 375 mL. A cider "pint" is a beer pint, so the word must not carry over.
    func testPintMeansDifferentThingsByCategory() {
        XCTAssertEqual(suggest("Jim Beam Pint", .shot).container, .ml375)
        XCTAssertEqual(suggest("Jim Beam Half Pint", .shot).container, .ml200)
        XCTAssertEqual(suggest("Angry Orchard Pint", .cider).container, .can12)
    }

    // MARK: - The negative cases that make token matching necessary

    /// A substring search for "200" finds it inside "2007" and would size this bottle at 200 mL.
    func testVintageYearIsNotReadAsABottleSize() {
        XCTAssertEqual(suggest("Josh Cellars 2007 Cabernet", .wineGlass).container, .ml750)
        XCTAssertEqual(suggest("Chateau Something 2005 Reserve", .wineGlass).container, .ml750)
    }

    /// Real product names contain the trade words as substrings: "Handley Cellars" contains
    /// "handle", "Nipozzano" contains "nip". Whole-word matching is what keeps these 750 mL bottles
    /// instead of a handle and a nip.
    func testTradeWordsInsideRealNamesDoNotTrigger() {
        XCTAssertEqual(suggest("Handley Cellars Chardonnay", .wineGlass).container, .ml750)
        XCTAssertEqual(suggest("Frescobaldi Nipozzano Riserva", .wineGlass).container, .ml750)
        XCTAssertEqual(suggest("Minimo Rosso", .wineGlass).container, .ml750)
    }

    /// "12pk" states a count, not a size, so it must not become a 12 of anything measured.
    func testPackCountIsNotReadAsASize() {
        let s = suggest("Some Lager 12pk", .bottledBeer)
        XCTAssertEqual(s.count, 12)
        XCTAssertEqual(s.container, .can12)   // from the category, not from the "12" in "12pk"
    }

    /// A big single bottle is sold on its own whatever the category default says.
    func testLargeContainerForcesACountOfOne() {
        XCTAssertEqual(suggest("Modelo Especial 24oz", .bottledBeer).count, 1)
        XCTAssertEqual(suggest("Bell's Two Hearted 19.2 oz", .draftBeer).count, 1)
    }

    // MARK: - Catalog data wins (tier 1)

    func testStatedSizeAndCountBeatTheName() {
        // The name says nothing; the catalog says a 355 mL can, twelve of them.
        let s = suggest("Some Seltzer", .seltzer, milliliters: 355, units: 12)
        XCTAssertEqual(s.container, .can12)   // 355 mL is a 12 oz can, within tolerance
        XCTAssertEqual(s.count, 12)

        // A stated size overrides a misleading name.
        let mismatch = suggest("Vodka Handle", .shot, milliliters: 750)
        XCTAssertEqual(mismatch.container, .ml750)
    }

    func testUnusualStatedSizeKeepsItsOwnLabel() {
        let sake = suggest("Gekkeikan Sake", .wineGlass, milliliters: 720)
        XCTAssertEqual(sake.container.volume.milliliters, 720, accuracy: 0.5)
        XCTAssertEqual(sake.container.label, "720 mL")   // not snapped to the 24 oz can nearby

        let import700 = suggest("Scotch", .shot, milliliters: 700)
        XCTAssertEqual(import700.container.label, "700 mL")
    }

    func testNearMissSnapsToThePreset() {
        XCTAssertEqual(ContainerSize.closest(toMilliliters: 749), .ml750)
        XCTAssertEqual(ContainerSize.closest(toFluidOunces: 12.0), .can12)
    }

    func testCountIsNeverBelowOne() {
        XCTAssertEqual(suggest("Anything", .bottledBeer, units: 0).count, 1)
        XCTAssertEqual(suggest("Anything", .bottledBeer, units: -3).count, 1)
    }
}
