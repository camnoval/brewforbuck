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
  cannot hold a nil price) can enter the ranker (§10, R-invariant). **This now covers the app's
  own prices too:** a supporter tier's price is a `String` from the store, never a number `Core`
  could format.
- **Estimated never masquerades as measured** — every axis carries its `Provenance`, and
  the UI shows it (§11). **Amber is reserved for exactly this** — nothing else in the app wears it,
  which is why the supporter badge and paywall messages are green and muted rather than amber.

---

## Layer table (§4)

| Layer | Lives in | Depends on | Job | Status |
|---|---|---|---|---|
| **Model** | `Core/Sources/CoreModel` | nothing | `DrinkOption` spine + `Provenance<T>` + units | ✅ Phase 2 |
| **Contracts** | `Core/Sources/CoreContracts` | CoreModel | Protocols the shell implements: OCR, beverage knowledge, purchases (+ the pure `StaticBeverageKnowledge`) | ✅ Phase 3, revised 2026-09-09 |
| **Services (pure)** | `Core/Sources/CoreServices` | CoreModel/CoreContracts | Parse → items; estimate ABV/size; compute + sort the value metric; the paywall state machine | ✅ Phases 4–5 + monetization |
| **Features (UI)** | `AppTarget/Features` | Core | Capture (camera/library), editable Results (correct, price, add/remove), 21+ gate, supporter paywall + badge | ✅ |
| **Infrastructure (shell)** | `AppTarget/Infrastructure` | Core (protocols) | Vision OCR ✅ ; RevenueCat purchases ✅ | ● |

**Dependency direction points down only.** `CoreServices` never imports Vision or
RevenueCat; it depends on the *protocols* in `CoreContracts`, and the shell supplies the
real implementations at app startup. Enforced by the package boundary: `Core` compiles with
no SwiftUI/UIKit/Vision import, **and no RevenueCat import**. If `Core` stops building on Linux,
the boundary has been broken.

**There is no ads layer.** `AdPresenter` was deleted 2026-09-09; ads are out of v1 entirely and the
banner view will have no `Core` representation when it arrives. See `AdsPlan.md`.

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
- **`Sources/CoreContracts/`** ✅ — **three** protocols + default knowledge + doubles:
  - `TextRecognizer.swift` — protocol + `CapturedImage` (Foundation-free photo handle).
  - `BeverageKnowledge.swift` — protocol + `BeverageProfile` + `EstimateSource`
    (`.styleChart` / `.categoryFallback` / `.unclassifiedFallback`).
  - `PurchaseController.swift` — **rewritten 2026-09-09.** The `supporter` entitlement:
    `supporterTiers()`, `purchase(_ tier:)`, `restorePurchases()`, `supporterStatus()`. Carries
    `SupporterTier` (identifier + store display name + **store price String**), `SupporterStatus`
    (`.notSupporter` / `.supporter(productIdentifier:)` + `.isActive`), `PurchaseOutcome`
    (`.purchased` / `.cancelled` / `.pending` — the last is Ask to Buy), and `RestoreOutcome`
    (`.restored` / `.nothingToRestore`). Foundation-free on purpose: no `Decimal`, no formatter, no
    numeric price. See `MonetizationPlan.md` §4–5 for the four gaps this fixed.
  - ~~`AdPresenter.swift`~~ — **deleted 2026-09-09.** Written against RevenueCat Ads, which is a
    beta analytics feature rather than an ad network. Do not resurrect it; see `AdsPlan.md`.
  - `StaticBeverageKnowledge.swift` — brand table → style/varietal chart → category fallback,
    each flagged by `EstimateSource` (see `docs/BeverageDataSources.md`).
  - `GeneratedBrandTable.swift` — AUTO-GENERATED 655-brand table (do not hand-edit; re-run
    `Tooling/generate_brand_table.sh` after editing `beverages.json`, or the table silently goes stale).
  - `BrandCatalog.swift` — `KnownBeverage` + `BrandCatalog.all`: the public, de-duped, alphabetical
    projection of the generated table, so `AppTarget` can build a brand picker without reaching into
    the matcher's internals.
  - `TestDoubles.swift` — `FakeTextRecognizer`, and `InMemoryPurchaseController` (actor). The latter
    is configurable across **every** branch a paywall must handle: no tiers, cancel, Ask-to-Buy
    hold, thrown failure, and a restore that finds nothing. `sampleTiers` mirrors the three shipping
    products. Also what the SwiftUI previews run on, so the paywall is designable with no account, no
    device and no SDK. `NoopAdPresenter` deleted with `AdPresenter`.
- **`Sources/CoreServices/`** ✅ — the pure pipeline + editable session + monetization logic:
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
    enrichment path (`MenuItem` → enriched `EditableDrink` or excluded-NA), shared by pipeline and
    session so both agree.
  - `EditableDrink.swift` — identity-bearing (`id`), mutable view of an enriched drink; `price` still
    the one never-fabricated axis (§10), `pricedDrink` is `nil` until priced.
  - `MenuSession.swift` — holds one menu's `[EditableDrink]`; `rankedDrinks` mirrors `ValueRanker`
    ordering but preserves `id`; mutating `correctABV`/`correctSize`/`setPrice`/`addDrink`/`removeDrink`.
    Both invariants (§10, Change B) survive every edit. Exposes `quality` and `isLowConfidence`.
  - `MenuQuality.swift` — `MenuQuality` + `MenuQualityGate.assess`. `isLowConfidence` fires below a
    0.25 priced fraction, and only once there are ≥ 8 parsed items to judge on. Now load-bearing
    beyond the UI: it also **suppresses the supporter prompt**, so the app never asks for money after
    a read it does not trust.
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
    with the same two invariants.
  - **`PaywallFlow.swift`** ✅ *new 2026-09-09* — the paywall as one pure function,
    `next(from:on:)`. `PaywallState`: `.loading`, `.unavailable`, `.ready(tiers:notice:)`,
    `.purchasing(tiers:chosen:)`, `.restoring(tiers:)`, `.pending`, `.thanks(productIdentifier:)`.
    `PaywallEvent` for everything the view reports; `PaywallNotice` for the three things worth saying
    once. Every state that can return to the list **carries the tiers**, so a cancel does not refetch.
    Inapplicable `(state, event)` pairs return the state unchanged, so a late reply cannot resurrect a
    dismissed sheet or walk a finished purchase backwards. **No state means "showing prices I do not
    have."**
  - **`SupporterPrompt.swift`** ✅ *new 2026-09-09* — `SupporterPrompt.shouldOffer(...)`, the four ask
    rules (never a supporter, never twice, **never on a thin read**, never without a comparison), plus
    `minimumRankedDrinks` / `minimumRatioWorthMentioning`. Also holds **`SupporterTierKind`** —
    a closed set (`.shot` / `.pint` / `.round` / `.unspecified`) resolved from the granting product
    identifier by **suffix**, so the identifier prefix can change without an edit here, and an
    unrecognized tier degrades to a plainer badge rather than a wrong one.
  - **`MenuValueSpread.swift`** ⚠️ *new 2026-09-09, currently unused* — the dimensionless best-to-worst
    value ratio on one menu, plus `MenuSession.valueSpread`. Built for a paywall line that was then
    cut. Deliberately a **ratio, not a saving**: multiplying a tier price by a drinks-per-dollar rate
    mixes the customer's storefront currency with the menu's and produces a confident wrong number.
    Kept only for the possible share card (`ShipatonSubmission.md`); delete it and its tests if that
    is dropped.
- **`Tests/CoreModelTests/`** ✅ — mirrors CoreModel 1:1 (§8).
- **`Tests/CoreContractsTests/`** ✅ — `ContractsSmokeTests` (13 tests: the recognizer double, tier
  order, missing tiers throwing rather than defaulting, store-supplied name/price strings, all four
  purchase behaviours, every tier granting the same entitlement, the charged tier matching the
  displayed one, and both restore outcomes), `StaticBeverageKnowledgeTests`, `BrandTableTests`.
- **`Tests/CoreServicesTests/`** ✅ — `ValueRankerTests`, `MenuParserTests`, `MenuPipelineTests`,
  `LineAssemblerTests`, `LineAssemblerColumnTests`, `MenuParserHardeningTests`, `DrinkResolverTests`,
  `MenuSessionTests`, `MenuSessionManualEntryTests`, `LineAssemblerRealMenuTests`,
  `MenuParserSectionTests`, `MenuParserConfidenceTests`, `MenuParserMultiPriceTests`,
  `ObservationFixtureTests`, `StoreComparisonTests`, `BrandCatalogTests`, `StoreSessionTests`;
  plus **`PaywallFlowTests`** (18: every transition, plus three cases proving inapplicable events are
  ignored), **`SupporterPromptTests`** (15: each ask rule, and tier-kind resolution incl. the unknown
  fallback), **`MenuValueSpreadTests`** (9).

> **XCTest gotcha, learned the hard way 2026-09-09.** `XCTAssertEqual` and friends take a
> **non-async** autoclosure, so `XCTAssertEqual(await thing(), x)` does not compile
> ("'async' call in an autoclosure that does not support concurrency"). Hoist every `await` into a
> `let` on its own line first. Same for reading an actor-isolated property. This bit an entire test
> file at once. See `ProjectConventions.md` §8.

### `Tooling/`

- **`run_checks.sh`** ✅ — the single pre-flight gate (§9): refresh `ProjectStructure.md` →
  `swift test` → app schemes on macOS. Green gate = safe to ship.
- **`print_structure.sh`** ✅ — regenerates `docs/ProjectStructure.md` from the real tree.
  **Re-run it:** the checked-in copy is stale (still lists `BangForBuckApp.swift`).
- **`generate_brand_table.sh`** ✅ — codegen: `Data/beverages.json` → `GeneratedBrandTable.swift`.
- **`Data/beverages.json`** ✅ — the brand → ABV/category dataset (script-readable source of truth).
- **`Fixtures/`** ✅ — transcribed real-menu OCR lines + `INSPECTION_FINDINGS.md` (§5).
- **`rename_to_abv.sh`** ✅ — dry-run verified, deliberately **not run**. See the part-3 Handoff note.

### `AppTarget/`

- **`ABVApp.swift`** — the `@main` entry. Calls `RevenueCatPurchases.configure()` in `init()` and
  then builds the `SupporterStore` around `RevenueCatPurchases()`, injecting it into `RootView`.
  Both happen in `init` rather than as a property default so the ordering is visible: a property
  initializer runs before the init body, and "configure before any other SDK call" is a documented
  requirement rather than a preference.
- **`App/RootView.swift`** — `@AppStorage` 21+ gate → `CaptureHomeView`, passing the supporter store
  through. ~~`ContentView.swift`~~ **deleted 2026-09-09**: unreferenced, superseded by
  `RootView` + `CaptureHomeView`, and independently broken (it held one `ResultsViewModel` and passed
  a second, fresh one to `ResultsView`, so its `load()` wrote to a view model nothing displayed).
- **`Design/Theme.swift`** — the design tokens: the glass/liquid palette with **green-tinted** darks,
  SF Rounded for the voice and SF Pro for the machinery, the 4pt `Space` scale, and the shared
  components `Wordmark`, `ValueFigure`, `PourLine`, `PourButtonStyle`, `ActionCardStyle`,
  `ActionCardLabel`, `Notice`, and the `ChipFlow` wrapping layout. **`Theme.amber` is reserved for
  "this is an estimate" and nothing else** — that reservation is why `Notice` is not used for
  paywall messages.
- **`Features/AgeGate/AgeGateView.swift`** — informational 21+ confirmation, once (R3).
- **`Features/Results/Capture/`** (nested under Results, not top-level as Architecture §3 sketches)
  — `CameraPicker`, `CaptureHomeView` (camera + `PhotosPicker` + sample + the Compare entry point →
  `viewModel.load(lines:)` → Results; now also shows the `SupporterBadge` under the wordmark and
  refreshes the entitlement in `.task`), `OCRDebugExportSheet` (DEBUG-only, long-press the logo).
- **`Features/Results/`** — `ResultsViewModel` (thin `@MainActor` shell over `MenuSession`;
  `load(lines:)` is the OCR seam) and `ResultsView` (ranking with badges/chips, tap-to-edit sheet,
  "Not sure about these" bucket, add-a-drink sheet, calculation explainer, and the
  `SupporterPromptRow` section above the explainer).
- **`Features/Shared/ValueChips.swift`** — the shared ranked-row vocabulary: `SectionHeader`,
  `RankMedal`, `MetaChip`, `ProvenanceChip`, `PricePill`, and the `ValueFormat` number formatters.
- **`Features/Compare/`** — `CompareViewModel` + `CompareView` (ranked shelf list, brand picker off
  `BrandCatalog.all`, container presets, "Waiting on a price" bucket, store explainer).
- **`Features/Supporter/`** ✅ *new 2026-09-09*:
  - `SupporterStore.swift` — `@MainActor ObservableObject` (matching `ResultsViewModel`'s shape, not
    the `@Observable` macro). Holds `status`, the persisted `scansSinceLastAsk` counter, and forwards
    to the injected `PurchaseController`. **The only impure piece of the feature**; every decision
    delegates to `SupporterPrompt`. `recordScan()` runs once per results screen *including* thin
    reads, so the counter measures use rather than asks; `markAsked()` restarts the interval and
    fires when the sheet *appears*, so dismissing it counts as asked. A fresh install starts at the
    interval so the first qualifying scan still asks.
  - `PaywallView.swift` — renders `PaywallState` and reports events; contains no transitions of its
    own. Also holds `TierRow` and `SupporterPromptRow`, and **seven previews** covering tiers ready,
    store unavailable, failed purchase, Ask-to-Buy hold, existing supporter, nothing-to-restore, and
    the prompt row.
  - `SupporterBadge.swift` — the home-screen badge, the `SupporterTierKind` → symbol/metal/copy
    mapping in one place, and `ContributorMark`, the large tier mark on the thank-you state. The
    round is **two mirrored `mug.fill`** rather than one glyph, because SF Symbols has no
    clinking-mugs symbol; which of the two is mirrored is the `mirrorsLeftMug` constant, so the
    handles can be flipped outward without re-reasoning about the glyph. Tiers read as a progression:
    a drop, a mug, two mugs. All symbols used here now render on device.
- **`Infrastructure/VisionTextRecognizer.swift`** — `TextRecognizer` via `VNRecognizeTextRequest`
  (on-device), PNG → `CGImage` → `[TextObservation]` → `LineAssembler`. Holds the
  `CapturedImage(uiImage:)` bridge.
- **`Infrastructure/RevenueCatPurchases.swift`** ✅ *2026-09-09 part 2* — the `PurchaseController`
  conformer and **the only file in the project that may import RevenueCat** (SDK 5.88.0). An
  `actor`, and not by preference: this target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so a
  `struct` or `final class` here is implicitly main-actor-isolated and cannot satisfy the protocol's
  nonisolated requirements. `InMemoryPurchaseController` is an actor for the same reason, so the real
  and fake conformers share an isolation shape. Caches the `Package` objects behind the displayed
  tiers, so `purchase(_:)` buys the exact package whose price went on screen rather than re-resolving
  it (§10). API surface verified 2026-09-09 and recorded in that Handoff note; re-check the vendor
  docs rather than trusting it.

### `docs/`

The §2 doc set. This file, plus README / Architecture / ProjectConventions / Handoff / Risks /
Changelog / PlainLanguageGuide / BeverageDataSources / StoreCatalogSources / MenuTestingPlan (done)
/ **MonetizationPlan** (design of record) / **AdsPlan** (v1.1) / **ShipatonSubmission** (competition
+ open-sourcing checklist).
