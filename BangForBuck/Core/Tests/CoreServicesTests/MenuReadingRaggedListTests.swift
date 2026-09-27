//
//  MenuReadingRaggedListTests.swift
//  Core
//

import XCTest
@testable import CoreServices
@testable import CoreModel

/// The numbered-tap-list failure class, end to end.
///
/// A very common bar layout is a single column of
///
///     1 - IC LIGHT 4.2% ABV ————————————————— $5
///
/// rows: a list number, a name, a printed ABV, a leader rule, and a right-aligned price. It breaks
/// the pipeline in three independent places, which is why it needs its own file:
///
///  1. **`LineAssembler` cut the page in half.** The leader rule is not text, so the channel it
///     occupies is blank, wide enough to clear `minColumnSpan`, and respected by every row — the
///     same geometry as a real two-column page. The page was split into "names" and "prices" and
///     every price was stranded from its drink. Fixed by `minNameFraction`: a side with no
///     name-bearing text is a price gutter, not a column.
///  2. **`MenuParser` threw the ABV away** whenever the style sat on a continuation row
///     (`BLUE MOON $6` / `(BELGIAN WHEAT) 5.4% ABV`), emitting a phantom priceless item and ranking
///     the beer on an estimate. Fixed by `isAttributeLine`.
///  3. **The list number and the leader rule ended up in the name** ("1 IC LIGHT ______"), which is
///     what brand matching keys on. Fixed by `dropEnumerator` and by `_` being a separator.
final class MenuReadingRaggedListTests: XCTestCase {

    // MARK: - Geometry

    private func obs(_ t: String, _ minX: Double, _ maxX: Double, midY: Double, h: Double = 0.02)
    -> TextObservation {
        TextObservation(text: t, box: TextBox(minX: minX, minY: midY - h / 2,
                                              maxX: maxX, maxY: midY + h / 2))
    }

    /// Lay one list row out as word boxes: text from x=0.05 to `endingAt`, then the price at `priceAt`.
    private func row(_ text: String, endingAt: Double, price: String, priceAt: Double, midY: Double)
    -> [TextObservation] {
        var out: [TextObservation] = []
        let charWidth = (endingAt - 0.05) / Double(max(1, text.count))
        var x = 0.05
        for word in text.split(separator: " ").map(String.init) {
            let w = charWidth * Double(word.count)
            out.append(obs(word, x, x + w, midY: midY))
            x += w + charWidth
        }
        out.append(obs(price, priceAt, priceAt + 0.06, midY: midY))
        return out
    }

    /// The load-bearing one: a ragged single column of right-aligned prices must NOT be read as two
    /// columns, however wide the price cluster is. Before `minNameFraction` this produced eight
    /// priceless beers followed by eight orphan `$5` lines.
    func testRaggedNumberedTapListKeepsEveryPriceWithItsDrink() {
        let spec: [(String, Double, String, Double)] = [
            ("1 - IC LIGHT 4.2% ABV", 0.46, "$5", 0.72),
            ("2 - IRON CITY OLD GERMAN 4.7% ABV", 0.60, "$5", 0.78),
            ("3 - YUENGLING TRADITIONAL LAGER 4.5% ABV", 0.66, "$5", 0.74),
            ("4 - SAM ADAMS SEASONAL 6.0% ABV", 0.57, "$5", 0.76),
            ("5 - TWISTED TEA 5.0% ABV", 0.48, "$6", 0.71),
            ("6 - BELL'S TWO HEARTED 6.2% ABV", 0.56, "$7", 0.77),
            ("7 - PLATFORM MARTIAN 8.6% ABV", 0.54, "$9", 0.73),
            ("8 - TROEGS DREAMWEAVER 4.8% ABV", 0.58, "$7", 0.75),
        ]
        var observations: [TextObservation] = []
        for (i, entry) in spec.enumerated() {
            observations += row(entry.0, endingAt: entry.1, price: entry.2, priceAt: entry.3,
                                midY: 0.90 - Double(i) * 0.09)
        }

        let lines = LineAssembler.lines(from: observations)
        XCTAssertEqual(lines.count, spec.count, "no line should have been torn from its price")
        for line in lines {
            XCTAssertTrue(line.contains("$"), "a name lost its price: \(line)")
            XCTAssertTrue(line.contains("ABV"), "a row was truncated: \(line)")
        }
        XCTAssertFalse(lines.contains("$5"), "an orphan price line means the page was cut")
    }

    /// The other half of the guard: a genuine two-column page still splits. The veto is a definition
    /// of a column, not a blanket ban on cutting.
    func testGenuineTwoColumnPageStillSplits() {
        let observations = [
            obs("Coors Light", 0.05, 0.30, midY: 0.80), obs("$5", 0.38, 0.44, midY: 0.80),
            obs("Guinness", 0.05, 0.25, midY: 0.70), obs("$9", 0.38, 0.44, midY: 0.70),
            obs("Yuengling", 0.05, 0.26, midY: 0.60), obs("$6", 0.38, 0.44, midY: 0.60),
            obs("Budweiser", 0.55, 0.78, midY: 0.80), obs("$5", 0.88, 0.95, midY: 0.80),
            obs("Corona Extra", 0.55, 0.80, midY: 0.70), obs("$6", 0.88, 0.95, midY: 0.70),
            obs("Modelo Especial", 0.55, 0.82, midY: 0.60), obs("$7", 0.88, 0.95, midY: 0.60),
        ]
        let lines = LineAssembler.lines(from: observations)
        XCTAssertTrue(lines.contains("Coors Light $5"))
        XCTAssertTrue(lines.contains("Modelo Especial $7"))
        XCTAssertFalse(lines.contains { $0.contains("Coors") && $0.contains("Budweiser") })
    }

    func testNameFractionSeparatesAColumnFromAPriceGutter() {
        XCTAssertTrue(LineAssembler.isNameBearing("Guinness"))
        XCTAssertTrue(LineAssembler.isNameBearing("(IPA)"))
        XCTAssertFalse(LineAssembler.isNameBearing("$5"))
        XCTAssertFalse(LineAssembler.isNameBearing("12.50"))
        XCTAssertFalse(LineAssembler.isNameBearing("4.2%"))
        XCTAssertFalse(LineAssembler.isNameBearing("ABV"))
        XCTAssertFalse(LineAssembler.isNameBearing("16oz"))
        XCTAssertFalse(LineAssembler.isNameBearing("750ml"))
        XCTAssertFalse(LineAssembler.isNameBearing("_______"))
        XCTAssertFalse(LineAssembler.isNameBearing("-"))
    }

    // MARK: - Curled pages

    /// Real coordinates from `Tooling/Fixtures/shortys_rotating.txt`. The row drifts 0.0132 in y
    /// across its width against a tolerance of 0.0088, so the old anchored band cut it into
    /// `1 - IC LIGHT` and `4.2% ABV` and the beer arrived at the parser with no strength.
    func testACurledRowStaysOneLine() {
        let observations = [
            obs("1", 0.2565, 0.2687, midY: 0.8304, h: 0.0155),
            obs("-", 0.2686, 0.2808, midY: 0.8293, h: 0.0155),
            obs("IC", 0.2808, 0.3003, midY: 0.8278, h: 0.0162),
            obs("LIGHT", 0.3002, 0.3464, midY: 0.8246, h: 0.0188),
            obs("$5", 0.6867, 0.7128, midY: 0.8216, h: 0.0118),
            obs("4.2%", 0.3464, 0.3829, midY: 0.8207, h: 0.0178),
            obs("ABV", 0.3827, 0.4167, midY: 0.8172, h: 0.0179),
        ]
        XCTAssertEqual(LineAssembler.lines(from: observations), ["1 - IC LIGHT 4.2% ABV $5"])
    }

    /// The curl reverses down the page, which is why a single deskew angle can't be the fix: this
    /// row (number 28 on the same photo) slopes the other way.
    func testARowCurlingTheOtherWayAlsoStaysOneLine() {
        let observations = [
            obs("28", 0.1795, 0.2096, midY: 0.0618, h: 0.0205),
            obs("-", 0.2121, 0.2259, midY: 0.0624, h: 0.0199),
            obs("TRULY", 0.2284, 0.2977, midY: 0.0634, h: 0.0211),
            obs("WILD", 0.3002, 0.3499, midY: 0.0648, h: 0.0207),
            obs("BERRY", 0.3523, 0.4183, midY: 0.0662, h: 0.0211),
            obs("5.0%", 0.4209, 0.4674, midY: 0.0675, h: 0.0206),
            obs("ABV", 0.4698, 0.5097, midY: 0.0685, h: 0.0205),
            obs("$5", 0.7513, 0.7807, midY: 0.0667, h: 0.0196),
        ]
        let lines = LineAssembler.lines(from: observations)
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("TRULY WILD BERRY"))
        XCTAssertTrue(lines[0].hasSuffix("$5"))
    }

    /// Chaining must not walk down a stack. Three rows far apart in y, each a name and a price:
    /// the prices share an x but not a baseline, so they stay with their own names.
    func testChainingDoesNotWalkDownAColumn() {
        let observations = [
            obs("Coors", 0.05, 0.25, midY: 0.80), obs("$5", 0.70, 0.76, midY: 0.80),
            obs("Guinness", 0.05, 0.28, midY: 0.60), obs("$9", 0.70, 0.76, midY: 0.60),
            obs("Stella", 0.05, 0.24, midY: 0.40), obs("$7", 0.70, 0.76, midY: 0.40),
        ]
        XCTAssertEqual(LineAssembler.lines(from: observations),
                       ["Coors $5", "Guinness $9", "Stella $7"])
    }

    // MARK: - Continuation lines

    private let parser = MenuParser()

    func testStyleAndABVOnTheRowBelowAreAdoptedByTheDrinkAbove() {
        let items = parser.parse([
            "ON TAP",
            "BLUE MOON $6",
            "(BELGIAN WHEAT) 5.4% ABV",
            "MICHELOB ULTRA $7",
            "(LAGER) 4.2% ABV",
        ])
        XCTAssertEqual(items.count, 2, "a continuation row must not become an item")
        XCTAssertEqual(items[0].name, "BLUE MOON")
        XCTAssertEqual(items[0].readABV, 5.4)
        XCTAssertEqual(items[0].price?.dollars, 6)
        XCTAssertEqual(items[1].readABV, 4.2)
        XCTAssertTrue(items[0].descriptionText?.contains("BELGIAN WHEAT") == true)
    }

    func testAContinuationRowCanCarryOnlyASize() {
        let items = parser.parse(["Firestone Walker 805 $6", "16 oz"])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].readSize?.fluidOunces, 16)
    }

    /// A parenthetical whose line has its own name is still an item — this is the Thirsty Duck shape,
    /// and absorbing it would delete a real drink.
    func testAnItemWithABracketedStyleOnItsOwnRowIsNotAbsorbed() {
        let items = parser.parse([
            "ON TAP",
            "Michelob Ultra (Light Lager) - 4.2%ABV",
            "Spotted Cow (Farmhouse Ale) - 4.8%ABV",
        ])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].readABV, 4.2)
        XCTAssertEqual(items[1].readABV, 4.8)
    }

    /// A priced line is an item no matter how it is punctuated.
    func testABracketedLineWithAPriceIsAnItem() {
        let items = parser.parse(["WINE", "(Pinot Noir) $12"])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].price?.dollars, 12)
    }

    /// Nothing to attach to yet, so a bracketed opening line is still free to be a header.
    func testABracketedLineBeforeAnyItemIsNotSwallowed() {
        let items = parser.parse(["(COCKTAILS)", "Old Fashioned $12"])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].category, .cocktail)
    }

    func testABVInsideADescriptionIsHarvested() {
        let items = parser.parse([
            "Hazy Little Thing $7",
            "juicy, tropical, unfiltered, 6.7% ABV",
        ])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].readABV, 6.7)
    }

    // MARK: - List numbers and leader rules

    func testListNumberIsNotPartOfTheName() {
        let items = parser.parse([
            "1 - IC LIGHT 4.2% ABV $5",
            "12. DOGFISH HEAD 60MIN IPA 6.0% ABV $7",
            "#3 TROEGS DREAMWEAVER 4.8% ABV $7",
        ])
        XCTAssertEqual(items.map(\.name), ["IC LIGHT", "DOGFISH HEAD 60MIN IPA", "TROEGS DREAMWEAVER"])
        XCTAssertEqual(items[0].readABV, 4.2)
        XCTAssertEqual(items[0].price?.dollars, 5)
    }

    func testALeadingNumberThatIsPartOfTheNameIsKept() {
        let items = parser.parse([
            "10 Barrel Pub Beer $4",
            "151 Rum Punch $9",
            "2019 Cabernet Sauvignon $14",
        ])
        XCTAssertEqual(items.map(\.name), ["10 Barrel Pub Beer", "151 Rum Punch", "2019 Cabernet Sauvignon"])
    }

    func testUnderscoreLeaderRuleIsNotPartOfTheName() {
        let items = parser.parse(["1 - IC LIGHT 4.2% ABV ________________ $5"])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "IC LIGHT")
        XCTAssertEqual(items[0].price?.dollars, 5)
    }
}
