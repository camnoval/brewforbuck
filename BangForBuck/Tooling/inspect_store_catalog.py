#
//  inspect_store_catalog.py
//  BangForBuck
//
//  Created by Noval, Cameron on 9/5/26.
//


#!/usr/bin/env python3
"""inspect_store_catalog - dump the REAL shape of the source catalogs before parsing them (§5).

The PLCB publishes full wholesale catalogs as .xlsx, and Open Food Facts publishes a nightly JSONL
dump. Neither schema should be written from memory, so this script downloads a sample and prints
the actual column names, dtypes, and a few rows. Run it first; feed what it prints into
`build_store_catalog.py`'s column map if the fuzzy matching there guesses wrong.

Usage:
    python3 Tooling/inspect_store_catalog.py plcb            # all four PLCB catalogs
    python3 Tooling/inspect_store_catalog.py plcb wine        # just one
    python3 Tooling/inspect_store_catalog.py off /path/to/openfoodfacts-products.jsonl.gz

Requires: pandas, openpyxl, requests  (pip3 install pandas openpyxl requests)
Needs a network for the PLCB URLs.
"""

import gzip
import io
import json
import sys

PLCB_CATALOGS = {
    "rtdc": "https://www.apps.lcb.pa.gov/webapp/reports/Wholesale_RTDC_Catalog_Full.xlsx",
    "wine": "https://www.apps.lcb.pa.gov/webapp/reports/Wholesale_Wines_Catalog_Full.xlsx",
    "spirits": "https://www.apps.lcb.pa.gov/webapp/reports/Wholesale_Spirits_Catalog_Full.xlsx",
    "special": "https://www.apps.lcb.pa.gov/webapp/reports/Wholesale_Non_Stock_Catalog_Full.xlsx",
}

FIELD_DESCRIPTIONS = "https://www.apps.lcb.pa.gov/webapp/reports/Product_Catalog_Field_Descriptions.csv"


def inspect_plcb(which=None):
    import pandas as pd
    import requests

    print(f"Field descriptions live at:\n  {FIELD_DESCRIPTIONS}\n")

    targets = {which: PLCB_CATALOGS[which]} if which else PLCB_CATALOGS
    for name, url in targets.items():
        print("=" * 78)
        print(f"{name}: {url}")
        print("=" * 78)
        try:
            response = requests.get(url, timeout=120)
            response.raise_for_status()
            # Read every column as text first: UPCs and SCCs are long digit strings that pandas
            # will happily turn into floats and corrupt (1.23e+13).
            frame = pd.read_excel(io.BytesIO(response.content), dtype=str)
        except Exception as error:  # noqa: BLE001 - this is a diagnostic script
            print(f"  FAILED: {error}\n")
            continue

        print(f"  rows: {len(frame)}   columns: {len(frame.columns)}\n")
        for position, column in enumerate(frame.columns):
            filled = frame[column].notna().sum()
            sample = frame[column].dropna().head(2).tolist()
            letter = chr(ord("A") + position) if position < 26 else f"col{position}"
            print(f"  [{letter}] {column!r}")
            print(f"        filled {filled}/{len(frame)}   e.g. {sample}")
        print()
        print("  First 3 rows as records:")
        for record in frame.head(3).to_dict(orient="records"):
            print(f"    {record}")
        print()


def inspect_off(path):
    """Print the alcohol-relevant fields of the first few beverage products in an OFF dump."""
    interesting = [
        "code", "product_name", "brands", "categories_tags", "quantity",
        "product_quantity", "alcohol_value", "alcohol_unit", "nutriments", "countries_tags",
    ]
    opener = gzip.open if path.endswith(".gz") else open
    shown = 0
    with opener(path, "rt", encoding="utf-8") as handle:
        for line in handle:
            try:
                product = json.loads(line)
            except json.JSONDecodeError:
                continue
            tags = product.get("categories_tags") or []
            if not any("alcoholic" in tag or "beer" in tag or "wine" in tag for tag in tags):
                continue
            print("-" * 78)
            for field in interesting:
                value = product.get(field)
                if field == "nutriments" and isinstance(value, dict):
                    value = {k: v for k, v in value.items() if "alcohol" in k}
                if value not in (None, "", [], {}):
                    print(f"  {field}: {str(value)[:200]}")
            shown += 1
            if shown >= 8:
                break
    print("-" * 78)
    print(f"\nShowed {shown} alcoholic products. Note which field actually carries the percentage:")
    print("it is usually `alcohol_value` (with `alcohol_unit`) or `nutriments.alcohol_100g`.")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    mode = sys.argv[1]
    if mode == "plcb":
        inspect_plcb(sys.argv[2] if len(sys.argv) > 2 else None)
    elif mode == "off":
        if len(sys.argv) < 3:
            print("Pass the path to the Open Food Facts JSONL dump.")
            return 1
        inspect_off(sys.argv[2])
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
