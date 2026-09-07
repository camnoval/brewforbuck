# Monetization plan (next session)

*Written 2026-09-07. Menu reading is done for this pass; monetization is the only thing left that
can disqualify the Shipaton entry. This doc is the plan and the conversation opener, in the same
shape as `MenuTestingPlan.md` was for the menu-reading session.*

---

## Paste this to open the next conversation

> I'm working on **ABV: A Better Value** (repo/target still named `BangForBuck`), an iOS app that
> photographs a drink menu and ranks the alcoholic options by standard drinks per dollar. The zip is
> the repo.
>
> **Read `BangForBuck/docs/Handoff.md` first** (newest note on top, each note says what it
> supersedes), then `Architecture.md` §A and §6 for the monetization design, and
> `CodebaseReference.md` for the file map.
>
> **This session's goal: RevenueCat integration — the `remove_ads` IAP, entitlement gating, a
> Paywall, and the ad banner.** Nothing monetization-related exists yet beyond two protocols and
> their test doubles. This is a *qualification* requirement for Shipaton, not a feature.
>
> **The hard constraint is the calendar, not the code.** Shipaton requires the first public version
> live between Aug 1 and Sep 30, 2026, with the RevenueCat SDK integrated and at least one IAP or
> RevenueCat Ads. Today is Sep 7. App Review needs the IAP approved alongside the build, so the
> target is **submit by ~Sep 18–20** with a resubmit buffer. If something has to give, it is the ad
> banner, not the purchase — see "Order of work" below for why.
>
> **My environment:** no Swift toolchain and no network in your bash. You can read the repo, write
> Swift, and reason about it; I run `swift test`, build in Xcode, and paste output back. That
> workflow is how the whole value engine got built and it works well.
>
> **Two things to verify before writing any SDK code, because your training data may be stale on
> both:** the current RevenueCat iOS SDK API surface, and whether **RevenueCat Ads** is generally
> available and what its alcohol-content policy is (R3). Ask me to check the docs, or tell me
> exactly what to look up. **Do not write SDK calls from memory and present them as correct.**
>
> **Start here, before writing code:**
> 1. Read the docs and the two existing protocols (`CoreContracts/PurchaseController.swift`,
>    `CoreContracts/AdPresenter.swift`) plus their doubles in `TestDoubles.swift`.
> 2. Tell me what those protocols are missing for a real paywall and a real banner. I already
>    suspect two gaps (below) — confirm or correct them, and propose the revised protocols before
>    touching the shell.
> 3. Then work in the order under "Order of work", keeping business logic in `CoreServices`/
>    `CoreContracts` with tests, and the SDK strictly inside `AppTarget/Infrastructure`.
>
> **House style:** no em-dashes in user-facing copy; business logic goes in pure `Core` with tests
> rather than in views; both load-bearing invariants hold (a price is never fabricated, an estimate
> never presents as measured). The app's visual tokens live in `AppTarget/Design/Theme.swift` — use
> them, don't introduce new colours or fonts.

---

## Where monetization actually stands

**Nothing is built.** What exists is the seam, not the implementation:

| Piece | State |
|---|---|
| `PurchaseController` protocol | ✅ exists, 3 methods |
| `AdPresenter` protocol | ✅ exists, 3 methods |
| `InMemoryPurchaseController`, `NoopAdPresenter` | ✅ exist, used in tests |
| RevenueCat SDK as a package dependency | ❌ not added |
| A real `PurchaseController` conformer | ❌ |
| A real `AdPresenter` conformer | ❌ |
| Paywall screen | ❌ |
| `remove_ads` product in App Store Connect | ❌ (verify — may not exist) |
| RevenueCat project + entitlement | ❌ (verify) |
| Entitlement check at launch | ❌ nothing calls `isRemoveAdsActive()` |

`Architecture.md` §A describes the intended design and is still the right plan. It has not been
started.

## Two protocol gaps to settle first

Both protocols were written in Phase 3 against a sketch of the feature, not against a real paywall.
Confirm these before building on them:

**1. `PurchaseController` can't drive a paywall.** It answers "is it active" and "buy it", but a
paywall has to *display a price*, and the price is localized and comes from the store — it can't be
hardcoded as "$0.99" without lying to anyone outside the US. There is also no way to distinguish a
user cancelling from a purchase failing, and those need different UI. Likely needs something like a
fetched offering (display price string + product identifier) and a purchase result that names the
cancelled case.

**2. `AdPresenter`'s shape may not fit SwiftUI.** `showBanner()` / `hideBanner()` is an imperative
API from a UIKit world. A banner in SwiftUI is a *view* in the hierarchy, so the natural shape is a
`UIViewRepresentable` the Results screen places, not a method that makes a banner appear from
nowhere. Decide whether `AdPresenter` keeps the imperative shape (and owns a window overlay) or
becomes a factory that vends a view. **This is a design decision, not a detail** — getting it wrong
means the banner fights the layout.

Neither gap is a reason to redesign the world: the protocols are small and only the shell
implements them. Change them deliberately, once, before the SDK work.

## Order of work

**Purchase before ads, deliberately.** The IAP is what makes the entry *qualify* and it is what
App Review has to approve alongside the build. The ad banner is revenue, and revenue can ship in
v1.1. If the calendar bites, shipping "IAP works, no ads" still qualifies; shipping "ads work, no
IAP" may not, depending on how the ads-only rule is read — which is exactly why §A calls the IAP
"qualification insurance".

1. **Store setup.** RevenueCat project, `remove_ads` non-consumable in App Store Connect, mapped to
   a `remove_ads` entitlement. Test with RevenueCat's Test Store while building; sandbox before
   submitting. *This gates everything else and involves waiting on Apple, so start it first.*
2. **Revise the two protocols** per the gaps above, with the doubles updated to match. Pure, tested.
3. **`RevenueCatPurchases`** in `AppTarget/Infrastructure`, conforming to `PurchaseController`.
   One file, SDK confined to it.
4. **Entitlement check at launch + Paywall screen.** Uses `Theme.swift` tokens. If the entitlement
   is active the app must **never construct a real `AdPresenter` at all** (§A) — gate at
   construction, not at render, so there is no code path where a paying user loads an ad SDK.
5. **`RevenueCatAds`** conforming to `AdPresenter`; banner on Results, interstitial at most
   occasionally. The ads award criterion is literally "an experience users don't hate."
6. **Restore purchases.** Required by App Review for a non-consumable. Easy to forget; it will be
   rejected without it.
7. **Store listing.** Screenshots, description with the informational framing (R3), privacy
   nutrition labels — Vision is on-device, so "no data collected" is a clean story, but confirm the
   ad SDK doesn't change that answer. **An ad network that collects an IDFA changes the privacy
   labels and may require App Tracking Transparency.** Check this before writing the labels.

## R3 is live again, and it is not just about the listing

`Risks.md` R3 covers App Review and ads in an alcohol context. Two concrete things to check early,
because both can invalidate work already done:

- **Does the ad network serve alcohol-adjacent inventory at all?** Some restrict it. If ads are
  refused or fill rates are near zero, the answer is to ship banner-free and lean on the IAP —
  which is cheap *if* we find out in week one and expensive if we find out after building it.
- **Does the ad SDK require ATT / collect an IDFA?** If so, the app needs an ATT prompt and honest
  privacy labels, and the current "no data collected" story is gone.

Not legal advice; confirm the current App Review guideline wording when writing the listing.

## Known-good baseline (don't regress this)

`swift test` is **264 tests green**. The pure `Core` package has no monetization code in it and
should still have none when this session ends: `CoreContracts` gains protocol *changes*, but the
SDK never enters `Core`. If `Core` stops building on Linux, the boundary has been broken.

The value engine, capture flow, editable results, store calculator, and menu reading (F/D/C) are
all done and tested. Don't reopen them.

## Two UI loose ends from the design pass

Small, unrelated to monetization, and both are components that exist but are unused. Fold them in
only if there is slack:

- **`MenuQuality.isLowConfidence` has no UI.** `Notice` in `Theme.swift` is built for it. One line
  in `ResultsView` shows the thin-read warning; without it, a badly-read menu silently presents a
  ranking with no caveat.
- **`ValueFigure` / `PourLine` are built and unused.** `RankedValueRow` still renders a plain
  accent-coloured number. This is the piece that makes the ranking look designed rather than
  themed.

## Menu-reading residuals, for reference only

Do not spend this session here. Recorded in the Handoff: the priced-description residual (a bulleted
ingredient run under a priced section can become a priced item, unmeasured), menu 1 losing its whole
wine list to a column mismatch, `COORS LIGHT $02` reading as $2.00, and `CANS` classifying as
seltzer. All are known, none blocks submission.
