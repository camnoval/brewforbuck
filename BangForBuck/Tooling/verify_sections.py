"""
Self-check + measurement for the section-header gate (F).

    python3 verify_sections.py Fixtures/console.txt            # must print 8/8 exact
    python3 verify_sections.py Fixtures/console.txt --measure   # effect of the gate

The dumps record the `MenuParser trace`, so the SECT lines are ground truth for what
the device decided. The port must reproduce that firing set exactly before any
candidate rule measured here means anything.
"""

import argparse
import re
import sys

import sections

START = "===== BANGFORBUCK OCR EXPORT (start) ====="
END = "===== BANGFORBUCK OCR EXPORT (end) ====="


def dumps(path):
    raw = open(path, "r", encoding="utf-8", errors="replace").read()
    blocks = re.findall(re.escape(START) + r"(.*?)" + re.escape(END), raw, re.S)
    if not blocks:
        sys.exit("no OCR export blocks found")

    out = []
    for block in blocks:
        rows = [l.rstrip("\r") for l in block.splitlines()]
        lines, trace, mode = [], [], None
        for row in rows:
            s = row.strip()
            if s.startswith("# LineAssembler.lines output"):
                mode = "lines"
                continue
            if s.startswith("# MenuParser trace"):
                mode = "trace"
                continue
            if s.startswith("#") or s.startswith("====="):
                mode = None
                continue
            if not s or mode is None:
                continue
            (lines if mode == "lines" else trace).append(s)
        out.append((lines, [t for t in trace if t.startswith("SECT")]))
    return out


def fired(lines, gate=None):
    """The lines this port treats as section headers, in order."""
    return [l for l in lines if sections.section_header(l, gate) is not None]


def validate(path):
    ok = 0
    for n, (lines, sect) in enumerate(dumps(path), 1):
        # The trace prints `SECT  cat=... headerPrice=... | <line>`
        device = [t.split("|", 1)[1].strip() for t in sect]
        port = fired(lines)
        if device == port:
            print(f"menu {n}  {len(device):3d} headers  MATCH")
            ok += 1
        else:
            print(f"menu {n}  device {len(device)}  port {len(port)}  MISMATCH")
            for d in device:
                if d not in port:
                    print(f"    device only: {d!r}")
            for p in port:
                if p not in device:
                    print(f"    port only:   {p!r}")
    print(f"\n{ok}/{len(dumps(path))} exact")
    return ok == len(dumps(path))


# --------------------------------------------------------- the candidate gate

MAX_MODIFIERS = 2


def gate(line, keyword):
    """
    A section header is a *label*, not a sentence. Reject a keyword match that reads
    like prose or like an item:

      - a comma or a bullet means a list or a sentence, never a label;
      - a printed ABV belongs to an item, never to a header;
      - a label carries at most a couple of modifiers around its head noun
        ("CRAFT BOTTLES", "TALL BOY CANS", "house brews on tap"), where words of the
        matched keyword and of the section vocabulary are not modifiers.
    """
    if "," in line or "•" in line or "·" in line:
        return False
    if sections.detect_abv(line) is not None:
        return False
    kw = set(keyword.split(" "))
    modifiers = 0
    for token in sections.replace_separators(line).split(" "):
        w = sections.strip_edge_punct(token).lower()
        if not w or not any(c.isalpha() for c in w):
            continue
        if w in sections.LABEL_FILLER or sections.is_measurement_or_price(w):
            continue
        if w in sections.SECTION_WORDS or w in kw:
            continue
        # "CIDER/CIDRE" is one token; guarded to 4+ chars so "on" (from "on tap") cannot
        # match inside an unrelated name.
        if any(len(k) >= 4 and k in w for k in kw):
            continue
        modifiers += 1
    return modifiers <= MAX_MODIFIERS


def measure(path):
    kept = dropped = 0
    for n, (lines, _) in enumerate(dumps(path), 1):
        before = fired(lines)
        after = fired(lines, gate)
        lost = [l for l in before if l not in after]
        print(f"\n===== menu {n}: {len(before)} -> {len(after)} headers =====")
        for l in before:
            mark = "  drop" if l in lost else "  keep"
            print(f"{mark}  {l}")
        kept += len(after)
        dropped += len(lost)
    print(f"\ntotal kept {kept}, dropped {dropped}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--measure", action="store_true")
    ap.add_argument("--lower", action="store_true", help="lowercase every line first")
    a = ap.parse_args()
    if a.lower:
        _orig = dumps
        dumps = lambda p: [([l.lower() for l in ls], s) for ls, s in _orig(p)]  # noqa: E731
    if a.measure:
        measure(a.path)
    else:
        sys.exit(0 if validate(a.path) else 1)


def measure_d(path):
    """D: which lines newly become headers, and does any existing verdict change?"""
    changed, new = [], []
    for n, (lines, _) in enumerate(dumps(path), 1):
        for l in lines:
            a = sections.section_header(l, gate)
            b = sections.section_header_d(l, gate)
            ca, cb = (a[0] if a else None), (b[0] if b else None)
            if ca == cb:
                continue
            (new if ca is None else changed).append((n, l, ca, cb))
    print("=== existing verdict changed (must be empty) ===")
    for n, l, ca, cb in changed:
        print(f"  menu {n}: {l!r}  {ca} -> {cb}")
    print(f"  ({len(changed)})\n=== newly a header ===")
    for n, l, _, cb in new:
        print(f"  menu {n}: {l!r} -> {cb}")
    print(f"  ({len(new)})")
    return not changed
