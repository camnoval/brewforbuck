# Bang-for-Buck — Architecture & Build Plan

*The app-specific design doc for the alcohol value-ranker. Read it alongside
**PROJECT_CONVENTIONS.md** — this file instantiates that playbook for one app, and the
`§` numbers below mirror the conventions doc so you can jump between them. Scope is
deliberately small: this is a clean, single-purpose utility shipped inside the Shipaton
2026 window, not a platform.*

> **Hard external constraint.** Shipaton 2026 requires the app's **first public version**
> to be **released** (not merely submitted) between **Aug 1 and Sep 30, 2026**, integrate the
> **RevenueCat SDK** powering at least one in-app purchase *or* serving ads through RevenueCat
> Ads, and be a brand-new listing. App Review eats into the window, so the schedule (§B)
> submits early on purpose.
>
> **Revised 2026-09-09: v1 ships the purchase only, no ads.** The original plan did both paths.
> Two findings killed the ad half: **RevenueCat Ads is a beta analytics feature, not an ad
> network** — it reports on an ad SDK you already have and serves nothing — and **AdMob cannot
> serve until the app is already live and linked**, which makes a working banner impossible in the
> build App Review sees. The purchase alone qualifies. Cutting ads also keeps the privacy labels
> at "no data collected", which is true because Vision is on-device. See `MonetizationPlan.md`
> and `AdsPlan.md`.

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

1. **Capture flow** — photo → OCR text boxes → `LineAssembler` reassembles them into
   lines/columns → parse into `{name, price, maybe size}` → enrich with estimated ABV/size
   where the menu didn't say → an editable `MenuSession` of drinks.
2. **Ranking flow** — the session computes the value metric → sorts best-to-worst → present,
   with estimated values visibly flagged and one-tap correctable, prices editable, and drinks
   addable/removable by hand.

**The two load-bearing rules** (the invariants everything else protects):

- **Price is the one thing we never fabricate.** A line with no readable price is *not*
  ranked with a guessed price — it drops to a "couldn't read a price" bucket the user can
  fix. Everything else (ABV, size) may be estimated; price may not. (§10)
- **Estimated never masquerades as measured.** Every axis knows its own provenance and the
  UI shows it. A ranking built on guesses is fine as long as it's honest that they're
  guesses. (§11)

Both rules turned out to have stricter cases at home than the ones they were written for. The price
rule now governs the app's own purchase prices, and the provenance rule now reserves the colour
amber for exactly one meaning. See §10 and §11.

---

## §3. Directory layout (single app, local Core package)

```
BangForBuck/
  docs/                         # this doc, plus README / Handoff / Risks / Changelog
  Core/                         # local Swift Package — NO SwiftUI/UIKit/Vision import
    Sources/
      CoreModel/                # DrinkOption, MenuItem, Provenance<T>, BeverageCategory, ValueMetric
      CoreContracts/            # TextRecognizer, BeverageKnowledge, PurchaseController
      CoreServices/             # MenuParser, ABVEstimator, SizeEstimator, ValueRanker,
                                #   PaywallFlow, SupporterPrompt  (all PURE)
    Tests/
      CoreModelTests/
      CoreContractsTests/
      CoreServicesTests/        # fixture-driven; this is where the value prop is proven
  AppTarget/
      Design/                   # Theme.swift — the only place colours, fonts and spacing live
      Features/
        AgeGate/                # informational 21+ confirmation, once (R3)
        Capture/                # camera + photo-library picker  (actually nested under Results/)
        Results/                # ranked list, provenance badges, inline correction
        Compare/                # the store-shelf calculator (Goal 2)
        Shared/                 # ValueChips — the vocabulary both ranked lists render through
        Supporter/              # SupporterStore, PaywallView, SupporterBadge
      Infrastructure/           # the impure shell (implements the CoreContracts protocols)
        VisionTextRecognizer/   # Apple Vision text recognition
        RevenueCatPurchases/    # RevenueCat SDK wrapper — the only file that imports it
    Tests/
  Tooling/                      # fixture capture, a lint/test gate script
```

The `Core` package compiles with **no Apple UI or Vision imports, and no RevenueCat import** — that
boundary is what forces the pure/impure split (§7) and keeps the whole value engine unit-testable
without a camera or a simulator.

There is deliberately **no ads wrapper**. When a banner arrives in v1.1 it will be an `AppTarget`
type with no `Core` representation at all, because AdMob's banner is a `UIView` and a protocol in
`Core` cannot return a `UIViewRepresentable` without `Core` importing SwiftUI.

---

## §4. Layer table

| Layer | Lives in | Depends on | Job |
|---|---|---|---|
| **Model** | `CoreModel` | nothing | The `DrinkOption` spine + the `Provenance<T>` wrapper + units. |
| **Contracts** | `CoreContracts` | CoreModel | Protocols the shell implements: OCR, beverage knowledge, purchases. |
| **Services (pure)** | `CoreServices` | CoreModel | Parse text → items; estimate ABV/size; compute + sort the value metric; the paywall state machine. |
| **Features (UI)** | `AppTarget/Features` | Core | Capture, Results, Compare, Supporter. Thin — no business logic. |
| **Infrastructure (shell)** | `AppTarget/Infrastructure` | Core (protocols) | Vision, RevenueCat. The only impure code. |

Dependency direction points down only. `CoreServices` never imports Vision or RevenueCat;
it depends on the *protocols* in `CoreContracts`, and the shell supplies the real
implementations at app startup. **The test of this is that `Core` still builds on Linux.** If it
stops, the boundary has been broken — that is the check, not a code review.

The `Features` layer being "thin" is enforced rather than encouraged: the paywall's entire behaviour
is `PaywallFlow`, a pure function in `CoreServices`, so `PaywallView` renders a state and reports an
event and contains no transition of its own.

---

## §6. The contracts (three small protocols)

Everything that touches the outside world sits behind one of these, so the core stays pure
and the whole pipeline is testable with fakes:

- **`TextRecognizer`** — `func recognizeLines(in image) async throws -> [String]`.
  Real impl: Apple **Vision** (`VNRecognizeTextRequest`, on-device, free, no network).
  Test impl: returns canned lines from a fixture.
- **`BeverageKnowledge`** — `func profile(for name: String) -> (category, typicalABV, typicalSize)`.
  Real impl: a static lookup table of beverage categories → typical ABV + pour size. (This
  one can actually be pure and live in Core; keep it behind the protocol anyway so it's
  swappable/tunable and testable.)
- **`PurchaseController`** — the `supporter` entitlement. `supporterTiers()` fetches the price
  tiers, `purchase(_ tier:)` buys the one that was displayed, `restorePurchases()` reports whether
  anything was found, `supporterStatus()` says whether support is active and which product granted
  it. Real impl: **RevenueCat**. Test impl: `InMemoryPurchaseController`, configurable across every
  branch (no tiers, cancel, Ask-to-Buy hold, thrown failure, nothing-to-restore).

  Three deliberate details: the tier's price is a **`String` from the store, never a number**, so
  nothing in `Core` can format a price wrongly (§10 applied to our own money); `purchase` takes the
  tier so the amount charged is provably the amount shown; and `supporterStatus()` **fails closed**
  to "not a supporter", because claiming support on an error would give the product away and would
  silently disable the future ad gate through an untested path.

- ~~**`AdPresenter`**~~ — **deleted 2026-09-09.** It was written against "RevenueCat Ads", which is
  a beta analytics feature rather than an ad network, so the protocol described a capability nobody
  had. It was deleted rather than reshaped, because a protocol designed for an SDK nobody has used
  is the mistake, not its method signatures. `Core`'s only stake in ads is one boolean. See §5 of
  `ProjectConventions.md` and `AdsPlan.md`.

Adding or swapping any external dependency is then a one-file change behind a fixed
interface. That's the modularity test from the conventions doc.

**The corollary, learned the hard way:** the pattern only protects you if the interface was designed
against something real. A contract written from a *remembered* description of a vendor's product
locks the mistake in behind a fixed interface, where it looks like architecture.

---

## §7. Pure core / impure shell

All these services are **pure** — no I/O, no framework, deterministic, fast, fixture-tested:

- **`LineAssembler`** — `[TextObservation] (OCR boxes) -> [String]`. Vision returns many small
  boxes in no reading order and often splits one menu row (name left, price right); this detects
  columns (two-column menus are common) and assembles each column into ordered lines so the parser
  sees one item per line. Pure/geometry-only, tested against synthetic boxes (R1).
- **`MenuParser`** — `[String] (OCR lines) -> [MenuItem]`. Detects a price on a line
  (no regex — char scanning), pulls and **cleans** the name (strips embedded `ABV x%`/size), and
  opportunistically detects an explicit size ("16 oz", "22oz.") or ABV ("5.5% ABV") when printed.
  Section-state machine (Change A); recognizes `drafts`/`cans`/`bottles`/… headers. Lines with
  no price → a `needsPrice` bucket, never dropped silently.
- **`ABVEstimator`** — `MenuItem -> Provenance<Double>`. If the menu printed an ABV, it's
  `.read`. Otherwise map the name/category to a typical ABV via `BeverageKnowledge` and
  return `.estimated`.
- **`SizeEstimator`** — same shape for serving volume (draft → pint, wine → 5 oz pour,
  cocktail → standard serving, shot → 1.5 oz), `.read` when printed, else `.estimated`.
- **`ValueRanker`** — `[DrinkOption] -> [RankedDrink]`, sorted best value first. Pure math
  (formulas below). Items in the `needsPrice` bucket are excluded from the ranking by
  construction, satisfying the price invariant.
- **`MenuSession`** — the interactive layer over the above: holds one menu's `[EditableDrink]`
  (each with a stable `id`), re-ranks on read using the same `ValueRanker` math, and exposes pure
  edits — correct an estimate, set a price, add a missed drink, remove a misread one. Every edit
  preserves both invariants (a manual add is forced alcoholic; a price is still never fabricated).
- **`MenuQualityGate`** — `[MenuItem] -> MenuQuality`. Flags a thin read (`isLowConfidence`) below a
  0.25 priced fraction, and only once there are at least 8 parsed items to judge on. Load-bearing
  beyond the UI caveat: it also suppresses the supporter prompt (below).
- **`PaywallFlow`** — the paywall as one pure function, `next(from: PaywallState, on: PaywallEvent)`.
  No SwiftUI, no SDK, no clock. Every state that can return to the tier list carries the tiers, so a
  cancel does not refetch. Inapplicable `(state, event)` pairs return the state unchanged, so a late
  reply cannot resurrect a dismissed sheet or walk a finished purchase backwards. There is
  deliberately **no state meaning "showing prices I do not have"**: a failed fetch becomes
  `.unavailable` with a retry.
- **`SupporterPrompt`** — the four rules for when the app may ask for money: never an existing
  supporter, never twice, **never on a thin read**, never without at least two ranked drinks to
  compare. Also `SupporterTierKind`, a closed set resolved from the granting product identifier by
  suffix, so an unrecognized tier degrades to a plainer badge rather than a wrong one.

The shell (`VisionTextRecognizer`, `RevenueCatPurchases`) is thin wiring that adapts a framework to
a protocol. It's the only code that can't run in a plain unit test, and it stays as small as
possible. `SupporterStore` in `AppTarget` is the monetization feature's only impure part: one
entitlement read and one persisted "already asked" flag.

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

**One thing the metric may not be used for.** Do not multiply a purchase price by a
drinks-per-dollar rate to say what a tip "buys" in drinks. The tier is priced in the customer's App
Store currency and the menu was priced in whatever the venue printed; dividing one by the other
produces a confident wrong number for anyone outside the US storefront. A dimensionless ratio
between two values under the *same* metric is safe; mixing money systems is not.

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
- **`PaywallFlowTests`** — every transition, plus explicit cases proving that inapplicable events
  are ignored. The paywall's six outcomes are testable in milliseconds because none of them live in
  the view.
- **`SupporterPromptTests`** — one test per ask rule, so each rule fails loudly if removed.

Keep a couple of real menu photos transcribed into fixtures under `Tooling/` — that's your
"inspect before you build" artifact (§5): decide the parser against real text, not
remembered menu formatting.

> **XCTest gotcha.** `XCTAssertEqual` and friends take a **non-async** autoclosure, so
> `XCTAssertEqual(await thing(), x)` does not compile. Hoist every `await` into a `let` first. Same
> for reading an actor-isolated property. See `ProjectConventions.md` §8.

---

## §10. Structurally-enforced invariant

Make the price rule impossible to violate rather than merely documented: `ValueRanker`
accepts a type that **cannot hold a nil price** (e.g. it takes `[PricedDrink]`, and
`PricedDrink` is only constructible with a real, read price). Items without a price never
have the type required to enter the ranker, so no future edit can accidentally rank a
guessed price. The `needsPrice` items travel on a separate path to the "add a price"
UI.

**Extended 2026-09-09 to the app's own prices.** The rule was written about prices read off a photo.
It applies with more force to a number shown to somebody in the instant before they are charged.
Three structural consequences, each tested:

- `SupporterTier.displayPrice` is a **`String` from the store, never a number.** There is no numeric
  price anywhere in `Core`, so nobody downstream can format one and no locale can be got wrong.
- `purchase(_ tier:)` takes **the tier that was displayed** rather than re-resolving the product
  internally, so the amount charged is provably the amount shown instead of coincidentally equal
  to it.
- `PaywallFlow` has **no state meaning "showing prices I do not have."** A failed offering fetch
  becomes `.unavailable` with a retry, so the honest response to missing data is structurally the
  only available one.

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

**Amber is reserved, and the reservation is an invariant.** `Theme.amber` means "this number is an
estimate" and nothing else in the product wears it. The supporter badge is green, and the paywall's
messages are plain muted text rather than the amber `Notice` component. The moment a second meaning
shares the signal, the first one stops being information — and because adding an amber element to an
unrelated feature looks like a styling choice in a diff, this rule lives next to the colour in
`Theme.swift` as well as here.

A related failure worth remembering: the honesty badge itself was once silently truncating to
"estimat…" depending on whether an ABV had a decimal point, because an overflowing `HStack`
compressed its children instead of wrapping. The §11 promise failing intermittently on the width of
a decimal point is why `ChipFlow` exists.

---

## §13. Risks (tagged; cross-reference from code comments)

*`Risks.md` is the living register and has the full versions. Keep this summary in sync.*

- **R1 — OCR/parsing on real menus *(existential for the utility)*.** If it can't reliably
  pull name+price from a photo of a real menu, nothing downstream matters. *Mitigation:*
  Vision on-device text recognition handles clean printed menus well; ship a fast **manual
  add / edit** path from day one so a partial read is still usable, and treat OCR as
  "assist," not "only way in." Test against transcribed real-menu fixtures (§8).
- **R2 — Estimates can be badly wrong** (craft cocktails, unknown pours, house wine).
  *Mitigation:* flag every estimate (§11), one-tap correction, show the assumption. The app
  promises "best value *given these assumptions*," visibly.
- **R3 — App Review in an alcohol context.** Apple is wary of apps that appear to encourage
  excessive drinking. *Mitigation:* frame strictly as an informational **price-comparison** tool
  (not "get drunk cheapest"), a **21+ age gate** on first launch (shipped), an age rating that
  reflects the alcohol reference, and product/paywall copy that stays on the price-transparency
  side of that line. **The ad half of this risk is retired for v1 by shipping no ads** — see
  `Risks.md` R3 for the two findings and `AdsPlan.md` for v1.1. New sub-risk: never sell an
  entitlement whose described benefit is absent from the build, which is why the product is
  `supporter` and not `remove_ads`. Not legal advice — confirm the current App Review guideline
  wording when you write the listing.
- **R4 — calories/$ is a much softer estimate than alcohol/$** (sugar/mixers).
  *Mitigation:* v2 only; ship as alcohol-only kcal lower bound, heavily flagged.
- **R5 — the window incl. review *(schedule)*.** *Mitigation:* the pure pipeline ships first and
  proves the value with zero UI; scope cut to the bone; submit ~Sep 18–20 with a resubmit buffer
  (§B). **Two hedges added 2026-09-09:** ads are out of scope, removing the largest uncontrollable
  block of work; and the Next Gen category needs a video and open-source code rather than a live
  listing, so a late rejection no longer means no entry.
- **R6 — App Store Connect may not let the first IAP reach review** (new). A brand-new app's first
  in-app purchase must be submitted with a binary, and the section for attaching it is widely
  reported not to render. *Mitigation:* archive and upload a throwaway build early and confirm the
  section exists.
- **R7 — the RevenueCat credential fails silently** (new). SDK 5.x needs an In-App Purchase Key, not
  a shared secret; without it transactions are not recorded and customers pay for nothing. A product
  identifier typo yields an empty paywall with no error.

---

## §14. How to add a new ranking metric (the one recipe you'll reuse)

1. Add a case to `ValueMetric` (e.g. `.caloriesPerDollar`).
2. Add the pure formula to `ValueRanker` (it already has `pure_ethanol_floz`).
3. Add a `ValueRankerTests` case with a worked example.
4. Add a segmented toggle in the Results feature. No other layer changes.

That localization is the whole point — the calories ranking is a metric swap, not a rebuild.

---

# §A. Monetization wiring (RevenueCat)

*Summary only. `MonetizationPlan.md` is the design of record and explains every choice below;
`AdsPlan.md` covers v1.1.*

- **A supporter purchase, not a "remove ads" unlock.** Three **non-consumables** —
  `supporter.shot` ($1.99), `supporter.pint` ($4.99), `supporter.round` ($9.99) — all mapped to one
  RevenueCat entitlement, **`supporter`**. Any tier grants the same thing; the tiers are how much
  you choose to give, not how much you get. Tiers come from a Current Offering, so they can be
  repriced and reordered from the dashboard without a build.
- **Named after drinks on purpose.** The app is denominated in dollars per standard drink, so the
  tip jar is too. The names live in App Store Connect, so they localize with the rest of the product
  page.
- **`supporter`, not `remove_ads`, and the distinction is load-bearing.** v1 has no ads, and selling
  a feature the build lacks is a rejection risk, so **v1 copy must not mention ads.** When the
  banner ships in v1.1 the ad gate checks this same entitlement, so v1 buyers are already covered:
  no second product, no migration, no re-review.
- **One-time by construction.** Non-consumables cannot be re-bought, and the paywall shows the
  thank-you state instead of the tier list once the entitlement is active.
- **The gate is at construction, not at render.** When ads exist, an entitled device must never
  build the ad SDK's objects at all. There must be no path where a paying customer initializes an ad
  SDK and then hides the result. This is why `supporterStatus()` fails closed.
- **All behaviour is pure.** `PaywallFlow` is the state machine, `SupporterPrompt` is the four ask
  rules, both in `CoreServices` with tests. `SupporterStore` in `AppTarget` is the only impure part:
  one entitlement read and one persisted "already asked" flag.
- **The ask is earned.** The prompt appears only after a scan that produced a ranking of at least
  two drinks, never when `MenuQuality.isLowConfidence` fired, never to an existing supporter, and
  never twice. Asking for money after a read the app does not trust is the wrong instinct, and that
  rule is the one most worth keeping if anything here is cut.
- **Store setup gates everything and involves waiting on Apple.** In order: Paid Apps Agreement
  (Account Holder only), Tax and Banking to status **"Clear"** (days, and no purchase can be tested
  until it lands), App ID, app record, the three products, the **In-App Purchase Key** (StoreKit 2
  requires it; the App-Specific Shared Secret is the wrong credential for SDK 5.x), then RevenueCat.
  Test with the Test Store while building — **a Test Store key must never ship** — and sandbox
  before submitting.
- **Visual rules.** The supporter badge and the paywall's messages never use `Theme.amber` or the
  `Notice` component, because amber means "this number is an estimate" and nothing else (§11).

---

# §B. Five-week build plan (today is Aug 25 → hard deadline Sep 30)

The rule of the schedule: **the value engine is done and tested before any camera code**,
and **submission targets ~Sep 18–20** to leave a real review + resubmit buffer.

**Week 0 — Aug 25–31 · Foundations + the value engine (no UI).**
Repo per the conventions doc; `Core` package; `Provenance<T>`, `DrinkOption`, units; the
`CoreContracts` protocols. Build and fully unit-test `MenuParser → ABVEstimator →
SizeEstimator → ValueRanker` against transcribed real-menu fixtures. Register on Devpost;
create the App Store Connect app record + RevenueCat project + the products now
(they gate later steps). *Exit:* `swift test` green — the app "works" headless.

**Week 1 — Sep 1–7 · Capture + Results.**
`VisionTextRecognizer` behind `TextRecognizer`; wire photo/camera → OCR → parse → rank.
Results screen with provenance badges and inline correction; the `needsPrice` add-a-price
path; the **21+ gate**. *Exit:* end-to-end from a photo to a ranked list on device.

**Week 2 — Sep 8–14 · Monetization.**
Revise `PurchaseController` against a real paywall's needs; `PaywallFlow` + `SupporterPrompt` in
pure `CoreServices` with tests; `PaywallView` + `SupporterBadge` on `Theme` tokens, previewable
against the in-memory double with no SDK. Then the RevenueCat SDK, `RevenueCatPurchases` in
`Infrastructure`, and a Test Store purchase end to end. *Exit:* a purchase flips the entitlement,
restore works, and the badge survives a relaunch.

**Week 3 — Sep 15–21 · Harden + submit.**
Land `ValueFigure`/`PourLine` in the ranked row and the `isLowConfidence` `Notice` — both already
written, both unused, and together they are the Design Award submission, so they are **not** on the
cut list. Make the 1948 Roosevelt list a built-in demo, because judges open the app once with no
menu in front of them. Screenshot the real paywall for the products' Review Information and get them
to "Ready to Submit". Sandbox purchase on device. **Archive early and confirm the "In-App Purchases
and Subscriptions" section renders on the version page (R6).** Store assets: screenshots,
description with the informational framing (R3), privacy labels — **"no data collected" is true and
stays true because no ad SDK is linked.** **Submit by ~Sep 18–20.** *Exit:* build in review with the
three products attached.

**Week 4 — Sep 22–30 · Land it.**
Respond to any rejection and resubmit (this buffer is why we submitted early); **release** the
public version inside the window, since the rules require released rather than approved; complete
the Devpost submission including Next Gen with an academic email; make the repo public after the
`LICENSE` / attribution / EXIF checklist in `ShipatonSubmission.md`; record the video; post the
#BuildInPublic notes. *Exit:* live on the App Store and submitted to Shipaton before Sep 30.

**Cut-first list if time slips**, in this order: the share card, the 1948 demo menu, paywall copy
refinement, calories/$ (v2), camera live-preview (photo-library import only), any menu-format
cleverness beyond "line with a price." Ship the thin thing that ranks honestly.

**Do not cut** `ValueFigure`/`PourLine` or the `isLowConfidence` `Notice`. They are written, they
are unused, and they are the highest-value work left in the repo. Ads are not on this list because
they are not in v1 at all.
