# Monetization plan — design of record

*Written 2026-09-07 as the plan for the monetization session. **Rewritten 2026-09-09** to record
what was actually decided, including two findings that invalidated the original design. The
"conversation opener" section that used to head this file is gone: that session happened. The v1.1
ad work moved to `AdsPlan.md`, and the competition strategy to `ShipatonSubmission.md`.*

**Status: integrated and proven on device (2026-09-09).** The SDK is in, a Test Store purchase
records end to end, and every purchase branch except Ask to Buy has been exercised. Remaining work is
Apple-side: R6, review screenshots, and a sandbox purchase once banking clears. See `Handoff.md`
(newest note) for the steps, and for the two R7 failures that both actually fired.

---

## 1. What the original plan got wrong

Two things, both verified against current vendor documentation on 2026-09-09. They are recorded here
rather than quietly fixed, because the *reason* they were wrong is the reusable lesson.

### RevenueCat Ads is not an ad network

`Architecture.md` §A said "RevenueCat Ads for revenue (banner on Results)". RevenueCat Ads is a
**beta analytics feature with experimental APIs**. It sits alongside an ad SDK you already have and
reports impressions, clicks and revenue back to RevenueCat so ad income appears next to purchase
income. It serves no ads and renders no banners.

Serving ads means Google AdMob, or AppLovin MAX / ironSource / Unity Ads. That is a different SDK,
a different account, a different review process, and a different privacy story.

**The lesson:** `AdPresenter` was designed against a product that was misremembered from a name.
No amount of care in the protocol's shape could have saved it. See `ProjectConventions.md` §5.

### AdMob cannot serve ads before the app is live

Google's own help states the app must be published and available to users, listed in a supported
store, and linked in AdMob, before it can fully serve ads. New iOS apps do not show Google ads until
they are listed on the App Store, and developers widely report the App Store to AdMob linking step
lagging by days after going live.

There is also a documented rejection pattern: an AdMob-gated feature does nothing before launch,
and App Review returns the build as "not working as intended". An empty banner frame on Results is a
plausible way to earn a rejection and burn the resubmit buffer.

**Conclusion: a banner cannot function in the build App Review sees.** This is structural, not a
time-budget problem. No amount of schedule would fix it.

## 2. The decision: purchase only in v1

Shipaton requires the RevenueCat SDK to power **at least one in-app purchase, or** to serve ads
through RevenueCat Ads. The purchase path qualifies on its own. §A previously called the IAP
"qualification insurance"; it is in fact the entire qualification, and the ads-only reading it was
hedging against turns out to point at a beta analytics product.

Cutting ads from v1 also protects something valuable. With no ad SDK linked there is:

- no IDFA and no App Tracking Transparency prompt
- no `NSUserTrackingUsageDescription`
- no Google UMP consent form for EEA users
- no `app-ads.txt`
- no AdMob alcohol restricted-category configuration
- and the privacy nutrition labels stay at **"no data collected"**, which is true because Vision is
  on-device

That last point is a genuine asset for an app whose entire pitch is honesty. Do not link an ad SDK
before submission for any reason. Ads are a v1.1 job; see `AdsPlan.md`.

## 3. The product: a tip jar priced in drinks

Not "Remove Ads". Three non-consumables, all granting one entitlement:

| Product identifier | Display name | Price |
|---|---|---|
| `supporter.shot` | Buy me a well shot | $1.99 |
| `supporter.pint` | Buy me a pint | $4.99 |
| `supporter.round` | Buy me a round | $9.99 |

Entitlement identifier: **`supporter`**. All three products attach to it, so a $1.99 shot grants
exactly what a $9.99 round grants. The tiers are how much you choose to give, not how much you get.

### Why `supporter` and not `remove_ads`

v1 has no ads, and **selling a feature the build does not have is a rejection risk**. So the v1
product descriptions and paywall copy must not mention ads at all.

When the banner ships in v1.1, the ad gate checks this same entitlement. Everyone who bought a tier
in v1 already has it and never sees a banner. No second product, no App Store Connect record to
create, no migration, no re-review. Naming it correctly on day one cost nothing; renaming it later
would have cost a new product and a new IAP review.

Sequencing of the ad claim:

| Version | Product description | Paywall copy | Ad gate |
|---|---|---|---|
| v1 | supports development, no mention of ads | no mention of ads | n/a, no ads exist |
| v1.1 | may mention ad-free | may mention ad-free | checks `supporter` |

### Why the tiers are named after drinks

The app is denominated in dollars per standard drink. A tip jar in the same unit is the joke the
product has earned, and it reads as part of the app rather than bolted on. The names live in App
Store Connect, not in code, so they are localized by the same system that localizes the rest of the
product page and can be edited without a build.

### One-time by construction

Non-consumables cannot be re-bought, so a purchase is permanent and restorable forever. The paywall
shows the thank-you state instead of the tier list once the entitlement is active, so somebody who
bought the shot is never offered the pint.

**Known limitation, accepted:** a person can therefore tip exactly once, ever. Repeat tipping would
need consumable products alongside the non-consumable, which is more products, more review surface,
and consumables cannot be restored. v1.1 can add "buy another round" consumables on top without
disturbing the entitlement.

### What the entitlement grants in v1

Something visible, so the purchase is not a black hole:

- The paywall becomes a thank-you state permanently and never asks again.
- A quiet supporter badge under the wordmark on the home screen, naming the tier
  ("Thanks for the pint").

## 4. The protocol gaps, resolved

The original plan named two suspected gaps. Both are addressed, one was mis-framed, and two more
were found.

### Gap 1, confirmed: `PurchaseController` could not drive a paywall

No display price, and no way to tell a cancel from a failure. Both correct.

### Gap 2, corrected: the proposed fix would have broken the boundary

The plan was right that `showBanner()` / `hideBanner()` is a UIKit-shaped API. It was wrong about the
remedy. The suggested "factory that vends a view" **cannot exist in `CoreContracts`**: AdMob's banner
is a `UIView`, so its SwiftUI wrapper is a `UIViewRepresentable`, and returning one from a protocol
in `Core` means `Core` imports SwiftUI. That is the Linux build and the entire pure/impure split
gone (§7).

**The correct answer: the banner view has no `Core` representation at all.** It is an `AppTarget`
type. `Core`'s only stake in ads is one boolean derived from the entitlement.

`AdPresenter.swift` and `NoopAdPresenter` were therefore **deleted, not revised.** The protocol's
problem was not its shape; it was being designed against an SDK nobody had used. Any shape designed
today would be designed against a second SDK nobody has used either. v1.1 writes a protocol against
the real API, after integrating it.

### Gap 3, new: `restorePurchases()` returned `Void`

A restore that found nothing was indistinguishable from one that worked, so the UI had to either
thank people for a purchase they never made or say nothing about success. App Review exercises the
restore path on a non-consumable. Now returns `RestoreOutcome` with an explicit
`.nothingToRestore` case.

### Gap 4, new: `purchaseRemoveAds()` named no product

If the paywall displays a fetched offer and the purchase call re-resolves the product internally, the
price shown and the price charged are only coincidentally the same. Now `purchase(_ tier:)`, so the
thing charged is provably the thing displayed.

**This is §10 turned on ourselves.** The price invariant was written about menu prices. It applies
with more force to a number we show someone immediately before charging them.

## 5. The contracts as they now stand

`CoreContracts/PurchaseController.swift`:

```swift
protocol PurchaseController: Sendable {
    func supporterTiers() async throws -> [SupporterTier]
    func purchase(_ tier: SupporterTier) async throws -> PurchaseOutcome
    func restorePurchases() async throws -> RestoreOutcome
    func supporterStatus() async -> SupporterStatus
}
```

Supporting types, all Foundation-free so `Core` still builds on Linux:

- `SupporterTier` — `productIdentifier`, `displayName`, `displayPrice`
- `SupporterStatus` — `.notSupporter` / `.supporter(productIdentifier:)`, plus `.isActive`
- `PurchaseOutcome` — `.purchased` / `.cancelled` / `.pending`
- `RestoreOutcome` — `.restored` / `.nothingToRestore`

Three design decisions worth not re-litigating:

**`displayPrice` is a `String`, never a number.** The store is the only authority on what something
costs in the customer's currency and locale. A `Double` in `Core` invites somebody to format it, and
a hand-formatted price shown to a person about to be charged is a fabricated price. There is
deliberately no numeric price anywhere in `Core`.

**`.pending` exists because Ask to Buy is real.** A child's purchase awaiting a parent's approval,
or a bank challenge, leaves nothing owed and the entitlement inactive. Without this case the app
thanks somebody for a purchase that has not happened.

**`supporterStatus()` fails closed to `.notSupporter`.** Claiming support on an error would give the
product away and would silently disable the v1.1 ad gate through an error path, which is not a state
anyone would think to test. The cost of failing closed is a supporter briefly seeing a banner on a
fresh, offline install before Restore has run, which is why Restore must be easy to find. RevenueCat
caches the entitlement locally, so a device that has already purchased answers `true` offline.

## 6. Where the logic lives

Business logic in pure `Core` with tests, per house style. The paywall view contains no decisions.

`CoreServices/PaywallFlow.swift` — the state machine as one pure function,
`next(from: PaywallState, on: PaywallEvent) -> PaywallState`. States: `.loading`, `.unavailable`,
`.ready(tiers:notice:)`, `.purchasing(tiers:chosen:)`, `.restoring(tiers:)`, `.pending`,
`.thanks(productIdentifier:)`. Inapplicable events return the state unchanged, so a late reply from
a call the person already backed out of cannot resurrect a dismissed sheet.

There is deliberately **no state meaning "showing prices I do not have"**: either the tiers are in
hand, or the state is `.loading` or `.unavailable`. A failed fetch shows a retry, never a plausible
guess (§10).

`CoreServices/SupporterPrompt.swift` — the four ask rules, one test each:

1. Never ask an existing supporter. This is what makes it one-time.
2. Never ask twice in a row. **Reversed 2026-09-09.** This was "never ask twice, ever", which spent
   the single ask on the first qualifying scan and then went silent even after the app had proved
   useful ten more times. It is now a cadence of `SupporterPrompt.scansBetweenAsks` scans (3 at time
   of writing; the number lives only in that constant, so tune it there and this stays true).
   Counted over scans rather than launches, and a thin read counts even though it does not ask, so
   the counter measures use rather than asks. Declining is still a real answer for the length of the
   interval, and rule 1 still means a supporter is never asked again.
3. **Never ask on a thin read.** If `isLowConfidence` fired, the app is not confident in the ranking
   it just produced, and asking for money on a job it may have done badly is the wrong instinct.
   *This is the rule most worth keeping if anything here is ever cut.*
4. Never ask without a comparison. Fewer than two ranked drinks is not a ranking.

`CoreServices/SupporterTierKind.swift` (in `SupporterPrompt.swift`) — a closed set of tier kinds so
the view switches exhaustively. An unrecognized product identifier resolves to `.unspecified` and
the badge degrades to a plain "Thanks for the support", which stays true for any product that grants
the entitlement. A tier added in the dashboard later cannot produce a wrong badge.

`AppTarget/Features/Supporter/SupporterStore.swift` — the only impure piece: the entitlement read
and one persisted `hasAskedForSupport` flag in `UserDefaults`.

### Two visual rules

**The supporter badge is never amber.** Amber means "this number is an estimate" and nothing else in
this app (§11). A purchase badge wearing it would quietly break the one thing amber signals.

**Paywall messages do not use the `Notice` component**, for the same reason: `Notice` is amber and
reserved for estimate warnings. Paywall messages are plain muted text.

## 7. What was cut, and why

**The value spread line.** The paywall was going to say "the best option here was 2.4 times the
worst" using `MenuValueSpread`. Cut by decision. Two reasons it was weak anyway: the original
version multiplied a tier price by a drinks-per-dollar rate, which mixes the customer's App Store
currency with whatever currency the menu printed and produces a confident wrong number outside the
US storefront; and the dimensionless ratio that replaced it is still a flourish on a screen that
works better plain.

`MenuValueSpread` and `SupporterPrompt.isWorthMentioning` are now **unused**. Kept in case the share
card in `ShipatonSubmission.md` is built. Delete both plus their tests if it is not.

## 8. Store setup, in dependency order

The order matters because only one step involves waiting on somebody else.

1. **Paid Apps Agreement.** App Store Connect → Business → Agreements → Paid Apps → View and Agree
   to Terms. **Account Holder only**, not Admin. The Developer Program License Agreement covers free
   apps; selling anything needs this one. Cannot be undone. ✅ done 2026-09-09.
2. **Tax and Banking**, same section. The bank account status must reach **"Clear"** before an
   in-app purchase can be tested at all. This is the step that takes days. ⏳ expected 2026-09-10.
3. **Register the App ID.** `NovalCo.BangForBuck`, Explicit, **no capabilities enabled.** In-App
   Purchase is automatic on every App ID and is not in the capabilities list. Camera access is an
   Info.plist string, already set via `INFOPLIST_KEY_NSCameraUsageDescription`. ✅ done.
4. **Create the app record** in App Store Connect, brand new (Shipaton requires a new listing; do
   not add this to any existing app).
5. **Create the three non-consumables** with localizations. ✅ done. Review screenshots pending the
   paywall, which is what the screenshot has to be *of*.
6. **Generate the In-App Purchase Key.** Users and Access → Integrations → In-App Purchase →
   Generate. Downloadable **once**. Note the Issuer ID and Key ID.
7. **RevenueCat.** Project → App (platform App Store, bundle ID `NovalCo.BangForBuck`) → upload the
   `.p8` and Issuer ID → three products → one `supporter` entitlement with all three attached → one
   Offering marked **Current** with three packages in shot, pint, round order.
8. **Both API keys.** Test Store key for Debug, App Store key for Release.

### The key is an In-App Purchase Key, not a shared secret

RevenueCat SDK 5.x uses StoreKit 2, which requires an **In-App Purchase Key**. Without it,
transactions fail to be recorded, which means people pay and receive nothing. The older
App-Specific Shared Secret is for StoreKit 1 and is the wrong credential here.

### The order that does not work

A build is **not** required to create the app record or the products. But the **first** in-app
purchase for an app must be submitted together with an app version. After Apple approves one, later
products can be submitted alone. See R6 in `Risks.md` for the App Store Connect failure this
routinely causes.

## 9. Known-good baseline

`swift test` is **319 green** (316 until 2026-09-09 part 2, which deleted `testItNeverAsksTwice` —
it asserted the opposite of the new cadence — and added five: the reset, the whole interval, the ask
returning, an overshooting counter, and a thin read still refusing however many scans have passed). `Core` contains no monetization SDK code and must still contain none:
`CoreContracts` and `CoreServices` gained monetization *types and logic*, but no dependency. **If
`Core` stops building on Linux, the boundary has been broken.**

The value engine, capture flow, editable results, store calculator, and menu reading (F/D/C) are
done and tested. Do not reopen them.
