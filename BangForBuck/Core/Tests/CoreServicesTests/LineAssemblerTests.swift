//
//  LineAssemblerTests.swift
//  Core
//
//  Created by Noval, Cameron on 8/27/26.
//


import XCTest
@testable import CoreServices
@testable import CoreModel

/// Mirrors `LineAssembler` (§8): the pure half of OCR. Synthetic boxes stand in for Vision output so
/// the make-or-break line-assembly heuristic (R1) is provable without a camera.
final class LineAssemblerTests: XCTestCase {

    /// Box centered at `midY` with horizontal span `[minX, maxX]` and a default text height.
    private func box(_ minX: Double, _ maxX: Double, midY: Double, height: Double = 0.04) -> TextBox {
        TextBox(minX: minX, minY: midY - height / 2, maxX: maxX, maxY: midY + height / 2)
    }
    private func obs(_ text: String, _ b: TextBox) -> TextObservation {
        TextObservation(text: text, box: b)
    }

    func testMergesNameAndPriceOnSameRowAndOrdersTopToBottom() {
        // Vision often returns name and price as separate boxes on the same visual line.
        let observations = [
            obs("Mojito", box(0.10, 0.30, midY: 0.70)),
            obs("$9",     box(0.85, 0.90, midY: 0.70)),
            obs("COCKTAILS", box(0.10, 0.40, midY: 0.90)),
            obs("The Best Margarita", box(0.10, 0.50, midY: 0.80)),
            obs("$13",   box(0.80, 0.90, midY: 0.80)),
        ]
        XCTAssertEqual(
            LineAssembler.lines(from: observations),
            ["COCKTAILS", "The Best Margarita $13", "Mojito $9"]
        )
    }

    func testDropsEmptyObservations() {
        let observations = [
            obs("Corona $5", box(0.1, 0.5, midY: 0.8)),
            obs("   ",       box(0.1, 0.2, midY: 0.7)),
        ]
        XCTAssertEqual(LineAssembler.lines(from: observations), ["Corona $5"])
    }

    func testEmptyInputYieldsNoLines() {
        XCTAssertTrue(LineAssembler.lines(from: []).isEmpty)
    }

    func testDistinctLinesStaySeparate() {
        let observations = [
            obs("Bud Light $4", box(0.1, 0.6, midY: 0.80)),
            obs("Guinness $6",  box(0.1, 0.6, midY: 0.60)),
        ]
        XCTAssertEqual(LineAssembler.lines(from: observations), ["Bud Light $4", "Guinness $6"])
    }

    /// End-to-end: assembled lines flow through the real pipeline and rank as expected — the whole
    /// point of assembling name+price back together.
    func testAssembledLinesFeedThePipeline() {
        let observations = [
            obs("WINE",     box(0.10, 0.30, midY: 0.90)),
            obs("Cabernet", box(0.10, 0.35, midY: 0.80)),
            obs("$9",       box(0.85, 0.92, midY: 0.80)),
            obs("Moscato",  box(0.10, 0.35, midY: 0.70)),
            obs("$6",       box(0.85, 0.92, midY: 0.70)),
        ]
        let lines = LineAssembler.lines(from: observations)
        XCTAssertEqual(lines, ["WINE", "Cabernet $9", "Moscato $6"])

        let analysis = MenuPipeline().analyze(lines: lines, metric: .standardDrinksPerDollar)
        XCTAssertEqual(analysis.ranked.map { $0.drink.name }, ["Cabernet", "Moscato"])
    }
}