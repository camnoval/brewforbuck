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
/// (the impure `VisionTextRecognizer` supplies real ones). Bounded v1 (R1): it handles one- and
/// two-column layouts; genuine 3+ column or free-form layouts fall back gracefully to fewer columns,
/// with the manual add/edit path as the safety net.
public enum LineAssembler {

    /// Assemble ordered lines. `rowToleranceFraction` is how close two boxes' vertical centers must
    /// be — as a fraction of the median text height — to count as the same row.
    public static func lines(
        from observations: [TextObservation],
        rowToleranceFraction: Double = 0.5
    ) -> [String] {
        let cleaned = observations.filter { !trimmed($0.text).isEmpty }
        guard !cleaned.isEmpty else { return [] }

        // Left column fully, then right column — headers stay with their own column's items.
        return columnGroups(cleaned).flatMap { column in
            assembleRows(column, rowToleranceFraction: rowToleranceFraction)
        }
    }

    // MARK: - Column detection

    /// Split observations into 1 or 2 columns by finding a low-coverage vertical **gutter** near the
    /// page center. Robust to a centered title/footer that spans the gutter (those only nudge the
    /// gutter's coverage up a little, not to column density), and guarded against mistaking the
    /// intra-row gap between a name and its right-aligned price for a real column boundary.
    static func columnGroups(_ observations: [TextObservation]) -> [[TextObservation]] {
        let single = [observations]
        guard observations.count >= 8 else { return single }

        let bins = 100
        var coverage = [Int](repeating: 0, count: bins)
        for observation in observations {
            let lo = max(0, Int(observation.box.minX * Double(bins)))
            let hi = min(bins - 1, Int(observation.box.maxX * Double(bins)))
            if lo <= hi { for b in lo...hi { coverage[b] += 1 } }
        }

        // Search a central band; among the lowest-coverage bins, take the one nearest the center
        // (the true gutter beats a name/price gap, which sits off-center).
        let bandLo = Int(0.33 * Double(bins))
        let bandHi = Int(0.67 * Double(bins))
        let band = Array(bandLo..<bandHi)
        guard let minCoverage = band.map({ coverage[$0] }).min() else { return single }
        let peak = coverage.max() ?? 0

        // A real gutter is clearly emptier than the columns it separates. `peak` need only confirm
        // there's *some* overlapping content; the per-column span and count guards below are what
        // actually prevent a single column from being split at a name/price gap.
        guard peak >= 2, minCoverage <= max(1, peak / 3) else { return single }

        let gutterBin = band
            .filter { coverage[$0] == minCoverage }
            .min { abs(center($0, bins) - 0.5) < abs(center($1, bins) - 0.5) }!
        let gutterX = center(gutterBin, bins)

        let left = observations.filter { $0.box.midX < gutterX }
        let right = observations.filter { $0.box.midX >= gutterX }

        // Both sides must be substantial AND each must span a real column's width — this rejects a
        // single column whose prices merely cluster to the right of their names.
        guard left.count >= 3, right.count >= 3,
              horizontalSpan(left) >= 0.18, horizontalSpan(right) >= 0.18
        else { return single }

        return [left, right]
    }

    private static func center(_ bin: Int, _ bins: Int) -> Double {
        (Double(bin) + 0.5) / Double(bins)
    }

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
