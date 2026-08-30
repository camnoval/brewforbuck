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

    // MARK: - N-column X-Y cut (generalized beyond two columns, R1)

    /// A three-column beer/wine/spirits grid must split into three, with no name from one column
    /// fused to another's — the recursive cut finds the second gutter after the first.
    func testThreeColumnSplit() {
        var observations: [TextObservation] = []
        let columns = [(0.03, 0.28), (0.37, 0.62), (0.71, 0.96)]
        let names = [["Lager", "Pils", "Stout"], ["Merlot", "Cab", "Rose"], ["Gin", "Rum", "Rye"]]
        for (c, span) in columns.enumerated() {
            for (r, name) in names[c].enumerated() {
                let y = 0.85 - Double(r) * 0.12
                observations.append(obs(name, box(span.0, span.0 + 0.14, midY: y)))
                observations.append(obs("$\(5 + c + r)", box(span.1 - 0.06, span.1, midY: y)))
            }
        }
        let lines = LineAssembler.lines(from: observations)
        XCTAssertTrue(lines.contains("Lager $5"))
        XCTAssertTrue(lines.contains("Merlot $6"))
        XCTAssertTrue(lines.contains("Gin $7"))
        // No cross-column chimera: a beer name never lands on a line with a spirit name.
        XCTAssertFalse(lines.contains { $0.contains("Lager") && $0.contains("Gin") })
        XCTAssertFalse(lines.contains { $0.contains("Merlot") && $0.contains("Rye") })
    }

    /// Four narrow columns still separate — proves the recursion isn't capped at two or three.
    func testFourColumnSplit() {
        var observations: [TextObservation] = []
        let columns = [(0.02, 0.20), (0.27, 0.45), (0.52, 0.70), (0.77, 0.95)]
        for (c, span) in columns.enumerated() {
            for r in 0..<3 {
                let y = 0.8 - Double(r) * 0.15
                observations.append(obs("name\(c)\(r)", box(span.0, span.0 + 0.10, midY: y)))
                observations.append(obs("$\(c)\(r)", box(span.1 - 0.05, span.1, midY: y)))
            }
        }
        let groups = LineAssembler.lines(from: observations)
        // Each of the four "name{c}{r} ${c}{r}" pairs is its own line, none fused across columns.
        for c in 0..<4 {
            for r in 0..<3 {
                XCTAssertTrue(groups.contains("name\(c)\(r) $\(c)\(r)"),
                              "missing clean line for column \(c) row \(r)")
            }
        }
        XCTAssertFalse(groups.contains { $0.contains("name0") && $0.contains("name3") })
    }

    /// A single wide column (long names left, prices far right) must NOT be split — the price
    /// cluster is too narrow to be a real column.
    func testSingleWideColumnNotSplit() {
        var observations: [TextObservation] = []
        for i in 0..<5 {
            let y = 0.9 - Double(i) * 0.1
            observations.append(obs("Item\(i)", box(0.10, 0.70, midY: y)))
            observations.append(obs("$\(8 + i)", box(0.78, 0.86, midY: y)))
        }
        let lines = LineAssembler.lines(from: observations)
        for i in 0..<5 { XCTAssertTrue(lines.contains("Item\(i) $\(8 + i)")) }
    }

    /// Three clean columns under a single full-width title: the title spans every gutter, so the
    /// corridor detector must suppress it (header width) to still find the gutters and split into
    /// three — never bisecting the middle column and stranding its prices.
    func testThreeColumnsUnderFullWidthTitle() {
        var observations = [obs("HAPPY HOUR MENU", box(0.20, 0.80, midY: 0.95))]
        let columns = [(0.03, 0.28), (0.37, 0.62), (0.71, 0.96)]
        for (c, span) in columns.enumerated() {
            for r in 0..<3 {
                let y = 0.8 - Double(r) * 0.13
                observations.append(obs("beer\(c)\(r)", box(span.0, span.0 + 0.16, midY: y)))
                observations.append(obs("$\(c)\(r)", box(span.1 - 0.05, span.1, midY: y)))
            }
        }
        let lines = LineAssembler.lines(from: observations)
        for c in 0..<3 {
            for r in 0..<3 {
                XCTAssertTrue(lines.contains("beer\(c)\(r) $\(c)\(r)"),
                              "column \(c) row \(r) should keep its price")
            }
        }
        XCTAssertFalse(lines.contains { $0.contains("beer0") && $0.contains("beer2") })
    }

    /// Regression for the real-world failure: Vision reads straight across a two-column menu and
    /// returns each physical row as one line, fusing a left-column draft with a right-column bottle.
    /// The recognizer now emits per-WORD boxes; this test feeds word-level boxes (left words + right
    /// words at the same height) and asserts the two columns stay separate — no "COORS … BUDWEISER"
    /// chimera. Positions approximate Southside's centered two-column layout.
    func testWordLevelBoxesKeepTwoColumnsApart() {
        func words(_ pairs: [(String, Double, Double)], midY: Double) -> [TextObservation] {
            pairs.map { obs($0.0, box($0.1, $0.2, midY: midY)) }
        }
        var observations: [TextObservation] = []
        // Row 1: left draft, right bottle.
        observations += words([("COORS", 0.10, 0.18), ("LIGHT", 0.19, 0.26), ("5", 0.40, 0.43)], midY: 0.80)
        observations += words([("BUDWEISER", 0.55, 0.70), ("5.50", 0.90, 0.96)], midY: 0.80)
        // Row 2.
        observations += words([("BLUE", 0.12, 0.19), ("MOON", 0.20, 0.28), ("7.50", 0.38, 0.44)], midY: 0.70)
        observations += words([("BUD", 0.55, 0.64), ("LIGHT", 0.65, 0.73), ("5.50", 0.90, 0.96)], midY: 0.70)
        // Row 3.
        observations += words([("MODELO", 0.10, 0.24), ("7.50", 0.38, 0.44)], midY: 0.60)
        observations += words([("CORONA", 0.55, 0.70), ("6.50", 0.90, 0.96)], midY: 0.60)

        let lines = LineAssembler.lines(from: observations)
        // No line fuses a left-column and a right-column drink.
        XCTAssertFalse(lines.contains { $0.contains("COORS") && $0.contains("BUDWEISER") })
        XCTAssertFalse(lines.contains { $0.contains("MODELO") && $0.contains("CORONA") })
        // Each column's rows are intact.
        XCTAssertTrue(lines.contains("COORS LIGHT 5"))
        XCTAssertTrue(lines.contains("BUDWEISER 5.50"))
        XCTAssertTrue(lines.contains("CORONA 6.50"))
    }
}
