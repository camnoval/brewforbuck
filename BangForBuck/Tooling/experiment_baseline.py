"""
Candidate fix #2: group a row by FOLLOWING ITS BASELINE, not by an anchored y band.

THE FAILURE (real coordinates, Fixtures/shortys_rotating.txt)
    `assembleRows` fixes `anchorMidY` to the row's topmost box and requires every later
    box to sit within `0.5 × medianHeight` of THAT anchor — the comment says it
    "prevents cumulative drift". On a menu photographed flat that is fine. On a paper
    strip held in the hand it is fatal: the page curls, so one printed row's baseline
    genuinely moves as you read across it. Row 1 of the tap list runs
    y = 0.8304 → 0.8172, a drift of 0.0132 against a tolerance of 0.0088, so the row
    is cut in half and `1 - IC LIGHT` / `4.2% ABV` become two lines. The ABV is
    separated from the beer before the parser ever sees it.

    The curl is not a rotation and cannot be fixed by deskewing: rows 1–8 slope DOWN to
    the right (up to -0.096 dy/dx), rows 13 and 22–27 are dead flat, and row 28 slopes
    UP (+0.023). A single global angle describes none of it.

THE RULE
    Adjacent words in one printed row are always close, however far the row's two ends
    have drifted apart. Measured on that page, the biggest step between neighbouring
    words inside a row is 0.0044 — half the tolerance — while the gap to the row above
    or below is ~0.032. So chain each word to its left-hand neighbour instead of to a
    fixed anchor, and let the row bend as much as the paper does.

    Tolerance stays `rowToleranceFraction × medianHeight`; only what it is measured
    FROM changes. Nothing new to tune.

WHY IT DOESN'T JUST RE-OPEN THE DRIFT BUG
    The original anchor exists to stop a chain walking down a column of prices and
    swallowing the whole page. That is still prevented, by x: chaining only ever
    appends a box to the row whose current rightmost member is nearest in y, and each
    box joins exactly one row. A column of stacked prices has no left neighbour at
    a similar y to chain to, so it cannot absorb anything.
"""

import faithful as f

_BASELINE_ASSEMBLE = f._assemble_rows


def chained_rows(observations: list, tolerance: float) -> list:
    """Rows as lists of observations, ordered top-to-bottom, each ordered left-to-right."""
    ordered = sorted(observations, key=lambda o: o.box.minX)
    rows: list[list] = []
    for obs in ordered:
        best, best_dy = None, None
        for row in rows:
            dy = min(abs(obs.box.midY - m.box.midY) for m in row)
            if dy <= tolerance and (best_dy is None or dy < best_dy):
                best, best_dy = row, dy
        if best is None:
            rows.append([obs])
        else:
            best.append(obs)
    rows.sort(key=lambda r: -max(o.box.midY for o in r))
    return rows


def assemble_rows(observations: list, t) -> list:
    """Mirrors `_assemble_rows` in the port, which (like the port generally) omits
    `splitAtPriceToNameBoundaries`. That step did not fire anywhere on this page, so it
    does not affect the measurement — but the Swift port of this change must keep it."""
    if not observations:
        return []
    tolerance = f._median_height(observations) * t.rowToleranceFraction
    return [
        " ".join(f._trimmed(o.text) for o in row)
        for row in chained_rows(observations, tolerance)
    ]


def install():
    f._assemble_rows = assemble_rows
    return lambda: setattr(f, "_assemble_rows", _BASELINE_ASSEMBLE)
