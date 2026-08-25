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
| **Contracts** | `Core/Sources/CoreContracts` | CoreModel | Protocols the shell implements: OCR, beverage knowledge, purchases, ads | ⏳ Phase 3 |
| **Services (pure)** | `Core/Sources/CoreServices` | CoreModel | Parse → items; estimate ABV/size; compute + sort the value metric | ⏳ Phases 4–5 |
| **Features (UI)** | `AppTarget/Sources/Features` | Core | Capture, Results, Paywall — thin, no business logic | ⏳ Week 1 |
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
- **`Sources/CoreContracts/`** ⏳ Phase 3 — `TextRecognizer`, `BeverageKnowledge`,
  `PurchaseController`, `AdPresenter` + `StaticBeverageKnowledge`, `FakeTextRecognizer`.
- **`Sources/CoreServices/`** ⏳ Phases 4–5 — `ValueRanker` (Phase 4), `MenuParser` /
  `ABVEstimator` / `SizeEstimator` (Phase 5).
- **`Tests/CoreModelTests/`** ✅ — mirrors CoreModel 1:1 (§8): Provenance/Price/Volume/
  BeverageCategory/DrinkOption/ValueMetric behaviour + `PricedDrinkInvariantTests` (the Change-B
  structural invariant). **`Tests/CoreServicesTests/`** ⏳ — scaffolding until Phase 4.

### `Tooling/`

- **`run_checks.sh`** ✅ — the single pre-flight gate (§9): refresh `ProjectStructure.md` →
  `swift test` → app schemes on macOS. Green gate = safe to ship.
- **`print_structure.sh`** ✅ — regenerates `docs/ProjectStructure.md` from the real tree.
- **`Fixtures/`** ✅ — transcribed real-menu OCR lines + `INSPECTION_FINDINGS.md` (§5).

### `AppTarget/` ⏳ Week 1

Not yet created. Xcode-project generation approach (raw `.xcodeproj` vs XcodeGen/Tuist vs
SPM-app) and min iOS version are the first Week-1 decisions.

### `docs/`

The §2 doc set. This file, plus README / Architecture / ProjectConventions / Handoff /
Risks / Changelog / PlainLanguageGuide.
