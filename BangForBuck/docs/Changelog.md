# Changelog

*Append-only history (§2). Newest on top. The Handoff is the live "where we are"; this is
the log — don't let them merge.*


## 2026-09-09 · Monetization: supporter purchase, pure paywall layer, ads cut from v1

**Two findings that changed the design.** Verified against vendor docs, not memory.
**RevenueCat Ads is not an ad network** — it is a beta analytics feature with experimental APIs that
reports impressions and revenue alongside an ad SDK you already have, and serves nothing.
`Architecture.md` §A described a product that does not exist. **AdMob cannot serve before the app is
live**: Google requires the app to be published, listed and linked before it fully serves ads, new
iOS apps do not serve until listed, and linking is widely reported to lag by days. A banner in the
submitted build would be an empty frame, and there is a documented rejection pattern for exactly
that. **v1 therefore ships the purchase only**; the Shipaton rules qualify on one IAP alone. Side
benefit: no ad SDK means no IDFA, no ATT prompt, no UMP consent form, no `app-ads.txt`, and privacy
labels that honestly say no data collected. New `AdsPlan.md` covers v1.1.

- **The product is a tip jar priced in drinks, not a "Remove Ads" unlock.** Three non-consumables —
  `supporter.shot` $1.99, `supporter.pint` $4.99, `supporter.round` $9.99 — all granting one
  `supporter` entitlement, so any tier grants the same thing. Named after drinks because the app is
  denominated in dollars per standard drink; names live in App Store Connect so they localize.
  Called `supporter` rather than `remove_ads` deliberately: v1 has no ads and selling an absent
  feature is a rejection risk, while v1.1's ad gate can check this same entitlement with no second
  product and no migration.
- **`PurchaseController` rewritten.** The plan named two protocol gaps; one was confirmed, one was
  mis-framed, and two more were found. Now `supporterTiers()` / `purchase(_ tier:)` /
  `restorePurchases()` / `supporterStatus()`, with `SupporterTier`, `SupporterStatus`,
  `PurchaseOutcome` (incl. `.pending` for Ask to Buy) and `RestoreOutcome` (incl.
  `.nothingToRestore`, the case a `Void` return could not report). `purchase` takes the displayed
  tier so the amount charged is provably the amount shown, and **`displayPrice` is a `String` from
  the store, never a number** — there is no numeric price anywhere in `Core`. This is §10 turned on
  our own money.
- **`AdPresenter` and `NoopAdPresenter` deleted, not revised.** The protocol's problem was not its
  shape but being designed against an SDK nobody had used. The plan's proposed fix — a factory
  vending a view — would have broken the boundary outright, since AdMob's banner is a `UIView` and a
  `CoreContracts` protocol cannot return a `UIViewRepresentable` without `Core` importing SwiftUI.
  **The banner has no `Core` representation at all**; `Core`'s only stake in ads is one boolean.
- **New pure layer in `CoreServices`.** `PaywallFlow` is the whole paywall as one function,
  `next(from:on:)`, with every state that can return to the tier list carrying the tiers, and
  inapplicable events returning the state unchanged so a late reply cannot resurrect a dismissed
  sheet. There is deliberately **no state meaning "showing prices I do not have"**: a failed fetch
  becomes `.unavailable` with a retry. `SupporterPrompt` holds the four ask rules — never a
  supporter, never twice, **never on a thin read**, never without a comparison — so the app does not
  ask for money after a read it does not trust. `SupporterTierKind` resolves the granting product by
  suffix into a closed set, so an unrecognized tier degrades to a plainer badge rather than a wrong
  one.
- **New `AppTarget/Features/Supporter/`.** `SupporterStore` (the only impure piece: one entitlement
  read plus one persisted "already asked" flag), `PaywallView`, `SupporterBadge`,
  `SupporterPromptRow`, and seven previews covering tiers ready, store unavailable, failed purchase,
  Ask-to-Buy hold, existing supporter, nothing-to-restore and the prompt row. Wired through
  `ABVApp` → `RootView` → `CaptureHomeView` (badge under the wordmark) → `ResultsView` (prompt above
  the explainer, shown only after a ranking of at least two drinks).
- **Amber formally reserved.** The supporter badge and the paywall's messages use green and muted
  text rather than `Theme.amber` or the `Notice` component, so an amber element anywhere in the app
  still means exactly one thing: this number is an estimate.
- **Cut: the value-spread line.** `MenuValueSpread` and `SupporterPrompt.isWorthMentioning` are
  built, tested and currently unused. The original version multiplied a tier price by a
  drinks-per-dollar rate, which mixes the customer's storefront currency with the menu's and produces
  a confident wrong number outside the US store; the dimensionless ratio that replaced it was then
  cut as a flourish. Kept only for a possible share card.
- **`ContentView.swift` deleted.** Unreferenced, superseded by `RootView` + `CaptureHomeView`, and
  independently broken: it held one `ResultsViewModel` and passed a second, fresh one to
  `ResultsView`, so its `load()` wrote to a view model nothing displayed.
- **`swift test` 264 → 316.** `ContractsSmokeTests` 3 → 13, plus `PaywallFlowTests` (18),
  `SupporterPromptTests` (15) and `MenuValueSpreadTests` (9). `Core` still has no monetization
  dependency and still builds on Linux.
- **XCTest gotcha recorded.** `XCTAssertEqual` and friends take a non-async autoclosure, so
  `XCTAssertEqual(await thing(), x)` does not compile. Every `await` now lands in a `let` before the
  assertion. This broke an entire test file at once and is now in `ProjectConventions.md` §8.
- **Store setup started.** Paid Apps Agreement signed; banking pending "Clear", which blocks all
  purchase testing including sandbox. App ID `NovalCo.BangForBuck` registered explicitly with **no
  capabilities** (In-App Purchase is automatic; the camera is an Info.plist string). Product
  localizations done; review screenshots pending the paywall they must depict. Noted that SDK 5.x
  needs an **In-App Purchase Key**, not the App-Specific Shared Secret, or transactions silently
  fail to record.
- **Docs.** `MonetizationPlan.md` rewritten as the design of record; new `AdsPlan.md` and
  `ShipatonSubmission.md`; `Risks.md` gains a corrected R3, a reduced R5, and new **R6** (App Store
  Connect refusing to attach a first IAP to a version) and **R7** (the RevenueCat credential failing
  silently); `Architecture.md` §3/§4/§6/§13/§A/§B corrected; `CodebaseReference.md`, `README.md` and
  `PlainLanguageGuide.md` updated; `ProjectConventions.md` gains four generalizable lessons.

## 2026-09-05 · Menu scanner on the shared catalog; metric container sizes
- **`CatalogBackedKnowledge` + `CatalogMatcher` (CoreServices):** the menu scanner now consults the
  same bundled product catalog as the store calculator, behind a strict match rule (one name
  contains the other whole, two-word minimum, at least one shared non-generic word) so a menu line
  naming a *category* keeps its style-chart estimate instead of inheriting a specific producer's
  ABV. Tier order: curated brand table → catalog → style chart → category fallback. The catalog's
  bottle size is never used for a menu pour. Wired into all three view models; an empty catalog is a
  no-op. 11 tests.
- **`ValueFormat.volume(_:)`:** bottle sizes now display in mL/L (750 mL, 1.75 L, 187 mL) while
  cans, pours and shots stay in ounces. A clean whole number of ounces takes priority, which stops a
  60 oz pitcher reading as "1.75 L" and a 24 oz can as "700 mL". Package totals follow the container
  unit, and the exact-size edit field switches to mL for bottles and converts both ways.
- Fixed `ResultsViewModel` building a throwaway second `MenuPipeline` in its init.

## 2026-09-05 · Search performance and name folding on the 16,730-product catalog
- **`InMemoryStoreCatalog` rewritten for speed:** names are precomputed into folded `[UInt8]` arrays
  with word-start offsets, so a query allocates nothing per product. The previous version built a
  `[Character]` array per product per keystroke (~50,000 allocations per typed character over the
  real catalog), which showed up as lag with an idle CPU gauge.
- **Name folding fixed real misses too:** accents stripped so "moet" finds "Moët"; apostrophes and
  periods deleted so "titos" finds "Tito's" and "vsop" finds "V.S.O.P."; separators folded to spaces
  so "chateau margaux" finds "MARGAUX - CHATEAU MARGAUX 2014". Six new tests.
- **Importer sanitizes invisible characters** (variation selectors, zero-width spaces, directional
  marks, BOM, soft hyphens, controls) and normalizes curly quotes and dashes, which clears a stream
  of benign CoreText "variant selector" console warnings.
- Compare search now needs 2 characters, matching the quick comparison.

## 2026-09-05 · Store catalog sourcing: BC LDB open data + barcode join
- Found a comprehensive open ABV source: the **BC Liquor Distribution Branch** monthly price-list
  CSV carries name, ABV, container litres, pack count, and UPC on ~10,000 SKUs including thousands
  of wines. Schema verified against the live April 2026 resource.
- `Tooling/build_store_catalog.py` rebuilt around it (`--bcldb`, `--plcb`, `--off`,
  `--drop-without-abv`, `--dry-run`), including an `enrich_by_upc` join so a PLCB shelf SKU with no
  percentage inherits one from the BC row with the same barcode. Tested end to end on real BC rows.
- `docs/StoreCatalogSources.md` (new): sources, verified schema, licence position, rebuild commands,
  and why the store catalog stays separate from the curated menu brand table.
- Prices still deliberately excluded.

## 2026-09-05 · Quick comparison (menu drinks) + shared comparison UI
- **New feature, `Features/Quick/`:** type two to five drinks off a menu with their prices and see
  them ranked by standard drinks per dollar. Defaults to a single serving (5 oz wine pour, 1.5 oz
  shot, 12 oz beer) rather than a package, with autofill from the same catalog and from the style
  chart for drinks no catalog carries. Size changes with one tap via a pour-preset chip strip. Soft
  cap of five, with a pointer to the store calculator beyond that.
- **Runs on the same pure `StoreSession`** as the store calculator, so identical numbers can never
  rank differently and the price invariant lives in one place (§10).
- **`PourDefaults` (CoreServices):** reads a pour off the menu wording, else borrows
  `BeverageKnowledge.typicalSize`, else 12 oz. "Glass" and "bottle" only count where the category
  settles the volume. `ContainerSize.pourPresets` and `closest(toFluidOunces:among:)` added.
- **Shared UI extracted:** `RankedValueRow`, `ProductEditSheet`, `SizeChipPicker`, plus `PriceText`
  and `ValueFormat.editable`. `CompareView` refactored onto them and lost its private duplicates.
- Tests: `PourDefaultsTests`. Not yet compiled.

## 2026-09-05 · Search-first store calculator, package inference, catalog import path
- **Search first:** the add flow opens on a focused search field over the catalog; picking a result
  pushes a prefilled form. `StoreCatalog` contract + `CatalogProduct` (CoreContracts) and
  `InMemoryStoreCatalog` (CoreServices) with five-tier ranked search and digits-only UPC lookup.
- **`PackageDefaults`:** infers container and pack count from catalog data, then the product name,
  then the category. Wine and spirits open at 750 mL, beer at a 12 oz six pack, seltzer at twelve.
  Size matching uses unit-normalized tokens so a vintage year is not a bottle size and "Handley
  Cellars" is not a handle. `ContainerSize` gained 50/200 mL presets and nearest-preset lookups in
  both mL and fl oz, so a 14.9 oz can keeps its own label.
- **Em-dashes removed** from all user-facing copy, including `BeverageKnowledge.abvNote`.
- **Catalog import path:** `Tooling/inspect_store_catalog.py` (dump the real schema first) and
  `Tooling/build_store_catalog.py` (PLCB wholesale catalogs + Open Food Facts →
  `store_catalog.json`; no prices by design). `BundledStoreCatalog` loads it if present and falls
  back to the curated 655-brand list otherwise.
- Tests: `PackageDefaultsTests`, `StoreCatalogSearchTests`. Not yet compiled.

## 2026-09-05 · Store calculator (Goal 2) + brand table regenerated
- **`StoreSession` (new, pure CoreServices):** the interactive store calculator — `EditableProduct`
  (unit volume × count, `Provenance<Double>` ABV, optional `Price`) and a session with
  `rankedProducts`, `needsPriceProducts`, and pure edits. Same shape as `EditableDrink`/`MenuSession`
  so both invariants hold identically on the store side: a priceless package can't rank (§10), and a
  brand-seeded ABV stays flagged `.estimated` until the shopper types the real one (§11).
- **`StoreComparison` scoring extracted** into `StoreValue` + `value(totalStandardDrinks:dollars:)`
  + `sortsBefore(...)`, shared by the one-shot `rank` and the session so the two ranking paths can't
  disagree; a parity test pins it. `ContainerSize` is now `Hashable`/`Identifiable`. No behaviour
  change to existing `StoreComparison` output.
- **`Features/Compare/`:** `CompareViewModel` + `CompareView` — ranked shelf list, add-product form
  with a searchable 655-brand picker (`BrandCatalog.all`), `ContainerSize.presets` plus a custom-oz
  path, count stepper, per-row edit sheet, "Waiting on a price" bucket, calculation explainer.
  Reached from a "Compare store prices" button on `CaptureHomeView`.
- **`Features/Shared/ValueChips.swift`:** `SectionHeader`/`RankMedal`/`MetaChip`/`ProvenanceChip`/
  `PricePill` lifted out of `ResultsView` (they were `private`) so both ranked lists share one visual
  vocabulary, plus a `ValueFormat` namespace. Fixes the size chip rounding a 1.5 oz shot to "2 oz".
- **Brand table regenerated:** `beverages.json` had grown to 655 valid brands but
  `GeneratedBrandTable.swift` was still the stale 161-brand build, so the brand tier was missing ~494
  products. All eight brand ABVs pinned by `BrandTableTests` verified unchanged at 655.
- **`INFOPLIST_KEY_NSCameraUsageDescription` added** to both build configs — it was missing entirely,
  so the camera picker would have trapped on presentation.
- Tests: `StoreSessionTests` (12 cases). *Not yet compiled — written without a Swift toolchain.*

## 2026-08-30 → 2026-09-02 · OCR/parse hardening against five real menus (consolidated)
*Backfilled from the Handoff, which had been carrying this history directly (§2 says it shouldn't).
See the Handoff's dated parts 3–9 for the full reasoning on each change.*
- **Word-level OCR boxes (part 3):** Vision returns one observation per *physical row*, fusing
  columns; `VisionTextRecognizer` now emits one per **word**, restoring the inter-column gutter.
  Plus dotted section totals, singular section headers, `/` separators, and N/A exclusion.
- **Gutter detector rebuilt (part 4):** real word-level dumps from all five menus exported on device;
  `bestVerticalSplit` gained a two-tier design — coverage corridors first, then per-row gap voting
  for a gutter bridged by centred text (the Reservoir's `BEER` title). `pureNumber` tolerates `$`→`S`.
- **Food/URL dropped, cocktail math audited (part 6):** food-section drop regions + a drink-safe dish
  gazetteer, `looksLikeURL`, a casing-independent `isRankableName` rank-eligibility gate, and pure
  section labels treated as headers even when priced. Embeddings/ML evaluated and **declined** —
  the gazetteer plus structural signals already handle identity offline.
- **Horizontal section banding (part 7):** `layoutBlocks` alternates axes — peel a horizontal section
  band, then cut vertical gutters within it — so a dense multi-section menu stops slicing bottle
  prices into a pseudo-column. Validated in Python against a full M/G transcription; all seven
  existing column fixtures unchanged.
- **Superscript-cent prices + shared grids (parts 8–9):** first-`$`-anchored price reading with
  4-digit dollars-and-cents interpretation (`1025`→$10.25), `$1s`→`$15` digit repair, nameless
  size/price grids adopting their smallest price as a section price, and a back-fill vs
  forward-inherit split so a cocktail's own price line doesn't leak onto the next cocktail's name.
  `gloss`/`pitchor` added as vessel-word misreads.
- Net: all five test menus parse acceptably; IPAs rank ~0.26/0.21 std-drinks/$. Known residuals
  (fully OCR-shredded price tokens, one happy-hour mini-grid with a typo'd size) accepted as low
  value. Tests: `LineAssemblerRealMenuTests`, `MenuParserConfidenceTests`, `MenuParserMultiPriceTests`.
- Also in this window: recursive X-Y cut for 1–4 columns, multi-price rows → one ranked drink per
  size, the pure `StoreComparison`/`BrandCatalog` store core, and the DEBUG OCR-export affordance
  (`ObservationFixture` + long-press on the logo).

## 2026-08-27 · R1 hardening + results clarity + manual add/remove
- **Two-column menus (R1):** real on-device scan of a two-column bar menu (Southside Braintree) fused
  a left-column draft with a right-column bottle into one line. `LineAssembler` now detects columns
  before assembling rows — an x-coverage histogram finds the low-coverage central **gutter** (robust
  to a centered title/footer that spans it) and splits left/right, guarded by per-column count (≥3)
  and width (≥0.18) so a single column with right-aligned prices is never mis-split. `MenuParser`
  gained `cleanName` (strips embedded `ABV x%`, `>.5%`, `22oz.`, and stray dashes from names so
  "COORS LIGHT 22oz. ABV 4.2%" reads as "COORS LIGHT" — ABV/size still captured on their own axes)
  and recognizes `drafts`/`draft`/`cans` section headers. Tests: `LineAssemblerColumnTests`,
  `MenuParserHardeningTests` (incl. an end-to-end two-column "no chimera" test).
- **Results clarity:** each ranked row now shows the **menu price** explicitly and labels the derived
  cost as **per standard drink** (e.g. "≈ 0.9 standard drinks · $9.44 per standard drink"), removing
  the "$/drink looked wrong vs the sticker" confusion. Added a "How this is calculated" explainer with
  the formulas. The standard-drink count is derived from the ranking value, so it can't drift from it.
- **Manual add / remove:** new pure `MenuSession.addDrink(...)` / `removeDrink(id:)` — add a drink the
  scan missed (all axes `.read`; category coerced alcoholic so Change B still holds) or remove a
  misread line. Surfaced in `ResultsView` as a "+" add sheet, per-row remove in the renamed **"Not
  sure about these"** section (was "Needs a price"), swipe-to-delete, and a "Remove" action in the
  edit sheet (which now also edits price, not just ABV/size). Tests: `MenuSessionManualEntryTests`.
- **UI pass:** `ResultsView` reworked from stock list rows to medallion ranks, chip-based metadata,
  explicit menu-price pill, empty state, and section headers with icons. iOS 16 target throughout.

## 2026-08-27 · Capture flow — Vision OCR, camera/library, 21+ gate (Week 1)
- `AppTarget/Infrastructure/VisionTextRecognizer.swift` implements `TextRecognizer` with
  `VNRecognizeTextRequest` (`.accurate`, on-device), decoding PNG → `CGImage` → observations off the
  main thread. Contains the `CapturedImage(uiImage:)` bridge (PNG-encoded so EXIF orientation is baked
  in and text isn't read rotated).
- New pure `CoreModel/TextObservation.swift` (`TextObservation` + normalized `TextBox`, Vision's
  bottom-left origin) and `CoreServices/LineAssembler.swift` (groups OCR boxes into visual rows,
  top-to-bottom, joined left-to-right — reunites a name with its separately-recognized price). Both
  Foundation-free and unit-tested (`LineAssemblerTests`) so the make-or-break geometry is provable.
- `AppTarget/Features/Capture/` (`CameraPicker` over `UIImagePickerController`; `CaptureHomeView`
  with camera + `PhotosPicker` library + sample fallback → `viewModel.load(lines:)`), the informational
  **21+ gate** (`Features/AgeGate/AgeGateView`, `@AppStorage`, R3), and `App/RootView` gating into
  `CaptureHomeView`. `Info.plist` needs `NSCameraUsageDescription`.
- The value engine is unchanged — only the *source* of the OCR lines is new (design seam held).

## 2026-08-27 · Editable results — session layer over the pure pipeline
- New pure `CoreServices` types: `EditableDrink` (identity-bearing, mutable view of an enriched drink),
  `DrinkResolver` (single enrichment path shared by pipeline + session), and `MenuSession` (holds one
  menu's drinks; `rankedDrinks` mirrors `ValueRanker` ordering but preserves `id`; mutating
  `correctABV`/`correctSize`/`setPrice`). `MenuPipeline` gained `makeSession(lines:metric:)`; `analyze`
  was refactored to route through the session (output parity verified). Both invariants survive editing.
- `AppTarget/Features/Results/` (`ResultsViewModel` — thin `@MainActor` shell over `MenuSession`;
  `ResultsView` — ranking with badges, tap-to-correct sheet, add-a-price rows). `load(lines:)` is the
  reusable seam the capture flow feeds. Tests: `DrinkResolverTests`, `MenuSessionTests`.

## 2026-08-25 · Phase 5 + demo app — end-to-end, on device
- `MenuParser` (section-state machine): price/ABV/size scanning, header-price inheritance (Change A),
  description-line suppression (Finding 4); Foundation-free, no regex. Bounded v1 (R1: OCR is assist).
- `ABVEstimator`/`SizeEstimator`: `.read` if the menu printed it, else `.estimated` with the profile
  note. `MenuPipeline`: `[String] → MenuAnalysis` (ranked + needsPrice + excludedNonAlcoholic).
- Tests: `MenuParserTests`, `MenuPipelineTests` (wine estimate ranking, needsPrice, NA-section and
  NA-brand exclusion, ordering).
- **Demo app** (`AppTarget/`): SwiftUI results screen over the real pipeline on bundled sample menus
  (no camera). Shows value, $/drink, ABV, provenance badge + note, and the needsPrice / excluded
  buckets. `HOW_TO_RUN.md` = create app shell in Xcode + add local Core package + run on device.
- The value engine is now end-to-end from OCR lines to a ranked list, still headless in Core.

## 2026-08-25 · Phase 4 — ValueRanker (the metric + sort)
- `Core/Sources/CoreServices/ValueRanker.swift`: pure `rank([PricedDrink], by: ValueMetric) ->
  [RankedDrink]`, best value first, ties broken by name for deterministic output.
- Metric (§7): pure_ethanol_floz = size × ABV/100; standard_drinks = /0.6; value = std_drinks / $.
  v2 calories = pure_ethanol_floz × 23.34 g × 7.1 kcal / $ (alcohol-only lower bound, R4).
- `ValueRankerTests` pins the doc's worked example (16 oz/6.5%/$7 = 0.248/$ beats 3 oz/40%/$10 =
  0.20/$), the 1-standard-drink identity (5 oz × 12% = 1 drink), v2 sanity, estimates, empty input,
  and the ranker-boundary invariant (ranks exactly its input; priceless/non-alcoholic can't be
  PricedDrinks).
- CoreServices placeholder removed. `MenuParser`/estimators remain Phase 5.

## 2026-08-25 · Phase 3+ — brand table (161 brands, data-driven)
- Added `Tooling/Data/beverages.json`: a script-readable brand → ABV/category dataset (domestics,
  imports, craft, cider, seltzers/RTDs, non-alcoholic), compiled from the menus + sourced ABV lists.
- Added `Tooling/generate_brand_table.sh` (python3 codegen) → `Core/Sources/CoreContracts/
  GeneratedBrandTable.swift` (Foundation-free, sorted most-specific-first). Edit JSON, re-run gen.
- `StaticBeverageKnowledge` now has a **brand tier** ahead of the style chart; new
  `EstimateSource.brandMatch`. Non-alcoholic brands (Athletic, Heineken 0.0) are caught even in a
  regular beer section (Change B). `BrandTableTests` added.
- Data provenance and regeneration documented in `docs/BeverageDataSources.md`.

## 2026-08-25 · Phase 3 — CoreContracts (protocols + sourced knowledge)
- Four protocols in `CoreContracts` (all Foundation-free): `TextRecognizer` (+ `CapturedImage`),
  `BeverageKnowledge` (+ `BeverageProfile`, `EstimateSource`), `PurchaseController`, `AdPresenter`.
- `StaticBeverageKnowledge`: sourced two-tier lookup — style/varietal chart → category fallback,
  each result flagged `.styleChart` / `.categoryFallback` / `.unclassifiedFallback` so the app can
  say when it fell back. Data + citations in `docs/BeverageDataSources.md` (NIAAA anchors; BJCP/Wine
  Folly style values).
- Test doubles: `FakeTextRecognizer`, `InMemoryPurchaseController` (actor), `NoopAdPresenter`.
- New test target `CoreContractsTests` (+ manifest entry): `ContractsSmokeTests` and
  `StaticBeverageKnowledgeTests` (chart hits incl. Guinness=4.2% beating generic stout; fallback
  flagging; non-alcoholic → 0; shot → 40%).
- `StaticBeverageKnowledge` placed in `CoreContracts` (§6: its default impl is pure enough to ship
  in Core). `CoreServices` remains placeholder until Phase 4.

## 2026-08-25 · Fix — CoreModel made Foundation-free (build fix)
- `swift test` on macOS hit `error: circular dependency between modules 'Foundation' and 'CoreModel'`
  — a known explicit-modules toolchain bug (Xcode 15.4/16/26), not a real cycle in our graph.
- `CoreModel`'s only Foundation use was `Decimal` in `Price`. Reworked `Price` to store integer
  **cents** (`Int`) with `dollars` accessor; removed `import Foundation`. `CoreModel` is now a
  zero-dependency module (§4), which removes the import that triggered the bogus cycle.
- Updated `PriceTests` accordingly. No behaviour change to the price invariant (§10).

## 2026-08-25 · Tooling — auto-generated structure doc
- Added `Tooling/print_structure.sh` → regenerates `docs/ProjectStructure.md` from the real tree
  (portable: no `tree`, no GNU `find -printf`). Wired into `run_checks` step [0/2] so it refreshes
  on every gate run and can't drift. Added to the README doc-set index.

## 2026-08-25 · Phase 2 — CoreModel (the spine)
- Built the spine in `Core/Sources/CoreModel`: `Provenance<T>`, `Price`, `Volume`,
  `BeverageCategory`, `MenuItem`, `DrinkOption`, `PricedDrink`, `RankedDrink`, `ValueMetric`.
- Two invariants enforced structurally, not by comment:
  - **Price (§10):** `Price`'s only init is failable and rejects non-positive amounts; `DrinkOption.price`
    is a non-optional `Price`. A priceless line yields no `Price`, so it can't build a `DrinkOption`.
  - **Change B:** `PricedDrink.init?` refuses `.nonAlcoholic`, so a priced mocktail can never be ranked.
- Business math kept OUT of the model: the value formulas live in `ValueRanker` (Phase 4).
- `CoreModelTests` mirror the module 1:1, incl. `PricedDrinkInvariantTests`.
- **Exit:** spine complete; suite expected green (`cd Core && swift test` on your Mac).

## 2026-08-25 · §5 inspection — 16 real menus transcribed
- Transcribed 7 format-diverse menus into `Tooling/Fixtures/` + wrote `INSPECTION_FINDINGS.md`.
- Two design changes surfaced (see findings): **(A)** `MenuParser` must be a section-state
  machine, because some menus price only on the category header (Rullo's `Elixirs | $14`);
  **(B)** `.nonAlcoholic` becomes a first-class `BeverageCategory` case, excluded from ranking
  before the metric (priced mocktails/sodas otherwise pollute results).
- Confirmed printed ABV/size is common on beer & wine menus → the `.read` provenance path is
  well-exercised, not a rare branch.

## 2026-08-25 · Phase 1 — Foundations & scaffolding
- Created repo laid out by layer/role (§3): `Core/` (local SPM package), `Tooling/`, `docs/`.
- `Core/Package.swift`: target graph with dependency directions CoreModel ← CoreContracts ←
  CoreServices (§4); platform-agnostic so `swift test` runs on Linux and macOS.
- Placeholder sources + trivial tests so the package compiles and the suite is green.
- `.gitignore`: build artifacts, secrets/keys, `data/` excluded from day one (§3).
- `Tooling/run_checks.sh`: the single pre-flight gate (§9).
- Full §2 doc set: README, CodebaseReference (mental model + layer table), Handoff, Risks
  (R1–R5 tagged), PlainLanguageGuide, this Changelog. Placed the two authored design docs
  (`Architecture.md`, `ProjectConventions.md`) verbatim.
- **Exit:** tree compiles, doc set complete. Awaiting Phase 1 approval before CoreModel.
