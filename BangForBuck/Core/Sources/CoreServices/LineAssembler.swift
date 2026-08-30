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
/// (the impure `VisionTextRecognizer` supplies real ones). Column detection is a **recursive X-Y
/// cut** (R1): it repeatedly splits at the best vertical gutter, so one-, two-, three- and
/// four-column menus all assemble without fusing a left item to a right one. Genuinely free-form or
/// very tight layouts still degrade gracefully to fewer columns, with the manual add/edit path as
/// the safety net; the guards below guarantee it never over-splits a single column at a name/price
/// gap and never bisects a column bridged by a spanning title.
public enum LineAssembler {

    /// Assemble ordered lines. `rowToleranceFraction` is how close two boxes' vertical centers must
    /// be — as a fraction of the median text height — to count as the same row.
    public static func lines(
        from observations: [TextObservation],
        rowToleranceFraction: Double = 0.5
    ) -> [String] {
        let cleaned = observations.filter { !trimmed($0.text).isEmpty }
        guard !cleaned.isEmpty else { return [] }

        // Columns left-to-right, each fully assembled before the next — headers stay with their
        // own column's items.
        return columnGroups(cleaned).flatMap { column in
            assembleRows(column, rowToleranceFraction: rowToleranceFraction)
        }
    }

    // MARK: - Column detection (recursive X-Y cut)

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

    /// The best single vertical cut of `group`, or `nil`. Tries a clean empty-corridor cut first
    /// (handles any number of columns), then a central-gutter fallback for a two-column page whose
    /// gutter is bridged by a modest, non-header title.
    static func bestVerticalSplit(
        _ group: [TextObservation]
    ) -> (left: [TextObservation], right: [TextObservation])? {
        guard group.count >= minGroupToSplit else { return nil }
        return corridorSplit(group) ?? centralSplit(group)
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
