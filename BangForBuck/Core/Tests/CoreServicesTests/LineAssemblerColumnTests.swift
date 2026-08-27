//
//  LineAssemblerColumnTests.swift
//  Core
//
//  Created by Noval, Cameron on 8/27/26.
//


import XCTest
@testable import CoreServices
@testable import CoreModel

/// Focused tests for `LineAssembler`'s column detection (§8, R1): a two-column page must split so
/// left and right items never fuse, and a single column with right-aligned prices must NOT be
/// mistaken for two columns.
final class LineAssemblerColumnTests: XCTestCase {

    private func box(_ minX: Double, _ maxX: Double, midY: Double, h: Double = 0.02) -> TextBox {
        TextBox(minX: minX, minY: midY - h / 2, maxX: maxX, maxY: midY + h / 2)
    }
    private func obs(_ t: String, _ b: TextBox) -> TextObservation { TextObservation(text: t, box: b) }

    func testTwoColumnSplitAvoidsCrossColumnMerge() {
        let observations = [
            obs("TITLE", box(0.30, 0.70, midY: 0.96)),
            obs("Coors Light", box(0.05, 0.30, midY: 0.80)), obs("$5", box(0.38, 0.44, midY: 0.80)),
            obs("Guinness",    box(0.05, 0.25, midY: 0.70)), obs("$9", box(0.38, 0.44, midY: 0.70)),
            obs("Budweiser",    box(0.55, 0.78, midY: 0.82)), obs("$5.50", box(0.88, 0.95, midY: 0.82)),
            obs("Corona Extra", box(0.55, 0.80, midY: 0.72)), obs("$6.50", box(0.88, 0.95, midY: 0.72)),
        ]
        let lines = LineAssembler.lines(from: observations)
        XCTAssertTrue(lines.contains("Coors Light $5"))
        XCTAssertTrue(lines.contains("Guinness $9"))
        XCTAssertTrue(lines.contains("Budweiser $5.50"))
        XCTAssertTrue(lines.contains("Corona Extra $6.50"))
        XCTAssertFalse(lines.contains { $0.contains("Coors") && $0.contains("Budweiser") })
    }

    func testSingleColumnWithRightAlignedPricesIsNotSplit() {
        // Names on the left, prices clustered right, but one column: the price cluster is too narrow
        // to be a real column, so each row stays "name price" in reading order.
        let observations = [
            obs("Sunset Tea", box(0.05, 0.48, midY: 0.90)), obs("$8", box(0.55, 0.62, midY: 0.90)),
            obs("Margarita",  box(0.05, 0.44, midY: 0.80)), obs("$13", box(0.55, 0.63, midY: 0.80)),
            obs("Mojito",     box(0.05, 0.40, midY: 0.70)), obs("$9", box(0.55, 0.62, midY: 0.70)),
            obs("Old Fashioned", box(0.05, 0.50, midY: 0.60)), obs("$12", box(0.55, 0.63, midY: 0.60)),
        ]
        XCTAssertEqual(
            LineAssembler.lines(from: observations),
            ["Sunset Tea $8", "Margarita $13", "Mojito $9", "Old Fashioned $12"]
        )
    }
}