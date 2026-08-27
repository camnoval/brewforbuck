# Changelog

*Append-only history (§2). Newest on top. The Handoff is the live "where we are"; this is
the log — don't let them merge.*

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
