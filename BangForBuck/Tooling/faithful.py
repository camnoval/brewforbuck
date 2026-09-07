"""
Line-by-line port of Core/Sources/CoreServices/LineAssembler.swift.

The ONLY purpose of this file is to be identical to the Swift. Every constant,
comparison and tie-break mirrors the source so that a threshold experiment run here
predicts what the device will do. It is verified against the `LineAssembler.lines
output` block of every real OCR dump: if `verify.py` does not report 8/8 exact
matches, nothing measured here can be trusted.

Do not "improve" anything in this file. Experiments belong in a Tunables instance
passed in, never in the algorithm.
"""

from dataclasses import dataclass, replace


# ---------------------------------------------------------------- model types

@dataclass(frozen=True)
class Box:
    minX: float
    minY: float
    maxX: float
    maxY: float

    @property
    def midX(self) -> float:
        return (self.minX + self.maxX) / 2

    @property
    def midY(self) -> float:
        return (self.minY + self.maxY) / 2

    @property
    def width(self) -> float:
        return self.maxX - self.minX

    @property
    def height(self) -> float:
        return self.maxY - self.minY


@dataclass(frozen=True)
class Obs:
    text: str
    box: Box


@dataclass(frozen=True)
class Tunables:
    """Mirrors the Swift static constants. Change these to run an experiment."""
    rowToleranceFraction: float = 0.5
    minSectionGap: float = 0.03
    sectionGapMultiple: float = 2.2
    minBandRows: int = 2
    bins: int = 100
    minColumnSpan: float = 0.18
    minSideCount: int = 3
    minGroupToSplit: int = 6
    spanEpsilon: float = 1e-9
    headerWidthFraction: float = 0.45
    minGutterGap: float = 0.045
    gutterClusterTolerance: float = 0.04
    minGutterVotes: int = 3


DEFAULTS = Tunables()


# -------------------------------------------------------------------- helpers

def _median(values: list) -> float:
    s = sorted(values)
    if not s:
        return 0.0
    mid = len(s) // 2
    return (s[mid - 1] + s[mid]) / 2 if len(s) % 2 == 0 else s[mid]


def _median_height(observations: list) -> float:
    return _median([o.box.height for o in observations])


def _trimmed(s: str) -> str:
    return s.strip(" \t\n\r")


def _center(bin_index: int, t: Tunables) -> float:
    return (bin_index + 0.5) / t.bins


def _horizontal_span(group: list) -> float:
    if not group:
        return 0.0
    return max(o.box.maxX for o in group) - min(o.box.minX for o in group)


def _coverage(observations: list, t: Tunables) -> list:
    coverage = [0] * t.bins
    for o in observations:
        lo = max(0, int(o.box.minX * t.bins))
        hi = min(t.bins - 1, int(o.box.maxX * t.bins))
        if lo <= hi:
            for b in range(lo, hi + 1):
                coverage[b] += 1
    return coverage


def _contiguous_runs(sorted_bins: list) -> list:
    if not sorted_bins:
        return []
    runs, run = [], [sorted_bins[0]]
    for b in sorted_bins[1:]:
        if b == run[-1] + 1:
            run.append(b)
        else:
            runs.append(run)
            run = [b]
    runs.append(run)
    return runs


# ------------------------------------------------------------------ row banding

def rows(observations: list, t: Tunables = DEFAULTS) -> list:
    """`LineAssembler.rows(of:)`. Anchored on the row's topmost box, not a running
    mean, so a slowly-drifting baseline cannot swallow the next row."""
    if not observations:
        return []
    ordered = sorted(observations, key=lambda o: -o.box.midY)
    tolerance = _median_height(ordered) * 0.5
    out, current, anchor = [], [], None
    for o in ordered:
        mid = o.box.midY
        if anchor is not None and abs(mid - anchor) > tolerance:
            out.append(current)
            current = [o]
            anchor = mid
        else:
            if anchor is None:
                anchor = mid
            current.append(o)
    if current:
        out.append(current)
    return out


def _row_mid_y(row: list) -> float:
    return _median([o.box.midY for o in row])


# ------------------------------------------------------- horizontal banding

def best_horizontal_split(group: list, t: Tunables = DEFAULTS):
    """`bestHorizontalSplit`. Peels the SINGLE strongest band, then recursion
    handles the rest. Gaps are between row MID-Ys (centre to centre)."""
    if len(group) < t.minGroupToSplit:
        return None
    banded = rows(group, t)
    if len(banded) < 4:
        return None
    centers = [_row_mid_y(r) for r in banded]
    gaps = [centers[i] - centers[i + 1] for i in range(len(centers) - 1)]
    if not gaps:
        return None
    max_gap = max(gaps)
    med = _median(gaps)
    if not (max_gap >= max(t.minSectionGap, med * t.sectionGapMultiple)):
        return None
    cut = gaps.index(max_gap)
    top_rows, bottom_rows = banded[: cut + 1], banded[cut + 1:]
    top = [o for r in top_rows for o in r]
    bottom = [o for r in bottom_rows for o in r]
    if (len(top_rows) < t.minBandRows or len(bottom_rows) < t.minBandRows
            or len(top) < t.minSideCount or len(bottom) < t.minSideCount):
        return None
    return top, bottom


# --------------------------------------------------------- vertical splitting

def _guarded_split(group: list, gutter_x: float, t: Tunables):
    left = [o for o in group if o.box.midX < gutter_x]
    right = [o for o in group if o.box.midX >= gutter_x]
    if (len(left) < t.minSideCount or len(right) < t.minSideCount
            or _horizontal_span(left) < t.minColumnSpan - t.spanEpsilon
            or _horizontal_span(right) < t.minColumnSpan - t.spanEpsilon):
        return None
    return left, right


def _corridor_split(group: list, t: Tunables):
    detect = [o for o in group if o.box.width <= t.headerWidthFraction]
    if len(detect) < t.minSideCount * 2:
        detect = group
    coverage = _coverage(detect, t)

    non_empty = [i for i, c in enumerate(coverage) if c > 0]
    if not non_empty:
        return None
    first, last = non_empty[0], non_empty[-1]
    if last - first < 2:
        return None
    interior_zeros = [b for b in range(first + 1, last) if coverage[b] == 0]

    best = None
    best_run_length = -1
    best_centrality = float("-inf")
    for run in _contiguous_runs(interior_zeros):
        gutter_x = _center(run[len(run) // 2], t)
        split = _guarded_split(group, gutter_x, t)
        if split is None:
            continue
        centrality = -abs(gutter_x - 0.5)
        if (len(run) > best_run_length
                or (len(run) == best_run_length and centrality > best_centrality)):
            best_run_length = len(run)
            best_centrality = centrality
            best = split
    return best


def _central_split(group: list, t: Tunables):
    """The tier my first port omitted entirely: a two-column page whose gutter is
    bridged by a modest (non-header) title, cut at the lowest-coverage bin nearest
    the centre."""
    coverage = _coverage(group, t)
    peak = max(coverage) if coverage else 0
    band_lo = int(0.33 * t.bins)
    band_hi = int(0.67 * t.bins)
    band = list(range(band_lo, band_hi))
    if not band:
        return None
    min_coverage = min(coverage[b] for b in band)
    if not (peak >= 2 and min_coverage <= max(1, peak // 3)):
        return None
    # Swift uses `.min(by:)` over the equal-coverage bins, comparing distance to 0.5.
    candidates = [b for b in band if coverage[b] == min_coverage]
    gutter_bin = candidates[0]
    for b in candidates[1:]:
        if abs(_center(b, t) - 0.5) < abs(_center(gutter_bin, t) - 0.5):
            gutter_bin = b
    return _guarded_split(group, _center(gutter_bin, t), t)


def ranked_gutters(group: list, t: Tunables = DEFAULTS) -> list:
    votes = []
    for row in rows(group, t):
        ordered = sorted(row, key=lambda o: o.box.minX)
        for i in range(max(0, len(ordered) - 1)):
            gap = ordered[i + 1].box.minX - ordered[i].box.maxX
            if gap >= t.minGutterGap:
                votes.append(((ordered[i].box.maxX + ordered[i + 1].box.minX) / 2, gap))
    if len(votes) < t.minGutterVotes:
        return []

    used = [False] * len(votes)
    order = sorted(range(len(votes)), key=lambda i: -votes[i][1])  # seed from widest
    clusters = []
    for seed in order:
        if used[seed]:
            continue
        cx = votes[seed][0]
        members = [i for i in range(len(votes))
                   if not used[i] and abs(votes[i][0] - cx) <= t.gutterClusterTolerance]
        for m in members:
            used[m] = True
        if len(members) >= t.minGutterVotes:
            avg_x = sum(votes[m][0] for m in members) / len(members)
            avg_w = sum(votes[m][1] for m in members) / len(members)
            clusters.append((len(members), avg_w, avg_x))
    clusters.sort(key=lambda c: (-c[0], -c[1]))
    return [c[2] for c in clusters]


def best_vertical_split(group: list, t: Tunables = DEFAULTS):
    if len(group) < t.minGroupToSplit:
        return None
    split = _corridor_split(group, t)
    if split is None:
        split = _central_split(group, t)
    if split is not None:
        return split
    for gutter_x in ranked_gutters(group, t):
        split = _guarded_split(group, gutter_x, t)
        if split is not None:
            return split
    return None


# ------------------------------------------------------------------- assembly

def layout_blocks(observations: list, t: Tunables = DEFAULTS) -> list:
    h = best_horizontal_split(observations, t)
    if h is not None:
        return layout_blocks(h[0], t) + layout_blocks(h[1], t)
    v = best_vertical_split(observations, t)
    if v is not None:
        return layout_blocks(v[0], t) + layout_blocks(v[1], t)
    return [observations]


def _assemble_rows(observations: list, t: Tunables) -> list:
    if not observations:
        return []
    ordered = sorted(observations, key=lambda o: -o.box.midY)
    tolerance = _median_height(ordered) * t.rowToleranceFraction
    out, current, anchor = [], [], None
    for o in ordered:
        mid = o.box.midY
        if anchor is not None and abs(mid - anchor) > tolerance:
            out.append(current)
            current = [o]
            anchor = mid
        else:
            if anchor is None:
                anchor = mid
            current.append(o)
    if current:
        out.append(current)
    return [
        " ".join(_trimmed(o.text) for o in sorted(row, key=lambda o: o.box.minX))
        for row in out
    ]


def lines(observations: list, t: Tunables = DEFAULTS) -> list:
    """`LineAssembler.lines(from:)`."""
    cleaned = [o for o in observations if _trimmed(o.text)]
    if not cleaned:
        return []
    out = []
    for block in layout_blocks(cleaned, t):
        out.extend(_assemble_rows(block, t))
    return out


def tuned(**kwargs) -> Tunables:
    """`tuned(minSectionGap=0.02)` for experiments."""
    return replace(DEFAULTS, **kwargs)
