import XCTest
@testable import CoreModel

final class ValueMetricTests: XCTestCase {
    func testCasesPresent() {
        XCTAssertTrue(ValueMetric.allCases.contains(.standardDrinksPerDollar))
        XCTAssertTrue(ValueMetric.allCases.contains(.caloriesPerDollar))
    }

    func testDisplayNamesNonEmpty() {
        for metric in ValueMetric.allCases {
            XCTAssertFalse(metric.displayName.isEmpty)
        }
    }
}
