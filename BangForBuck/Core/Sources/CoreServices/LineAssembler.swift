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
    /// (enough observations AND wide enough). This is the guard that stops over-splitting.
    private static func guardedSplit(
        _ group: [TextObservation],
        at gutterX: Double
    ) -> (left: [TextObservation], right: [TextObservation])? {
        let left = group.filter { $0.box.midX < gutterX }
        let right = group.filter { $0.box.midX >= gutterX }
        guard left.count >= minSideCount, right.count >= minSideCount,
              horizontalSpan(left) >= minColumnSpan - spanEpsilon,
              horizontalSpan(right) >= minColumnSpan - spanEpsilon
        else { return nil }
        return (left, right)
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

    private static func assembleRows(
        _ observations: [TextObservation],
        rowToleranceFraction: Double
    ) -> [String] {
        guard !observations.isEmpty else { return [] }

        // Top of page first (Vision y increases upward, so descending midY).
        let sorted = observations.sorted { $0.box.midY > $1.box.midY }
        let tolerance = medianHeight(of: sorted) * rowToleranceFraction

        var rows: [[TextObservation]] = []
        var current: [TextObservation] = []
        var anchorMidY: Double? = nil   // the row's first (topmost) box; prevents cumulative drift

        for observation in sorted {
            let mid = observation.box.midY
            if let anchor = anchorMidY, abs(mid - anchor) > tolerance {
                rows.append(current)
                current = [observation]
                anchorMidY = mid
            } else {
                if anchorMidY == nil { anchorMidY = mid }
                current.append(observation)
            }
        }
        if !current.isEmpty { rows.append(current) }

        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }        // left to right within the row
               .map { trimmed($0.text) }
               .joined(separator: " ")
        }
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
