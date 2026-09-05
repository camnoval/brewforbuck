# Handoff

*Live "here's where we are" + carry-on context (§2). History lives in `Changelog.md`, not
here — keep this lean. Newest note on top; each new note says plainly what it supersedes.*

---

## ⇢ STATUS (2026-09-05, part 2) — Search-first store calculator; the catalog import path

*Supersedes the part-1 note below re: the add flow, which was brand-picker-behind-a-button and is
now search-first. Everything else in part 1 still stands. `swift test` was green at 146/146 after the
part-1 fix; these additions are again uncompiled.*

**Search first (owner's call).** `AddProductFlow` opens on a focused search field over the whole
catalog; results rank live, and picking one pushes a form already filled in except the price. New in
Core so the logic is tested rather than living in a view:
- `CoreContracts/StoreCatalog.swift` (new): `CatalogProduct` (name, category, optional ABV, optional
  size, optional pack count, optional **UPC**) + the `StoreCatalog` protocol. Fifth contract (§6).
  The UPC field is unused today and exists so the barcode step is a data question, not a redesign.
- `CoreServices/InMemoryStoreCatalog.swift` (new): ranked search in five tiers (exact, name-prefix,
  word-prefix, substring, all-words-any-order), length tiebreak, precomputed lowercased names, and
  digits-only UPC lookup that reconciles a 12-digit UPC-A with the 14-digit GTIN form. Ranking, not
  filtering, because with a large catalog a substring filter buries the obvious answer.
- `CoreServices/PackageDefaults.swift` (new): the "if it knows it's wine, make it 750 mL" logic, in
  three tiers (catalog-stated → read off the name → category default). Wine and spirits open at
  750 mL × 1, beer at 12 oz × 6, seltzer at 12 oz × 12; names carrying "1.75 L", "16oz 12pk",
  "handle", "magnum", "tallboy", "30 rack", "14.9oz" are read exactly. Size matching is on
  unit-normalized **tokens**, not substrings, which is what stops "Josh Cellars **200**7 Cabernet"
  becoming a 200 mL bottle and "Hand**le**y Cellars" becoming a handle. Both are regression tests.
- `ContainerSize` gained `ml50`/`ml200`, `closest(toMilliliters:)` and `closest(toFluidOunces:)`, so
  an unlisted real size (14.9 oz Guinness, 11.2 oz Peroni, 5 L box) keeps its own label instead of
  snapping to the nearest preset. Snap tolerance is 1% by volume.
- Tests: `PackageDefaultsTests` (23 cases incl. the negative ones above), `StoreCatalogSearchTests`
  (16 cases incl. tier ordering and barcode normalization).

**Em-dashes removed from every user-facing string** in `ResultsView`, `ValueChips`, `CompareView`,
and `BeverageKnowledge.abvNote` (that one renders in the app, so it counted). The em-dash characters
still in `MenuParser` are menu text it matches *on* and must stay.

**The big catalog: sourced, with an import path, not yet imported.** Two public sources cover the
shelf between them, and neither can be fetched from this environment (no network), so the work here
is the pipeline plus honest reporting rather than a bundled dataset:
- **PLCB wholesale catalogs** (`pa.gov/agencies/lcb/.../item-catalogs`): full .xlsx catalogs for
  wine, spirits, and ready-to-drink cocktails, every SKU sold in PA, with a retail size and a
  **UPC** (their own instructions confirm the UPC column, with leading zeros stripped). No beer,
  because PA doesn't sell beer through these stores.
- **Open Food Facts**: nightly JSONL/Parquet dump, barcode-keyed, alcohol percentage on most beers
  and wines. Covers the beer gap. **ODbL licensed**, so attribution plus share-alike obligations on
  the database; `--plcb`-only is the clean-license build. Not legal advice.
- `Tooling/inspect_store_catalog.py` (new, §5): prints the real headers, fill rates, and sample rows
  before anything is parsed. **Run this first** and correct `COLUMN_CANDIDATES` if the fuzzy header
  matching guessed wrong; the PLCB has renamed columns before and I could not see the live file.
- `Tooling/build_store_catalog.py` (new): both sources → `AppTarget/Resources/store_catalog.json`,
  with ABV derived from proof when only proof is given, size parsed from the retail-size text,
  UPC zero-padded, dedupe by barcode preferring the richer record, and `--dry-run` to check the
  mapping without writing. Helpers unit-checked in Python here; the download paths were not run.
- **Price is deliberately not imported.** Shelf prices are local and weekly, and a stale bundled
  price would be the one dishonest number in the app (§10). Name, ABV, size, and UPC only.
- `AppTarget/Infrastructure/BundledStoreCatalog.swift` (new) loads that JSON if it's in the bundle
  and **falls back to the curated 655-brand list** otherwise, so the app works today and improves
  the moment the file is added to the target. A malformed file degrades to the fallback rather than
  crashing someone mid-aisle.

**Why the store catalog is bundled JSON and not codegen'd Swift:** `GeneratedBrandTable` is the
*menu* matcher, where a small curated list is a feature (a 30,000-SKU list would match menu text
like "Chardonnay" against one specific winery's bottling). Different job, different data, separate
artifact. Also, 30,000 `BrandEntry` literals would be wretched to compile.

**Next, unchanged in priority:** RevenueCat is still the critical path and still untouched. After
that: run the import, check `store_catalog.json` size on device (if it's large, consider a
prefix-indexed format or SQLite before shipping it), then the barcode scanner via
`StoreCatalog.product(withUPC:)`, which is already the seam it needs.

---

## STATUS (2026-09-05) — Store calculator (Goal 2) is built; **RevenueCat is now the critical path**

*Supersedes the 09-02 status note below re: next steps. The parser situation is unchanged — that note
is still accurate about OCR; ignore only its numbered next-step list, which items 3 and 4 have now
consumed.*

**Landed this session (Compare / store calculator, per owner's call):**
- `CoreServices/StoreSession.swift` (new, pure): `EditableProduct` (id, unit volume, count,
  `Provenance<Double>` ABV, optional `Price`) + `StoreSession` with `rankedProducts` /
  `needsPriceProducts` / add / setPrice / correctABV / setPackage / remove. Deliberately the same
  shape as `EditableDrink`/`MenuSession`, so both invariants read identically on the store side:
  a priceless package waits in its own bucket (§10), and a brand-seeded ABV is `.estimated` with a
  note until the shopper types the number off the can (§11).
- `StoreComparison` refactored to expose the shared `StoreValue` / `value(totalStandardDrinks:
  dollars:)` / `sortsBefore(...)` primitives; `rank` and `StoreSession.rankedProducts` both call
  them, so the one-shot and interactive paths can't drift. `ContainerSize` gained
  `Hashable`/`Identifiable` (so the app needs no retroactive conformance for its picker).
  **Behaviour is unchanged — the existing `StoreComparisonTests` should still pass verbatim.**
- `Tests/CoreServicesTests/StoreSessionTests.swift` (new, 12 cases): worked example (6× 12 oz at
  5% = 6.0 standard drinks → 0.60/$ → $1.67 per drink), the handle-beats-wine ordering, **parity
  with `StoreComparison.rank`**, name tiebreak, zero-alcohol → infinite $/drink, the two invariants,
  id stability across removal, stale-id no-ops.
- `AppTarget/Features/Shared/ValueChips.swift` (new): `SectionHeader`/`RankMedal`/`MetaChip`/
  `ProvenanceChip`/`PricePill` lifted out of `ResultsView` (they were `private`, so Compare couldn't
  reuse them) plus a `ValueFormat` namespace. `ProvenanceChip` now takes its labels, and `PricePill`
  its caption, so each screen names its own thing ("menu price" vs "pack price").
- `AppTarget/Features/Compare/` (new): `CompareViewModel` (thin `@MainActor` shell over
  `StoreSession`, same shape as `ResultsViewModel`) and `CompareView` — ranked shelf list reusing the
  Results row vocabulary, add-product form with a searchable **655-brand** picker off
  `BrandCatalog.all`, `ContainerSize.presets` + an "Other…" custom-ounces path, count stepper,
  per-row edit sheet, "Waiting on a price" bucket, and a store-flavoured calculation explainer.
  Entry point: a "Compare store prices" button on `CaptureHomeView` → `navigationDestination`.
- **Brand table regenerated** — `beverages.json` was already valid (the `2/.4` bug is fixed, 655
  brands) but `GeneratedBrandTable.swift` was still the stale **161-brand** build, so the picker and
  every brand-tier ABV lookup were missing ~494 products. Re-ran `Tooling/generate_brand_table.sh`.
  Checked first: all eight brand ABVs pinned by `BrandTableTests` resolve identically at 655.
  **One consequence, fixed:** `StaticBeverageKnowledgeTests.testSectionRefinesCategoryButChartKeepsABV`
  used "Community Mosaic IPA" as a stand-in for a *generic* IPA, but that beer is now a real entry in
  the 655-brand table at its true 7.5% — so the brand tier correctly beat the 6.5% IPA style chart
  and the test failed at 7.5 ≠ 6.5. The engine was right; the fixture was stale. Renamed to
  "Nonesuch Placeholder IPA" (verified absent from `beverages.json`) and the test now asserts
  `.styleChart` as the *tier*, so if a future JSON edit shadows it the failure says so instead of
  looking like a bad ABV. Watch for this whenever the dataset grows: two other fixtures
  ("Guinness Draught", "Weihenstephan") now resolve via the brand tier rather than the chart, but
  their ABVs agree (4.2 / 5.4) so those tests still pass on the same numbers.
- **`INFOPLIST_KEY_NSCameraUsageDescription` added** to both build configs. It was absent from
  `project.pbxproj` and there's no `Info.plist`, so "Take a photo" would have trapped on
  presentation — the camera path was never actually exercised on device.
- Cosmetic fix from the old list: the size chip now prints `1.5 oz` for a shot instead of rounding to
  `2 oz` (`ValueFormat.ounces`, one decimal only when the value isn't whole).

**⚠ Nothing here has been compiled** — it was written without a Swift toolchain. Run
`cd Core && swift test` and build `AppTarget` in Xcode first; the Core additions are pure and
inline-fixture tested, the SwiftUI is the part to eyeball. `Features/` is inside a
`fileSystemSynchronizedGroups` root group, so the two new folders need no `.xcodeproj` surgery.

**Suggested next steps (new session), in priority order:**
1. **RevenueCat — this is the schedule risk, not a feature.** Week 2 of the plan (Sep 8–14) is
   `remove_ads` IAP + entitlement gating + RevenueCat Ads + a Paywall screen, and *none* of it
   exists: no `Features/Paywall/`, no conformer for `PurchaseController`/`AdPresenter`. It's a
   Shipaton **qualification** requirement, the IAP has to be approved alongside the build, and the
   plan submits ~Sep 18–20. Everything else below is optional next to this.
2. Store-side polish if it survives device testing: the comparison doesn't persist across launches
   (no storage layer exists) — decide whether an aisle list should survive backgrounding.
3. `ImageDeskew` — **the file described in the 09-02 (part 6) note was never committed**; it isn't in
   `Infrastructure/`. It has to be written, not wired. Pair with the "retake straighter" capture hint.
4. Run 3–5 brand-new menus through the DEBUG OCR export; triage by failure class before coding.
5. Store screenshots + listing copy (informational price-comparison framing, R3).

---

## STATUS (2026-09-02) — OCR/parse pipeline is good enough; pivoting to breadth + other features

All five test menus now parse acceptably. M/G (the hard one) is confirmed on device: horizontal
banding done (part 7), superscript-cent prices + shared-grid inheritance (part 8), cocktail
back-fill + `$1s`/`gloss` fixes (part 9). IPAs rank ~0.26/0.21 std-drinks/$; beers keep prices;
cocktails back-fill from their own price lines. Owner's call: **stop tuning the parser on M/G** and
(a) test the pipeline on NEW menus to find the next real failure class, and (b) start building out
other app functionality.

**Known residuals (accepted, low value — don't chase without a new failing menu):**
- Fully OCR-shredded price tokens (`Sis"`, `Sir"`, `glass Sir"`) stay unpriced → "Not sure".
- The happy-hour beer mini-grid `16oz $5" | 220z 59*` isn't recognized (OCR typo'd `22oz`→`220z`,
  price `59*`), so those 3 happy-hour beers don't inherit.
- Occasional recipe line with 0 recipe-keywords (e.g. "tito's vodka ruby red grapefruit") lands in
  the "Not sure" bucket as a priceless item — harmless, never ranks.

**Suggested next steps (new session):**
1. Run 3–5 brand-new menus through the DEBUG OCR export; triage by failure class before coding.
2. Wire `ImageDeskew.flattened` into `VisionTextRecognizer` + a "retake straighter" capture hint
   (El Perrito angled-photo case — still PENDING from earlier).
3. Fix `Tooling/Data/beverages.json` `"abv": 2/.4` → `2.4` (blocks the brand-table generator).
4. Build the `AppTarget/Features/Compare/` store-calculator screen (StoreComparison is ready in Core).
5. Optional cosmetic: ResultsView size chip shows 1.5 oz (one decimal), not "2 oz", for shots.

Everything below is the detailed parser/assembler history; read newest-first as needed.

---

## 2026-09-02 (part 9) — Cocktail back-fill vs grid forward-inherit; $1s repair; gloss vessel

Second M/G device pass (post part 8): IPAs now rank correctly (~0.26, 0.21 std/$), but two bugs from
the part-8 grid change surfaced, both fixed in `MenuParser`:

**1. `Strawberry Fields $1` (price leaked forward).** The part-8 grid handler always set the section
`headerPrice` forward. That's right for DRAFTS (grid *leads* a list) but wrong for the Specialty
cocktails, which are laid out *name-then-price* (`Strawberry Fields` line, then `glass $14 | pitcher
$49`). Each cocktail's price line set a forward price that leaked onto the *next* cocktail's name.
Fix: the bare-grid branch now **back-fills** the smallest price onto the immediately-preceding
priceless, rankable name (`backfillIndex`) when one is waiting; it only forward-inherits when a
section header just started the block (DRAFTS, happy-hour). `backfillIndex` is cleared by any header
and by any priced emit, so a price never crosses a section or item boundary. Validated on the real
sequence: DRAFTS/happy-hour forward ($7/$9), every Specialty cocktail back-fills its own price
(Paloma $13, Full Bloom $15, Strawberry Fields $14, Espresso Martini $15).

**2. `gloss (pitcher) $13` ranked as a drink.** `gloss`/`pitchor` are Vision's misreads of
`glass`/`pitcher`; added them to `sizeWordTable` + `sizeOnlyWords` so the price line is a nameless
grid (→ back-fill) instead of a "gloss" item.

**Also:** `$1s"` (a superscript `5` read as `s`) now repairs to `$15` via `repairPriceDigits`
(`s→5`, `o→0`, applied only after the `$`); `barePriceGridSmallest` ignores stray `"`/`*`/`°` tokens
and requires a size cue or ≥2 prices; and a pure wine sub-label (`whites`/`reds`/`bubbles`) no longer
resets the shared `glass $14 | bottle $58` wine price (so those wines inherit ~$14 instead of falling
to "Not sure"). `Moët Impérial Brut` correctly stays $150 (ranks low, as it should).

New tests in `MenuParserConfidenceTests` (back-fill vs forward, `$1s` repair, `gloss` suppression).
Residual unchanged: OCR-shredded lines like `Sis"`/`Sir"` stay unpriced; the `16oz $5" | 220z 59*`
happy-hour beer grid isn't recognized (OCR typo'd size/price).

---

## 2026-09-02 (part 8) — Superscript-cent prices, bare grids, section-price inheritance (M/G)

Device re-dump of M/G after part 7 confirmed the banding fix (clean 138-line assembly; beers keep
prices, DRAFTS grid intact). Three follow-on parser bugs it exposed, all now fixed in `MenuParser`:

**1. Superscript-cent price garble.** M/G prints cents as tiny superscripts; Vision returns them as
junk (`$8°5`, `$10$5`, `$1055`, `$12"`, or bare `1025 1325 2825`). Old scanner took the *last* `$`/
number, so `$10$5` → $5 (with `$10` stranded in the name) and bare `2825` → $2825. New helpers
`leadingDigitString` / `normalizedDollars` / `dollarValue`: read the **first** `$`-anchored price,
tolerate a `$`→`S` misread and glued garble, and interpret a **4-digit** run as dollars-and-cents
(`1055`→$10.55, `1025`→$10.25, `2825`→$28.25). 1–3 digit runs stay face value so a real `$150`
champagne isn't halved (a 3-digit price is ambiguous; a mispriced pitcher just sinks harmlessly).
`parseItem` also gained a bare-4-digit path (`firstBarePriceToken`) so Guinness `…1025 1325 2825` →
$10.25 with name `Guinness Stout`. `classifyToken` now uses `dollarValue`.

**2. Known name freed.** Fixing `$10$5` also strips `$10` from the name, so `High Noon Pineapple`
resolves to the brand cleanly (was `High Noon Pineapple $10`).

**3. Shared size/price grid → section price.** DRAFTS lists each beer with no per-item price; the
`16oz $7 | 22oz $12 | Pitcher $25` grid prices them all. `barePriceGridSmallest` detects a nameless
size/price-only line and adopts its **smallest** (single-serving) price as the section `headerPrice`,
which the listed drafts inherit (Blue Moon, Stella, Michelob Ultra, etc. now rank instead of →"Not
sure"); the grid line itself is dropped. Guard: `isRankableName` now rejects a name made only of
section words, and `sectionWords` gained `bubbles`/`rosé`/`rose`/`rosados`, so a bare `whites`/`reds`
sub-label under an inherited wine price does **not** rank as a phantom $14 drink.

All paths validated in Python against the exact device lines and against regression lines (Southside
`BUDWEISER ABV 5% - 5.50`→$5.50, `Dogfish Head 60 MIN IPA … - 7.50`→$7.50 with `60` kept in name,
`House Cabernet glass $9 bottle $32`→2-size split). New tests in `MenuParserConfidenceTests`.
Residual (left, low value): the happy-hour mini-grid `16oz $5" | 220z 59*` isn't recognized (OCR
typo `220z`/`59*`), and OCR-shredded cocktail-price lines like `Sir"`/`Sis"` stay unpriced.

---

## 2026-09-01 (part 7) — Horizontal section banding (X-Y cut completed) for dense menus

**Problem.** Dense multi-section menus (the "M/G" case) stack different layouts in one vertical
strip — a `name │ size │ price` bottle grid above a specialty-cocktail list above a wine list, with a
shared-price draft grid on the right. The vertical-only cut sliced the bottle prices into a separate
pseudo-column (beers → priceless → "Not sure") and tore the draft price-grid apart.

**Fix (`LineAssembler`).** The recursive cut now alternates axes: `layoutBlocks` peels a **horizontal
section band** first (top-then-bottom) whenever a strong section-sized vertical gap exists, then falls
to the existing **vertical gutter** cut within each band. Isolating a section before column detection
means the confusing wide content from *other* sections is gone, so within the bottle band no vertical
cut fires (narrow price column fails the span guard) and each beer keeps `name size price` on one
line; the draft grid stays whole. New: `bestHorizontalSplit` + constants `minSectionGap` 0.03,
`sectionGapMultiple` 2.2 (gap must clear both the absolute floor AND 2.2× the region's median row
gap), `minBandRows` 2. `columnGroups` (vertical-only) is retained but no longer the entry point.

**Why it won't regress the working menus.** The horizontal cut only fires on a gap clearly larger
than a section's own line spacing, so a uniform single-section column (max gap ≈ median gap, ratio ~1)
never bands, and a lone-title top band fails the min-observation guard. Validated in Python
(`xycut.py`/`xycut2.py`) against a faithful full-structure M/G transcription (`mg_full.txt`, 192 obs):
M/G now segments correctly — every BOTTLES beer keeps its price, the DRAFTS grid + all draft names
survive (`Pacifico Clara`, `Guinness Stout...1025 1325 2825`), cocktails keep glass/pitcher price
lines, and Wine/Happy-hour/Food band cleanly. All 7 existing `LineAssemblerColumnTests` fixtures and
the Southside/Reservoir/Exclusive real-menu outputs are **unchanged**. New regression test:
`LineAssemblerRealMenuTests.testDenseMultiSectionMenuKeepsPricesWithSectionBanding` (real M/G coords;
asserts beers keep prices, draft grid intact, and no orphaned bare-price line).

**⚠ MUST device-verify.** This is the one change validated partly on hand-transcribed data (the M/G
full transcription is faithful but compressed; the Reservoir/Southside/Exclusive checks used earlier
*subsets*, whose omitted rows create phantom vertical gaps that don't perfectly mirror a full device
dump). Before trusting: re-run the DEBUG OCR export on **all five** menus on device and confirm none
of the four working menus regressed. If any do, this is a single self-contained commit — revert
`layoutBlocks`→`columnGroups` in `lines(from:)` to fall straight back to vertical-only.

---

## 2026-09-01 (part 6) — Food/URL dropped; cocktail math audited

**Food dropped entirely (`MenuParser`).** A food-section header ("FOOD", "KITCHEN", "Small Plates",
"Shareables" — `isFoodSectionHeader`, size adjectives allowed as filler) starts a drop region that any
drink-section header ends; plus a drink-SAFE dish gazetteer (`looksLikeFood`, exact-token match:
fries/cheeseburger/quesadilla/nachos/wings/tenders/parmesan/chicken/bites/…) drops stray dishes even
with no header. `taco`/`beer`/`tea`/`cheese` are deliberately excluded so the real beer *Off Color
"Beer for Tacos"* survives. Food is dropped outright (not shown for review). Fixes M/G ranking "Fries"
as a 12% ABV $8 drink.

**URLs/emails dropped (`looksLikeURL`).** Lines containing www./.com/.net/.org/:// are dropped — fixes
El Perrito ranking "WWW.ELFERRITOATX.COM" as a 40% shot.

Both are new drop paths at the top of `parse`, before item emission. Validated in Python against every
dump: all food lines + the URL drop, all 22 sampled real drinks (incl. Off Color Beer for Tacos, Sun
Cruiser Iced Tea, Twisted Tea) are kept. Tests added to `MenuParserConfidenceTests`.

**Cocktail-math audit (no code change — it's correct).** `standardDrinks = size × abv/100 ÷ 0.6`
(NIAAA 0.6 fl oz ethanol per standard drink). Cocktail estimate = 5 oz × 12% = **1.00** standard
drink, identical to a single 1.5 oz shot of 40% spirit (0.6 oz ethanol); shot estimate = 1.5 oz × 40%
= **1.00**; martini = 3.5 oz × 25% = 1.46. So "assume one shot" holds and value math is sound.
COSMETIC ONLY: the size *chip* in `ResultsView` rounds a 1.5 oz shot to "2 oz" (display formatting);
the calculation correctly uses 1.5. Consider formatting sub-2 oz sizes with one decimal.

*On-device re-scan: Reservoir, Southside, Exclusive all rank correctly now. Remaining problems were
the dense promo-heavy **M/G** menu (recipe/promo/header lines ranking) and the angled **El Perrito**
(bad OCR). Both addressed generalizably — validated the classifier across all 5 real dumps, not just
M/G, so it can't regress the working three.*

**Rank-eligibility gate (`MenuParser`), generalizable + casing-independent.** Two additions:
1. **Pure section labels are headers even when priced.** `sectionHeader` no longer bails just because
   a line has a price; `isPureSectionLabel` treats a line whose only substantive tokens are section
   words (+ a price / "each") as a header. Fixes "SHOTS 4" ranking as a $4 drink.
2. **`isRankableName` — decided by structure, NOT capitalization.** An early version gated on
   Title-Case, which would have broken on any bar that lowercases its menu (a real, common style).
   Reworked to a casing-independent predicate: a priced line ranks unless it is a *fragment* (no real
   word, or only vessel words like "glass"/"pitcher"), an *imperative/promo* line (lead word in
   `promoLeadWords`: make/add/ask/get/for/with/any/…), or a *recipe* (≥2 words in `recipeWords`:
   juice/syrup/fresh/squeezed/puree/…). A failing line keeps no price → visible "Not sure" bucket,
   never deleted. New sets: `sizeOnlyWords`, `recipeWords` (+ existing `promoLeadWords`).
Validated in Python against every dump's assembled lines **and lowercased copies of them**: output is
identical capitalized vs lowercased (Southside's beers rank either way), all promo/recipe/section junk
drops, and the working three don't regress. Because ranking needs a price and priceless lines already
route to review, the gate only had to catch *priced* junk. Tests: `MenuParserConfidenceTests`
(incl. `testLowercaseStyledMenuStillRanks`). El Perrito still ranks nothing (unreadable, all priceless
→ review) — correct.

**On identity / ML (design decision, keep it simple).** Evaluated using the 655-brand
`beverages.json` gazetteer + `StaticBeverageKnowledge` styles (all matched case-insensitively) and, as
an option, Apple's on-device `NLEmbedding`. Finding: the gazetteer + structural signals already handle
identity case-independently, so **embeddings were not adopted** — they'd add a framework dependency and
nondeterminism to help only novel un-listed cocktail names, which already degrade to a flagged
"estimated" rank (acceptable per product intent: guesses are fine when the menu is hard). If future
real menus show a systematic gap on un-gazetteered craft names, revisit with an on-device Core ML
line-classifier trained on labeled OCR exports — not an LLM (offline is a hard requirement). No change
to min iOS (NL/CoreML/`NLEmbedding` all back-compatible; nothing new was added).
DATA BUG found in `Tooling/Data/beverages.json`: `"abv": 2/.4` (Budweiser Select 55) is invalid JSON —
should be `2.4`; the brand-table generator will choke until it's fixed.

**Angled photos — perspective de-skew.** New shell file `Infrastructure/ImageDeskew.swift`
(compile-on-device; uses Vision + Core Image, untestable in sandbox): `VNDetectDocumentSegmentation`
finds the menu quad, `CIPerspectiveCorrection` flattens it, run BEFORE `recognizeObservations`. This
"twists" a tilted menu back to rectangular and recovers perspective-distorted text; it does not fix
genuine blur/low-res from a bad shot, so pair it with a "hold straight / retake" capture hint. Wire it
in `VisionTextRecognizer` by mapping the input image through `ImageDeskew.flattened(_:)` first.

---

## 2026-08-30 (part 4) — Real OCR dumps: word-level confirmed, gutter detector rebuilt

*Exported real word-level `[TextObservation]` from all 5 menus on device (via the DEBUG console dump
added to `VisionTextRecognizer`). This supersedes part 3's "word-level is the fix" as incomplete: it
fixed Southside but not the Reservoir. Every change below is validated in Python against the **real**
coordinates and ported.*

**Confirmed from the dumps:**
- **Word-level extraction works** — Vision returns clean per-word boxes (not degenerate whole-line),
  so the gutter geometry is real.
- **Southside**: assembles into ~47 clean columned lines. Fixed. ✓
- **Reservoir**: was still fusing DOMESTIC+IMPORT. Root cause: its gutter is crossed by a centered
  `BEER` title, a `bottles & cans` subtitle, and a full-width `MISC` section, so the coverage
  histogram never sees an empty channel. ✗ → now fixed (below).
- **El Perrito**: columns actually split fine; failure is pure OCR quality from the **angled** photo
  (`Sauza…fresh` → `chu8…tresh`). Not a code bug — needs a straight-on shot.
- **Exclusive**: single column correct, but `$` prices were OCR'd as letters (`......S13`,
  `BEER.....S-`); partially recovered (below), but fancy-font price glyphs remain unreliable.

**New gutter detector (`LineAssembler`), the core fix.** `bestVerticalSplit` now has two tiers:
1. **Coverage corridors / central** (primary, unchanged): a clean empty-corridor cut (any number of
   columns) or a central-gutter fallback. This correctly prefers the true inter-column gutter over a
   within-column name/price gap — the widest *passing* empty corridor is the one between columns —
   so it keeps the word-level two-column and N-column synthetics intact.
2. **Per-row gap voting** (fallback): used only when coverage finds nothing — i.e. when the gutter is
   bridged by centered text (Reservoir's `BEER` title, `bottles & cans` subtitle, full-width `MISC`
   section) so there's no empty corridor. Each visual row votes at the midpoint of every blank gap ≥
   `minGutterGap` (0.045) between adjacent words; votes are clustered and ranked, first passing the
   column guards wins. Centered/full-width rows are contiguous → cast no vote → can't hide the gutter.
   New helpers: `rankedGutters`, `rows(of:)`.
(Order matters: an earlier pass ran per-row-gap first and mis-split the word-level test by picking a
within-column name/price gap that was wider than the true gutter; coverage-first fixes that.)
Validated in Python against real Reservoir → 2 cols (DOMESTIC|IMPORT split), real Southside → 2 cols,
real Exclusive → 1 col, the word-level two-column test (lines intact), and synthetic 1/2/3/4-col,
title-spanning, and single-col-with-right-prices. Residual: a full-width section crossing the gutter
(Reservoir's MISC) gets its centered rows chopped at the split — acceptable (those items are mostly
N/A → excluded).

**Also:** `pureNumber` now tolerates `$`→`S` misreads (`S13` → 13) for trailing price tokens.

**Tests:** `LineAssemblerRealMenuTests` gains `testReservoirRealOCRSeparatesDomesticFromImport` (real
coords). Regenerate/verify with `cd Core && swift test`.

**Still open / next:** angled-photo OCR (El Perrito) — guidance is shoot straight-on; consider a
"retake straighter" hint when confidence is low. Fancy-font price glyphs (Exclusive) — hard. The
`Features/Compare` store-calculator UI and the token-noise/confidence pass remain queued.

---

## 2026-08-30 (part 3) — Real-menu testing: root-caused the multi-column failure

*Tested the build against 5 real menu photos. Only Southside "worked" — and even it was silently
broken (see below). This entry supersedes the R1 status in part 1.*

**The big finding: Vision merges columns before Core sees them.** On a two-column menu Apple Vision
reads straight across the gutter and returns each *physical row* as one line observation — so a
left-column draft and a right-column bottle arrive fused ("COORS LIGHT … 5 BUDWEISER ABV 5%"). No
amount of `LineAssembler` column logic can split a box that already contains both columns' text. This
is why every multi-column menu produced chimera rows (Southside's ranked list looked plausible but
every entry was two drinks mashed together; the Reservoir fused DOMESTIC with IMPORT).

**Fix — word-level bounding boxes (`VisionTextRecognizer`).** Instead of one observation per Vision
line, we now emit one per **word** via `candidate.boundingBox(for: range)`, with a whole-line
fallback if per-word geometry is unavailable. This restores the true x-positions, the inter-column
gutter reappears, and the existing X-Y cut separates the columns; `LineAssembler` rejoins words on a
row by vertical position. Shell code — **compile/behavior only verifiable on device.** Pure-side
proof: `LineAssemblerColumnTests.testWordLevelBoxesKeepTwoColumnsApart` feeds word-level boxes for a
Southside-like layout and asserts no cross-column fusion. NOTE residual risk: right-aligned prices
create a coverage-0 "canyon" between names and prices within a column that can rival a narrow
inter-column gutter; the widest+central heuristic handled every test case but watch real dumps.

**Parser fixes (pure, tested — `MenuParserSectionTests`):**
- **Dotted section totals** ("COCKTAILS........$13"): `sectionHeader` now treats a dot-leader run
  (2+ '.') like a pipe, so the price becomes the section header price and the drinks under it inherit
  it (fixes Exclusive Drink Menu, where WINES had become a $50 item and the cocktails fell to
  needsPrice). `hasDotLeaderRun` added.
- **Singular headers**: added DOMESTIC/IMPORT/CIDER/SELTZER to the lexicon (the Reservoir). Safe
  because the price guard still rejects priced item lines as headers.
- **`/` separator**: `replaceSeparators` now maps `/`→space, so "Miller High Life 16oz / 6" prices
  and cleans correctly.
- **N/A exclusion**: `looksNonAlcoholic` flags "N/A", "non-alcoholic", "zero proof" (NOT bare "zero" —
  "Mike's Zero Sugar" is alcoholic) on the raw line and tags the item `.nonAlcoholic`; `DrinkResolver`
  now hard-excludes any `.nonAlcoholic` item up front, before brand/style matching can re-rank it
  (fixes "Gruvi IPA N/A beer" ranking as a 6.5% IPA).

**Still limited:** angled/rotated photos (El Perrito) — Vision's axis-aligned word boxes get a
sloped baseline, so rows mis-group and OCR text degrades ("Sauza blanco, Cointreau, fresh" →
"chu8 blanco Cointreau tresh"). Guidance: shoot straight-on. The dense M/G menu is still hard.

**Next:** rebuild, re-scan the 5 menus. The DEBUG long-press OCR export now dumps **word-level**
observations — send those for any menu still failing and they become fixtures directly.

---

## 2026-08-30 — N-column OCR + multi-price rows; store-calculator pure core landed

*Supersedes the 08-27 note re: R1 column bound and re: the calculator being unstarted. Everything
here is pure `Core` code with `swift test` coverage; two shell pieces are deliberately deferred
(below).*

**Robustness (Goal 1, R1):**
- **`LineAssembler` now does a recursive X-Y cut** (was 1-or-2 column only). Handles 1/2/3/4-column
  and free-form layouts; splits at truly-empty corridors, suppressing spanning **headers/titles**
  from gutter detection (a full-width title no longer bisects the middle column), with a central
  fallback for a 2-column gutter bridged by a modest title. Guards (per-side count ≥ 3, span ≥ 0.18)
  still guarantee it never over-splits a single column at a name/price gap. Validated in Python
  against 7 layouts before porting; new tests: `testThreeColumnSplit`, `testFourColumnSplit`,
  `testSingleWideColumnNotSplit`, `testThreeColumnsUnderFullWidthTitle`. Added `TextBox.width`.
- **Multi-price rows → one ranked drink per size** (Decision, supersedes INSPECTION_FINDINGS §5's
  "smallest pour"). `MenuParser.splitMultiPrice` turns "Cabernet glass $9 bottle $32" into two items
  and "Bud Light 12oz $4 16oz $6 22oz $8" into three, each with its own price + size, ranked
  separately. Binds a size label before **or** after its price; two-price wine with no cue → smaller
  glass / larger bottle. Fires only on ≥2 `$`-prices, else the single-price path is untouched. Each
  emitted item carries a real `Price`, so the price invariant holds. Tests:
  `MenuParserMultiPriceTests`.

**Store calculator (Goal 2) — pure core done, UI deferred.** Per the design decision it's a
**separate** type sharing only the value formula:
- `ValueRanker.standardDrinks(sizeFloz:abvPercent:)` is now the one shared ethanol→standard-drinks
  primitive (the `PricedDrink` path delegates to it).
- `StoreComparison.swift` (new, CoreServices): `StoreProduct` (unitVolume × count, abv, packagePrice
  as a failable `Price`), `StoreComparison.rank` → `[RankedProduct]` sorted by standard-drinks-per-
  dollar, also surfacing **$/standard drink**; zero-alcohol sorts last without div-by-zero.
  `ContainerSize.presets` (12/16/19.2/24/25 oz, 187/375/500/750 mL, 1/1.5/1.75 L) for the picker.
- `BrandCatalog.all` (new, CoreContracts): public `[KnownBeverage]` (label/category/abv, alphabetical,
  de-duped) projecting the internal `generatedBrandTable` for the brand dropdown.
- `Volume` gained a pure `liters` bridge. Tests: `StoreComparisonTests`, `BrandCatalogTests`.

**Deferred to next session (shell-only, not sandbox-testable — need device + visual iteration):**
1. **`AppTarget/Features/Compare/`** SwiftUI screen: add-product form (brand dropdown from
   `BrandCatalog.all`, size from `ContainerSize.presets`, count/abv/price fields) → `StoreComparison`
   ranked list reusing `ResultsView`'s `RankRow`/chips; entry point button/tab on `RootView`.
2. **Token/OCR-noise + per-line confidence** pass (price ranges, O↔0, more size spellings, header
   lexicon, low-confidence → "Not sure" bucket) — now unblocked by the export affordance below; do it
   fixture-by-fixture against real dumps.

**OCR-export debug affordance — DONE (this session, part 2).** `ObservationFixture` (new, CoreServices,
pure + tested) serializes `[TextObservation]` into a paste-ready Swift literal for a `LineAssembler`
test plus a readable dump (positions + current assembled lines). Shell: `VisionTextRecognizer` now
exposes `recognizeObservations(in:)`; `CaptureHomeView` keeps the last scanned image and, in **DEBUG
only**, a 0.8s **long-press on the menucard logo** re-runs Vision and opens `OCRDebugExportSheet`
(share/copy). Release builds don't include the trigger.

**Workflow for the ~5 sample-menu photos (how to turn them into regression tests):**
1. In a DEBUG build, scan/pick a photo, then long-press the logo → Share/Copy the export.
2. Paste the `let observations: [TextObservation] = [...]` block into a new test in
   `LineAssemblerColumnTests.swift` (or a per-menu file); assert `LineAssembler.lines(from:)` groups
   the rows/columns correctly — this is what locks in the X-Y-cut behavior against real geometry.
3. The dump's "LineAssembler.lines output" section shows the current result, so a bad split is
   visible immediately and tells you whether it's a column bug (fix `LineAssembler`) or a parse/size
   bug (fix `MenuParser`). Feed recurring OCR noise into the deferred token-noise pass (#2 above).

**Verify:** `cd Core && swift test` (all new tests are pure/inline-fixture). Files touched:
`CoreModel/TextBox.swift`, `CoreModel/Volume.swift`, `CoreServices/LineAssembler.swift`,
`CoreServices/MenuParser.swift`, `CoreServices/ValueRanker.swift`, `CoreServices/StoreComparison.swift`
(new), `CoreContracts/BrandCatalog.swift` (new), + 4 test files.

---

## 2026-08-27 — Capture flow live on device; results editable; OCR hardened

*Supersedes the notes below re: current state and next step.*

**State:** the app runs end-to-end on device. Point the camera (or pick from the library) → Apple
**Vision** OCR (`VisionTextRecognizer` behind `TextRecognizer`) → `LineAssembler` reassembles rows
(and now **columns**) → `MenuParser` → `MenuSession` → a ranked, **editable** list behind a 21+ gate.
Estimates are one-tap correctable, prices are editable, priceless/low-confidence lines sit in a **"Not
sure about these"** bucket, and the user can **add a drink the scan missed** or **remove** a misread
one. Results now show the menu price alongside a clearly-labelled per-standard-drink cost, with a
formulas explainer.

**Verify (engine):** `cd Core && swift test` — now also covers `LineAssembler` column detection,
`MenuParser` name-cleanup + `drafts`/`cans` headers, the editable `MenuSession`, and manual add/remove.
**Run (app):** build `AppTarget` in Xcode against the local `Core` package; needs
`NSCameraUsageDescription` in `Info.plist`. iOS 16 target.

**R1 status:** OCR is materially better — two-column layouts split correctly and item names are clean.
Still bounded v1: genuine 3+ column or free-form layouts fall back to fewer columns, and the manual
add/edit path remains the safety net. Tunable knob if rows merge/over-split on a specific photo:
`LineAssembler.lines(rowToleranceFraction:)` (default 0.5).

**Next — monetization (Week 2):** RevenueCat `remove_ads` IAP + RevenueCat Ads, implemented in
`AppTarget/Infrastructure/` behind the existing `PurchaseController` / `AdPresenter` contracts — no
`CoreServices` change. Owner-only setup first: App Store Connect record, RevenueCat project +
`remove_ads` product, ad-network alcohol-policy check (R3). Then the App Store listing (informational
price-comparison framing, 21+ gate already in place) and submission with a resubmit buffer (R5).

**Icon:** iOS uses a 1024×1024 PNG in `Assets.xcassets/AppIcon` (single-size), not `.ico` — flatten
any alpha before shipping (App Store rejects alpha).

---

## 2026-08-25 — Phase 5 + demo app landed (end-to-end)

*Supersedes the notes below re: current state and next step.*

**State:** the pure value engine is complete — `MenuParser` → `ABVEstimator`/`SizeEstimator` →
`ValueRanker`, assembled by `MenuPipeline` (`[String] → MenuAnalysis`). A minimal SwiftUI **demo
app** in `AppTarget/` runs that pipeline on bundled sample menus and shows the ranking, provenance
notes, and the needsPrice / excluded-non-alcoholic buckets — runnable on device via
`AppTarget/HOW_TO_RUN.md` (no camera yet).

**Verify (engine):** `cd Core && swift test`. **Run (app):** follow `AppTarget/HOW_TO_RUN.md`.

**Parser is bounded v1 (R1).** It handles the common menu shapes (see `MenuParserTests`), not every
layout; the manual add/edit path is the intended safety net for misreads.

**Next — the real capture flow (Week 1):** `VisionTextRecognizer` implementing `TextRecognizer`
(`VNRecognizeTextRequest`, on-device), a camera/photo picker, the **21+ gate** (R3), and inline
correction that promotes an estimate to `.read` and re-ranks. The engine doesn't change — only the
source of the OCR lines. Then monetization (Week 2): RevenueCat `remove_ads` + RevenueCat Ads behind
the existing `PurchaseController`/`AdPresenter` contracts.

---

## 2026-08-25 — Phase 4 landed (ValueRanker)

*Supersedes the notes below re: current state and next step.*

**State:** `ValueRanker` (CoreServices) computes standard-drinks-per-dollar (v1) and
calories-per-dollar (v2) and sorts best-first, taking `[PricedDrink]`. The doc's worked example is a
test. The whole value engine is now provable headless: brand/style/fallback knowledge → priced,
alcoholic drinks → ranking.

**Verify:** `cd Core && swift test`.

**Next (Phase 5 — parser + estimators):** the section-state `MenuParser` (Change A: header-priced
sections), `ABVEstimator`/`SizeEstimator` wiring `StaticBeverageKnowledge` (read-if-printed, else
estimate), the `needsPrice` split, and the description-line suppression (Finding 4). Designed against
`Tooling/Fixtures/` + a Vision-noise pass (real OCR is messy, per your note). This is the last pure
phase; after it the value engine is end-to-end from OCR lines to a ranked list, still with no UI.

---

## 2026-08-25 — Brand table added (data-driven, 161 brands)

*Supersedes nothing structural; extends Phase 3.*

Brand data now lives in `Tooling/Data/beverages.json` (script-readable) and is codegen'd to
`GeneratedBrandTable.swift` by `Tooling/generate_brand_table.sh`. Lookup order is now **brand →
style → category fallback**, each flagged via `EstimateSource` (`.brandMatch` / `.styleChart` /
`.categoryFallback` / `.unclassifiedFallback`). To change the data: edit the JSON, run the generator,
`swift test`.

---

## 2026-08-25 — Phase 3 landed (CoreContracts + sourced knowledge)

*Supersedes the notes below re: current state and next step.*

**State:** four protocols in `CoreContracts` (Foundation-free), the sourced `StaticBeverageKnowledge`
(style chart → category fallback, flagged by `EstimateSource`), and test doubles. New `CoreContractsTests`
target. Data provenance is documented in `docs/BeverageDataSources.md`.

**Design note (per your ask):** ABV/size are sourced (NIAAA + BJCP/Wine Folly), and the app is honest
about confidence — `.styleChart(matched:)` when a style/varietal matched, `.categoryFallback` when it
didn't. The menu's printed value still wins over both.

**Verify:** `cd Core && swift test` — now includes `CoreContractsTests`.

**Next (Phase 4 — ValueRanker):** the standard-drinks-per-dollar metric + sort, taking `[PricedDrink]`,
with the worked-example test and the price-invariant test (§8). No photos needed.

**Then Phase 5 (parser + estimators):** wires `StaticBeverageKnowledge` into `ABVEstimator`/`SizeEstimator`
and adds the section-state `MenuParser` (Change A), designed against the fixtures + a Vision-noise pass.

---

## 2026-08-25 — Phase 2 landed (CoreModel spine)

*Supersedes the notes below re: current state and next step.*

**State:** the spine is built in `Core/Sources/CoreModel` — `Provenance<T>`, `Price`, `Volume`,
`BeverageCategory`, `MenuItem`, `DrinkOption`, `PricedDrink`, `RankedDrink`, `ValueMetric` — with
`CoreModelTests` mirroring it 1:1. Two invariants are now enforced by type:
- **Price (§10):** non-positive/absent amounts can't make a `Price`; `DrinkOption.price` is
  non-optional, so a priceless line can't become a rankable drink.
- **Change B:** `PricedDrink.init?` rejects `.nonAlcoholic` — a priced mocktail can't be ranked.

The value *formulas* are deliberately NOT in the model — they land in `ValueRanker` (Phase 4).

**Verify:** `cd Core && swift test` on your Mac (I can't run Swift in my environment).

**Next (Phase 3 — CoreContracts):** the four protocols (`TextRecognizer`, `BeverageKnowledge`,
`PurchaseController`, `AdPresenter`) + a pure `StaticBeverageKnowledge` seeded from
INSPECTION_FINDINGS §Finding 3, and a `FakeTextRecognizer` test double.

**Still waiting:** nothing blocking Phases 3–4. Phase 5 (parser) will use the fixtures + a
Vision-noise pass (per your note that real input is on-device OCR, not clean transcription).

---

## 2026-08-25 — §5 inspection done; two design changes folded in

*Supersedes the Phase-1 note below only re: the Phase 2/5 plan (adds Changes A & B).*

16 real menus transcribed to `Tooling/Fixtures/` (`INSPECTION_FINDINGS.md` has the full
write-up). R1's main input is now real, not remembered. Two changes to carry forward:

- **Change A (Phase 5):** `MenuParser` is a **section-state machine**, not a per-line map —
  some menus price only on the section header (Rullo's `Elixirs | $14`). Still pure/testable.
- **Change B (Phase 2):** add `.nonAlcoholic` to `BeverageCategory`; those items are dropped
  before ranking (they have a price, so the price invariant won't catch them). Everything
  else in the spine is unchanged.

Also confirmed printed ABV/size is common (beer/wine), so the `.read` path is well-used.
**Next unchanged:** Phase 2 (CoreModel) — now including the `.nonAlcoholic` case.

---

## 2026-08-25 — Phase 1 landed (scaffolding + doc set)

*Supersedes nothing (first note).*

**State:** repo skeleton is up, laid out by layer/role (§3). `Core` SPM package compiles and
`swift test` is green on placeholder sources. Full §2 doc set exists. `.gitignore` and the
`run_checks` gate are in place. The two authored design docs (`Architecture.md`,
`ProjectConventions.md`) are placed verbatim in `docs/`.

**Environment note:** the value engine is being generated as source to build on a Mac (and
`swift test` runs on plain Linux since `Core` is framework-free). No Xcode/iOS SDK was used
to produce it.

**Next (Phase 2 — CoreModel):** implement the spine — `Provenance<T>`, `Volume`,
`BeverageCategory`, `MenuItem`, `DrinkOption`, `PricedDrink`, `RankedDrink`, `ValueMetric`
— with `CoreModelTests`. Then Phase 3 (contracts), Phase 4 (ValueRanker + metric).

**Blocked / waiting:** **Phase 5 (MenuParser + estimators) needs real menu photos** to
transcribe into `Tooling/Fixtures/` (§5, R1). Upload them any time before we reach Phase 5;
Phases 2–4 don't need them.

**Open decisions deferred to Week 1:** AppTarget Xcode-project generation approach
(`.xcodeproj` vs XcodeGen/Tuist vs SPM-app); min iOS version; then account actions only the
owner can do — App Store Connect record, RevenueCat project + `remove_ads` product, Devpost
registration.

**Naming:** canonical name is `BangForBuck` (per the design doc); "brewforbuck" is the
marketing tagline from the original README.

---

## Recipes — "how to add a new ___" (§14)

### Add a new ranking metric (the one you'll reuse — Architecture §14)
1. Add a case to `ValueMetric` (e.g. `.caloriesPerDollar`).
2. Add the pure formula to `ValueRanker` (it already has `pure_ethanol_floz`).
3. Add a `ValueRankerTests` case with a worked example.
4. Add a segmented toggle in the Results feature. **No other layer changes.**

### Add / swap an external dependency (OCR engine, purchase backend, ad network)
1. It already has a protocol in `CoreContracts`. Write one new type conforming to it in
   `AppTarget/Infrastructure/` (§6).
2. Inject the real conformer at app startup; inject a fake in tests.
3. No `CoreServices` change — the core depends on the protocol, never the concrete impl.
