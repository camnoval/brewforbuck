# ABV: A Better Value

*Formerly "Bang-for-Buck". The repo directory, Xcode target and bundle
identifier still carry the old name on purpose; see the Handoff for why.*

**Take a picture of a drink menu, get the alcoholic options ranked by value — how much
alcohol you get per dollar — so you can pick the best deal at a glance.** (v2 adds a
calories-per-dollar ranking on the same pipeline.)

Built for the **Shipaton 2026** window (first public version **released** Aug 1 – Sep 30, 2026),
integrating the RevenueCat SDK.

## Run it

The value engine is a pure, framework-free Swift package that builds and tests anywhere:

```bash
cd Core
swift test        # 316 tests, the whole value engine headless — no camera, no simulator
```

Or run the full pre-flight gate:

```bash
./Tooling/run_checks.sh
```

The iOS app (`AppTarget/`) — camera/library → Vision OCR → editable, ranked results behind a 21+
gate — opens in Xcode on macOS against the local `Core` package. Deployment target iOS 18.6.

## Where monetization stands

A supporter purchase, not a "remove ads" unlock: three non-consumable tiers named after drinks
(`supporter.shot`, `supporter.pint`, `supporter.round`) all granting one `supporter` entitlement.

- ✅ The pure layer: revised `PurchaseController`, `PaywallFlow`, `SupporterPrompt`
- ✅ The UI: `PaywallView`, `SupporterBadge`, the prompt on Results, seven previews
- ⏳ The RevenueCat SDK dependency and `Infrastructure/RevenueCatPurchases.swift`
- ⏳ Review screenshots, sandbox purchase, submission

**No ads in v1**, and that is a design decision rather than a deferral: RevenueCat Ads turns out to
be a beta analytics feature rather than an ad network, and AdMob cannot serve until the app is
already live. See `AdsPlan.md`. A side effect worth protecting: with no ad SDK there is no IDFA, no
ATT prompt, and the privacy labels honestly say **no data collected**, because Vision runs
on-device.

## The two promises the code keeps

1. **A price is never fabricated.** A drink with no readable price is set aside rather than ranked on
   a guess, enforced by type. This extends to the app's own prices: a purchase tier carries the
   store's price *string*, never a number the app could format wrongly.
2. **An estimate never presents as measured.** Every axis carries its `Provenance`, and amber in the
   UI means exactly one thing: this number was estimated.

## Where to go next

| If you want… | Read |
|---|---|
| The design & data flow | [`Architecture.md`](./Architecture.md) — **start here for design** |
| The portable playbook this app instantiates | [`ProjectConventions.md`](./ProjectConventions.md) |
| A file-by-file map of the code | [`CodebaseReference.md`](./CodebaseReference.md) |
| The current directory tree (auto-generated) | [`ProjectStructure.md`](./ProjectStructure.md) |
| **Current state + what to do next** | [`Handoff.md`](./Handoff.md) — **start here for work** |
| How the purchase is designed and why | [`MonetizationPlan.md`](./MonetizationPlan.md) |
| The v1.1 ad work, and why it isn't in v1 | [`AdsPlan.md`](./AdsPlan.md) |
| Competition categories + the open-sourcing checklist | [`ShipatonSubmission.md`](./ShipatonSubmission.md) |
| The plan for the menu-reading test pass (done) | [`MenuTestingPlan.md`](./MenuTestingPlan.md) |
| The assumptions that could break it | [`Risks.md`](./Risks.md) |
| Where the ABV/size numbers come from | [`BeverageDataSources.md`](./BeverageDataSources.md) |
| Where the store catalog comes from (and its licence) | [`StoreCatalogSources.md`](./StoreCatalogSources.md) |
| A non-technical overview | [`PlainLanguageGuide.md`](./PlainLanguageGuide.md) |
| Session-by-session history | [`Changelog.md`](./Changelog.md) |

> Read `Architecture.md` and `ProjectConventions.md` together — the former instantiates the
> latter, and their `§` numbers line up so you can jump between them.

## Before this repo goes public

Open-sourcing is a requirement for the Next Gen category and it is hard to undo. Four blockers, all
tracked in [`ShipatonSubmission.md`](./ShipatonSubmission.md): there is **no `LICENSE` file**, the
store catalog's Open Government Licence **requires attribution**, `BangForBuck/photos/` holds real
menu photos whose **EXIF carries GPS**, and API keys must stay out of source.
