"""
Faithful port of the `MenuParser` section-header decision (F).

Same discipline as `faithful.py`: this is a line-by-line port of the Swift, and it is
self-checking. Every OCR dump records the `MenuParser trace`, so the SECT lines in that
trace are ground truth for what the device decided. `validate()` replays each dump's
assembled lines through this port and requires the firing set to match exactly.

Until validate() reports 8/8, nothing measured here says anything about the device.

Ported from Core/Sources/CoreServices/MenuParser.swift:
  sectionHeader, isPureSectionLabel, isWineSubLabel, hasDotLeaderRun, headerKeywords,
  sectionWords, labelFillerWords, isMeasurementOrPrice, stripEdgePunctuation,
  detectABV, replaceSeparators, collapseDotRuns, leadingDigitString, repairPriceDigits,
  normalizedDollars, pureNumber, firstBarePriceToken, dollarValue.
"""

# ----------------------------------------------------------- ported constants

HEADER_KEYWORDS = [
    (["non-alcoholic", "non alcoholic", "mocktails", "booze free", "zero proof"], "nonAlcoholic"),
    (["frozen cocktails", "frozen margaritas", "frozen"], "frozenCocktail"),
    (["on tap", "on draught", "draught", "draft beers", "draft selections", "draft beer",
      "on draft", "drafts", "draft"], "draftBeer"),
    (["tall boy", "bottled beer", "bottles/cans", "bottles", "imports", "import",
      "domestic beer", "domestics", "domestic"], "bottledBeer"),
    (["hard seltzer", "canned cocktails", "seltzers", "seltzer", "cans"], "seltzer"),
    (["ciders", "cider"], "cider"),
    (["shots"], "shot"),
    (["martinis", "old-fashioneds", "old fashioneds"], "martini"),
    (["sangria"], "sangria"),
    (["by the glass", "sparkling", "reds", "whites", "rosé", "rosados", "wine"], "wineGlass"),
    (["specialty cocktails", "original cocktails", "signature cocktails", "cocktails",
      "elixirs", "back to basics", "hand-crafted", "hand crafted", "specialty",
      "signature"], "cocktail"),
]

SECTION_WORDS = {
    "beer", "beers", "wine", "wines", "drinks", "drink", "menu", "shots", "shot",
    "cocktail", "cocktails", "food", "drafts", "draft", "bottles", "bottle", "cans", "can",
    "cider", "ciders", "seltzer", "seltzers", "domestic", "domestics", "import", "imports",
    "specialty", "signature", "sangria", "martinis", "elixirs", "reds", "whites", "sparkling",
    "mocktails", "spirits", "beverages", "selections", "bubbles", "rosé", "rose", "rosados",
}
LABEL_FILLER = {"each", "ea", "per", "and", "the", "our", "list", "of"}
WINE_SUB_LABELS = {"whites", "reds", "rosé", "rose", "bubbles", "sparkling"}

PUNCT = set(".,|:;-–—()/")


# ------------------------------------------------------------ ported helpers

def strip_edge_punct(s):
    chars = list(s)
    while chars and chars[0] in PUNCT:
        chars.pop(0)
    while chars and chars[-1] in PUNCT:
        chars.pop()
    return "".join(chars)


def pure_number(token):
    t = token
    if t.startswith("$"):
        t = t[1:]
    elif t.startswith("S") or t.startswith("s"):
        t = t[1:]
    if not t:
        return None
    for c in t:
        if not (c.isdigit() or c == "."):
            return None
    try:
        return float(t)
    except ValueError:
        return None


def is_measurement_or_price(w):
    if w in ("|", "-", "/", "&", "$"):
        return True
    if w.startswith("+"):
        return True
    if pure_number(w) is not None:
        return True
    if w.endswith("oz") or w.endswith("oz.") or w.endswith("%") or w.endswith("ml"):
        return True
    return w == "abv"


def replace_separators(s):
    return "".join(" " if c in "•·…|/" else c for c in s)


def collapse_dot_runs(s):
    chars, out, i = list(s), [], 0
    while i < len(chars):
        if chars[i] == ".":
            j = i
            while j < len(chars) and chars[j] == ".":
                j += 1
            out.append(" " if j - i >= 2 else ".")
            i = j
        else:
            out.append(chars[i])
            i += 1
    return "".join(out)


def leading_digit_string(s):
    out = ""
    for c in s:
        if c.isdigit() or c == ".":
            out += c
        else:
            break
    return out


def repair_price_digits(s):
    return "".join({"s": "5", "S": "5", "o": "0", "O": "0"}.get(c, c) for c in s)


def normalized_dollars(digits):
    if not digits:
        return None
    if "." in digits:
        try:
            return float(digits)
        except ValueError:
            return None
    if len(digits) >= 4:
        cut = len(digits) - 2
        try:
            return float(digits[:cut]) + float(digits[cut:]) / 100
        except ValueError:
            return None
    try:
        return float(digits)
    except ValueError:
        return None


def dollar_value(token):
    if not token or token[0] not in "$Ss":
        return None
    digits = leading_digit_string(repair_price_digits(token[1:]))
    return normalized_dollars(digits) if digits else None


def first_bare_price_token(line):
    for i, t in enumerate(line.split(" ")):
        core = strip_edge_punct(t)
        if len(core) >= 4 and all(c.isdigit() for c in core):
            return i, core
    return None


def detect_abv(raw):
    chars = list(raw)
    for i, c in enumerate(chars):
        if c != "%":
            continue
        j, digits = i - 1, ""
        while j >= 0 and (chars[j].isdigit() or chars[j] == "."):
            digits = chars[j] + digits
            j -= 1
        try:
            v = float(digits)
        except ValueError:
            continue
        if 0 < v <= 100:
            return v
    return None


def has_dot_leader_run(s):
    return any(s[i] == "." and s[i - 1] == "." for i in range(1, len(s)))


def parsed_price(raw):
    """`parseItem(...).price` only — the part sectionHeader consults."""
    line = collapse_dot_runs(replace_separators(raw))
    if "$" in line:
        idx = line.index("$")
        after = line[idx + 1:]
        return normalized_dollars(leading_digit_string(repair_price_digits(after)))
    bare = first_bare_price_token(line)
    if bare:
        return normalized_dollars(bare[1])
    tokens = line.split(" ")
    if tokens:
        return pure_number(tokens[-1])
    return None


def is_pure_section_label(line):
    saw = False
    for token in line.split(" "):
        w = strip_edge_punct(token).lower()
        if not w:
            continue
        if is_measurement_or_price(w) or w in LABEL_FILLER:
            continue
        if w in SECTION_WORDS:
            saw = True
            continue
        return False
    return saw


def is_wine_sub_label(line):
    saw = False
    for token in line.split(" "):
        w = strip_edge_punct(token).lower()
        if not w:
            continue
        if w in WINE_SUB_LABELS:
            saw = True
            continue
        return False
    return saw


# ----------------------------------------------------- the decision under test

def section_header(line, gate=None):
    """(category, headerPrice, matchedKeyword) or None. `gate` = the candidate F rule."""
    lower = line.lower()
    price = parsed_price(line)
    has_pipe = "|" in line
    has_dots = has_dot_leader_run(line)
    if price is not None and not has_pipe and not has_dots and not is_pure_section_label(line):
        return None
    for keywords, cat in HEADER_KEYWORDS:
        hit = next((k for k in keywords if k in lower), None)
        if hit is None:
            continue
        if gate is not None and not gate(line, hit):
            return None       # matched a keyword but doesn't read as a header
        return cat, price, hit
    return None


# ============================================================ D: priced labels
# Token-exact section vocabulary. A wine colour is far too common inside a beer
# name ("Fire Red Ale", "White Claw", "Allagash White") to be matched as a
# substring, which is why red/white live here and NOT in HEADER_KEYWORDS.
# Same group order as HEADER_KEYWORDS so priority is unchanged.

LABEL_CATEGORIES = [
    (["non-alcoholic", "mocktails"], "nonAlcoholic"),
    (["frozen"], "frozenCocktail"),
    (["draught", "drafts", "draft"], "draftBeer"),
    (["bottles", "imports", "import", "domestics", "domestic"], "bottledBeer"),
    (["seltzers", "seltzer", "cans"], "seltzer"),
    (["ciders", "cider"], "cider"),
    (["shots"], "shot"),
    (["martinis"], "martini"),
    (["sangria"], "sangria"),
    (["sparkling", "bubbles", "reds", "red", "whites", "white", "rosé", "rose",
      "rosados", "wines", "wine"], "wineGlass"),
    (["cocktails", "cocktail", "elixirs", "specialty", "signature"], "cocktail"),
]

# Vessel words. Allowed as filler in a label ("WHITES - $9 GLASS / $82 BOTTLE")
# but never category-bearing on their own, so "Bottle 25" and "Glass 12 Bottle 40"
# stay size/price rows rather than becoming a Bottled Beer section priced at $25.
SIZE_ONLY_WORDS = {
    "glass", "gloss", "bottle", "pitcher", "pitchor", "carafe", "flight", "pint",
    "mug", "can", "draft", "double", "single", "neat", "rocks", "shot",
}

SECTION_WORDS_D = SECTION_WORDS | {"red", "white"}
WINE_SUB_LABELS_D = WINE_SUB_LABELS | {"red", "white"}


def is_pure_section_label_d(line):
    """As shipped, plus: a vessel word is filler, not a disqualifying real word."""
    saw = False
    for token in replace_separators(line).split(" "):
        w = strip_edge_punct(token).lower()
        if not w:
            continue
        if is_measurement_or_price(w) or w in LABEL_FILLER:
            continue
        if w in SECTION_WORDS_D:
            saw = True
            continue
        if w in SIZE_ONLY_WORDS:
            continue
        return False
    return saw


def pure_label_category(line):
    tokens = {strip_edge_punct(t).lower()
              for t in replace_separators(line).split(" ")}
    for words, cat in LABEL_CATEGORIES:
        for w in words:
            if w in tokens:
                return cat
    return None


def section_header_d(line, gate=None):
    """Shipping decision + the D pure-label path."""
    lower = line.lower()
    price = parsed_price(line)
    has_pipe = "|" in line
    has_dots = has_dot_leader_run(line)
    pure = is_pure_section_label_d(line)

    # A label made only of section words, vessels, prices and filler is a header
    # whatever price it carries, and its own tokens name the category.
    if pure:
        cat = pure_label_category(line)
        if cat is not None:
            return cat, price, "<pure-label>"

    if price is not None and not has_pipe and not has_dots and not pure:
        return None
    for keywords, cat in HEADER_KEYWORDS:
        hit = next((k for k in keywords if k in lower), None)
        if hit is None:
            continue
        if gate is not None and not gate(line, hit):
            return None
        return cat, price, hit
    return None
