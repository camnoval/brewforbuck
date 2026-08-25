import XCTest
@testable import CoreServices
@testable import CoreModel

final class MenuParserTests: XCTestCase {
    private let parser = MenuParser()

    func testDollarPrice() {
        let items = parser.parse(["Sunset Tea $8"])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "Sunset Tea")
        XCTAssertEqual(items[0].price?.dollars, 8)
    }

    func testBareTrailingIntegerPrice() {
        let items = parser.parse(["The Top Dawg        8"])
        XCTAssertEqual(items[0].name, "The Top Dawg")
        XCTAssertEqual(items[0].price?.dollars, 8)
    }

    func testDotLeaderPrice() {
        let items = parser.parse(["The Queen Mother ... 12"])
        XCTAssertEqual(items[0].name, "The Queen Mother")
        XCTAssertEqual(items[0].price?.dollars, 12)
    }

    func testDecimalWithSeparator() {
        let items = parser.parse(["miller lite - 4.25"])
        XCTAssertEqual(items[0].name, "miller lite")
        XCTAssertEqual(items[0].price?.dollars, 4.25)
    }

    // Change A: items under a header-priced section inherit that price (Rullo's).
    func testHeaderPriceInheritance() {
        let items = parser.parse(["Elixirs | $14", "Barrel Aged Manhattan"])
        XCTAssertEqual(items.count, 1)                       // the header is not an item
        XCTAssertEqual(items[0].name, "Barrel Aged Manhattan")
        XCTAssertEqual(items[0].price?.dollars, 14)
        XCTAssertEqual(items[0].category, .cocktail)
    }

    // No price, no header price → needsPrice (price stays nil, §10).
    func testPricelessLineIsNeedsPrice() {
        let items = parser.parse(["COCKTAILS", "Fancy Thing"])
        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].price)
        XCTAssertTrue(items[0].needsPrice)
        XCTAssertEqual(items[0].category, .cocktail)
    }

    // Ingredient line is attached, not mistaken for a priceless drink (Finding 4).
    func testDescriptionIsAttachedNotBucketed() {
        let items = parser.parse(["Sunset Tea $8", "Lemon Vodka, Triple Sec, and Sweet Tea"])
        XCTAssertEqual(items.count, 1)
        XCTAssertNotNil(items[0].descriptionText)
        XCTAssertEqual(items[0].price?.dollars, 8)
    }

    func testPrintedABVIsRead() {
        let items = parser.parse(["ON TAP", "Blue Moon (Belgian Wheat) - 5.4%ABV"])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].readABV, 5.4)
        XCTAssertEqual(items[0].category, .draftBeer)
    }
}
