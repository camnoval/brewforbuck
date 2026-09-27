import CoreModel

/// Which of several OCR readings of the **same photo** to trust (R1).
///
/// Two readers now exist and they fail in different places rather than one dominating:
///
///  - **document structure** (Apple's `RecognizeDocumentsRequest`, iOS 26): reads tables, lists and
///    paragraphs, so a `name │ ABV │ price` grid and a two-row item come out intact. It can also
///    decline to find structure at all on a photographed, skewed laminated card.
///  - **geometry** (`LineAssembler` over per-word boxes): no notion of a table, but it degrades
///    predictably and has been proven against the real corpus.
///
/// Picking one engine forever is the mistake this type exists to avoid — it is the same mistake as
/// picking a threshold that suits the menu in front of you. So rank the **readings**, not the
/// engines, on the only thing the app actually needs from them: how many lines became a drink with a
/// usable price. That is measurable per photo, at runtime, with no new heuristic and no vocabulary.
///
/// Scored through `MenuParser` + `PricePlausibility`, the same two steps `MenuPipeline` will apply,
/// so the reading that scores best is the reading that will genuinely rank best. An absurd price is
/// withdrawn before it can inflate a score, which is what stops a junk reading (the 1948 list's
/// `7-Up 415`) from winning on volume.
public enum MenuReadSelection {

    public struct Score: Equatable, Sendable {
        /// Lines carrying a **currency-anchored** price — a `$` attached to a number. Ranked first
        /// because the 09-27 log showed that counting priced drinks alone rewards the wrong reading:
        /// the no-language-correction pass won 40 priced to 37, but several of its 40 were `$38`,
        /// `$39`, `$31` and `$4` — bare numbers that OCR had mangled out of `$8`, `$9`, `$3` and
        /// `$14`. A reading with *more* prices is not a reading with more *correct* prices, and a
        /// printed `$` is the one piece of evidence that a number was meant as money.
        public let anchored: Int
        /// Lines that became a drink carrying a plausible price — the useful output.
        public let priced: Int
        /// Lines that became a drink at all. Lower is better at equal yield: the surplus is junk
        /// headed for the "Not sure" bucket.
        public let items: Int

        public init(anchored: Int, priced: Int, items: Int) {
            self.anchored = anchored
            self.priced = priced
            self.items = items
        }
    }

    public static func score(_ lines: [String]) -> Score {
        let items = PricePlausibility.withdrawingImplausiblePrices(MenuParser().parse(lines))
        var priced = 0
        for item in items where item.price != nil { priced += 1 }
        var anchored = 0
        for line in lines where containsAnchoredPrice(line) { anchored += 1 }
        return Score(anchored: anchored, priced: priced, items: items.count)
    }

    /// A currency symbol attached to a number: `$9`, `$ 12`. A bare `9` doesn't count — that is the
    /// ambiguity being resolved, not evidence of resolving it.
    static func containsAnchoredPrice(_ line: String) -> Bool {
        var sawSymbol = false
        for character in line {
            if character == "$" || character == "£" || character == "€" {
                sawSymbol = true
            } else if sawSymbol {
                if character.isNumber { return true }
                if character != " " { sawSymbol = false }
            }
        }
        return false
    }

    /// The best reading, or `[]` if there are none. Most **anchored** prices wins; then most priced
    /// drinks; then the leaner reading; then, at a full tie, the **earlier** candidate, so callers
    /// should pass the proven reader first and a tie changes nothing.
    public static func best(of candidates: [[String]]) -> [String] {
        guard var bestLines = candidates.first else { return [] }
        var bestScore = score(bestLines)
        for candidate in candidates.dropFirst() {
            let candidateScore = score(candidate)
            if isBetter(candidateScore, than: bestScore) {
                bestScore = candidateScore
                bestLines = candidate
            }
        }
        return bestLines
    }

    static func isBetter(_ lhs: Score, than rhs: Score) -> Bool {
        if lhs.anchored != rhs.anchored { return lhs.anchored > rhs.anchored }
        if lhs.priced != rhs.priced { return lhs.priced > rhs.priced }
        return lhs.items < rhs.items
    }
}
