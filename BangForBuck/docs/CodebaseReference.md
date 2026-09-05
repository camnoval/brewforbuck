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
1. **Capture** — photo → OCR text boxes → **assemble** into lines/columns (`LineAssembler`) →
   parse `{name, price, size?}` → enrich estimated ABV/size → `[EditableDrink]` in a `MenuSession`.
2. **Ranking** — the session ranks by the value metric → present best-first, estimates flagged and
   one-tap correctable, prices editable, and drinks addable/removable by hand.

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
| **Features (UI)** | `AppTarget/Features` | Core | Capture (camera/library), editable Results (correct, price, add/remove), 21+ gate | ✅ Week 1 |
| **Infrastructure (shell)** | `AppTarget/Infrastructure` | Core (protocols) | Vision OCR ✅ ; RevenueCat + Ads ⏳ Week 2 | ◑ |

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
  - `TextBox.swift` — pure `TextObservation` + normalized `TextBox` (Vision's bottom-left
    origin). The OCR handoff type; lets `LineAssembler` be tested without Vision. *(The file is named
    for the box, not the observation — grep `TextObservation` and you'll land here.)*
- **`Sources/CoreContracts/`** ✅ Phase 3 — four protocols + default knowledge + doubles:
  - `TextRecognizer.swift` — protocol + `CapturedImage` (Foundation-free photo handle).
  - `BeverageKnowledge.swift` — protocol + `BeverageProfile` + `EstimateSource`
    (`.styleChart` / `.categoryFallback` / `.unclassifiedFallback`).
  - `PurchaseController.swift`, `AdPresenter.swift` — entitlement + ads protocols.
  - `StaticBeverageKnowledge.swift` — brand table → style/varietal chart → category fallback,
    each flagged by `EstimateSource` (see `docs/BeverageDataSources.md`).
  - `GeneratedBrandTable.swift` — AUTO-GENERATED 655-brand table (do not hand-edit; re-run
    `Tooling/generate_brand_table.sh` after editing `beverages.json`, or the table silently goes stale).
  - `BrandCatalog.swift` — `KnownBeverage` + `BrandCatalog.all`: the public, de-duped, alphabetical
    projection of the generated table, so `AppTarget` can build a brand picker without reaching into
    the matcher's internals.
  - `TestDoubles.swift` — `FakeTextRecognizer`, `InMemoryPurchaseController` (actor), `NoopAdPresenter`.
- **`Sources/CoreServices/`** ✅ — the pure pipeline + editable session:
  - `LineAssembler.swift` — `[TextObservation] → [String]`. **Column detection** (central-gutter
    histogram, guarded against single-column false-splits) then per-column row assembly, top-to-bottom,
    joined left-to-right. Reunites a name with its separately-recognized price (R1).
  - `MenuParser.swift` — section-state machine: price/ABV/size scanning, header-price inheritance
    (Change A), description-line suppression (Finding 4), `cleanName` (strips `ABV x%`/size/dash from
    names), `drafts`/`draft`/`cans` headers. Foundation-free (no regex).
  - `ABVEstimator.swift` / `SizeEstimator.swift` — read-if-printed, else estimate via the profile.
  - `ValueRanker.swift` — the metric + sort (§7). `value(of:metric:)` is reused by the session.
  - `MenuPipeline.swift` — `[String] → MenuAnalysis` (one-shot) **and** `makeSession(lines:metric:)`
    for the interactive path; `analyze` routes through the session for parity.
  - `DriveResolver.swift` — **contains `DrinkResolver`** (filename typo, harmless). The single
    enrichment path (`MenuItem` → enriched `EditableDrink` or
    excluded-NA), shared by pipeline and session so both agree.
  - `EditableDrink.swift` — identity-bearing (`id`), mutable view of an enriched drink; `price` still
    the one never-fabricated axis (§10), `pricedDrink` is `nil` until priced.
  - `MenuSession.swift` — holds one menu's `[EditableDrink]`; `rankedDrinks` mirrors `ValueRanker`
    ordering but preserves `id`; mutating `correctABV`/`correctSize`/`setPrice`/`addDrink`/`removeDrink`.
    Both invariants (§10, Change B) survive every edit.
  - `ObservationFixture.swift` — serializes `[TextObservation]` into a paste-ready Swift literal plus
    a readable dump, so a real on-device OCR export becomes a `LineAssembler` test fixture directly.
  - `StoreComparison.swift` — **the store side (Goal 2)**, a separate type sharing only
    `ValueRanker`'s ethanol formula: `StoreProduct` (unitVolume × count), `rank` → `[RankedProduct]`
    with both standard-drinks-per-dollar and $/standard-drink, `ContainerSize.presets` for the picker,
    and the shared `StoreValue` / `value(totalStandardDrinks:dollars:)` / `sortsBefore(...)` scoring
    primitives that `StoreSession` also calls.
  - `StoreSession.swift` — the interactive store calculator: `EditableProduct` (id, unit volume,
    count, `Provenance<Double>` ABV, optional `Price`) + `StoreSession` with `rankedProducts` /
    `needsPriceProducts` and pure add/price/ABV/package/remove edits. The store twin of `MenuSession`,
    with the same two invariants: a priceless package can't rank (§10), and a brand-seeded ABV stays
    flagged until corrected (§11).
- **`Tests/CoreModelTests/`** ✅ — mirrors CoreModel 1:1 (§8).
- **`Tests/CoreContractsTests/`** ✅ — `ContractsSmokeTests` (the doubles),
  `StaticBeverageKnowledgeTests` (chart hits, fallback flagging), `BrandTableTests` (brand
  specificity, NA-brand detection, section refinement).
- **`Tests/CoreServicesTests/`** ✅ — `ValueRankerTests`, `MenuParserTests`, `MenuPipelineTests`,
  plus the capture/edit additions: `LineAssemblerTests` + `LineAssemblerColumnTests` (row + column
  assembly, no cross-column merge, single-column not split), `MenuParserHardeningTests` (name-cleanup,
  `drafts`/`cans`, end-to-end two-column "no chimera"), `DrinkResolverTests`, `MenuSessionTests`
  (correction/add-price re-ranks; invariants hold), `MenuSessionManualEntryTests` (add/remove);
  plus the OCR-hardening set `LineAssemblerRealMenuTests` (real device coordinates),
  `MenuParserSectionTests`, `MenuParserConfidenceTests` (rank-eligibility gate, price repair,
  back-fill), `MenuParserMultiPriceTests`, `ObservationFixtureTests`; and the store side
  `StoreComparisonTests`, `BrandCatalogTests`, `StoreSessionTests` (incl. ranking **parity** between
  the session and the one-shot comparison).

### `Tooling/`

- **`run_checks.sh`** ✅ — the single pre-flight gate (§9): refresh `ProjectStructure.md` →
  `swift test` → app schemes on macOS. Green gate = safe to ship.
- **`print_structure.sh`** ✅ — regenerates `docs/ProjectStructure.md` from the real tree.
- **`generate_brand_table.sh`** ✅ — codegen: `Data/beverages.json` → `GeneratedBrandTable.swift`.
- **`Data/beverages.json`** ✅ — the brand → ABV/category dataset (script-readable source of truth).
- **`Fixtures/`** ✅ — transcribed real-menu OCR lines + `INSPECTION_FINDINGS.md` (§5).

### `AppTarget/` ✅ Week 1 — capture → editable results (on device)

- **`App/`** — `BangForBuckApp` (entry) → `RootView` (`@AppStorage` 21+ gate → capture). `ContentView`
  / `SampleMenus` linger as a sample fallback; superseded by `RootView` + `CaptureHomeView`.
- **`Features/AgeGate/AgeGateView.swift`** — informational 21+ confirmation, once (R3).
- **`Features/Results/Capture/`** (nested under Results, not top-level as Architecture §3 sketches)
  — `CameraPicker` (`UIImagePickerController` wrapper; `NSCameraUsageDescription` now set via
  `INFOPLIST_KEY_…` in the project), `CaptureHomeView` (camera + `PhotosPicker` library + sample +
  the Compare entry point → `viewModel.load(lines:)` → navigate to Results), `OCRDebugExportSheet`
  (DEBUG-only, reached by long-pressing the logo).
- **`Features/Results/`** — `ResultsViewModel` (thin `@MainActor` shell over `MenuSession`;
  `load(lines:)` is the OCR seam) and `ResultsView` (ranking with badges/chips, tap-to-edit sheet for
  price/ABV/size + remove, "Not sure about these" bucket with add-price/remove, "+" add-a-drink sheet,
  calculation explainer).
- **`Features/Shared/ValueChips.swift`** — the shared ranked-row vocabulary: `SectionHeader`,
  `RankMedal`, `MetaChip`, `ProvenanceChip`, `PricePill`, and the `ValueFormat` number formatters.
  Both ranked lists render through these, so the menu and store screens can't drift visually.
- **`Features/Compare/`** — `CompareViewModel` (thin `@MainActor` shell over `StoreSession`) and
  `CompareView` (ranked shelf list, add-product form with the searchable brand picker off
  `BrandCatalog.all` + `ContainerSize.presets` + custom-oz path, per-row edit sheet, "Waiting on a
  price" bucket, store calculation explainer).
- **`Infrastructure/VisionTextRecognizer.swift`** — `TextRecognizer` via `VNRecognizeTextRequest`
  (on-device), PNG → `CGImage` → `[TextObservation]` → `LineAssembler`. Holds the `CapturedImage(uiImage:)`
  bridge. The only impure code so far; RevenueCat purchases + ads land here in Week 2.

### `docs/`

The §2 doc set. This file, plus README / Architecture / ProjectConventions / Handoff /
Risks / Changelog / PlainLanguageGuide.
