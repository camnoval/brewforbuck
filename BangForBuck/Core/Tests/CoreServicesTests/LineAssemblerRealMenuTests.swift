import XCTest
@testable import CoreServices
import CoreModel

/// Regression fixtures built from **real on-device Vision output** (word-level boxes exported from
/// the Southside menu on 2026-08-30). This is the exact case that used to fuse a left-column draft
/// with a right-column bottle; these coordinates lock in that the columns now separate.
final class LineAssemblerRealMenuTests: XCTestCase {

    private func box(_ minX: Double, _ maxX: Double, midY: Double, h: Double = 0.017) -> TextBox {
        TextBox(minX: minX, minY: midY - h / 2, maxX: maxX, maxY: midY + h / 2)
    }
    private func obs(_ text: String, _ b: TextBox) -> TextObservation {
        TextObservation(text: text, box: b)
    }
    private func row(_ words: [(String, Double, Double)], _ y: Double) -> [TextObservation] {
        words.map { obs($0.0, box($0.1, $0.2, midY: y)) }
    }

    /// Southside: drafts (left) and bottles (right), word-level boxes as Vision actually returned
    /// them. MAINE LUNCH (left) and MILLER LITE (right) share the same vertical position — the exact
    /// shape that produced a chimera before the per-word fix.
    func testSouthsideRealOCRSeparatesColumns() {
        var o: [TextObservation] = []
        o += row([("drafts", 0.1683, 0.3499)], 0.808)
        o += row([("COORS", 0.1062, 0.1742), ("LIGHT", 0.1775, 0.2325), ("22oz.", 0.2358, 0.2876),
                  ("ABV", 0.2908, 0.3199), ("4.2%", 0.3232, 0.3685), ("-", 0.3718, 0.388), ("5", 0.3912, 0.4067)], 0.770)
        o += row([("BLUE", 0.1269, 0.1788), ("MOON", 0.182, 0.2403), ("ABV", 0.2435, 0.2759),
                  ("5.4%", 0.2791, 0.3212), ("-", 0.3245, 0.3407), ("7.50", 0.3439, 0.3886)], 0.7417)
        o += row([("MAINE", 0.1295, 0.1943), ("LUNCH", 0.1975, 0.2655), ("ABV", 0.2688, 0.3012),
                  ("7%", 0.3044, 0.3335), ("-", 0.3368, 0.353), ("11", 0.3562, 0.3808)], 0.6233)
        o += row([("bottles", 0.6449, 0.8551)], 0.808)
        o += row([("BUDWEISER", 0.6192, 0.7328), ("ABV", 0.7358, 0.7678), ("5%", 0.7707, 0.7999),
                  ("-", 0.8028, 0.8203), ("5.50", 0.8232, 0.8705)], 0.7708)
        o += row([("MILLER", 0.6062, 0.6807), ("LITE", 0.6839, 0.726), ("ABV", 0.7293, 0.7617),
                  ("4.2%", 0.7649, 0.8102), ("-", 0.8135, 0.8297), ("5.50", 0.8329, 0.8808)], 0.6233)
        o += row([("CORONA", 0.5907, 0.6749), ("EXTRA", 0.6781, 0.7429), ("ABV", 0.7461, 0.7785),
                  ("4.5%", 0.7817, 0.8271), ("-", 0.8303, 0.8465), ("6.50", 0.8497, 0.8964)], 0.565)

        let lines = LineAssembler.lines(from: o)

        // The drinks assemble one-per-line with their own price.
        XCTAssertTrue(lines.contains("COORS LIGHT 22oz. ABV 4.2% - 5"))
        XCTAssertTrue(lines.contains("BUDWEISER ABV 5% - 5.50"))
        XCTAssertTrue(lines.contains("MAINE LUNCH ABV 7% - 11"))
        XCTAssertTrue(lines.contains("MILLER LITE ABV 4.2% - 5.50"))

        // No line fuses a left-column draft with a right-column bottle (the original bug).
        XCTAssertFalse(lines.contains { $0.contains("COORS") && $0.contains("BUDWEISER") })
        XCTAssertFalse(lines.contains { $0.contains("MAINE") && $0.contains("MILLER") })
    }

    /// End-to-end through the parser: the same OCR yields clean, individually-priced drinks.
    func testSouthsideRealOCRParsesToIndividualDrinks() {
        var o: [TextObservation] = []
        o += row([("drafts", 0.1683, 0.3499)], 0.808)
        o += row([("COORS", 0.1062, 0.1742), ("LIGHT", 0.1775, 0.2325), ("22oz.", 0.2358, 0.2876),
                  ("ABV", 0.2908, 0.3199), ("4.2%", 0.3232, 0.3685), ("-", 0.3718, 0.388), ("5", 0.3912, 0.4067)], 0.770)
        o += row([("bottles", 0.6449, 0.8551)], 0.808)
        o += row([("BUDWEISER", 0.6192, 0.7328), ("ABV", 0.7358, 0.7678), ("5%", 0.7707, 0.7999),
                  ("-", 0.8028, 0.8203), ("5.50", 0.8232, 0.8705)], 0.7708)

        let items = MenuParser().parse(LineAssembler.lines(from: o))
        let coors = items.first { $0.name == "COORS LIGHT" }
        XCTAssertEqual(coors?.price, Price(dollars: 5))
        XCTAssertEqual(coors?.readABV, 4.2)
        XCTAssertEqual(coors?.readSize?.fluidOunces ?? -1, 22, accuracy: 0.001)
        XCTAssertEqual(coors?.category, .draftBeer)
        let bud = items.first { $0.name == "BUDWEISER" }
        XCTAssertEqual(bud?.price, Price(dollars: 5.50))
        XCTAssertEqual(bud?.category, .bottledBeer)
    }

    /// The Reservoir: a two-column beer list (DOMESTIC | IMPORT) whose gutter is crossed by a
    /// centered "BEER" title, a "bottles & cans" subtitle, and a full-width "MISC" section. The
    /// coverage histogram couldn't find the gutter through all that; per-row gap voting does,
    /// because those centered/full-width rows are contiguous and cast no vote. Real coordinates.
    func testReservoirRealOCRSeparatesDomesticFromImport() {
        var o: [TextObservation] = []
        o += row([("DOMESTIC", 0.1344, 0.3437)], 0.6687)
        o += row([("IMPORT", 0.6561, 0.8126)], 0.6723)
        o += row([("Miller", 0.0875, 0.1594), ("High", 0.1625, 0.225), ("Life", 0.2281, 0.2781),
                  ("16oz", 0.2813, 0.3438), ("/", 0.3469, 0.3656), ("6", 0.3688, 0.3875)], 0.602)
        o += row([("Corona", 0.6656, 0.7559), ("/", 0.7586, 0.7777), ("6", 0.7805, 0.8031)], 0.6084)
        o += row([("Coors", 0.1469, 0.2187), ("Light", 0.2219, 0.2906), ("/", 0.2938, 0.3125), ("5", 0.3156, 0.3344)], 0.5422)
        o += row([("Harp", 0.6843, 0.7439), ("/", 0.7468, 0.7657), ("8", 0.7686, 0.7907)], 0.5469)
        o += row([("Lagunitas", 0.1313, 0.2531), ("IPA", 0.2563, 0.3), ("/", 0.3031, 0.3219), ("7", 0.325, 0.3437)], 0.4506)
        o += row([("Paulaner", 0.6156, 0.725), ("Radler", 0.7281, 0.8156), ("/", 0.8188, 0.8375), ("6", 0.8406, 0.8594)], 0.4578)

        let lines = LineAssembler.lines(from: o)
        XCTAssertFalse(lines.contains { $0.contains("Miller") && $0.contains("Corona") },
                       "DOMESTIC Miller must not fuse with IMPORT Corona")
        XCTAssertFalse(lines.contains { $0.contains("Lagunitas") && $0.contains("Paulaner") })
        XCTAssertTrue(lines.contains { $0.contains("Miller") && $0.contains("High") && $0.contains("Life") })
        XCTAssertTrue(lines.contains { $0.contains("Corona") && !$0.contains("Miller") })
    }
}
