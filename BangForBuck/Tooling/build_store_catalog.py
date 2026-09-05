#!/usr/bin/env python3
"""build_store_catalog - build AppTarget/Resources/store_catalog.json for the store calculator.

Three public sources, because no single one covers a US shelf with an ABV on every row:

  * **BC Liquor Distribution Branch price list** (open data, CSV, monthly). The best source of
    *alcohol percentage* anywhere in the open: ~10,000 SKUs, and every row carries the name, the
    barcode, litres per container, containers per sell unit (the pack count), AND the ABV. Wine
    included, which is the category nobody else publishes a percentage for. Prices are Canadian and
    are deliberately dropped.
  * **PLCB wholesale catalogs** (public Commonwealth records, .xlsx). This is what's actually on a
    Pennsylvania shelf: every wine, spirit, and ready-to-drink cocktail sold in the state, with a
    retail size and a UPC. It usually lacks ABV, which is fine, because...
  * ...**the two join on barcode.** A PLCB row with no percentage inherits one from the BC row with
    the same UPC. That join is the whole trick: PA tells us what's on the shelf, BC tells us how
    strong it is.
  * **Open Food Facts** (optional, ODbL) fills the beer gap, since PA doesn't sell beer through
    state stores and BC's beer coverage is Canadian.

Never imported: **price**. Shelf prices are local and change weekly, and a stale bundled price
would be the one dishonest number in an app whose promise is that it never invents one (§10).

    python3 Tooling/build_store_catalog.py --bcldb
    python3 Tooling/build_store_catalog.py --bcldb --plcb
    python3 Tooling/build_store_catalog.py --bcldb --plcb --drop-without-abv
    python3 Tooling/inspect_store_catalog.py plcb

(Do not paste a trailing "# comment" after these: zsh does not treat # as a comment in an
interactive shell, so it arrives as an argument and argparse rejects it.)

Then add the generated file to the Xcode target's Resources. `BundledStoreCatalog` picks it up and
falls back to the curated 655-brand list if it's absent.

LICENSING, before shipping: the BC list is BC open data (Open Government Licence, attribution) and
the PLCB catalogs are public Commonwealth records. Open Food Facts is ODbL, which adds share-alike
obligations on the database, so `--off` is opt-in and a `--bcldb --plcb` build avoids it. Not legal
advice.

Requirements: --bcldb needs nothing but the Python standard library. --plcb reads .xlsx and needs
`pip3 install pandas openpyxl`. --off reads a JSONL dump and needs nothing extra.
"""

import argparse
import csv
import gzip
import io
import json
import os
import re
import sys
import urllib.request
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEFAULT_OUT = os.path.join(ROOT, "AppTarget", "Resources", "store_catalog.json")

# The dataset publishes a new resource each month; the landing page lists them all. Override with
# --bcldb-url when a newer month is out.
BCLDB_URL = ("https://catalogue.data.gov.bc.ca/dataset/e43be180-7511-4e6f-84d3-ad6c9f5c3e2b/"
             "resource/09a4eba7-c357-4764-8ef8-5f0499e11a3e/download/"
             "bc_liquor_store_product_price_list_april_2026.csv")
BCLDB_LANDING = "https://catalogue.data.gov.bc.ca/dataset/bc-liquor-store-product-price-list-historical-prices"

PLCB_CATALOGS = {
    "wine": ("https://www.apps.lcb.pa.gov/webapp/reports/Wholesale_Wines_Catalog_Full.xlsx", "wineGlass"),
    "spirits": ("https://www.apps.lcb.pa.gov/webapp/reports/Wholesale_Spirits_Catalog_Full.xlsx", "shot"),
    "rtdc": ("https://www.apps.lcb.pa.gov/webapp/reports/Wholesale_RTDC_Catalog_Full.xlsx", "cocktail"),
}

# PLCB header names are matched loosely; they have been renamed before. --dry-run prints the result.
PLCB_COLUMNS = {
    "name": ["product description", "description", "brand name", "item description", "product name"],
    # Nothing in the real PLCB headers contains "size", so cast a wider net; when none of these
    # hit, the size is parsed out of the item description instead (it is usually in there).
    "size": ["retail size", "size description", "bottle size", "size", "unit of measure",
             "volume", "liter", "litre", "capacity", "container", "ml"],
    "upc": ["upc"],
    "proof": ["proof"],
    "abv": ["alcohol", "abv"],
}

SIZE_PATTERN = re.compile(r"(\d+(?:\.\d+)?)\s*(ml|mls|l|lt|ltr|liter|litre|oz|ounce)\b", re.IGNORECASE)

# Words that should stay upper-cased when a SHOUTED catalog name is title-cased.
KEEP_UPPER = {"VSOP", "VS", "XO", "IPA", "IPAS", "NV", "GSM", "BC", "USA", "XXX", "DOCG", "DOC",
              "IGT", "AOC", "LBV", "RD", "XA", "PET", "SRP", "GG", "1ER", "NA", "RTD",
              # Roman numerals, which title() would render as "Xiii".
              "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII"}


# ---------------------------------------------------------------- download

# Standard library only, on purpose. This script is meant to be runnable on a fresh Mac with no
# `pip install` at all for the BC path; only the PLCB path needs pandas/openpyxl, because parsing
# .xlsx by hand would be silly. A browser-ish User-Agent is required because some government hosts
# reject the default Python one with a 403.
USER_AGENT = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
              "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")


def download(url, timeout=300):
    """Fetch a URL and return raw bytes. Raises with a readable message on failure."""
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.read()
    except Exception as error:  # noqa: BLE001 - the message matters more than the type here
        raise SystemExit(f"download failed: {url}\n  {error}\n"
                         f"  If this is the BC list, check the current monthly resource URL at\n"
                         f"  {BCLDB_LANDING}\n"
                         f"  You can also download it by hand and pass --bcldb-file PATH.")


def require_pandas():
    """The PLCB catalogs are .xlsx, which genuinely needs a library."""
    try:
        import pandas  # noqa: F401
        import openpyxl  # noqa: F401
    except ImportError:
        raise SystemExit("The --plcb path reads .xlsx files and needs two libraries:\n"
                         "    pip3 install pandas openpyxl\n"
                         "  (--bcldb needs nothing beyond the standard library.)")


# ---------------------------------------------------------------- shared helpers

def normalize_upc(raw):
    """Digits only, zero-padded to 12. The PLCB export strips leading zeros (their own docs say so),
    so padding is what lets a PLCB row and a BC row find each other."""
    if raw is None:
        return None
    digits = re.sub(r"\D", "", str(raw))
    if not digits or int(digits or 0) == 0:
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


# A size at the end of a product description: "750ML", "1.75 L", "4/187ML", "12OZ".
TRAILING_SIZE = re.compile(
    r"[\s,/-]*\b(?:(\d+)\s*[/xX*]\s*)?(\d+(?:\.\d+)?)\s*"
    r"(ml|mls|l|lt|ltr|liter|litre|oz|ounce)\b\.?\s*$",
    re.IGNORECASE,
)


def size_from_description(name):
    """Pull a trailing size off a product description.

    Returns (millilitres or None, pack count or None, cleaned name).

    The multipack form carries both numbers: "4/187ML" is four 187 mL bottles, so the *container* is
    187 mL and the *count* is 4. Reading 748 mL out of that would misprice every split-pack of
    champagne in the catalog, and dropping the 4 would lose a pack count we can otherwise only guess.
    """
    match = TRAILING_SIZE.search(name)
    if not match:
        return None, None, name

    value, unit = float(match.group(2)), match.group(3).lower()
    if value <= 0:
        return None, None, name
    if unit.startswith("ml"):
        milliliters = value
    elif unit in ("l", "lt", "ltr", "liter", "litre"):
        milliliters = value * 1000
    else:
        milliliters = value * 29.5735

    count = None
    if match.group(1):
        parsed = int(match.group(1))
        if 2 <= parsed <= 48:
            count = parsed

    cleaned = name[:match.start()].strip(" ,-/")
    return round(milliliters, 1), count, (cleaned or name)


# Characters that carry no meaning in a product name but do make CoreText complain
# ("The variant selector cell index number could not be found") when iOS renders them:
# variation selectors, zero-width spaces/joiners, directional marks, and the BOM.
INVISIBLE = re.compile(
    "[\ufe00-\ufe0f\u200b-\u200f\u202a-\u202e\u2060-\u2064\ufeff\u00ad]"
)
CONTROL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")


def sanitize(name):
    """Strip invisible and control characters and normalize the quotes and dashes.

    Catalog exports carry these more often than you would think, and they are invisible by
    definition, so the only symptom is a console full of CoreText warnings and the occasional
    search that mysteriously fails to match.
    """
    text = INVISIBLE.sub("", str(name))
    text = CONTROL.sub(" ", text)
    text = (text.replace("\u2019", "'").replace("\u2018", "'")
                .replace("\u201c", '"').replace("\u201d", '"')
                .replace("\u2013", "-").replace("\u2014", "-")
                .replace("\u00a0", " "))
    return " ".join(text.split())


def prettify(name):
    """Catalog names are SHOUTED. Sanitize, then title-case, keeping the acronyms that matter."""
    words = sanitize(name).split(" ")
    out = []
    for word in words:
        stripped = re.sub(r"[^A-Za-z0-9]", "", word).upper()
        if stripped in KEEP_UPPER:
            out.append(word.upper())
        elif word.isupper() or word.islower():
            # str.title() capitalizes the letter after an apostrophe ("TITO'S" -> "Tito'S"), so
            # lower a single letter that follows one.
            titled = word.title()
            out.append(re.sub(r"(['\u2019])(\w)(?!\w)", lambda m: m.group(1) + m.group(2).lower(), titled))
        else:
            out.append(word)
    return " ".join(out)


def clean_float(raw, low=0.0, high=100.0):
    try:
        value = float(re.sub(r"[^\d.]", "", str(raw)))
    except (TypeError, ValueError):
        return None
    return value if low < value <= high else None


# ---------------------------------------------------------------- BC LDB

def bcldb_category(category, subcategory, item_class):
    """Map the BC taxonomy onto our BeverageCategory raw values."""
    blob = f"{category} {subcategory} {item_class}".lower()
    if "de-alcoholized" in blob or "alcohol free" in blob:
        return "nonAlcoholic"
    if category == "Beer":
        return "bottledBeer"
    if "cider" in blob:
        return "cider"
    if "cooler" in blob or "seltzer" in blob:
        return "seltzer"
    if category == "Wine":
        return "wineGlass"
    if category == "Spirits":
        if "liqueur" in blob or "ready to serve" in blob or "cocktail" in blob:
            return "cocktail"
        return "shot"
    if "refreshment" in blob:
        return "seltzer"
    return "unknown"


def load_bcldb(url, source_text=None):
    """The BC price list. Schema verified against the April 2026 resource:
    ITEM_CATEGORY_NAME, ITEM_SUBCATEGORY_NAME, ITEM_CLASS_NAME, PRODUCT_COUNTRY_ORIGIN_NAME,
    PRODUCT_SKU_NO, PRODUCT_LONG_NAME, PRODUCT_BASE_UPC_NO, PRODUCT_LITRES_PER_CONTAINER,
    PRD_CONTAINER_PER_SELL_UNIT, PRODUCT_ALCOHOL_PERCENT, PRODUCT_PRICE, SWEETNESS_CODE
    """
    if source_text is None:
        print(f"[bcldb] downloading {url}")
        source_text = download(url).decode("utf-8-sig", errors="replace")

    reader = csv.DictReader(io.StringIO(source_text))
    required = {"PRODUCT_LONG_NAME", "PRODUCT_ALCOHOL_PERCENT", "PRODUCT_LITRES_PER_CONTAINER"}
    missing = required - set(reader.fieldnames or [])
    if missing:
        sys.exit(f"[bcldb] unexpected schema, missing {sorted(missing)}.\n"
                 f"        Check the current resource URL on {BCLDB_LANDING}")

    products = []
    for row in reader:
        name = (row.get("PRODUCT_LONG_NAME") or "").strip()
        if not name:
            continue

        litres = clean_float(row.get("PRODUCT_LITRES_PER_CONTAINER"), 0, 100)
        units = clean_float(row.get("PRD_CONTAINER_PER_SELL_UNIT"), 0, 1000)
        abv = clean_float(row.get("PRODUCT_ALCOHOL_PERCENT"))

        products.append({
            "name": prettify(name),
            "category": bcldb_category(row.get("ITEM_CATEGORY_NAME", ""),
                                       row.get("ITEM_SUBCATEGORY_NAME", ""),
                                       row.get("ITEM_CLASS_NAME", "")),
            "abv": round(abv, 2) if abv is not None else None,
            "ml": round(litres * 1000, 1) if litres else None,
            "units": int(units) if units and units >= 1 else None,
            "upc": normalize_upc(row.get("PRODUCT_BASE_UPC_NO")),
        })

    print(f"[bcldb] {len(products):,} products, "
          f"{sum(1 for p in products if p['abv'] is not None):,} with an ABV")
    return products


# ---------------------------------------------------------------- PLCB

def map_plcb_columns(headers):
    lowered = {str(h).strip().lower(): h for h in headers}
    mapping, missing = {}, []
    for key, candidates in PLCB_COLUMNS.items():
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
    require_pandas()
    import pandas as pd

    products = []
    for label, (url, category) in PLCB_CATALOGS.items():
        print(f"[plcb] {label}: downloading")
        payload = download(url)
        # dtype=str throughout: a UPC read as a float becomes 1.23e+13 and is destroyed.
        frame = pd.read_excel(io.BytesIO(payload), dtype=str)

        columns, missing = map_plcb_columns(frame.columns)
        print(f"[plcb] {label}: {len(frame)} rows; mapped {columns}")
        if missing:
            print(f"[plcb] {label}: NOT MAPPED {missing}")
            print(f"[plcb] {label}: actual headers are {[str(c) for c in frame.columns]}")
            if "size" in missing:
                print(f"[plcb] {label}: falling back to reading the size out of the description")
        if "name" not in columns:
            print(f"[plcb] {label}: skipped, no usable product-name column")
            continue
        if dry_run:
            continue

        for row in frame.to_dict(orient="records"):
            name = row.get(columns["name"])
            if not name or str(name).strip().lower() == "nan":
                continue
            name = " ".join(str(name).split())

            abv = clean_float(row.get(columns["abv"])) if columns.get("abv") else None
            if abv is None and columns.get("proof"):
                proof = clean_float(row.get(columns["proof"]), 0, 200)
                abv = round(proof / 2, 2) if proof else None

            milliliters, units = None, None
            if columns.get("size"):
                milliliters = milliliters_from_size(row.get(columns["size"]))
            if milliliters is None:
                # PLCB descriptions carry the size ("JOSH CELLARS CABERNET 750ML") and sometimes the
                # pack ("MOET IMPERIAL 4/187ML"). Take both from there and drop the size off the
                # display name, since it's shown as its own chip anyway.
                milliliters, units, name = size_from_description(name)

            # Note: a "units per case" column, where one exists, is a *wholesale* case quantity and
            # is deliberately not used. Nobody carries out 12 bottles of one wine.
            products.append({
                "name": prettify(name),
                "category": category,
                "abv": abv,
                "ml": milliliters,
                "units": units,
                "upc": normalize_upc(row.get(columns["upc"])) if columns.get("upc") else None,
            })
    return products


# ---------------------------------------------------------------- Open Food Facts

def off_category(tags):
    joined = " ".join(tags)
    if "beer" in joined or "ale" in joined:
        return "bottledBeer"
    if "cider" in joined:
        return "cider"
    if "seltzer" in joined:
        return "seltzer"
    if "wine" in joined or "champagne" in joined or "sparkling" in joined:
        return "wineGlass"
    if "spirit" in joined or "whisky" in joined or "whiskey" in joined or "vodka" in joined:
        return "shot"
    if "alcoholic" in joined:
        return "unknown"
    return None


def load_off(path, countries=("united-states",)):
    opener = gzip.open if path.endswith(".gz") else open
    products, scanned = [], 0
    with opener(path, "rt", encoding="utf-8") as handle:
        for line in handle:
            scanned += 1
            if scanned % 500_000 == 0:
                print(f"[off] scanned {scanned:,}, kept {len(products):,}")
            try:
                product = json.loads(line)
            except json.JSONDecodeError:
                continue

            category = off_category(product.get("categories_tags") or [])
            if not category:
                continue
            if countries:
                tags = product.get("countries_tags") or []
                if not any(f"en:{c}" in tags or c in tags for c in countries):
                    continue

            name = (product.get("product_name") or "").strip()
            if not name:
                continue

            abv = product.get("alcohol_value")
            if abv is None:
                abv = (product.get("nutriments") or {}).get("alcohol_100g")
            abv = clean_float(abv)

            milliliters = clean_float(product.get("product_quantity"), 0, 100000)
            if milliliters is None:
                milliliters = milliliters_from_size(product.get("quantity"))

            products.append({
                "name": " ".join(name.split()),
                "category": category,
                "abv": abv,
                "ml": milliliters,
                "units": None,
                "upc": normalize_upc(product.get("code")),
            })
    print(f"[off] scanned {scanned:,}, kept {len(products):,}")
    return products


# ---------------------------------------------------------------- merge

def enrich_by_upc(products):
    """The join that makes this worth doing: a row with a barcode but no ABV borrows the ABV (and
    size, if it's missing) from any other row sharing that barcode. This is how a PA shelf SKU with
    no percentage gets one from the BC list."""
    by_upc = {}
    for product in products:
        upc = product.get("upc")
        if not upc:
            continue
        known = by_upc.setdefault(upc, {})
        for field in ("abv", "ml", "units"):
            if known.get(field) is None and product.get(field) is not None:
                known[field] = product[field]

    filled = 0
    for product in products:
        upc = product.get("upc")
        if not upc or upc not in by_upc:
            continue
        for field in ("abv", "ml", "units"):
            if product.get(field) is None and by_upc[upc].get(field) is not None:
                product[field] = by_upc[upc][field]
                if field == "abv":
                    filled += 1
    print(f"[merge] filled {filled:,} missing ABVs by barcode join")
    return products


def deduplicate(products):
    """One entry per barcode, and per (name, size) when there's no barcode. Richer records win."""
    def richness(product):
        return sum(1 for field in ("abv", "ml", "units") if product.get(field) is not None)

    best = {}
    for product in products:
        key = product["upc"] or f"{product['name'].lower()}|{product.get('ml')}"
        current = best.get(key)
        if current is None or richness(product) > richness(current):
            best[key] = product
    return sorted(best.values(), key=lambda p: p["name"].lower())


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--bcldb", action="store_true",
                        help="include the BC Liquor Distribution Branch price list (best ABV source)")
    parser.add_argument("--bcldb-url", default=BCLDB_URL, help="override the monthly resource URL")
    parser.add_argument("--bcldb-file", help="use a already-downloaded BC CSV instead of fetching")
    parser.add_argument("--plcb", action="store_true", help="include the PLCB wholesale catalogs")
    parser.add_argument("--off", metavar="PATH", help="path to an Open Food Facts JSONL(.gz) dump")
    parser.add_argument("--out", default=DEFAULT_OUT, help=f"output path (default {DEFAULT_OUT})")
    parser.add_argument("--drop-without-abv", action="store_true",
                        help="keep only products with a real percentage (smaller, more honest file)")
    parser.add_argument("--dry-run", action="store_true", help="report mappings, write nothing")
    args = parser.parse_args()

    if not (args.bcldb or args.bcldb_file or args.plcb or args.off):
        parser.error("pick at least one source: --bcldb, --plcb, and/or --off")

    products, sources = [], []

    if args.bcldb or args.bcldb_file:
        text = None
        if args.bcldb_file:
            text = open(args.bcldb_file, encoding="utf-8-sig", errors="replace").read()
        products += load_bcldb(args.bcldb_url, source_text=text)
        sources.append("BC Liquor Distribution Branch product price list (BC open data)")

    if args.plcb:
        products += load_plcb(dry_run=args.dry_run)
        sources.append("PLCB wholesale catalogs (public Commonwealth of Pennsylvania records)")

    if args.off and not args.dry_run:
        products += load_off(args.off)
        sources.append("Open Food Facts (ODbL, attribution required)")

    if args.dry_run:
        print("\nDry run: nothing written.")
        return 0

    products = enrich_by_upc(products)
    products = deduplicate(products)

    if args.drop_without_abv:
        before = len(products)
        products = [p for p in products if p["abv"] is not None]
        print(f"[filter] dropped {before - len(products):,} products with no percentage")

    with_abv = sum(1 for p in products if p["abv"] is not None)
    with_size = sum(1 for p in products if p["ml"] is not None)
    with_upc = sum(1 for p in products if p["upc"] is not None)
    with_units = sum(1 for p in products if p["units"] is not None)

    payload = {
        "meta": {
            "generated": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
            "count": len(products),
            "withABV": with_abv,
            "withSize": with_size,
            "withUPC": with_upc,
            "withPackCount": with_units,
            "sources": sources,
            "note": "Prices are deliberately not included; the shopper always reads the real tag.",
        },
        "products": products,
    }

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, separators=(",", ":"), ensure_ascii=False)

    size_mb = os.path.getsize(args.out) / (1024 * 1024)
    percent = with_abv * 100 // max(1, len(products))
    print(f"\nwrote {args.out}")
    print(f"  {len(products):,} products, {size_mb:.1f} MB")
    print(f"  ABV on {with_abv:,} ({percent}%), size on {with_size:,},"
          f" pack count on {with_units:,}, UPC on {with_upc:,}")
    print("  Products with no ABV fall back to the style chart in StaticBeverageKnowledge and")
    print("  stay flagged as estimates either way.")
    print("\nAdd the file to the Xcode target's Resources so it ships in the bundle.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
