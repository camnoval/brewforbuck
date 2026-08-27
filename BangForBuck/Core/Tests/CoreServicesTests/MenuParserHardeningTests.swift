//
//  MenuParserHardeningTests.swift
//  Core
//
//  Created by Noval, Cameron on 8/27/26.
//


import XCTest
@testable import CoreServices
@testable import CoreModel

/// Hardening pass driven by a real two-column menu (Southside Braintree) that exposed three
/// failures on-device (§8, R1): columns glued together, `ABV x%`/size text left in names, and
/// unrecognized `drafts`/`cans` headers.
final class MenuParserHardeningTests: XCTestCase {
    private let parser = MenuParser()

    // MARK: - Name cleanup ("NAME ABV x% — price" is common on beer/wine menus)

    func testStripsABVAndSizeFragmentsFromName() {
        let items = parser.parse(["drafts", "COORS LIGHT 22oz. ABV 4.2% — 5"])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "COORS LIGHT")        // 22oz. / ABV / 4.2% / — all stripped
        XCTAssertEqual(items[0].price?.dollars, 5)
        XCTAssertEqual(items[0].readABV, 4.2)               // captured on its own axis
        XCTAssertEqual(items[0].readSize?.fluidOunces, 22)
        XCTAssertEqual(items[0].category, .draftBeer)
    }

    func testKeepsLegitimateNumberWordsInName() {
        // "60" and "MIN" are part of the name, not an ABV/size token.
        let items = parser.parse(["bottles", "DOGFISH HEAD 60 MIN IPA ABV 6% — 7.50"])
        XCTAssertEqual(items[0].name, "DOGFISH HEAD 60 MIN IPA")
        XCTAssertEqual(items[0].readABV, 6)
        XCTAssertEqual(items[0].price?.dollars, 7.5)
    }

    // MARK: - New section headers

    func testDraftsAndCansHeadersClassify() {
        let items = parser.parse([
            "drafts", "Maine Lunch ABV 7% — 11",
            "cans", "White Claw Hard Seltzer 16oz. ABV 5% — 8",
        ])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].category, .draftBeer)
        XCTAssertEqual(items[1].category, .seltzer)
    }

    // MARK: - End-to-end: two-column menu must not produce chimeras

    private func box(_ minX: Double, _ maxX: Double, midY: Double, h: Double = 0.02) -> TextBox {
        TextBox(minX: minX, minY: midY - h / 2, maxX: maxX, maxY: midY + h / 2)
    }
    private func obs(_ text: String, _ b: TextBox) -> TextObservation { TextObservation(text: text, box: b) }

    func testTwoColumnMenuAssemblesWithoutCrossColumnMerge() {
        // Left = drafts, right = bottles; each item's name+ABV on the left, price on the right —
        // exactly the shape that fused "Coors Light … 5 Budweiser ABV 5%" before column splitting.
        let observations = [
            obs("SOUTHSIDE", box(0.30, 0.70, midY: 0.97)),                 // centered title spans gutter
            obs("drafts", box(0.10, 0.30, midY: 0.90)),
            obs("COORS LIGHT 22oz. ABV 4.2%", box(0.05, 0.40, midY: 0.80)),
            obs("5", box(0.44, 0.47, midY: 0.80)),
            obs("MAINE LUNCH ABV 7%", box(0.05, 0.35, midY: 0.72)),
            obs("11", box(0.42, 0.47, midY: 0.72)),
            obs("bottles", box(0.60, 0.80, midY: 0.90)),
            obs("BUDWEISER ABV 5%", box(0.55, 0.80, midY: 0.82)),
            obs("5.50", box(0.90, 0.96, midY: 0.82)),
            obs("DOGFISH HEAD 60 MIN IPA ABV 6%", box(0.55, 0.85, midY: 0.74)),
            obs("7.50", box(0.90, 0.96, midY: 0.74)),
        ]

        let lines = LineAssembler.lines(from: observations)
        let analysis = MenuPipeline().analyze(lines: lines, metric: .standardDrinksPerDollar)
        let names = Set(analysis.ranked.map { $0.drink.name })

        XCTAssertEqual(analysis.ranked.count, 4)
        XCTAssertEqual(names, ["COORS LIGHT", "MAINE LUNCH", "BUDWEISER", "DOGFISH HEAD 60 MIN IPA"])
        // The original bug: a single row holding two drinks. Prove it can't happen now.
        XCTAssertFalse(analysis.ranked.contains {
            $0.drink.name.contains("COORS") && $0.drink.name.contains("BUDWEISER")
        })

        if let coors = analysis.ranked.first(where: { $0.drink.name == "COORS LIGHT" }) {
            XCTAssertEqual(coors.drink.abv.value, 4.2)
            XCTAssertFalse(coors.drink.abv.isEstimated)   // printed ABV, read not estimated
        } else {
            XCTFail("Coors Light missing from ranking")
        }
    }
}