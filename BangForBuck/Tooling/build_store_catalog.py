#
//  build_store_catalog.py
//  BangForBuck
//
//  Created by Noval, Cameron on 9/5/26.
//


#!/usr/bin/env python3
"""build_store_catalog - build AppTarget/Resources/store_catalog.json for the store calculator.

Two sources, because neither covers the shelf on its own:

  * **PLCB wholesale catalogs** (.xlsx, public) cover every wine, spirit, and ready-to-drink
    cocktail sold in Pennsylvania, with a bottle size and a **UPC**. Pennsylvania doesn't sell beer
    through these stores, so there's no beer here.
  * **Open Food Facts** (nightly JSONL dump, ODbL) covers beer and a lot else, barcode-keyed, with
    an alcohol percentage on most beers and wines.

What lands in the app is name, category, ABV, container size, pack count, and UPC. Deliberately
NOT price: shelf prices are local, change weekly, and the whole point of the app is that the shopper
reads the real tag. A stale bundled price would be the one dishonest number in the product (§10).

    python3 Tooling/inspect_store_catalog.py plcb          # ALWAYS run this first (§5)
    python3 Tooling/build_store_catalog.py --plcb
    python3 Tooling/build_store_catalog.py --plcb --off ~/Downloads/openfoodfacts-products.jsonl.gz
    python3 Tooling/build_store_catalog.py --plcb --dry-run    # report the column mapping, write nothing

Then add the generated file to the Xcode target so it ships in the bundle; `BundledStoreCatalog`
picks it up automatically and falls back to the curated 655-brand list if it's absent.

LICENSING, read before shipping: Open Food Facts data is ODbL, which requires attribution and has
share-alike obligations on the database. The PLCB catalogs are public Commonwealth records. Neither
is legal advice; if you'd rather not carry the ODbL obligation, build with `--plcb` only and the
app ships wine and spirits coverage with no OFF data in it.

Requires: pandas, openpyxl, requests  (pip3 install pandas openpyxl requests)
"""

import argparse
import gzip
import io
import json
import os
import re
import sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEFAULT_OUT = os.path.join(ROOT, "AppTarget", "Resources", "store_catalog.json")

PLCB_CATALOGS = {
    "wine": ("https://www.apps.lcb.pa.gov/webapp/reports/Wholesale_Wines_Catalog_Full.xlsx", "wineGlass"),
    "spirits": ("https://www.apps.lcb.pa.gov/webapp/reports/Wholesale_Spirits_Catalog_Full.xlsx", "shot"),
    "rtdc": ("https://www.apps.lcb.pa.gov/webapp/reports/Wholesale_RTDC_Catalog_Full.xlsx", "cocktail"),
}

# Header names are matched loosely because the PLCB has renamed these columns before. Each entry is
# a list of substrings tried in order against the lowercased header; --dry-run prints what matched.
COLUMN_CANDIDATES = {
    "name": ["product description", "description", "brand name", "item description", "product name"],
    "size": ["retail size", "size description", "bottle size", "size", "unit of measure"],
    "upc": ["upc"],
    "proof": ["proof"],
    "abv": ["alcohol", "abv"],
    # Mapped for diagnostics only. "Units per case" is a wholesale case quantity, NOT what a
    # shopper carries out (nobody buys 12 bottles of one wine), so load_plcb leaves units unset and
    # lets PackageDefaults infer the retail pack from the name and category instead.
    "units": ["units per case", "bottles per case", "pack"],
}

SIZE_PATTERN = re.compile(r"(\d+(?:\.\d+)?)\s*(ml|mls|l|lt|ltr|liter|litre|oz|ounce)\b", re.IGNORECASE)


def normalize_upc(raw):
    """Digits only, and pad back the leading zeros the PLCB export strips (per their own docs)."""
    if raw is None:
        return None
    digits = re.sub(r"\D", "", str(raw))
    if not digits:
        return None
    if len(digits) < 12:
        digits = digits.zfill(12)
    return digits


def milliliters_from_size(text):
    """'750 ML' -> 750.0, '1.75 L' -> 1750.0, '12 OZ' -> 354.9. None when unreadable."""
    if not text:
        return None
    match = SIZE_PATTERN.search(str(text))
    if not match:
        return None
    value, unit = float(match.group(1)), match.group(2).lower()
    if value <= 0:
        return None
    if unit.startswith("ml"):
        return value
    if unit in ("l", "lt", "ltr", "liter", "litre"):
        return value * 1000
    return value * 29.5735


def abv_from_row(row, columns):
    """Prefer a stated ABV; otherwise halve the proof. Returns None when neither is present."""
    if columns.get("abv"):
        raw = row.get(columns["abv"])
        try:
            value = float(re.sub(r"[^\d.]", "", str(raw)))
            if 0 < value <= 100:
                return round(value, 2)
        except (TypeError, ValueError):
            pass
    if columns.get("proof"):
        raw = row.get(columns["proof"])
        try:
            proof = float(re.sub(r"[^\d.]", "", str(raw)))
            if 0 < proof <= 200:
                return round(proof / 2, 2)
        except (TypeError, ValueError):
            pass
    return None


def map_columns(headers):
    """Fuzzy-match the headers we need. Returns (mapping, unmatched_keys)."""
    lowered = {str(h).strip().lower(): h for h in headers}
    mapping, missing = {}, []
    for key, candidates in COLUMN_CANDIDATES.items():
        found = None
        for candidate in candidates:
            for low, original in lowered.items():
                if candidate in low:
                    found = original
                    break
            if found:
                break
        if found:
            mapping[key] = found
        else:
            missing.append(key)
    return mapping, missing


def load_plcb(dry_run=False):
    import pandas as pd
    import requests

    products = []
    for label, (url, category) in PLCB_CATALOGS.items():
        print(f"[plcb] {label}: downloading")
        response = requests.get(url, timeout=180)
        response.raise_for_status()
        # dtype=str throughout: a UPC read as a float becomes 1.23e+13 and is destroyed.
        frame = pd.read_excel(io.BytesIO(response.content), dtype=str)

        columns, missing = map_columns(frame.columns)
        print(f"[plcb] {label}: {len(frame)} rows; mapped {columns}")
        if missing:
            print(f"[plcb] {label}: NOT MAPPED {missing}"
                  f" (run inspect_store_catalog.py and add the real header to COLUMN_CANDIDATES)")
        if "name" not in columns:
            print(f"[plcb] {label}: skipped, no usable product-name column")
            continue
        if dry_run:
            continue

        for row in frame.to_dict(orient="records"):
            name = row.get(columns["name"])
            if not name or str(name).strip().lower() == "nan":
                continue
            size_text = row.get(columns["size"]) if columns.get("size") else None
            products.append({
                "name": " ".join(str(name).split()),
                "category": category,
                "abv": abv_from_row(row, columns),
                "ml": milliliters_from_size(size_text),
                "units": None,
                "upc": normalize_upc(row.get(columns["upc"])) if columns.get("upc") else None,
            })
    return products


def off_category(tags):
    """Map Open Food Facts category tags onto our BeverageCategory raw values."""
    joined = " ".join(tags)
    if "beer" in joined or "ale" in joined:
        return "bottledBeer"
    if "cider" in joined:
        return "cider"
    if "hard-seltzer" in joined or "seltzer" in joined:
        return "seltzer"
    if "wine" in joined or "champagne" in joined or "sparkling" in joined:
        return "wineGlass"
    if "spirit" in joined or "whisky" in joined or "whiskey" in joined or "vodka" in joined:
        return "shot"
    if "alcoholic" in joined:
        return "unknown"
    return None


def load_off(path, countries=("united-states",)):
    """Beer and anything else alcoholic from an OFF dump, filtered to the given countries."""
    opener = gzip.open if path.endswith(".gz") else open
    products, seen, scanned = [], set(), 0

    with opener(path, "rt", encoding="utf-8") as handle:
        for line in handle:
            scanned += 1
            if scanned % 500_000 == 0:
                print(f"[off] scanned {scanned:,} lines, kept {len(products):,}")
            try:
                product = json.loads(line)
            except json.JSONDecodeError:
                continue

            tags = product.get("categories_tags") or []
            category = off_category(tags)
            if not category:
                continue

            if countries:
                product_countries = product.get("countries_tags") or []
                if not any(f"en:{c}" in product_countries or c in product_countries
                           for c in countries):
                    continue

            name = (product.get("product_name") or "").strip()
            if not name:
                continue

            abv = product.get("alcohol_value")
            if abv is None:
                abv = (product.get("nutriments") or {}).get("alcohol_100g")
            try:
                abv = float(abv) if abv is not None else None
                if abv is not None and not (0 < abv <= 100):
                    abv = None
            except (TypeError, ValueError):
                abv = None

            milliliters = None
            quantity = product.get("product_quantity")
            try:
                if quantity is not None:
                    milliliters = float(quantity)
            except (TypeError, ValueError):
                milliliters = None
            if milliliters is None:
                milliliters = milliliters_from_size(product.get("quantity"))

            upc = normalize_upc(product.get("code"))
            key = upc or name.lower()
            if key in seen:
                continue
            seen.add(key)

            products.append({
                "name": " ".join(name.split()),
                "category": category,
                "abv": abv,
                "ml": milliliters,
                "units": None,
                "upc": upc,
            })

    print(f"[off] scanned {scanned:,} lines, kept {len(products):,}")
    return products


def deduplicate(products):
    """One entry per barcode, and per name when there is no barcode. Richer records win."""
    def richness(product):
        return sum(1 for field in ("abv", "ml", "upc") if product.get(field) is not None)

    best = {}
    for product in products:
        key = product["upc"] or product["name"].lower()
        current = best.get(key)
        if current is None or richness(product) > richness(current):
            best[key] = product
    return sorted(best.values(), key=lambda p: p["name"].lower())


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--plcb", action="store_true", help="include the PLCB wholesale catalogs")
    parser.add_argument("--off", metavar="PATH", help="path to an Open Food Facts JSONL(.gz) dump")
    parser.add_argument("--out", default=DEFAULT_OUT, help=f"output path (default {DEFAULT_OUT})")
    parser.add_argument("--dry-run", action="store_true",
                        help="report the column mapping and write nothing")
    args = parser.parse_args()

    if not args.plcb and not args.off:
        parser.error("pick at least one source: --plcb and/or --off")

    products = []
    sources = []
    if args.plcb:
        products += load_plcb(dry_run=args.dry_run)
        sources.append("PLCB wholesale catalogs (public Commonwealth of Pennsylvania records)")
    if args.off and not args.dry_run:
        products += load_off(args.off)
        sources.append("Open Food Facts (ODbL, attribution required)")

    if args.dry_run:
        print("\nDry run: nothing written. Check the mappings above against"
              " inspect_store_catalog.py output.")
        return 0

    products = deduplicate(products)
    with_abv = sum(1 for p in products if p["abv"] is not None)
    with_size = sum(1 for p in products if p["ml"] is not None)
    with_upc = sum(1 for p in products if p["upc"] is not None)

    payload = {
        "meta": {
            "generated": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
            "count": len(products),
            "withABV": with_abv,
            "withSize": with_size,
            "withUPC": with_upc,
            "sources": sources,
        },
        "products": products,
    }

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, separators=(",", ":"), ensure_ascii=False)

    size_mb = os.path.getsize(args.out) / (1024 * 1024)
    print(f"\nwrote {args.out}")
    print(f"  {len(products):,} products, {size_mb:.1f} MB")
    print(f"  ABV on {with_abv:,} ({with_abv * 100 // max(1, len(products))}%),"
          f" size on {with_size:,}, UPC on {with_upc:,}")
    print("  products with no ABV fall back to the style chart in StaticBeverageKnowledge,")
    print("  and stay flagged as estimates either way.")
    print("\nAdd the file to the Xcode target's Resources so it ships in the bundle.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
