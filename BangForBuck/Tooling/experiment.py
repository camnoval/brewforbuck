"""
Candidate fix, tested against the faithful port.

`faithful.py` stays byte-identical to the shipping Swift. This module overrides ONE
decision so the effect is attributable, and reuses everything else from there.

THE RULE
    Per-row gap voting currently counts only the rows that AGREE with a candidate
    gutter. It ignores the rows that run straight through it. On a centred
    single-column menu with a couple of genuinely two-column blocks (Rullo's), those
    blocks supply enough votes to cut the WHOLE PAGE at x~0.516, and every centred
    line is sliced in half.

    A gutter is a blank channel that most rows RESPECT. So a voted gutter is
    rejected when more rows cross it than vote for it. Crossing means either a
    single box spans the candidate x, or the row has boxes on both sides with no
    qualifying gap at that x.

WHY THIS IS A CLASS AND NOT A RULLO'S PATCH
    It is the definition of a gutter, applied symmetrically. It cannot help only one
    layout: on a real two-column menu almost no row crosses the gutter, so the veto
    never fires; on a centred menu most rows cross it, so it always does. It also
    needs no new magic number - the comparison is votes vs crossers.
"""

import faithful
import faithful as f


def crossing_rows(group: list, x: float, t: faithful.Tunables) -> tuple:
    """(voters, crossers) for a candidate gutter at `x`."""
    voters = crossers = 0
    for row in f.rows(group, t):
        ordered = sorted(row, key=lambda o: o.box.minX)
        if len(ordered) < 2:
            # A lone box that straddles x is still evidence against the gutter.
            if ordered and ordered[0].box.minX < x < ordered[0].box.maxX:
                crossers += 1
            continue

        spans = any(o.box.minX < x < o.box.maxX for o in ordered)
        gap_here = any(
            a.box.maxX <= x <= b.box.minX and (b.box.minX - a.box.maxX) >= t.minGutterGap
            for a, b in zip(ordered, ordered[1:])
        )
        both_sides = (any(o.box.maxX <= x for o in ordered)
                      and any(o.box.minX >= x for o in ordered))

        if gap_here:
            voters += 1
        elif spans or both_sides:
            crossers += 1
    return voters, crossers


def _voting_rows(group: list, x: float, t: faithful.Tunables) -> list:
    """Per-row verdicts on a candidate gutter, top-to-bottom.

    True  = the row has a qualifying blank gap at x (votes for it)
    False = the row runs through x (evidence against)
    None  = the row is entirely on one side, so it says nothing either way
    """
    verdicts = []
    for row in f.rows(group, t):
        ordered = sorted(row, key=lambda o: o.box.minX)
        gap_here = any(
            a.box.maxX <= x <= b.box.minX and (b.box.minX - a.box.maxX) >= t.minGutterGap
            for a, b in zip(ordered, ordered[1:])
        )
        if gap_here:
            verdicts.append(True)
            continue
        spans = any(o.box.minX < x < o.box.maxX for o in ordered)
        both_sides = (any(o.box.maxX <= x for o in ordered)
                      and any(o.box.minX >= x for o in ordered))
        verdicts.append(False if (spans or both_sides) else None)
    return verdicts


def _longest_voting_run(verdicts: list) -> tuple:
    """Longest contiguous run of rows that vote yes, allowing `None` rows inside it
    (a short row sitting wholly in one column is not evidence against its own
    block). Returns (start, end_exclusive) or None."""
    best = None
    i = 0
    while i < len(verdicts):
        if verdicts[i] is not True:
            i += 1
            continue
        j = i
        last_yes = i
        while j < len(verdicts) and verdicts[j] is not False:
            if verdicts[j] is True:
                last_yes = j
            j += 1
        run = (i, last_yes + 1)
        if best is None or (run[1] - run[0]) > (best[1] - best[0]):
            best = run
        i = j
    return best


def _isolate_voting_band(group: list, t: faithful.Tunables):
    """Peel the contiguous rows that agree on a gutter into their own band.

    This is the refinement over a plain veto. A voted gutter is evidence about the
    rows that voted for it, not about the whole page. On Rullo's the wine grid and
    the Back-to-Basics block each vote; the centred cocktail lines cross. Peeling
    the voting run lets those blocks be column-split while leaving the centred lines
    whole - which a global cut (current behaviour) and a global veto (first attempt,
    which fused the BOURBON & RYE grid) both get wrong in opposite directions.
    """
    for x in f.ranked_gutters(group, t):
        verdicts = _voting_rows(group, x, t)
        if not any(v is False for v in verdicts):
            continue                      # nobody crosses: a plain split is correct
        run = _longest_voting_run(verdicts)
        if run is None:
            continue
        start, end = run
        if end - start < t.minGutterVotes:
            continue
        banded = f.rows(group, t)
        above = [o for r in banded[:start] for o in r]
        middle = [o for r in banded[start:end] for o in r]
        below = [o for r in banded[end:] for o in r]
        if not middle or (not above and not below):
            continue
        if f._guarded_split(middle, x, t) is None:
            continue                      # the run is not really two columns
        return above, middle, below
    return None


def best_vertical_split(group: list, t: faithful.Tunables):
    """`faithful.best_vertical_split` with the voting tier made row-aware."""
    if len(group) < t.minGroupToSplit:
        return None
    split = f._corridor_split(group, t)
    if split is None:
        split = f._central_split(group, t)
    if split is not None:
        return split
    for gutter_x in f.ranked_gutters(group, t):
        voters, crossers = crossing_rows(group, gutter_x, t)
        if crossers > voters:
            continue                      # most rows run through it: not a gutter
        candidate = f._guarded_split(group, gutter_x, t)
        if candidate is not None:
            return candidate
    return None


def layout_blocks(observations: list, t: faithful.Tunables) -> list:
    h = f.best_horizontal_split(observations, t)
    if h is not None:
        return layout_blocks(h[0], t) + layout_blocks(h[1], t)
    # Before giving up on a region, try isolating a two-column block inside it.
    band = _isolate_voting_band(observations, t)
    if band is not None:
        above, middle, below = band
        out = []
        if above:
            out += layout_blocks(above, t)
        out += layout_blocks(middle, t)
        if below:
            out += layout_blocks(below, t)
        return out
    v = best_vertical_split(observations, t)
    if v is not None:
        return layout_blocks(v[0], t) + layout_blocks(v[1], t)
    return [observations]


def lines(observations: list, t: faithful.Tunables = None) -> list:
    t = t or f.DEFAULTS
    cleaned = [o for o in observations if f._trimmed(o.text)]
    if not cleaned:
        return []
    out = []
    for block in layout_blocks(cleaned, t):
        out.extend(f._assemble_rows(block, t))
    return out
