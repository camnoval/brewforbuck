//
//  ObservationFixtureTests.swift
//  Core
//
//  Created by Noval, Cameron on 8/30/26.
//

import XCTest
@testable import CoreServices
import CoreModel

/// The OCR export serializer: it must round-trip real observations into a Swift literal that pastes
/// cleanly into a test, with deterministic, human-readable coordinates.
final class ObservationFixtureTests: XCTestCase {

    func testCoordinateFormatting() {
        XCTAssertEqual(ObservationFixture.fmt(0.05), "0.05")
        XCTAssertEqual(ObservationFixture.fmt(0.8), "0.8")
        XCTAssertEqual(ObservationFixture.fmt(1.0), "1")
        XCTAssertEqual(ObservationFixture.fmt(0.0), "0")
        XCTAssertEqual(ObservationFixture.fmt(0.3266), "0.3266")
        XCTAssertEqual(ObservationFixture.fmt(0.30000000000000004), "0.3")
        XCTAssertEqual(ObservationFixture.fmt(25.36), "25.36")
    }

    func testQuotingEscapesSpecials() {
        XCTAssertEqual(ObservationFixture.quoted("Coors"), "\"Coors\"")
        XCTAssertEqual(ObservationFixture.quoted("a\"b"), "\"a\\\"b\"")
        XCTAssertEqual(ObservationFixture.quoted("a\\b"), "\"a\\\\b\"")
    }

    func testSwiftLiteralIsPasteReady() {
        let obs = [
            TextObservation(text: "Coors", box: TextBox(minX: 0.05, minY: 0.79, maxX: 0.30, maxY: 0.81)),
            TextObservation(text: "$5", box: TextBox(minX: 0.38, minY: 0.79, maxX: 0.44, maxY: 0.81)),
        ]
        let literal = ObservationFixture.swiftLiteral(obs)
        XCTAssertTrue(literal.hasPrefix("let observations: [TextObservation] = ["))
        XCTAssertTrue(literal.contains(
            "TextObservation(text: \"Coors\", box: TextBox(minX: 0.05, minY: 0.79, maxX: 0.3, maxY: 0.81))"))
        XCTAssertTrue(literal.contains("TextObservation(text: \"$5\","))
    }

    func testDebugDumpIncludesAssembledLines() {
        let obs = [
            TextObservation(text: "Coors", box: TextBox(minX: 0.05, minY: 0.79, maxX: 0.30, maxY: 0.81)),
            TextObservation(text: "$5", box: TextBox(minX: 0.38, minY: 0.79, maxX: 0.44, maxY: 0.81)),
        ]
        let dump = ObservationFixture.debugDump(obs)
        XCTAssertTrue(dump.contains("# 2 observations"))
        XCTAssertTrue(dump.contains("LineAssembler.lines output"))
        XCTAssertTrue(dump.contains("Coors $5"))   // one row, name + price joined
    }
}
