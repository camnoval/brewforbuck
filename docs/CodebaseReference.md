# Codebase Reference

*The file-by-file, type-by-type map. Jump around in this. Read `Architecture.md` for the
"why", this for the "where". Populated per build phase — sections marked ⏳ are scaffolded
but not yet implemented.*

---

## Mental model (read this first)

**The one job:** point the camera at a drink menu and get the alcoholic options ranked by
**value** — alcohol per dollar — so you can pick the best deal at a glance.

**The spine:** one value type, `DrinkOption` — a name, a price, a serving size, and an ABV,
each carrying whether it was **read** off the menu or **estimated**. Everything reduces to
producing a list of these and sorting it.

**The two flows:**
1. **Capture** — photo → OCR lines → parse `{name, price, size?}` → enrich estimated
   ABV/size → `[DrinkOption]`.
2. **Ranking** — `[DrinkOption]` → compute the value metric → sort best-first → present,
   estimates flagged and one-tap correctable.

**The two load-bearing invariants:**
- **Price is never fabricated** — a line with no readable price drops to a `needsPrice`
  bucket, never ranked on a guess. Enforced *structurally*: only a `PricedDrink` (which
  cannot hold a nil price) can enter the ranker (§10, R-invariant).
- **Estimated never masquerades as measured** — every axis carries its `Provenance`, and
  the UI shows it (§11).

---

## Layer table (§4)

| Layer | Lives in | Depends on | Job | Status |
|---|---|---|---|---|
| **Model** | `Core/Sources/CoreModel` | nothing | `DrinkOption` spine + `Provenance<T>` + units | ✅ Phase 2 |
| **Contracts** | `Core/Sources/CoreContracts` | CoreModel | Protocols the shell implements: OCR, beverage knowledge, purchases, ads (+ the pure `StaticBeverageKnowledge`) | ✅ Phase 3 |
| **Services (pure)** | `Core/Sources/CoreServices` | CoreModel/CoreContracts | Parse → items; estimate ABV/size; compute + sort the value metric | ✅ Phases 4–5 |
| **Features (UI)** | `AppTarget/` | Core | Results screen demo (sample menus, no camera yet) | ◑ demo app |
| **Infrastructure (shell)** | `AppTarget/Sources/Infrastructure` | Core (protocols) | Vision, RevenueCat, RevenueCat Ads — the only impure code | ⏳ Week 2 |

**Dependency direction points down only.** `CoreServices` never imports Vision or
RevenueCat; it depends on the *protocols* in `CoreContracts`, and the shell supplies the
real implementations at app startup. Enforced by the package boundary: `Core` compiles with
no SwiftUI/UIKit/Vision import.

---

## File map

### `Core/` (local SPM package — the product)

- **`Package.swift`** ✅ — target graph + dependency directions. Platform-agnostic (builds
  on Linux) so `swift test` runs anywhere.
- **`Sources/CoreModel/`** ✅ Phase 2 — the spine:
  - `Provenance.swift` — `read` / `estimated(note:)`, `.value`, `.corrected(to:)`, `.map` (§11).
  - `Price.swift` — value type; failable init rejects non-positive → the §10 price guard.
  - `Volume.swift` — serving volume in fl oz (mL bridge); no domain defaults.
  - `BeverageCategory.swift` — cases from the 16 menus; `.isAlcoholic` (Change B).
  - `MenuItem.swift` — raw parse output; optional price = `needsPrice` signal.
  - `DrinkOption.swift` — the spine; non-optional `Price` ⇒ price invariant by type.
  - `PricedDrink.swift` — ranker input; `init?` refuses `.nonAlcoholic` (Change B).
  - `RankedDrink.swift` — ranker output holder (value + rank).
  - `ValueMetric.swift` — `.standardDrinksPerDollar` (v1) + `.caloriesPerDollar` (v2).
- **`Sources/CoreContracts/`** ✅ Phase 3 — four protocols + default knowledge + doubles:
  - `TextRecognizer.swift` — protocol + `CapturedImage` (Foundation-free photo handle).
  - `BeverageKnowledge.swift` — protocol + `BeverageProfile` + `EstimateSource`
    (`.styleChart` / `.categoryFallback` / `.unclassifiedFallback`).
  - `PurchaseController.swift`, `AdPresenter.swift` — entitlement + ads protocols.
  - `StaticBeverageKnowledge.swift` — brand table → style/varietal chart → category fallback,
    each flagged by `EstimateSource` (see `docs/BeverageDataSources.md`).
  - `GeneratedBrandTable.swift` — AUTO-GENERATED 161-brand table (do not hand-edit).
  - `TestDoubles.swift` — `FakeTextRecognizer`, `InMemoryPurchaseController` (actor), `NoopAdPresenter`.
- **`Sources/CoreServices/`** ✅ — the pure pipeline:
  - `MenuParser.swift` — section-state machine: price/ABV/size scanning, header-price inheritance
    (Change A), description-line suppression (Finding 4). Foundation-free (no regex).
  - `ABVEstimator.swift` / `SizeEstimator.swift` — read-if-printed, else estimate via the profile.
  - `ValueRanker.swift` — the metric + sort (§7).
  - `MenuPipeline.swift` — end-to-end `[String] → MenuAnalysis` (ranked + needsPrice + excluded NA).
- **`Tests/CoreModelTests/`** ✅ — mirrors CoreModel 1:1 (§8).
- **`Tests/CoreContractsTests/`** ✅ — `ContractsSmokeTests` (the doubles),
  `StaticBeverageKnowledgeTests` (chart hits, fallback flagging), `BrandTableTests` (brand
  specificity, NA-brand detection, section refinement).
- **`Tests/CoreServicesTests/`** ✅ — `ValueRankerTests`, `MenuParserTests` (price formats,
  header-price inheritance, needsPrice, description suppression, printed ABV), `MenuPipelineTests`
  (end-to-end ranking + buckets).

### `Tooling/`

- **`run_checks.sh`** ✅ — the single pre-flight gate (§9): refresh `ProjectStructure.md` →
  `swift test` → app schemes on macOS. Green gate = safe to ship.
- **`print_structure.sh`** ✅ — regenerates `docs/ProjectStructure.md` from the real tree.
- **`generate_brand_table.sh`** ✅ — codegen: `Data/beverages.json` → `GeneratedBrandTable.swift`.
- **`Data/beverages.json`** ✅ — the brand → ABV/category dataset (script-readable source of truth).
- **`Fixtures/`** ✅ — transcribed real-menu OCR lines + `INSPECTION_FINDINGS.md` (§5).

### `AppTarget/` ◑ demo app

A minimal SwiftUI app that runs the real `MenuPipeline` on bundled sample menus (no camera yet).
`BangForBuckApp.swift`, `ContentView.swift`, `SampleMenus.swift`, and `HOW_TO_RUN.md` (create the
app shell in Xcode, add the local `Core` package, run on device). Camera/Vision + the full
Features/Infrastructure split is the next step.

### `docs/`

The §2 doc set. This file, plus README / Architecture / ProjectConventions / Handoff /
Risks / Changelog / PlainLanguageGuide.
