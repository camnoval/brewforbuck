#!/usr/bin/env python3
"""
Take a raw Xcode console log, pull the BangForBuck blocks out of it, save each scan as a
reusable fixture, and run the assembler bench over it.

    python3 ingest_dump.py ~/Desktop/rescan.txt
    python3 ingest_dump.py ~/Desktop/rescan.txt --name shortys

Paste or save the WHOLE console — RevenueCat noise and all. This finds:

    ===== BANGFORBUCK OCR EXPORT (start) ... (end) =====     one per scanned page
    ===== BANGFORBUCK RANKING (start) ... (end) =====        what the person saw, per scan
    ===== BANGFORBUCK READ SELECTION =====                   which reading won, and by how much

Each OCR block becomes `Fixtures/<name>_<n>.txt`, which `verify.py` and `faithful.py` read
directly, so every scan you take is permanently replayable without the phone.

Then, for each page, it reports the shipping assembler against the two candidate fixes:

    price-gutter veto   experiment_pricegutter   a side with no names is not a column
    baseline chaining   experiment_baseline      follow a row's baseline instead of pinning it

The number to watch is COMPLETE ROWS: lines carrying a name, an ABV and a price at once. That
is the thing the ranking needs and the thing that was 0 of 22 on the tap list.
"""

import argparse
import os
import re
import sys

import faithful as f
import verify

try:
    import experiment_pricegutter as gutter
except ImportError:
    gutter = None
try:
    import experiment_baseline as baseline
except ImportError:
    baseline = None

OCR_BLOCK = re.compile(
    r"===== BANGFORBUCK OCR EXPORT \(start\) =====.*?===== BANGFORBUCK OCR EXPORT \(end\) =====",
    re.S)
RANKING_BLOCK = re.compile(
    r"===== BANGFORBUCK RANKING \(start\) =====(.*?)===== BANGFORBUCK RANKING \(end\) =====", re.S)
SELECTION_BLOCK = re.compile(
    r"===== BANGFORBUCK READ SELECTION =====\n((?:[#\s].*\n)+)")
ALTERNATES = re.compile(r"^# Alternative readings.*?\n((?:  .*\n)+)", re.M)


def complete_rows(lines):
    """Lines that carry a name, a printed ABV and a price together."""
    return [l for l in lines
            if "$" in l and "ABV" in l.upper() and any(c.isalpha() for c in l)]


def priced_rows(lines):
    return [l for l in lines if "$" in l and any(c.isalpha() for c in l)]


def bench(obs, label):
    tunables = gutter.Tunables() if gutter else f.DEFAULTS
    rows = []

    def run(name):
        ls = f.lines(obs, tunables)
        rows.append((name, len(ls), len(priced_rows(ls)), len(complete_rows(ls))))
        return ls

    run("shipping")
    if gutter:
        restore = gutter.install(); run("+ gutter veto"); restore()
    if baseline:
        restore = baseline.install(); run("+ chaining"); restore()
    if gutter and baseline:
        r1 = gutter.install(); r2 = baseline.install()
        best = run("+ both")
        r2(); r1()
    else:
        best = None

    print("  %-16s %6s %8s %9s" % ("variant", "lines", "priced", "complete"))
    for name, n, p, c in rows:
        print("  %-16s %6d %8d %9d" % (name, n, p, c))
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log", help="raw console log saved to a file")
    ap.add_argument("--name", default="rescan", help="fixture filename stem")
    ap.add_argument("--dir", default="Fixtures", help="where to write fixtures")
    ap.add_argument("--show", type=int, default=6, help="assembled lines to print per page")
    args = ap.parse_args()

    raw = open(args.log, encoding="utf-8", errors="replace").read()
    blocks = OCR_BLOCK.findall(raw)
    if not blocks:
        print("No BANGFORBUCK OCR EXPORT block found. Is this the right log, and is the build DEBUG?")
        return 1

    os.makedirs(args.dir, exist_ok=True)
    print("%d scan(s) found.\n" % len(blocks))

    for index, block in enumerate(blocks, 1):
        path = os.path.join(args.dir, "%s_%d.txt" % (args.name, index))
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(block + "\n")

        menus = verify.parse(path)
        if not menus or not menus[0]["obs"]:
            print("=== scan %d -> %s   (no observations parsed)" % (index, path))
            continue
        obs = menus[0]["obs"]

        dims = re.search(r"# image (\d+)x(\d+) px", block)
        size = "%sx%s px" % dims.groups() if dims else "size unknown"
        correction = re.search(r"# languageCorrection = (\w+)", block)
        print("=== scan %d -> %s" % (index, path))
        print("  %s, %d observations%s" % (
            size, len(obs),
            ", languageCorrection=%s" % correction.group(1) if correction else ""))
        if dims and int(dims.group(1)) < 1200:
            print("  ⚠️  under 1200 px wide — expect glyph errors. Was this a camera scan or a saved copy?")

        best = bench(obs, path)
        if best:
            print("  best variant, first %d lines:" % args.show)
            for line in best[:args.show]:
                print("     ", line)
        print()

    for match in ALTERNATES.finditer(raw):
        rows = [r for r in match.group(1).splitlines() if "[2]" in r]
        if rows:
            print("=== Vision disagreed with itself on %d line(s) containing digits:" % len(rows))
            for row in rows[:20]:
                print("  ", row.strip())
            print("  (if a correct price is sitting in [2] or [3], candidate selection is worth doing)\n")
            break

    rankings = RANKING_BLOCK.findall(raw)
    for index, ranking in enumerate(rankings, 1):
        head = [l for l in ranking.strip().splitlines() if l.strip().startswith("#")]
        print("=== ranking %d (what the person saw):" % index)
        for line in head:
            print("  ", line.strip())
        print()

    for match in SELECTION_BLOCK.finditer(raw):
        print("=== read selection:")
        for line in match.group(1).strip().splitlines():
            print("  ", line.strip())
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
