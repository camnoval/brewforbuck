import XCTest
@testable import CoreModel

final class BeverageCategoryTests: XCTestCase {
    func testNonAlcoholicIsNotAlcoholic() {
        XCTAssertFalse(BeverageCategory.nonAlcoholic.isAlcoholic)
    }

    func testEveryOtherCategoryIsAlcoholic() {
        for category in BeverageCategory.allCases where category != .nonAlcoholic {
            XCTAssertTrue(category.isAlcoholic, "\(category) should be alcoholic")
        }
    }
}
