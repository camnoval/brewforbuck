import CoreModel

/// Turns raw OCR observations into parser-ready text lines (§7, R1). Apple Vision returns many small
/// text boxes in no guaranteed reading order, and it routinely splits one menu row into separate
/// observations — e.g. the drink name on the left and its `$price` on the right. Feeding those to
/// `MenuParser` raw would strand prices from their names. This step:
///
///   1. **splits the page into columns** (many drink menus are two-column: drafts/cans on the left,
///      bottles on the right), so a left-column item and a right-column item at the same height are
///      never glued into one line; then
///   2. within each column, groups observations into visual **rows** by vertical position, orders
///      them top-to-bottom, and joins each row left-to-right so `"Coors Light"` + `"$5"` become the
///      single line the parser expects.
///
/// Pure and Foundation-free so this make-or-break heuristic is unit-testable against synthetic boxes
/// (the impure `VisionTextRecognizer` supplies real ones). Layout detection is a **recursive X-Y
/// cut** (R1): at each region it first peels off a **horizontal section band** when a strong
/// section-sized vertical gap exists, then within a band splits at the best **vertical gutter**.
/// Peeling bands first is what lets a dense multi-section menu — one that stacks a `name │ size │
/// price` beer grid above a cocktail list above a wine list in the *same* column strip — assemble
/// correctly: each section is isolated before column detection runs, so a beer's price is never
/// sliced into a separate pseudo-column and a shared draft price-grid is never torn apart. One-,
/// two-, three- and four-column menus still assemble without fusing a left item to a right one.
/// The horizontal cut only fires on a gap clearly larger than the section's own line spacing, so it
/// never bands a uniform single-section column; genuinely free-form or very tight layouts still
/// degrade gracefully, with the manual add/edit path as the safety net. The guards below guarantee
/// it never over-splits a single column at a name/price gap and never bisects a column bridged by a
/// spanning title.
public enum LineAssembler {

    /// Assemble ordered lines. `rowToleranceFraction` is how close two boxes' vertical centers must
    /// be — as a fraction of the median text height — to count as the same row.
    public static func lines(
        from observations: [TextObservation],
        rowToleranceFraction: Double = 0.5
    ) -> [String] {
        let cleaned = observations.filter { !trimmed($0.text).isEmpty }
        guard !cleaned.isEmpty else { return [] }

        // Blocks in reading order (each section band top-to-bottom, each column left-to-right),
        // fully assembled before the next — headers stay with their own section/column's items.
        return layoutBlocks(cleaned).flatMap { block in
            assembleRows(block, rowToleranceFraction: rowToleranceFraction)
        }
    }

    // MARK: - Layout detection (recursive X-Y cut)

    /// Partition observations into reading-order leaf blocks. At each region a **horizontal section
    /// band** is peeled first (top then bottom) whenever a strong section-sized vertical gap exists,
    /// otherwise the region is cut at the best **vertical gutter** (left then right). Peeling bands
    /// before columns is what keeps a stacked multi-section strip from having its beer prices sliced
    /// into a pseudo-column. Returns `[observations]` unchanged when no defensible cut exists.
    static func layoutBlocks(_ observations: [TextObservation]) -> [[TextObservation]] {
        if let (top, bottom) = bestHorizontalSplit(observations) {
            return layoutBlocks(top) + layoutBlocks(bottom)
        }
        if let (left, right) = bestVerticalSplit(observations) {
            return layoutBlocks(left) + layoutBlocks(right)
        }
        return [observations]
    }

    // MARK: - Horizontal section banding

    /// A section gap must be at least this fraction of page height in absolute terms — stops a
    /// merely-slightly-larger line gap inside one section from being read as a section break.
    static let minSectionGap = 0.03
    /// …and at least this multiple of the region's median row-to-row spacing. Uniform single-section
    /// columns have a max gap ≈ their median spacing (ratio ~1), so they never band; a real section
    /// break sits well above this.
    static let sectionGapMultiple = 2.2
    /// A band needs at least this many rows to be worth peeling (so a lone title line isn't a band).
    static let minBandRows = 2

    /// Peel the single strongest horizontal section band, or `nil`. Finds the largest vertical gap
    /// between consecutive rows; accepts it only if it clears both the absolute `minSectionGap` and
    /// `sectionGapMultiple ×` the median row gap, and both resulting bands are real (enough rows and
    /// observations). Reuses the same row banding the assembler and gutter voter use.
    static func bestHorizontalSplit(
        _ group: [TextObservation]
    ) -> (top: [TextObservation], bottom: [TextObservation])? {
        guard group.count >= minGroupToSplit else { return nil }
        let banded = rows(of: group)                       // top-to-bottom
        guard banded.count >= 4 else { return nil }
        let centers = banded.map { rowMidY($0) }           // descending (top first)
        var gaps: [Double] = []
        for i in 0..<(centers.count - 1) { gaps.append(centers[i] - centers[i + 1]) }
        guard let maxGap = gaps.max() else { return nil }
        let med = median(gaps)
        guard maxGap >= max(minSectionGap, med * sectionGapMultiple) else { return nil }
        let cutIndex = gaps.firstIndex(of: maxGap)!        // rows[0...cutIndex] | rows[cutIndex+1...]
        let topRows = Array(banded[0...cutIndex])
        let bottomRows = Array(banded[(cutIndex + 1)...])
        let top = topRows.flatMap { $0 }
        let bottom = bottomRows.flatMap { $0 }
        guard topRows.count >= minBandRows, bottomRows.count >= minBandRows,
              top.count >= minSideCount, bottom.count >= minSideCount
        else { return nil }
        return (top, bottom)
    }

    private static func rowMidY(_ row: [TextObservation]) -> Double {
        median(row.map { $0.box.midY })
    }

    private static func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        let mid = s.count / 2
        return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    // MARK: - Column detection (vertical gutter)

    private static let bins = 100
    /// A resulting column must span at least this fraction of page width — rejects a single column
    /// whose right-aligned prices cluster into a too-narrow pseudo-column, and rejects splitting a
    /// column at the gap between its names and its prices.
    static let minColumnSpan = 0.18
    /// Each side of a split needs at least this many observations to be a real column.
    static let minSideCount = 3
    /// Below this many observations there's nothing worth splitting.
    static let minGroupToSplit = 6
    /// Guard comparisons on normalized coordinates sit exactly on `minColumnSpan` for evenly-spaced
    /// layouts; a tiny epsilon keeps a `Double` tie from failing the guard.
    static let spanEpsilon = 1e-9
    /// For **gutter detection only**, a box wider than this is treated as a spanning header/title:
    /// it's dropped from the coverage histogram so a title stretched across a gutter can't hide it.
    /// The box is still assigned to a column and still counts toward the column-span guards.
    static let headerWidthFraction = 0.45

    /// Partition observations into columns by recursively cutting at the best vertical gutter.
    /// Returns `[observations]` unchanged when no defensible cut exists (single column).
    static func columnGroups(_ observations: [TextObservation]) -> [[TextObservation]] {
        guard let (left, right) = bestVerticalSplit(observations) else { return [observations] }
        return columnGroups(left) + columnGroups(right)
    }

    /// Minimum blank horizontal gap (fraction of page width) between two boxes in a row to count as
    /// a possible column gutter. Below this it's just inter-word spacing.
    static let minGutterGap = 0.045
    /// Votes within this x-distance are treated as the same gutter.
    static let gutterClusterTolerance = 0.04
    /// A gutter needs at least this many agreeing rows.
    static let minGutterVotes = 3

    /// The best single vertical cut of `group`, or `nil`. Two tiers, in order:
    /// 1. **Coverage corridors / central** — the primary detector. A clean empty-corridor cut
    ///    (handles any number of columns) or a central-gutter fallback for a two-column page. This
    ///    correctly prefers the true inter-column gutter over a within-column name/price gap, because
    ///    the widest *passing* empty corridor is the one between columns.
    /// 2. **Per-row gap voting** — used only when coverage finds nothing, i.e. when the gutter is
    ///    bridged by centered text (a `BEER` title, a `bottles & cans` subtitle, a full-width `MISC`
    ///    section, as on the Reservoir) so no empty corridor exists. A real gutter is still the blank
    ///    channel most two-column *rows* share; those centered/full-width rows are contiguous and
    ///    cast no vote, so they can't hide it.
    static func bestVerticalSplit(
        _ group: [TextObservation]
    ) -> (left: [TextObservation], right: [TextObservation])? {
        guard group.count >= minGroupToSplit else { return nil }
        if let split = corridorSplit(group) ?? centralSplit(group) { return split }
        for gutterX in rankedGutters(group) {
            // A gutter is a blank channel most rows RESPECT. Voting only counts the
            // rows that agree, so on a centred single-column menu that happens to
            // contain a couple of genuinely two-column blocks (Rullo's: the wine
            // grid and "Back to Basics"), those blocks can out-vote nothing at all
            // and cut the WHOLE page — slicing every centred line in half. Rows
            // that run through the candidate are evidence against it, so count them
            // too and reject when they win. Tiers 1 and 2 need no such check: a
            // coverage corridor is empty by construction, so nothing can cross it.
            let (voters, crossers) = gutterSupport(group, at: gutterX)
            if crossers > voters { continue }
            if let split = guardedSplit(group, at: gutterX) { return split }
        }
        return nil
    }

    /// Candidate gutter x-positions from per-row gap voting, ranked best-first (most agreeing rows,
    /// then widest gap). Each row contributes a vote at the midpoint of every blank gap ≥ `minGutterGap`
    /// between horizontally-adjacent boxes; votes are clustered and the widest gaps seed the clusters
    /// so a real inter-column gutter is tried before a narrow name/price gap.
    static func rankedGutters(_ group: [TextObservation]) -> [Double] {
        var votes: [(x: Double, width: Double)] = []
        for row in rows(of: group) {
            let ordered = row.sorted { $0.box.minX < $1.box.minX }
            for i in 0..<max(0, ordered.count - 1) {
                let gap = ordered[i + 1].box.minX - ordered[i].box.maxX
                if gap >= minGutterGap {
                    votes.append(((ordered[i].box.maxX + ordered[i + 1].box.minX) / 2, gap))
                }
            }
        }
        guard votes.count >= minGutterVotes else { return [] }

        var used = [Bool](repeating: false, count: votes.count)
        let order = votes.indices.sorted { votes[$0].width > votes[$1].width }  // seed from widest
        var clusters: [(count: Int, width: Double, x: Double)] = []
        for seed in order where !used[seed] {
            let cx = votes[seed].x
            let members = votes.indices.filter { !used[$0] && abs(votes[$0].x - cx) <= gutterClusterTolerance }
            for m in members { used[m] = true }
            if members.count >= minGutterVotes {
                let avgX = members.reduce(0.0) { $0 + votes[$1].x } / Double(members.count)
                let avgW = members.reduce(0.0) { $0 + votes[$1].width } / Double(members.count)
                clusters.append((members.count, avgW, avgX))
            }
        }
        clusters.sort { a, b in a.count != b.count ? a.count > b.count : a.width > b.width }
        return clusters.map { $0.x }
    }

    /// How many rows support a candidate gutter versus how many run through it.
    ///
    /// A row **votes** when it has a blank gap of at least `minGutterGap` straddling
    /// `gutterX`. A row **crosses** when it has no such gap there but still occupies
    /// both sides — either one box spans the position outright, or it has boxes to
    /// the left and to the right with continuous text between them. A row wholly on
    /// one side is silent and counts as neither: a short left-column item is not
    /// evidence against its own block's gutter.
    ///
    /// Needs no new tuning constant; the decision is a comparison of the two counts.
    static func gutterSupport(
        _ group: [TextObservation],
        at gutterX: Double
    ) -> (voters: Int, crossers: Int) {
        var voters = 0
        var crossers = 0
        for row in rows(of: group) {
            let ordered = row.sorted { $0.box.minX < $1.box.minX }

            var votes = false
            for i in 0..<max(0, ordered.count - 1) {
                let left = ordered[i].box.maxX
                let right = ordered[i + 1].box.minX
                if left <= gutterX, gutterX <= right, right - left >= minGutterGap {
                    votes = true
                    break
                }
            }
            if votes { voters += 1; continue }

            let spans = ordered.contains(where: {
                $0.box.minX < gutterX && gutterX < $0.box.maxX
            })
            let hasLeft = ordered.contains(where: { $0.box.maxX <= gutterX })
            let hasRight = ordered.contains(where: { $0.box.minX >= gutterX })
            if spans || (hasLeft && hasRight) { crossers += 1 }
        }
        return (voters, crossers)
    }

    /// Group observations into visual rows by vertical position — same banding the row assembler
    /// uses, exposed here so gutter voting sees the two-column rows.
    static func rows(of observations: [TextObservation]) -> [[TextObservation]] {
        guard !observations.isEmpty else { return [] }
        let sorted = observations.sorted { $0.box.midY > $1.box.midY }
        let tolerance = medianHeight(of: sorted) * 0.5
        var rows: [[TextObservation]] = []
        var current: [TextObservation] = []
        var anchorMidY: Double? = nil
        for observation in sorted {
            let mid = observation.box.midY
            if let anchor = anchorMidY, abs(mid - anchor) > tolerance {
                rows.append(current); current = [observation]; anchorMidY = mid
            } else {
                if anchorMidY == nil { anchorMidY = mid }
                current.append(observation)
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    /// Cut at a truly-empty interior corridor. Header-width boxes are suppressed from the coverage
    /// used to *find* corridors (so a title spanning a gutter doesn't fill it), but every box is
    /// still partitioned and the column guards run on the full set. Among passing corridors the
    /// widest wins, tie-broken toward the more central cut.
    private static func corridorSplit(
        _ group: [TextObservation]
    ) -> (left: [TextObservation], right: [TextObservation])? {
        var detect = group.filter { $0.box.width <= headerWidthFraction }
        if detect.count < minSideCount * 2 { detect = group }   // too little left → use all
        let coverage = self.coverage(of: detect)

        let nonEmpty = coverage.indices.filter { coverage[$0] > 0 }
        guard let first = nonEmpty.first, let last = nonEmpty.last, last - first >= 2 else { return nil }
        let interiorZeros = ((first + 1)..<last).filter { coverage[$0] == 0 }

        // Pick the widest passing corridor; tie-break toward the more central cut.
        var bestLeft: [TextObservation]?
        var bestRight: [TextObservation]?
        var bestRunLength = -1
        var bestCentrality = -Double.infinity   // higher = closer to center
        for run in contiguousRuns(interiorZeros) {
            let gutterX = center(run[run.count / 2])
            guard let split = guardedSplit(group, at: gutterX) else { continue }
            let centrality = -abs(gutterX - 0.5)
            if run.count > bestRunLength
                || (run.count == bestRunLength && centrality > bestCentrality) {
                bestRunLength = run.count
                bestCentrality = centrality
                bestLeft = split.left
                bestRight = split.right
            }
        }
        guard let left = bestLeft, let right = bestRight else { return nil }
        return (left, right)
    }

    /// Fallback for a two-column page whose gutter is bridged by a modest (non-header) title:
    /// the lowest-coverage bin nearest the center. Only ever yields a single two-way cut.
    private static func centralSplit(
        _ group: [TextObservation]
    ) -> (left: [TextObservation], right: [TextObservation])? {
        let coverage = self.coverage(of: group)
        let peak = coverage.max() ?? 0
        let bandLo = Int(0.33 * Double(bins))
        let bandHi = Int(0.67 * Double(bins))
        let band = Array(bandLo..<bandHi)
        guard let minCoverage = band.map({ coverage[$0] }).min() else { return nil }
        guard peak >= 2, minCoverage <= max(1, peak / 3) else { return nil }

        let gutterBin = band
            .filter { coverage[$0] == minCoverage }
            .min { abs(center($0) - 0.5) < abs(center($1) - 0.5) }!
        return guardedSplit(group, at: center(gutterBin))
    }

    /// Partition `group` at `gutterX` and accept only if both sides are real columns
    /// (enough observations, wide enough, AND name-bearing). This is the guard that stops
    /// over-splitting.
    private static func guardedSplit(
        _ group: [TextObservation],
        at gutterX: Double
    ) -> (left: [TextObservation], right: [TextObservation])? {
        let left = group.filter { $0.box.midX < gutterX }
        let right = group.filter { $0.box.midX >= gutterX }
        guard left.count >= minSideCount, right.count >= minSideCount,
              horizontalSpan(left) >= minColumnSpan - spanEpsilon,
              horizontalSpan(right) >= minColumnSpan - spanEpsilon,
              nameFraction(left) >= minNameFraction,
              nameFraction(right) >= minNameFraction
        else { return nil }
        return (left, right)
    }

    // MARK: - Is a side a column, or is it the price gutter of one column?

    /// **Geometry alone cannot answer this.** A single column of right-aligned prices produces the
    /// same shape as a genuine two-column page: a blank vertical channel that nearly every row
    /// respects. On a ragged tap list — `1 - IC LIGHT 4.2% ABV ————— $5` repeated down the page,
    /// whose leader rules Vision does not return as text — that channel is ~0.2 of the page wide, so
    /// it clears `minColumnSpan`, and every row votes for it, so `gutterSupport`'s votes-vs-crossers
    /// veto sees nothing wrong either. The page is cut into "names" and "prices" and **every price on
    /// the menu is stranded from its drink**, which is a total read failure on a menu that is
    /// otherwise perfectly legible.
    ///
    /// Content answers it. A menu **column** carries drink names; a **price gutter** carries prices,
    /// an ABV and the odd stray size. So a cut is refused unless both sides carry names of their own.
    /// Applied inside `guardedSplit` so it protects all three detector tiers at once (corridor,
    /// central, per-row voting) rather than only the one that happened to fire.
    ///
    /// Measured on all eight real OCR dumps: every side of every accepted split sits at **0.33 or
    /// above** (running to 0.97), while the tap list's price gutter sits at **0.03**. That is an 11×
    /// gap with nothing inside it, and anywhere in 0.05–0.40 gives byte-identical output on all
    /// eight menus, so this is a gap rather than a fitted number. Set nearer the column side because
    /// the two errors are not symmetric: wrongly vetoing a real gutter fuses two items into one
    /// visible row that a person can see and edit, while wrongly accepting a price gutter silently
    /// destroys every price on the page.
    static let minNameFraction = 0.2

    /// Unit words that name a measurement rather than a drink.
    static let unitWords: Set<String> = ["abv", "alc", "vol", "oz", "ozs", "ml", "cl", "proof"]

    /// Whether an observation could be part of a drink **name**: at least two letters once edge
    /// punctuation is trimmed (so `$7`, `5`, `%`, `-`, a leader rule and any bare number are out),
    /// and not a unit word or a digits-glued unit (`ABV`, `oz`, `12oz`, `750ml`).
    static func isNameBearing(_ text: String) -> Bool {
        let trim: Set<Character> = [
            "$", ".", ",", "%", "|", "•", "·", "(", ")", "/", "-", "–", "—",
            "_", "\"", "'", "*", "°", ":", ";", " ",
        ]
        var chars = Array(text)
        var start = 0
        var end = chars.count
        while start < end, trim.contains(chars[start]) { start += 1 }
        while end > start, trim.contains(chars[end - 1]) { end -= 1 }
        chars = Array(chars[start..<end])

        var letters = 0
        for c in chars where c.isLetter { letters += 1 }
        guard letters >= 2 else { return false }

        let word = String(chars).lowercased()
        if unitWords.contains(word) { return false }

        // A digit run glued to a unit is a size, not a name: "12oz", "16OZ.", "750ml".
        var digits = ""
        var suffix = ""
        for c in word {
            if suffix.isEmpty, c.isNumber || c == "." { digits.append(c) } else { suffix.append(c) }
        }
        if !digits.isEmpty, unitWords.contains(suffix) { return false }

        return true
    }

    /// Share of `group` that is name-bearing.
    static func nameFraction(_ group: [TextObservation]) -> Double {
        guard !group.isEmpty else { return 0 }
        var count = 0
        for observation in group where isNameBearing(observation.text) { count += 1 }
        return Double(count) / Double(group.count)
    }

    private static func coverage(of observations: [TextObservation]) -> [Int] {
        var coverage = [Int](repeating: 0, count: bins)
        for observation in observations {
            let lo = max(0, Int(observation.box.minX * Double(bins)))
            let hi = min(bins - 1, Int(observation.box.maxX * Double(bins)))
            if lo <= hi { for b in lo...hi { coverage[b] += 1 } }
        }
        return coverage
    }

    /// Group sorted bin indices into maximal contiguous runs.
    private static func contiguousRuns(_ sorted: [Int]) -> [[Int]] {
        guard !sorted.isEmpty else { return [] }
        var runs: [[Int]] = []
        var run = [sorted[0]]
        for b in sorted.dropFirst() {
            if b == run.last! + 1 { run.append(b) }
            else { runs.append(run); run = [b] }
        }
        runs.append(run)
        return runs
    }

    private static func center(_ bin: Int) -> Double { (Double(bin) + 0.5) / Double(bins) }

    private static func horizontalSpan(_ group: [TextObservation]) -> Double {
        guard let maxX = group.map({ $0.box.maxX }).max(),
              let minX = group.map({ $0.box.minX }).min() else { return 0 }
        return maxX - minX
    }

    // MARK: - Row assembly within one column

    /// Group each printed row by **following its baseline**, not by holding it to a fixed band.
    ///
    /// The previous rule pinned `anchorMidY` to a row's topmost box and required every later box to
    /// sit within `tolerance` of *that* anchor, to "prevent cumulative drift". On a menu lying flat
    /// that is right. On a paper strip held in the hand it is fatal, because the drift is real: the
    /// page curls, so one printed row's baseline genuinely moves as you read across it. Measured on
    /// the Shorty's tap list (`Tooling/Fixtures/shortys_rotating.txt`), row 1 runs y = 0.8304 →
    /// 0.8172 — a drift of 0.0132 against a tolerance of 0.0088 — so `1 - IC LIGHT` and `4.2% ABV`
    /// came out as two lines and the beer lost its printed strength before the parser saw it.
    ///
    /// Deskewing cannot fix this: the curl is not a rotation. On that same page rows 1–8 slope down
    /// to the right (to -0.096 dy/dx), rows 13 and 22–27 are flat, and row 28 slopes *up*. No single
    /// angle describes it.
    ///
    /// What is stable is the step between neighbours. Adjacent words in one printed row stay close
    /// however far the row's two ends have drifted apart — the largest neighbour step on that page
    /// is 0.0044, half the tolerance, while the gap to the row above is ~0.032. So each box chains
    /// onto whichever open row has a member **nearest** to it in y. The tolerance is unchanged;
    /// only what it is measured *from* changes, so there is nothing new to tune.
    ///
    /// **Nearest member, not last member.** Measuring against the row's rightmost box lets drift
    /// accumulate across the row, and a right-aligned price does not sit on the drifted baseline —
    /// it sits near where the row *started*. On the rectified tap list, rows 4 and 6 lost their
    /// price by 0.0086 and 0.0091 against a tolerance of 0.00825: measured against the last word
    /// they were out, measured against the nearest word (`ADAMS`, 0.0028 away) they were never in
    /// doubt. This is also what Docstrum actually does — nearest-neighbour linkage — and taking the
    /// last member was the simplification that cost two prices.
    ///
    /// The anchor's real job — stopping a chain from walking down a column and swallowing the page —
    /// is still done, by x. Boxes are consumed left to right and each joins exactly one row, so a
    /// stack of right-aligned prices has no neighbour at a similar y to chain onto and cannot
    /// absorb anything.
    private static func assembleRows(
        _ observations: [TextObservation],
        rowToleranceFraction: Double
    ) -> [String] {
        guard !observations.isEmpty else { return [] }
        let tolerance = medianHeight(of: observations) * rowToleranceFraction

        var rows: [[TextObservation]] = []
        for observation in observations.sorted(by: { $0.box.minX < $1.box.minX }) {
            var bestIndex: Int?
            var bestDelta = Double.greatestFiniteMagnitude
            for (index, row) in rows.enumerated() {
                var delta = Double.greatestFiniteMagnitude
                for member in row {
                    delta = min(delta, abs(observation.box.midY - member.box.midY))
                }
                if delta <= tolerance, delta < bestDelta {
                    bestDelta = delta
                    bestIndex = index
                }
            }
            if let bestIndex { rows[bestIndex].append(observation) } else { rows.append([observation]) }
        }

        // Top of page first (Vision y increases upward). Each row is already left-to-right, which
        // `splitAtPriceToNameBoundaries` relies on, so it must not be re-sorted here.
        return rows.sorted { topEdge(of: $0) > topEdge(of: $1) }.flatMap { row in
            splitAtPriceToNameBoundaries(row).map { segment in
                segment.map { trimmed($0.text) }.joined(separator: " ")
            }
        }
    }

    private static func topEdge(of row: [TextObservation]) -> Double {
        row.reduce(-Double.greatestFiniteMagnitude) { max($0, $1.box.midY) }
    }

    // MARK: - Price → name boundaries within one row

    /// A price token followed by a *word* means two columns' items were glued into
    /// one row: a menu row reads "name … price", so once the price has been printed
    /// the item is finished and a following name belongs to a different item. Splits
    /// `MAKER'S MARK 2 OZ. POUR 10 RITTENHOUSE RYE 2 OZ. POUR 8` and
    /// `Red | $11/ $40 White | $12 / $44` into their two real items.
    ///
    /// Two conditions keep it off ordinary names, both necessary:
    ///
    ///  - **a name must already precede the price**, so a leading price (a
    ///    right-aligned price OCR'd before its name) is never a boundary; and
    ///  - **the blank gap at the boundary must be `priceNameGapMultiple ×` the
    ///    row's own median inter-word gap.** Numerals inside names are common
    ///    ("MERLOT, 14 HANDS", "Racer 5 IPA", "glenmorangie 10 year",
    ///    "aged 6 weeks") and they sit at ordinary word spacing, ratio ≈ 1. Real
    ///    column boundaries measured 11.9–27.1 across the real OCR dumps, so the
    ///    two populations are cleanly separated and any multiple from ~2 to ~11
    ///    gives identical output. Being relative to the row's own spacing makes it
    ///    independent of font size, crop and aspect ratio.
    static let priceNameGapMultiple = 4.0

    /// Words that describe a **serving**, not a new item. A price followed by one of
    /// these is still the same drink priced at another size — `glass $13 pitcher $45`
    /// is one cocktail, and `MenuParser`'s multi-price split needs it on one line.
    /// A price followed by anything *else* is a different drink.
    ///
    /// This is the load-bearing half of the rule. The gap multiple alone is not
    /// enough: on the real M/G coordinates `$13 → pitcher` measures ratio 4.97 and
    /// `$14 → bottle` measures below 4, so a purely geometric test both splits a
    /// size grid and treats two identical layouts differently. The vocabulary is
    /// what actually separates "another size of this drink" from "the next drink".
    static let servingWords: Set<String> = [
        "glass", "glasses", "pitcher", "pitchers", "bottle", "bottles",
        "can", "cans", "oz", "ozs", "ounce", "ounces", "pint", "pints",
        "split", "splits", "carafe", "half", "quart", "liter", "litre",
        "mug", "stein", "growler", "flight", "shot", "shots", "double",
        "single", "draft", "drafts", "draught", "each", "ea", "per",
        "cup", "cups", "goblet", "magnum", "taster", "sample", "pour", "pours",
    ]

    static func isServingWord(_ text: String) -> Bool {
        let trim: Set<Character> = ["$", ".", ",", "%", "|", "•", "(", ")", "/", "-"]
        var chars = Array(text)
        var start = 0
        var end = chars.count
        while start < end, trim.contains(chars[start]) { start += 1 }
        while end > start, trim.contains(chars[end - 1]) { end -= 1 }
        chars = Array(chars[start..<end])
        return servingWords.contains(String(chars).lowercased())
    }

    static func splitAtPriceToNameBoundaries(
        _ ordered: [TextObservation]
    ) -> [[TextObservation]] {
        guard ordered.count >= 2 else { return [ordered] }

        var gaps: [Double] = []
        for i in 0..<(ordered.count - 1) {
            gaps.append(ordered[i + 1].box.minX - ordered[i].box.maxX)
        }
        let positive = gaps.filter { $0 > 0 }
        let medianGap = max(positive.isEmpty ? 0 : median(positive), 0.0005)

        var cuts: [Int] = []
        for i in 0..<(ordered.count - 1) {
            guard isPriceLike(ordered[i].text), hasLetter(ordered[i + 1].text) else { continue }
            guard ordered[0...i].contains(where: { hasLetter($0.text) }) else { continue }
            guard !isServingWord(ordered[i + 1].text) else { continue }
            guard gaps[i] >= priceNameGapMultiple * medianGap else { continue }
            cuts.append(i + 1)
        }
        guard !cuts.isEmpty else { return [ordered] }

        var segments: [[TextObservation]] = []
        var start = 0
        for cut in cuts + [ordered.count] {
            let segment = Array(ordered[start..<cut])
            if !segment.isEmpty { segments.append(segment) }
            start = cut
        }
        return segments
    }

    /// A bare number, with currency/punctuation trimmed from the ENDS only: `8`,
    /// `$12`, `4.25`, `$40`, `$11/`, `(4.8%)`. Deliberately not `1/2` — an interior
    /// slash is text ("Try a beach bum - 1/2 Mango Cart"), so trimming happens at
    /// the edges and the remainder must be digits with at most one decimal mark.
    static func isPriceLike(_ text: String) -> Bool {
        let trim: Set<Character> = ["$", ".", ",", "%", "|", "•", "(", ")", "/"]
        var chars = Array(text)
        var start = 0
        var end = chars.count
        while start < end, trim.contains(chars[start]) { start += 1 }
        while end > start, trim.contains(chars[end - 1]) { end -= 1 }
        chars = Array(chars[start..<end])
        guard !chars.isEmpty else { return false }

        var marks = 0
        for c in chars {
            if c.isNumber { continue }
            if c == "." || c == "," {
                marks += 1
                if marks > 2 { return false }
                continue
            }
            return false
        }
        return true
    }

    static func hasLetter(_ text: String) -> Bool {
        text.contains { $0.isLetter }
    }

    // MARK: - Helpers (Foundation-free)

    private static func medianHeight(of observations: [TextObservation]) -> Double {
        let heights = observations.map { $0.box.height }.sorted()
        guard !heights.isEmpty else { return 0 }
        let mid = heights.count / 2
        return heights.count % 2 == 0 ? (heights[mid - 1] + heights[mid]) / 2 : heights[mid]
    }

    private static func trimmed(_ s: String) -> String {
        let whitespace: Set<Character> = [" ", "\t", "\n", "\r"]
        let chars = Array(s)
        var start = 0, end = chars.count
        while start < end, whitespace.contains(chars[start]) { start += 1 }
        while end > start, whitespace.contains(chars[end - 1]) { end -= 1 }
        return String(chars[start..<end])
    }
}
