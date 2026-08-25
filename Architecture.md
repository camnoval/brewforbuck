# Bang-for-Buck — Architecture & Build Plan

*The app-specific design doc for the alcohol value-ranker. Read it alongside
**PROJECT_CONVENTIONS.md** — this file instantiates that playbook for one app, and the
`§` numbers below mirror the conventions doc so you can jump between them. Scope is
deliberately small: this is a clean, single-purpose utility shipped inside the Shipaton
2026 window, not a platform.*

> **Hard external constraint.** Shipaton 2026 requires the app's **first public version**
> to go live between **Aug 1 and Sep 30, 2026**, integrate the **RevenueCat SDK** (at
> least one in-app purchase *or* RevenueCat Ads), and be a brand-new listing. We do
> **both** monetization paths: RevenueCat Ads for revenue + a trivial $0.99 "Remove Ads"
> non-consumable IAP as qualification insurance. App Review eats into the window, so the
> schedule (§B) submits early on purpose.

---

## §1. Mental model (read this first)

**The one job:** point the camera at a drink menu and get the alcoholic options ranked by
**value** — how much alcohol you get per dollar — so you can pick the best deal at a
glance. (v2 adds a calories-per-dollar ranking on the same pipeline.)

**The spine:** a single value type, `DrinkOption` — a name, a price, a serving size, and an
ABV, each carrying whether it was **read** off the menu or **estimated**. Everything in the
app reduces to producing a list of these and sorting it. If you understand `DrinkOption`
and its provenance wrapper, you understand the app.

**The two flows:**

1. **Capture flow** — photo → OCR text lines → parse into `{name, price, maybe size}` →
   enrich with estimated ABV/size where the menu didn't say → `[DrinkOption]`.
2. **Ranking flow** — `[DrinkOption]` → compute the value metric → sort best-to-worst →
   present, with estimated values visibly flagged and one-tap correctable.

**The two load-bearing rules** (the invariants everything else protects):

- **Price is the one thing we never fabricate.** A line with no readable price is *not*
  ranked with a guessed price — it drops to a "couldn't read a price" bucket the user can
  fix. Everything else (ABV, size) may be estimated; price may not. (§10)
- **Estimated never masquerades as measured.** Every axis knows its own provenance and the
  UI shows it. A ranking built on guesses is fine as long as it's honest that they're
  guesses. (§11)

---

## §3. Directory layout (single app, local Core package)

```
BangForBuck/
  docs/                         # this doc, plus README / Handoff / Risks / Changelog
  Core/                         # local Swift Package — NO SwiftUI/UIKit/Vision import
    Sources/
      CoreModel/                # DrinkOption, MenuItem, Provenance<T>, BeverageCategory, ValueMetric
      CoreContracts/            # TextRecognizer, BeverageKnowledge, PurchaseController, AdPresenter
      CoreServices/             # MenuParser, ABVEstimator, SizeEstimator, ValueRanker  (all PURE)
    Tests/
      CoreModelTests/
      CoreServicesTests/        # fixture-driven; this is where the value prop is proven
  AppTarget/
    Sources/
      Features/
        Capture/                # camera + photo-library picker + 21+ gate
        Results/                # ranked list, provenance badges, inline correction
        Paywall/                # $0.99 Remove-Ads unlock
      Infrastructure/           # the impure shell (implements the CoreContracts protocols)
        VisionTextRecognizer/   # Apple Vision text recognition
        RevenueCatPurchases/    # RevenueCat SDK wrapper
        RevenueCatAds/          # RevenueCat Ads (AdMob underneath) wrapper
    Tests/
  Tooling/                      # fixture capture, a lint/test gate script
```

The `Core` package compiles with **no Apple UI or Vision imports** — that boundary is what
forces the pure/impure split (§7) and keeps the whole value engine unit-testable without a
camera or a simulator.

---

## §4. Layer table

| Layer | Lives in | Depends on | Job |
|---|---|---|---|
| **Model** | `CoreModel` | nothing | The `DrinkOption` spine + the `Provenance<T>` wrapper + units. |
| **Contracts** | `CoreContracts` | CoreModel | Protocols the shell implements: OCR, beverage knowledge, purchases, ads. |
| **Services (pure)** | `CoreServices` | CoreModel | Parse text → items; estimate ABV/size; compute + sort the value metric. |
| **Features (UI)** | `AppTarget/Features` | Core | Capture, Results, Paywall. Thin — no business logic. |
| **Infrastructure (shell)** | `AppTarget/Infrastructure` | Core (protocols) | Vision, RevenueCat, RevenueCat Ads. The only impure code. |

Dependency direction points down only. `CoreServices` never imports Vision or RevenueCat;
it depends on the *protocols* in `CoreContracts`, and the shell supplies the real
implementations at app startup.

---

## §6. The contracts (four small protocols)

Everything that touches the outside world sits behind one of these, so the core stays pure
and the whole pipeline is testable with fakes:

- **`TextRecognizer`** — `func recognizeLines(in image) async throws -> [String]`.
  Real impl: Apple **Vision** (`VNRecognizeTextRequest`, on-device, free, no network).
  Test impl: returns canned lines from a fixture.
- **`BeverageKnowledge`** — `func profile(for name: String) -> (category, typicalABV, typicalSize)`.
  Real impl: a static lookup table of beverage categories → typical ABV + pour size. (This
  one can actually be pure and live in Core; keep it behind the protocol anyway so it's
  swappable/tunable and testable.)
- **`PurchaseController`** — query the `remove_ads` entitlement; buy it; restore.
  Real impl: **RevenueCat**. Test impl: in-memory fake.
- **`AdPresenter`** — show/hide banner + occasional interstitial.
  Real impl: **RevenueCat Ads**. Test impl: no-op. **Gated:** if `remove_ads` is active,
  the app never constructs the real `AdPresenter` at all.

Adding or swapping any external dependency is then a one-file change behind a fixed
interface. That's the modularity test from the conventions doc.

---

## §7. Pure core / impure shell

All four services are **pure** — no I/O, no framework, deterministic, fast, fixture-tested:

- **`MenuParser`** — `[String] (OCR lines) -> [MenuItem]`. Detects a price on a line
  (currency regex), pulls the name, and opportunistically detects an explicit size
  ("16 oz", "pint") or an explicit ABV ("5.5% ABV") when the menu prints them. Lines with
  no price → a `needsPrice` bucket, never dropped silently.
- **`ABVEstimator`** — `MenuItem -> Provenance<Double>`. If the menu printed an ABV, it's
  `.read`. Otherwise map the name/category to a typical ABV via `BeverageKnowledge` and
  return `.estimated`.
- **`SizeEstimator`** — same shape for serving volume (draft → pint, wine → 5 oz pour,
  cocktail → standard serving, shot → 1.5 oz), `.read` when printed, else `.estimated`.
- **`ValueRanker`** — `[DrinkOption] -> [RankedDrink]`, sorted best value first. Pure math
  (formulas below). Items in the `needsPrice` bucket are excluded from the ranking by
  construction, satisfying the price invariant.

The shell (`VisionTextRecognizer`, `RevenueCatPurchases`, `RevenueCatAds`) is thin wiring
that adapts a framework to a protocol. It's the only code that can't run in a plain unit
test, and it stays as small as possible.

### The metric (headline: **standard drinks per dollar**)

Use the US standard drink so the number is defensible and unit-consistent:

```
pure_ethanol_floz = serving_volume_floz × (ABV_percent / 100)
standard_drinks    = pure_ethanol_floz / 0.6          # 0.6 fl oz ethanol = 1 US standard drink
value              = standard_drinks / price_dollars   # higher = better value
```

**v2 calories-per-dollar** runs on the *same* pipeline, swapping the metric:

```
ethanol_grams = pure_ethanol_floz × 23.34             # 29.57 mL/floz × 0.789 g/mL
alcohol_kcal  = ethanol_grams × 7.1
value_cal     = alcohol_kcal / price_dollars
```

Ship v1 calories as **alcohol-only kcal**, clearly labeled a lower bound — beer/cocktail
sugars add more and are their own estimate problem (Risk R4). Don't try to model mixers in
v1.

---

## §8. Tests mirror modules

`CoreServicesTests` is where the app is really proven. Before any camera exists:

- **`MenuParserTests`** — feed fixture OCR-line arrays (transcribed from a handful of real
  menu photos), assert the parsed `{name, price, size?}`, and assert no-price lines land in
  the right bucket.
- **`ABVEstimatorTests` / `SizeEstimatorTests`** — assert `.read` when the text has the
  value, `.estimated` otherwise, with a sane category default.
- **`ValueRankerTests`** — assert the ordering on known inputs (worked example: a 16 oz /
  6.5% draft at $7 ≈ 1.73 drinks → 0.248/$, which should beat a 3 oz / 40% well double at
  $10 → 0.20/$).
- **Invariant test** — construct a menu with one priceless line; assert it is *never*
  present in the ranked output. (§10)

Keep a couple of real menu photos transcribed into fixtures under `Tooling/` — that's your
"inspect before you build" artifact (§5): decide the parser against real text, not
remembered menu formatting.

---

## §10. Structurally-enforced invariant

Make the price rule impossible to violate rather than merely documented: `ValueRanker`
accepts a type that **cannot hold a nil price** (e.g. it takes `[PricedDrink]`, and
`PricedDrink` is only constructible with a real, read price). Items without a price never
have the type required to enter the ranker, so no future edit can accidentally rank a
guessed price. The `needsPrice` items travel on a separate path to the "add a price"
UI.

---

## §11. Provenance (the honesty core)

The whole app hangs off one small type:

```swift
enum Provenance<Value> {
    case read(Value)                 // taken directly off the menu
    case estimated(Value, note: String)   // inferred; note explains the assumption
    var value: Value { ... }
}
```

`DrinkOption` carries `price` (always `.read`), `abv: Provenance<Double>`, and
`size: Provenance<Volume>`. The Results UI renders estimated axes distinctly (a badge / an
asterisk, tappable to reveal the assumption — "assumed 16 oz pint") and lets the user
correct any estimate inline; correcting promotes it to `.read` and re-ranks. The ranking is
honest at a glance about how much of it is inference.

---

## §13. Risks (tagged; cross-reference from code comments)

- **R1 — OCR/parsing on real menus *(existential for the utility)*.** If it can't reliably
  pull name+price from a photo of a real menu, nothing downstream matters. *Mitigation:*
  Vision on-device text recognition handles clean printed menus well; ship a fast **manual
  add / edit** path from day one so a partial read is still usable, and treat OCR as
  "assist," not "only way in." Test against transcribed real-menu fixtures (§8).
- **R2 — Estimates can be badly wrong** (craft cocktails, unknown pours, house wine).
  *Mitigation:* flag every estimate (§11), one-tap correction, show the assumption. The app
  promises "best value *given these assumptions*," visibly.
- **R3 — App Review + ads in an alcohol context.** Apple is wary of apps that appear to
  encourage excessive drinking; ad networks restrict alcohol-adjacent inventory.
  *Mitigation:* frame strictly as an informational **price-comparison** tool (not "get drunk
  cheapest"), add a **21+ age gate** on first launch, and verify the ad network's alcohol
  policy before relying on the revenue. Not legal advice — confirm the current App Review
  guideline wording when you write the listing.
- **R4 — calories/$ is a much softer estimate than alcohol/$** (sugar/mixers).
  *Mitigation:* v2 only; ship as alcohol-only kcal lower bound, heavily flagged.
- **R5 — the five-week window incl. review *(schedule)*.** *Mitigation:* the pure pipeline
  ships first and proves the value with zero UI; scope is cut to the bone; submission is
  scheduled early with a resubmit buffer (§B).

---

## §14. How to add a new ranking metric (the one recipe you'll reuse)

1. Add a case to `ValueMetric` (e.g. `.caloriesPerDollar`).
2. Add the pure formula to `ValueRanker` (it already has `pure_ethanol_floz`).
3. Add a `ValueRankerTests` case with a worked example.
4. Add a segmented toggle in the Results feature. No other layer changes.

That localization is the whole point — the calories ranking is a metric swap, not a rebuild.

---

# §A. Monetization wiring (RevenueCat)

- **RevenueCat Ads** for revenue (banner on Results; at most an occasional interstitial —
  keep it "an experience users don't hate," which is literally the ads-award criterion).
  Wrap it behind `AdPresenter`.
- **$0.99 "Remove Ads"** — a **non-consumable** product mapped to a RevenueCat
  `remove_ads` **entitlement**. On launch, `PurchaseController` checks the entitlement; if
  active, the app **never initializes ads**. This is a real feature *and* the belt-and-
  suspenders IAP so the entry qualifies regardless of how the "ads-only" rule is read.
- Set up the RevenueCat project + App Store Connect product early (App Review needs the IAP
  approved alongside the build). Test with RevenueCat's Test Store while building, sandbox
  before submitting.

---

# §B. Five-week build plan (today is Aug 25 → hard deadline Sep 30)

The rule of the schedule: **the value engine is done and tested before any camera code**,
and **submission targets ~Sep 18–20** to leave a real review + resubmit buffer.

**Week 0 — Aug 25–31 · Foundations + the value engine (no UI).**
Repo per the conventions doc; `Core` package; `Provenance<T>`, `DrinkOption`, units; the
four `CoreContracts` protocols. Build and fully unit-test `MenuParser → ABVEstimator →
SizeEstimator → ValueRanker` against transcribed real-menu fixtures. Register on Devpost;
create the App Store Connect app record + RevenueCat project + the `remove_ads` product now
(they gate later steps). *Exit:* `swift test` green — the app "works" headless.

**Week 1 — Sep 1–7 · Capture + Results.**
`VisionTextRecognizer` behind `TextRecognizer`; wire photo/camera → OCR → parse → rank.
Results screen with provenance badges and inline correction; the `needsPrice` add-a-price
path; the **21+ gate**. *Exit:* end-to-end from a photo to a ranked list on device.

**Week 2 — Sep 8–14 · Monetization + polish.**
RevenueCat SDK + `remove_ads` IAP + entitlement gating; RevenueCat Ads banner/interstitial;
Paywall screen. Tighten the Results UI and empty/error states. *Exit:* ads show, purchase
removes them, entitlement persists.

**Week 3 — Sep 15–21 · Harden + submit.**
Test on messy real menus; fix the top parsing failures; (optional, only if ahead) the
calories/$ toggle. Store assets: screenshots, description (informational framing),
privacy nutrition labels (Vision is on-device → no data collected, which is a clean story).
**Submit to App Review by ~Sep 18–20.** *Exit:* build in review.

**Week 4 — Sep 22–30 · Land it.**
Respond to any review rejection and resubmit (this buffer is why we submitted early);
release the public version **inside the window**; complete the **Devpost submission**;
post a couple of #BuildInPublic notes. *Exit:* live on the App Store + submitted to
Shipaton before Sep 30.

**Cut-first list if time slips:** calories/$ (v2), interstitial ads (banner only),
camera live-preview (photo-library import only), any menu-format cleverness beyond
"line with a price." Ship the thin thing that ranks honestly.
