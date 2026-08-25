# Beverage data sources

*Where the numbers in `StaticBeverageKnowledge` come from. Facts (typical ABV / pour) are drawn
from the public references below and encoded as **seed midpoints**; they are always shown as
estimates in-app (`Provenance.estimated`) and are one-tap correctable (§11). This file exists so the
sourcing is auditable and tunable (R2).*

## Two tiers

1. **Brand table** — a keyword match on a specific product (e.g. "Bud Light", "White Claw",
   "Heineken 0.0"). **The machine-readable source of truth is `Tooling/Data/beverages.json`**
   (161 brands), compiled to a Foundation-free Swift table by `Tooling/generate_brand_table.sh`
   → `Core/Sources/CoreContracts/GeneratedBrandTable.swift`. Flagged `EstimateSource.brandMatch`.
   Edit the JSON and re-run the generator to change the data; don't hand-edit the Swift.
2. **Style chart** — a keyword match on the drink name (beer style / wine varietal) → a typical ABV
   from the sources below. Flagged `EstimateSource.styleChart(matched:)`.
3. **Category fallback** — no brand and no style match → the section's category default. Flagged
   `EstimateSource.categoryFallback` (or `.unclassifiedFallback` when the section is unknown), so
   the app can **say it fell back**.

The menu's own printed ABV always wins over both (that's `.read`, not `.estimated`).

## Category anchors (fallback tier)

Anchored on the U.S. standard-drink reference (NIAAA): regular beer ~5%, malt liquor ~7%, table
wine ~12%, 80-proof spirits ~40%; light beer ~4.2–4.3%; hard seltzers/FMB ~5–6%+; fortified wine
17–21%. Serving sizes (12 oz beer, 5 oz wine, 1.5 oz shot) are the NIAAA standard-drink pours.
Cocktail/frozen/martini defaults are chosen so a typical serving lands near one standard drink,
which is the honest default for a mixed drink (R2).

- NIAAA — What Is A Standard Drink / Rethinking Drinking:
  https://www.niaaa.nih.gov/health-professionals-communities/core-resource-on-alcohol/basics-defining-how-much-alcohol-too-much
- NIAAA drink-size / cocktail calculator: https://rethinkingdrinking.niaaa.nih.gov/tools/calculators/alcohol-drink-size-calculator

## Beer / ale styles (chart tier)

Typical midpoints from BJCP-derived and craft-beer references:

| Style keyword(s) | Seed ABV |
|---|---|
| light lager (Bud/Coors/Miller Light, Michelob Ultra) | 4.2% |
| Mexican lager (Modelo, Corona, Pacifico) | 4.5% |
| pilsner | 4.7% |
| blonde / golden ale / kölsch | 4.8% |
| lager (generic) | 5.0% |
| amber / Vienna / Märzen / Oktoberfest | 5.2% |
| wheat / hefeweizen / witbier | 5.4% |
| pale ale | 5.5% |
| porter | 5.5% |
| stout (generic) | 6.0% |
| Irish/dry stout, Guinness | 4.2% |
| IPA | 6.5% |
| bock | 6.5% |
| Baltic porter | 8.0% |
| double/imperial IPA | 8.5% |
| imperial stout | 9.0% |
| barleywine / doppelbock / tripel / quad | 9.5% |
| cider | 5.0% |
| hard seltzer (White Claw, High Noon, Truly, Nutrl, Surfside) | 5.0% |

Sources: Brewer's Friend BJCP ABV chart (https://www.brewersfriend.com/2017/05/07/beer-styles-abv-chart-alcohol-by-volume-ranges-2017-update/),
craftbeerme.com style tiers, and pinter.com brand ABVs (Guinness 4.2%, Modelo 4.4%, Corona 4.6%,
Heineken/Stella ~5%, most craft IPAs 6–7%).

## Wine varietals (chart tier)

Typical midpoints from Wine Folly and WSET-style references:

| Varietal keyword(s) | Seed ABV |
|---|---|
| Moscato / Muscat | 6.0% |
| Riesling | 10.0% |
| Prosecco | 11.0% |
| sparkling / Champagne / Cava / Brut | 12.0% |
| Pinot Grigio / Pinot Gris | 12.0% |
| rosé | 12.5% |
| Sauvignon Blanc | 13.0% |
| Chardonnay | 13.5% |
| Pinot Noir / Merlot / red blend | 13.5% |
| Cabernet / Malbec | 14.0% |
| Syrah / Shiraz | 14.5% |
| Zinfandel | 15.0% |
| Port / Sherry / Madeira / Marsala / vermouth | 18.0% |

Sources: Wine Folly alcohol-content chart (https://winefolly.com/tips/alcohol-content-in-wine/),
plus corroborating varietal ranges from WSET workbook material and multiple wine references
(Champagne ~12%, Prosecco ~11%, Moscato d'Asti ~5.5–6.5%, reds 12.5–15%).

## Notes & tuning

- These are **typical** values; real ABV varies by producer and vintage, which is exactly why the
  menu's printed value wins and every estimate is correctable (R2).
- Brand names are only partially covered (a few ubiquitous ones). Most brands fall back to the
  category default — that's expected and honest.
- Retune by editing `styleRules` / `defaultABV` in `StaticBeverageKnowledge.swift`; the tests in
  `CoreContractsTests/StaticBeverageKnowledgeTests.swift` pin the current values.
