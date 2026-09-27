"""
Candidate fix, in the `experiment.py` style: `faithful.py` stays byte-identical to the
shipping Swift, this module overrides ONE decision so the effect is attributable.

THE FAILURE
    A single column of right-aligned prices produces the SAME geometry as a real
    two-column page: a blank vertical channel that (almost) every row respects. On a
    ragged tap list whose leader rules Vision does not read as text, the channel is
    ~0.2 of the page wide, so it clears `minColumnSpan`, and every row votes for it,
    so the votes-vs-crossers veto cannot see anything wrong either. The page is cut
    into "names" and "prices" and EVERY price is stranded from its drink.
    Confirmed on the device dump in `Fixtures/shortys_rotating.txt`: the page splits
    into 168 name observations and 41 price observations, and 22 priced beers reach the
    parser with no price at all.

THE RULE
    Geometry cannot distinguish "name | price" from "item | item" — on a
    right-aligned column they are the same shape. Content can: a menu COLUMN carries
    drink names; a price gutter carries prices, an ABV, a stray size. So a vertical
    cut is rejected when either side carries no independent content of its own.

    "Name-like" = an observation with at least two letters that is not a measurement
    (price, percent, oz/ml size, the word ABV). A side is a column only if it holds
    at least `minSideCount` name-like observations AND at least `minNameFraction` of
    its observations are name-like.

WHY IT IS A CLASS AND NOT A PATCH
    It is the definition of a text column, applied symmetrically inside
    `guardedSplit`, so it protects all three detector tiers at once (corridor,
    central, per-row voting) rather than the one that happened to fire here. It
    cannot help only one layout: a real column is majority names, so the veto never
    fires on one; a price gutter is ~0% names, so it always does.
"""

import faithful as f
from dataclasses import dataclass

MEASUREMENT_WORDS = {"abv", "alc", "vol", "oz", "ozs", "ml", "cl", "proof"}


def is_name_like(text: str) -> bool:
    """An observation that could be part of a drink NAME rather than a measurement."""
    core = text.strip(" $.,|:;-–—()/\"'*°%_·•\t\n")
    letters = [c for c in core if c.isalpha()]
    if len(letters) < 2:
        return False                      # "$7", "5", "%", "-", a leader rule
    if core.lower() in MEASUREMENT_WORDS:
        return False                      # "ABV", "oz", "ml"
    # "12oz", "16OZ.", "750ml" — digits glued to a unit.
    head = core.rstrip("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.")
    tail = core[len(head):].lower().rstrip(".")
    if head and tail in MEASUREMENT_WORDS and all(c.isdigit() or c == "." for c in head):
        return False
    return True


def name_like(group: list) -> list:
    return [o for o in group if is_name_like(o.text)]


@dataclass(frozen=True)
class Tunables(f.Tunables):
    #: Share of a side's observations that must be name-like for it to be a column.
    minNameFraction: float = 0.2          # 0.0 would be shipping behaviour (no veto)


def side_is_column(side: list, t) -> bool:
    """Fraction ONLY, deliberately.

    An absolute floor (`len(names) >= minSideCount`) reads as the more conservative
    rule and is not: deep in the recursion a legitimate leaf block can hold as few
    as one name-bearing observation out of three, and the floor vetoes it. Measured,
    that costs one of the eight real menus while the fraction alone costs none.
    """
    side = [o for o in side if o is not None]
    if not side:
        return False
    return len(name_like(side)) / len(side) >= getattr(t, "minNameFraction", 0.0)


# ---- the single overridden decision -------------------------------------------------

#: Captured once at import so `install()` can never wrap an already-wrapped function
#: (doing so recurses until the stack blows).
_BASELINE_GUARDED_SPLIT = f._guarded_split


def guarded_split(group: list, gutter_x: float, t):
    base = _BASELINE_GUARDED_SPLIT(group, gutter_x, t)
    if base is None:
        return None
    left, right = base
    if not side_is_column(left, t) or not side_is_column(right, t):
        return None
    return left, right


def install():
    """Swap the veto into the faithful port; returns a restore callable.

    Idempotent: re-installing does not stack, because `guarded_split` always calls
    the module-level baseline rather than whatever is currently bound.
    """
    f._guarded_split = guarded_split

    def restore():
        f._guarded_split = _BASELINE_GUARDED_SPLIT

    return restore
