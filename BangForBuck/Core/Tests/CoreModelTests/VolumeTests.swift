import XCTest
@testable import CoreModel

final class VolumeTests: XCTestCase {
    func testMilliliterBridge() {
        XCTAssertEqual(Volume(fluidOunces: 16).milliliters, 16 * 29.5735, accuracy: 0.001)
        XCTAssertEqual(Volume(milliliters: 29.5735).fluidOunces, 1, accuracy: 0.0001)
    }

    func testComparable() {
        XCTAssertTrue(Volume(fluidOunces: 5) < Volume(fluidOunces: 16))
    }
}
