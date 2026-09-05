# Store catalog sources

*Where the store calculator's product list comes from, and how to rebuild it. Companion to
`BeverageDataSources.md`, which covers the small curated brand table used by the **menu** scanner.
These are two different datasets doing two different jobs; see "Why two datasets" below.*

## The problem

The store calculator needs names, alcohol percentages, container sizes, and pack counts for as much
of a real shelf as possible. Names and sizes are easy. **Alcohol percentage on wine is the hard
part**: retail sites almost never publish it, and brand-by-brand lookup does not scale past a few
dozen products.

## What actually works: three sources, joined on barcode

### 1. BC Liquor Distribution Branch price list (the ABV source)

**This is the find.** British Columbia publishes its entire retail catalog as open data, refreshed
monthly, and every row carries a percentage.

- Landing page (lists every monthly resource):
  https://catalogue.data.gov.bc.ca/dataset/bc-liquor-store-product-price-list-historical-prices
- Schema, verified against the April 2026 resource:

| Column | Use |
|---|---|
| `PRODUCT_LONG_NAME` | product name (SHOUTED; the importer title-cases it) |
| `PRODUCT_ALCOHOL_PERCENT` | **ABV**, populated on essentially every row |
| `PRODUCT_LITRES_PER_CONTAINER` | container size (0.355 = a 12 oz can, 0.75 = a wine bottle) |
| `PRD_CONTAINER_PER_SELL_UNIT` | **pack count** (36 for a Coors case, 4 for a tall-can 4-pack) |
| `PRODUCT_BASE_UPC_NO` | barcode, which is what makes the join below possible |
| `ITEM_CATEGORY_NAME` / `ITEM_SUBCATEGORY_NAME` / `ITEM_CLASS_NAME` | mapped to `BeverageCategory` |
| `PRODUCT_PRICE` | **deliberately discarded** (Canadian, and stale by definition) |

Roughly 10,000 SKUs, thousands of them wine, with real percentages: 13% on a Chateau Margaux, 11%
on a La Marca Prosecco, 15% on a Dassai sake. Spot-checked against independent sources: High Noon
reads 4.5% here, matching the label everywhere else.

Licence: BC open data (Open Government Licence), attribution required. Not legal advice.

### 2. PLCB wholesale catalogs (what is on a Pennsylvania shelf)

- https://www.pa.gov/agencies/lcb/supplier-vendors/wine-and-spirits-suppliers/item-catalogs
- Full `.xlsx` catalogs for wine, spirits, and ready-to-drink cocktails: every SKU sold in PA, with
  a retail size and a **UPC** (their own instructions confirm the UPC column, with leading zeros
  stripped, which is why the importer zero-pads).
- Usually **no ABV**, and no beer at all, because PA does not sell beer through state stores.
- Licence: public Commonwealth records.

**Real headers, from a live run (Sep 2026):** `Item Description`, `UPC`, `Proof`, and no column
containing the word "size" at all. So:
- Spirits and RTDC ABV comes from **`Proof` ÷ 2**, which covers those two catalogs.
- **Wine has neither an ABV nor a proof column**, which is exactly why the BC barcode join matters.
- Size is parsed out of `Item Description`, which carries it: "JOSH CELLARS CABERNET 750ML". The
  multipack form gives both numbers, so "MOET IMPERIAL 4/187ML" reads as a 187 mL container with a
  pack count of 4, not a 748 mL bottle.
- Row counts: wine 6,293, spirits 4,651, RTDC 290.

### 3. The barcode join (the actual trick)

A PLCB row with a barcode but no percentage inherits the percentage from the BC row with the same
barcode. Pennsylvania tells us what is on the shelf; British Columbia tells us how strong it is.
`enrich_by_upc` in the importer does this and reports how many percentages it filled.

### 4. Open Food Facts (optional, fills the beer gap)

- https://world.openfoodfacts.org/data — nightly JSONL dump, barcode-keyed, alcohol percentage on
  most beers and wines.
- **ODbL licensed**, which adds attribution *and* share-alike obligations on the database. It is
  opt-in for that reason: a `--bcldb --plcb` build carries no ODbL obligation. Not legal advice.

## Rebuilding

```bash
python3 Tooling/build_store_catalog.py --bcldb
python3 Tooling/build_store_catalog.py --bcldb --plcb
python3 Tooling/build_store_catalog.py --bcldb --plcb --drop-without-abv
python3 Tooling/inspect_store_catalog.py plcb
```

Those are, in order: the simplest useful catalog; the same plus PA shelf coverage; the same again
keeping only products with a real percentage; and a dump of the live PLCB headers.

**Do not paste a trailing `# comment` after any of these.** `zsh` does not treat `#` as a comment in
an interactive shell, so it arrives as an argument and argparse rejects the whole command.

**Dependencies:** `--bcldb` needs nothing but the Python standard library. `--plcb` reads `.xlsx`
and needs `pip3 install pandas openpyxl`. `--off` reads a JSONL dump and needs nothing extra.

Output is `AppTarget/Resources/store_catalog.json`. Add it to the Xcode target's Resources;
`BundledStoreCatalog` loads it and falls back to the curated 655-brand list if it is absent.

Useful flags: `--bcldb-url` for a newer monthly resource, `--bcldb-file` to reuse a download,
`--dry-run` to check the PLCB column mapping without writing, `--drop-without-abv` to keep only
products with a genuine percentage.

## What is never imported

**Price.** Shelf prices are local, change weekly, and differ by store. A bundled price would be the
one fabricated number in an app whose entire promise is that it never invents one (§10, R-invariant).
The shopper reads the tag; that is the point.

## Why two datasets

`Tooling/Data/beverages.json` (655 curated brands, compiled into `GeneratedBrandTable.swift`) is the
**menu** matcher. There, a small curated list is a feature: it substring-matches against OCR'd menu
text, and a 10,000-SKU list would match the word "Chardonnay" on a menu against one specific
winery's bottling from one vintage.

`store_catalog.json` is the **store** search. It is large, loaded at runtime rather than compiled,
and matched by ranked whole-name search rather than substring. Different job, different data,
separate artifact. Ten thousand `BrandEntry` literals would also be miserable to compile.

## What a real build produces

From a run on 2026-09-05 with `--bcldb --plcb`:

```
[bcldb] 8,250 products, 8,236 with an ABV
[plcb]  wine 6,293 rows · spirits 4,651 · rtdc 290
[merge] filled 134 missing ABVs by barcode join
        16,730 products, 2.0 MB
        ABV on 11,090 (66%), size on 7,998, pack count on 7,998, UPC on 16,318
```

2 MB bundles fine with no indexing, and 16,730 rows is well within what the in-memory ranked search
handles per keystroke. Two observations worth carrying forward:

- **The barcode join filled only 134.** Fewer than hoped. PLCB and BC stock different products and,
  where they overlap, often list different package barcodes for the same wine. The join is worth
  keeping (it is free and it is exactly right when it fires) but it is not the main ABV source; BC's
  own 8,236 rows are.
- **The remaining 34% with no percentage are mostly PLCB wine**, which has no ABV or proof column.
  Those fall back to the varietal style chart, which for wine is a genuinely decent estimate
  (12 to 14.5% covers most of it) and is flagged as an estimate in the UI. Adding
  `--drop-without-abv` trades that coverage for a smaller, all-measured file; worth comparing both
  on device before deciding.

## Accuracy notes

- Every ABV in the app is still shown as an **estimate** and is one-tap correctable (§11, R2). A
  catalog percentage is a label figure for a product line, not a measurement of the bottle in hand.
- A product with no percentage falls back to the style chart in `StaticBeverageKnowledge`, which is
  honest about being a fallback.
- BC names lead with the appellation or varietal ("MARGAUX - CHATEAU MARGAUX 2014"). The ranked
  search handles this: its all-words-in-any-order tier finds that row for "chateau margaux".
- If `store_catalog.json` gets large enough to slow launch, index it (prefix buckets or SQLite)
  rather than parsing the whole file up front.
