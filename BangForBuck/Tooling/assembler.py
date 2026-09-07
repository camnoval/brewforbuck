"""
Validation harness for LineAssembler geometry changes.

Reads the BANGFORBUCK OCR EXPORT blocks out of a raw console log and re-runs line
assembly in Python so a threshold change can be checked against EVERY menu at once
before anything is ported to Swift.

The point of the exercise: the current Swift thresholds are fractions of the PAGE
(minSectionGap 0.03 of height, minGutterGap 0.045 and minColumnSpan 0.18 of width).
Across the real dumps the aspect ratio runs 0.386 to 0.751, so an identical physical
gap measures ~2x differently depending on the crop. Every threshold here is instead
expressed as a multiple of MEDIAN TEXT HEIGHT, which is a property of the type on the
page rather than of the photographer's framing.

Usage:
    python3 assembler.py /path/to/console.txt            # summary table
    python3 assembler.py /path/to/console.txt --menu 3   # one menu, full lines
    python3 assembler.py /path/to/console.txt --sweep    # threshold sensitivity
"""

import argparse
import re
import statistics
import sys
from dataclasses import dataclass


# ---------------------------------------------------------------- parsed input

@dataclass
class Obs:
    text: str
    mid_x: float
    mid_y: float
    w: float
    h: float

    @property
    def min_x(self) -> float:
        return self.mid_x - self.w / 2

    @property
    def max_x(self) -> float:
        return self.mid_x + self.w / 2


@dataclass
class Menu:
    px_w: int
    px_h: int
    obs: list
    swift_lines: list          # what the device's LineAssembler produced
    confidences: list          # per Vision line candidate

    @property
    def aspect(self) -> float:
        return self.px_w / self.px_h

    @property
    def mean_confidence(self) -> float:
        return statistics.fmean(self.confidences) if self.confidences else 0.0


# The dump prints `"text" @ midX,midY  WxH`. Text may contain escaped quotes.
OBS_RE = re.compile(r'^"(.*)" @ ([-\d.]+),([-\d.]+)\s+([-\d.]+)[x\u00d7]([-\d.]+)\s*$')
DIMS_RE = re.compile(r'^# image (\d+)x(\d+) px')
CONF_RE = re.compile(r'^\s{2}([01]\.\d\d)\s\s(.*)$')


def parse_log(path: str) -> list:
    """Split a console log into menus. Tolerant of interleaved OS noise."""
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        raw = fh.read()

    blocks = re.findall(
        r"===== BANGFORBUCK OCR EXPORT \(start\) =====(.*?)"
        r"===== BANGFORBUCK OCR EXPORT \(end\) =====",
        raw,
        re.S,
    )
    if not blocks:
        sys.exit("No OCR export blocks found. Is this the right log?")

    menus = []
    for block in blocks:
        px_w = px_h = 0
        obs, swift_lines, confidences = [], [], []
        section = None

        for line in block.splitlines():
            if (m := DIMS_RE.match(line)):
                px_w, px_h = int(m.group(1)), int(m.group(2))
                continue
            if line.startswith("# Vision line candidates"):
                section = "conf"; continue
            if "observations" in line and line.startswith("#"):
                section = "obs"; continue
            if line.startswith("# LineAssembler.lines output"):
                section = "lines"; continue
            if line.startswith("# MenuParser trace"):
                section = "trace"; continue

            if section == "conf" and (m := CONF_RE.match(line)):
                confidences.append(float(m.group(1)))
            elif section == "obs" and (m := OBS_RE.match(line.rstrip())):
                obs.append(Obs(
                    text=m.group(1).replace('\\"', '"').replace("\\\\", "\\"),
                    mid_x=float(m.group(2)), mid_y=float(m.group(3)),
                    w=float(m.group(4)), h=float(m.group(5)),
                ))
            elif section == "lines" and line.startswith("  ") and line.strip():
                swift_lines.append(line.strip())

        if obs:
            menus.append(Menu(px_w, px_h, obs, swift_lines, confidences))
    return menus


# ------------------------------------------------------- geometry, normalized

class Thresholds:
    """Two different kinds of threshold, and mixing them up is the bug.

    VERTICAL whitespace scales with the type: leading is proportional to font size,
    so a section break is best measured in MEDIAN TEXT HEIGHTS. This is what the
    Swift code gets wrong — `minSectionGap` is 0.03 of page height, so Rullo's real
    section gap (0.028 of the page, but ~0.9 text-heights) falls under the bar and
    the two-column blocks get to vote a page-wide gutter.

    HORIZONTAL column structure does NOT scale with the type: a column occupies
    roughly half the page whether the body text is 8pt or 24pt. These stay
    fractions of PAGE WIDTH, exactly as Swift has them. Converting them to
    text-heights (first attempt) made the gutter threshold font-size dependent and
    over-split the dense small-text menus: at unit=0.0119, 1.2 text-heights is 0.014
    of the width, a third of Swift's 0.045, so ordinary inter-word gaps qualified.
    """
    # --- vertical: multiples of median text height, measured BOX TO BOX ---
    row_tolerance = 0.5
    # Consecutive lines in a list have near-zero whitespace between boxes; a real
    # section break runs ~0.9-1.0. Narrow usable band, so --sweep decides.
    section_gap = 0.9

    # --- horizontal: fractions of page width (unchanged from Swift) ---
    gutter_gap = 0.045
    column_span = 0.18
    cluster_tol = 0.04
    gutter_votes = 3
    # For corridor DETECTION only: a box wider than this is a spanning header and is
    # dropped from the histogram, so a title across a gutter cannot hide it.
    header_width = 0.45


def median_height(obs: list) -> float:
    return statistics.median([o.h for o in obs]) if obs else 0.0


def band_rows(obs: list, t: Thresholds) -> list:
    """Group observations into rows by vertical proximity (Vision y increases upward)."""
    if not obs:
        return []
    unit = median_height(obs)
    tol = unit * t.row_tolerance
    rows, current, anchor = [], [], None
    for o in sorted(obs, key=lambda o: -o.mid_y):
        if anchor is not None and abs(o.mid_y - anchor) > tol:
            rows.append(current)
            current = []
            anchor = None
        if anchor is None:
            anchor = o.mid_y
        current.append(o)
    if current:
        rows.append(current)
    return rows


def split_bands(obs: list, t: Thresholds) -> list:
    """Peel the page into horizontal bands at section-sized vertical gaps.

    THE key change vs. Swift: the gap that qualifies is measured in text-heights,
    not as a fraction of page height. Rullo's section gap is 0.028 of the page
    (below the 0.03 Swift floor, so it was missed) but 2.3x median glyph height,
    which is unambiguous. A gap that reads as a section break to a human eye reads
    as one here regardless of how the photo was cropped.
    """
    rows = band_rows(obs, t)
    if len(rows) < 2:
        return [obs]
    unit = median_height(obs)
    bands, current = [], list(rows[0])
    for prev, row in zip(rows, rows[1:]):
        prev_bottom = min(o.mid_y - o.h / 2 for o in prev)
        row_top = max(o.mid_y + o.h / 2 for o in row)
        if (prev_bottom - row_top) >= unit * t.section_gap:
            bands.append(current)
            current = []
        current.extend(row)
    if current:
        bands.append(current)
    return bands


def gutter_candidates(group: list, t: Thresholds) -> list:
    """Per-row gap voting, ranked by agreement then width. Page-width units."""
    votes = []
    for row in band_rows(group, t):
        ordered = sorted(row, key=lambda o: o.min_x)
        for left, right in zip(ordered, ordered[1:]):
            gap = right.min_x - left.max_x
            if gap >= t.gutter_gap:
                votes.append(((left.max_x + right.min_x) / 2, gap))
    if not votes:
        return []

    clusters, used = [], [False] * len(votes)
    for i in sorted(range(len(votes)), key=lambda i: -votes[i][1]):
        if used[i]:
            continue
        cx = votes[i][0]
        members = [j for j in range(len(votes))
                   if not used[j] and abs(votes[j][0] - cx) <= t.cluster_tol]
        for j in members:
            used[j] = True
        if len(members) >= t.gutter_votes:
            clusters.append((
                len(members),
                statistics.fmean([votes[j][1] for j in members]),
                statistics.fmean([votes[j][0] for j in members]),
            ))
    clusters.sort(key=lambda c: (-c[0], -c[1]))
    return [c[2] for c in clusters]


def guarded_split(group: list, x: float, t: Thresholds):
    """Cut at x only if BOTH sides are a plausible column width (page-width units)."""
    left = [o for o in group if o.mid_x < x]
    right = [o for o in group if o.mid_x >= x]
    if not left or not right:
        return None
    for side in (left, right):
        span = max(o.max_x for o in side) - min(o.min_x for o in side)
        if span < t.column_span:
            return None
    return left, right


def coverage_split(group: list, t: Thresholds):
    """Cut at a truly-empty vertical corridor, preferring the most central one.

    This is Swift's PRIMARY mechanism and the one my first port omitted. Boxes wider
    than `header_width` are suppressed from the histogram used to FIND corridors, so
    a title or a full-width prose line spanning the gutter cannot fill it in - but
    every box is still used for the guard and the actual split. Without this,
    per-row gap voting alone slices spanning lines apart ("DRINK" | "MENU").
    """
    detect = [o for o in group if o.w <= t.header_width]
    if not detect:
        return None
    lo = min(o.min_x for o in detect)
    hi = max(o.max_x for o in detect)
    if hi - lo <= 0:
        return None

    bins = 400
    covered = [False] * bins

    def index(x: float) -> int:
        return min(bins - 1, max(0, int((x - lo) / (hi - lo) * bins)))

    for o in detect:
        for i in range(index(o.min_x), index(o.max_x) + 1):
            covered[i] = True

    best = None
    i = 0
    while i < bins:
        if covered[i]:
            i += 1
            continue
        j = i
        while j < bins and not covered[j]:
            j += 1
        # interior corridors only; a margin is not a gutter
        if i > 0 and j < bins:
            width = (j - i) / bins * (hi - lo)
            if width >= t.gutter_gap:
                x = lo + ((i + j) / 2) / bins * (hi - lo)
                centrality = -abs(x - 0.5)
                if best is None or centrality > best[0]:
                    best = (centrality, x)
        i = j

    if best is None:
        return None
    return guarded_split(group, best[1], t)


def columns(group: list, t: Thresholds, depth: int = 0) -> list:
    if depth >= 3 or len(group) < 4:
        return [group]
    # 1. coverage corridor (primary), then 2. per-row gap voting (fallback)
    split = coverage_split(group, t)
    if split is None:
        for x in gutter_candidates(group, t):
            if (candidate := guarded_split(group, x, t)):
                split = candidate
                break
    if split is None:
        return [group]
    out = []
    for side in split:
        out.extend(columns(side, t, depth + 1))
    return out


def assemble(menu: Menu, t: Thresholds) -> list:
    """Bands first, then columns within each band, then rows within each column.

    Band-before-column is the second half of the fix: a page that is mostly single
    column with one or two two-column blocks (Rullo's) currently lets those blocks
    vote a global gutter that slices every centred line in half. Isolating bands
    first confines each vote to the block that earned it.
    """
    lines = []
    for band in split_bands(menu.obs, t):
        for col in columns(band, t):
            for row in band_rows(col, t):
                ordered = sorted(row, key=lambda o: o.min_x)
                text = " ".join(o.text for o in ordered).strip()
                if text:
                    lines.append(text)
    return lines


# --------------------------------------------------------------------- report

def score(menu: Menu, t: Thresholds) -> dict:
    """Two-sided quality metric. The earlier `fragment_score` only counted short
    orphan lines, so it penalised OVER-splitting and rewarded FUSION - a chimera
    like "Bramble Gin & House Tonic" is long, so it scored as healthy. Fusion is
    the R1 bug the column detection exists to prevent, so it has to be measured.

      orphans  - output lines of <=2 words with no digits (over-split)
      fused    - output lines whose words contain an internal horizontal gap wide
                 enough to be a gutter (under-split); measured on the geometry, so
                 it needs no ground truth and no price tokens
    """
    orphans = fused = total = 0
    for band in split_bands(menu.obs, t):
        for col in columns(band, t):
            for row in band_rows(col, t):
                ordered = sorted(row, key=lambda o: o.min_x)
                text = " ".join(o.text for o in ordered).strip()
                if not text:
                    continue
                total += 1
                if len(text.split()) <= 2 and not any(c.isdigit() for c in text):
                    orphans += 1
                if any(b.min_x - a_.max_x >= t.gutter_gap
                       for a_, b in zip(ordered, ordered[1:])):
                    fused += 1
    if total == 0:
        return {"orphan": 0.0, "fused": 0.0, "bad": 0.0, "lines": 0}
    return {"orphan": orphans / total, "fused": fused / total,
            "bad": (orphans + fused) / total, "lines": total}


def fragment_score(lines: list) -> float:
    """Kept only to score the device's already-assembled text, where no geometry is
    available. Do not use it to choose thresholds - see `score`."""
    if not lines:
        return 0.0
    orphans = sum(
        1 for l in lines
        if len(l.split()) <= 2 and not any(ch.isdigit() for ch in l)
    )
    return orphans / len(lines)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--menu", type=int, help="1-based index; print full lines")
    ap.add_argument("--sweep", action="store_true", help="threshold sensitivity")
    args = ap.parse_args()

    menus = parse_log(args.log)
    t = Thresholds()

    if args.menu:
        m = menus[args.menu - 1]
        new = assemble(m, t)
        print(f"# menu {args.menu}: {m.px_w}x{m.px_h} aspect {m.aspect:.3f} "
              f"conf {m.mean_confidence:.2f}  unit {median_height(m.obs):.4f}")
        print(f"# swift {len(m.swift_lines)} lines -> python {len(new)} lines\n")
        for line in new:
            marker = " " if line in m.swift_lines else "*"
            print(f"{marker} {line}")
        return

    if args.sweep:
        # Only section_gap is being changed from Swift, so only section_gap is
        # swept. A value ships if it is a PLATEAU across every menu, not a peak on
        # one: a peak means it is fitted to this sample and menu seventeen breaks.
        print(f"{'section_gap':>12}  " + "  ".join(f"m{i}" for i in range(1, len(menus) + 1))
              + f"  {'mean':>6}")
        for sg in (0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.2, 1.5, 2.0):
            t.section_gap = sg
            fr = [fragment_score(assemble(m, t)) for m in menus]
            cells = "  ".join(f"{f:.2f}" for f in fr)
            print(f"{sg:>12}  {cells}  {statistics.fmean(fr):>6.3f}")
        print("\nbaseline (device):  "
              + "  ".join(f"{fragment_score(m.swift_lines):.2f}" for m in menus))
        return

    print(f"{'#':>2} {'pixels':>12} {'aspect':>7} {'conf':>5} "
          f"{'unit':>7} {'swift':>6} {'python':>7} {'frag→':>7}")
    for i, m in enumerate(menus, 1):
        new = assemble(m, t)
        print(f"{i:>2} {f'{m.px_w}x{m.px_h}':>12} {m.aspect:>7.3f} "
              f"{m.mean_confidence:>5.2f} {median_height(m.obs):>7.4f} "
              f"{len(m.swift_lines):>6} {len(new):>7} "
              f"{fragment_score(m.swift_lines):>.2f}→{fragment_score(new):.2f}")


if __name__ == "__main__":
    main()
