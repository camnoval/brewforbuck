import XCTest
import CoreModel
@testable import CoreServices

/// The crossing-row veto on per-row gutter voting.
///
/// Class being pinned: a voted gutter is only real if the rows that run THROUGH it
/// do not outnumber the rows that vote for it. Found on the Rullo's menu, where a
/// centred single-column layout containing two genuinely two-column blocks had its
/// whole page cut at x≈0.516, slicing every centred line in half (80 assembled
/// lines where 42 were correct).
///
/// Validated in Python against a byte-exact port of this file over 8 real on-device
/// OCR dumps before being written here: 668 → 615 lines, orphan fragments 188 → 159,
/// chimera rows 41 → 39, with 6 of the 8 menus byte-identical.
final class LineAssemblerGutterSupportTests: XCTestCase {

    private func obs(_ text: String, x: Double, y: Double,
                     w: Double, h: Double = 0.02) -> TextObservation {
        TextObservation(text: text,
                        box: TextBox(minX: x, minY: y - h / 2,
                                     maxX: x + w, maxY: y + h / 2))
    }

    // MARK: - The veto fires

    /// A centred list with a couple of two-column rows must NOT be cut page-wide.
    /// The centred rows cross the candidate gutter and outnumber the voters.
    func testCentredListWithTwoColumnBlockIsNotCutPageWide() {
        var page: [TextObservation] = []
        // Six centred full-width lines that run straight through the middle.
        for i in 0..<6 {
            page.append(obs("Centred Cocktail Name With Description",
                            x: 0.10, y: 0.90 - Double(i) * 0.04, w: 0.80))
        }
        // Three two-column rows further down that share a gutter at ~0.50.
        for i in 0..<3 {
            let y = 0.60 - Double(i) * 0.04
            page.append(obs("Bramble", x: 0.20, y: y, w: 0.20))
            page.append(obs("Whiskey Sour", x: 0.55, y: y, w: 0.25))
        }

        let lines = LineAssembler.lines(from: page)
        XCTAssertTrue(
            lines.contains("Centred Cocktail Name With Description"),
            "a centred line must survive whole; got \(lines)"
        )
    }

    func testGutterSupportCountsCrossingRows() {
        var page: [TextObservation] = []
        for i in 0..<4 {
            page.append(obs("Full Width Prose Line", x: 0.10, y: 0.90 - Double(i) * 0.04, w: 0.80))
        }
        for i in 0..<2 {
            let y = 0.60 - Double(i) * 0.04
            page.append(obs("Left", x: 0.20, y: y, w: 0.15))
            page.append(obs("Right", x: 0.60, y: y, w: 0.15))
        }
        let support = LineAssembler.gutterSupport(page, at: 0.5)
        XCTAssertEqual(support.voters, 2)
        XCTAssertEqual(support.crossers, 4)
    }

    // MARK: - The veto must NOT fire (regression guards)

    /// A genuine two-column menu: almost no row crosses the gutter, so the veto is
    /// silent and the columns still separate. This is the R1 case the whole column
    /// detector exists for, and the veto must not weaken it.
    func testGenuineTwoColumnMenuStillSplits() {
        var page: [TextObservation] = []
        for i in 0..<8 {
            let y = 0.90 - Double(i) * 0.05
            page.append(obs("COORS LIGHT", x: 0.08, y: y, w: 0.22))
            page.append(obs("5", x: 0.36, y: y, w: 0.04))
            page.append(obs("BUDWEISER", x: 0.58, y: y, w: 0.22))
            page.append(obs("6", x: 0.86, y: y, w: 0.04))
        }
        let lines = LineAssembler.lines(from: page)
        XCTAssertTrue(lines.contains("COORS LIGHT 5"), "got \(lines)")
        XCTAssertTrue(lines.contains("BUDWEISER 6"), "got \(lines)")
        XCTAssertFalse(
            lines.contains(where: { $0.contains("COORS") && $0.contains("BUDWEISER") }),
            "left and right column fused into one chimera row: \(lines)"
        )
    }

    /// A row sitting wholly inside one column is silent, not a crosser — otherwise
    /// short left-column items would veto their own block's gutter.
    func testRowWhollyInOneColumnIsSilent() {
        var page: [TextObservation] = []
        for i in 0..<4 {
            let y = 0.90 - Double(i) * 0.05
            page.append(obs("Left Item", x: 0.10, y: y, w: 0.20))
            page.append(obs("Right Item", x: 0.60, y: y, w: 0.20))
        }
        page.append(obs("Gimlet", x: 0.10, y: 0.66, w: 0.15))   // left only
        let support = LineAssembler.gutterSupport(page, at: 0.5)
        XCTAssertEqual(support.crossers, 0, "a one-sided row must not count against")
        XCTAssertEqual(support.voters, 4)
    }

    /// A single box straddling the candidate is a crosser on its own.
    func testSingleSpanningBoxCountsAsCrosser() {
        let page = [obs("A Wide Spanning Title", x: 0.15, y: 0.90, w: 0.70)]
        let support = LineAssembler.gutterSupport(page, at: 0.5)
        XCTAssertEqual(support.crossers, 1)
        XCTAssertEqual(support.voters, 0)
    }

    /// The veto only guards tier 3. A clean empty corridor is still cut on sight,
    /// even where crossing rows exist above it, because a corridor is empty by
    /// construction.
    func testCoverageCorridorIsUnaffectedByCrossingRows() {
        var page: [TextObservation] = []
        page.append(obs("SPANNING HEADER ACROSS THE PAGE", x: 0.05, y: 0.95, w: 0.90))
        for i in 0..<6 {
            let y = 0.85 - Double(i) * 0.05
            page.append(obs("Left", x: 0.05, y: y, w: 0.30))
            page.append(obs("Right", x: 0.60, y: y, w: 0.30))
        }
        let lines = LineAssembler.lines(from: page)
        XCTAssertFalse(
            lines.contains(where: { $0.contains("Left") && $0.contains("Right") }),
            "corridor split should still separate the columns: \(lines)"
        )
    }
}

/// Splitting a row at a price → name boundary.
///
/// Class: a menu row reads "name … price", so a price followed by a word means two
/// columns' items were glued together. Recovers the `BOURBON & RYE` grid and the
/// `Red | $11/ $40 White | $12 / $44` wine header. Verified against the real OCR
/// dumps: exactly 6 splits, all 6 correct, no other line in the corpus affected.
final class LineAssemblerPriceNameSplitTests: XCTestCase {

    private func obs(_ text: String, x: Double, y: Double,
                     w: Double, h: Double = 0.02) -> TextObservation {
        TextObservation(text: text,
                        box: TextBox(minX: x, minY: y - h / 2,
                                     maxX: x + w, maxY: y + h / 2))
    }

    /// A wide gap after the price, with a name before it: two items.
    func testPriceThenNameAcrossWideGapSplits() {
        let row = [
            obs("Red", x: 0.20, y: 0.5, w: 0.06),
            obs("$11", x: 0.28, y: 0.5, w: 0.05),
            obs("$40", x: 0.35, y: 0.5, w: 0.05),
            obs("White", x: 0.58, y: 0.5, w: 0.09),   // 0.18 gap: ~9x word spacing
            obs("$12", x: 0.70, y: 0.5, w: 0.05),
            obs("$44", x: 0.77, y: 0.5, w: 0.05),
        ]
        let segments = LineAssembler.splitAtPriceToNameBoundaries(row)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments.first?.first?.text, "Red")
        XCTAssertEqual(segments.last?.first?.text, "White")
    }

    /// A numeral inside a name sits at ordinary word spacing and must NOT split.
    /// These are the real false positives the gap multiple exists to reject.
    func testNumeralInsideNameDoesNotSplit() {
        for name in [["MERLOT,", "14", "HANDS,", "WASHINGTON"],
                     ["Racer", "5", "IPA", "(7%)", "8"],
                     ["glenmorangie", "10", "year", "highland", "scotch"],
                     ["Kentucky", "red", "ale", "aged", "6", "weeks", "in", "barrels"]] {
            var row: [TextObservation] = []
            var x = 0.10
            for word in name {
                let w = 0.012 * Double(word.count)
                row.append(obs(word, x: x, y: 0.5, w: w))
                x += w + 0.004                       // ordinary word spacing
            }
            let segments = LineAssembler.splitAtPriceToNameBoundaries(row)
            XCTAssertEqual(segments.count, 1,
                           "\(name.joined(separator: " ")) must stay one line")
        }
    }

    /// A leading price has no name before it, so it is not a boundary — this is a
    /// right-aligned price recognised ahead of its own name, not a second item.
    func testLeadingPriceIsNotABoundary() {
        let row = [
            obs("4.5", x: 0.10, y: 0.5, w: 0.04),
            obs("STELLA", x: 0.30, y: 0.5, w: 0.10),   // wide gap, but no name before
            obs("CIDRE", x: 0.42, y: 0.5, w: 0.09),
        ]
        XCTAssertEqual(LineAssembler.splitAtPriceToNameBoundaries(row).count, 1)
    }

    /// A price followed by a **serving descriptor** is the same drink at another
    /// size, not a new item — `glass $13 pitcher $45` is one cocktail, and
    /// `MenuParser`'s multi-price split needs it on one line. Real M/G coordinates;
    /// this is the case that caught a purely geometric version of the rule, where
    /// the gap measured ratio 4.97 and cleared the multiple.
    func testPriceThenServingWordDoesNotSplit() {
        let cocktail = [
            obs("glass", x: 0.2039, y: 0.635, w: 0.0346),
            obs("$13", x: 0.2414, y: 0.635, w: 0.0374),
            obs("pitcher", x: 0.2932, y: 0.635, w: 0.0518),
            obs("$45", x: 0.3479, y: 0.635, w: 0.0435),
        ]
        XCTAssertEqual(LineAssembler.splitAtPriceToNameBoundaries(cocktail).count, 1,
                       "a size grid for one drink must stay on one line")

        let wine = [
            obs("glass", x: 0.1875, y: 0.282, w: 0.0461),
            obs("$14", x: 0.2368, y: 0.282, w: 0.0461),
            obs("bottle", x: 0.2961, y: 0.282, w: 0.0493),
            obs("$58", x: 0.3487, y: 0.282, w: 0.0526),
        ]
        XCTAssertEqual(LineAssembler.splitAtPriceToNameBoundaries(wine).count, 1)
    }

    func testIsServingWordVocabulary() {
        for yes in ["glass", "Pitcher", "bottle", "OZ", "pint", "each", "pour"] {
            XCTAssertTrue(LineAssembler.isServingWord(yes), "\(yes) is a serving word")
        }
        for no in ["White", "Sparkling", "RITTENHOUSE", "BLANTON'S", "Corona", "16oz"] {
            XCTAssertFalse(LineAssembler.isServingWord(no), "\(no) is not a bare serving word")
        }
    }

    func testIsPriceLikeBoundaries() {
        for yes in ["8", "$12", "4.25", "$40", "$11/", "(4.8%)", "202.", "5.50"] {
            XCTAssertTrue(LineAssembler.isPriceLike(yes), "\(yes) should be price-like")
        }
        // An interior slash is text, not a price: "Try a beach bum - 1/2 Mango Cart".
        for no in ["1/2", "20Z", "IPA", "", "-", "$"] {
            XCTAssertFalse(LineAssembler.isPriceLike(no), "\(no) should not be price-like")
        }
    }

    /// End to end: a two-column spirits grid that no gutter split reached.
    /// Word spacing here is ~0.004 and the column boundary ~0.05, matching the real
    /// dumps (ratio ≈ 12); an inflated synthetic spacing would mask the effect.
    func testSpiritsGridRowSplitsIntoTwoItems() {
        let row = [
            obs("MAKER'S", x: 0.260, y: 0.5, w: 0.070),
            obs("MARK", x: 0.334, y: 0.5, w: 0.040),
            obs("POUR", x: 0.378, y: 0.5, w: 0.030),
            obs("10", x: 0.412, y: 0.5, w: 0.020),
            obs("RITTENHOUSE", x: 0.482, y: 0.5, w: 0.110),   // 0.05 gap
            obs("RYE", x: 0.596, y: 0.5, w: 0.030),
            obs("POUR", x: 0.630, y: 0.5, w: 0.030),
            obs("8", x: 0.664, y: 0.5, w: 0.020),
        ]
        let lines = LineAssembler.lines(from: row)
        XCTAssertEqual(lines.count, 2, "got \(lines)")
        XCTAssertEqual(lines[0], "MAKER'S MARK POUR 10")
        XCTAssertEqual(lines[1], "RITTENHOUSE RYE POUR 8")
    }
}
