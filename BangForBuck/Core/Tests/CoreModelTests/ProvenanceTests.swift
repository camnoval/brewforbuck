import XCTest
@testable import CoreModel

final class ProvenanceTests: XCTestCase {
    func testReadIsNotEstimated() {
        let p = Provenance.read(6.5)
        XCTAssertEqual(p.value, 6.5)
        XCTAssertFalse(p.isEstimated)
        XCTAssertNil(p.note)
    }

    func testEstimatedCarriesValueAndNote() {
        let p = Provenance.estimated(5.0, note: "assumed lager")
        XCTAssertEqual(p.value, 5.0)
        XCTAssertTrue(p.isEstimated)
        XCTAssertEqual(p.note, "assumed lager")
    }

    // §11: correcting an estimate inline promotes it to .read.
    func testCorrectionPromotesToRead() {
        let corrected = Provenance.estimated(5.0, note: "guess").corrected(to: 6.0)
        XCTAssertFalse(corrected.isEstimated)
        XCTAssertEqual(corrected.value, 6.0)
    }

    func testMapPreservesProvenance() {
        XCTAssertTrue(Provenance.estimated(2.0, note: "n").map { $0 * 2 }.isEstimated)
        XCTAssertEqual(Provenance.read(2.0).map { $0 * 2 }.value, 4.0)
    }
}
