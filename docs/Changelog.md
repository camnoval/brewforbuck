# Changelog

*Append-only history (§2). Newest on top. The Handoff is the live "where we are"; this is
the log — don't let them merge.*

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
