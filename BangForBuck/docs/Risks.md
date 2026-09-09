# Risks — load-bearing assumptions

*Living register (§13). Each risk is tagged `R#`; reference the tag from code comments and
other docs (e.g. `// composition-only fallback (R2)`) so the reasoning stays traceable
without bloating the code. Keep this open next to the code.*

**Severity tiers:** *Existential* (if wrong, the app has no reason to exist) ·
*Trust* (breaks the honesty promise / user confidence) · *Schedule* (threatens the window).

---

## R1 — OCR/parsing on real menus · **Existential**
**Threatens:** the whole utility. If it can't reliably pull name+price from a photo of a
real menu, nothing downstream matters.
**Counter-case:** Apple Vision on-device text recognition handles clean printed menus well,
and we don't need perfect reads — a partial read plus fast manual edit is still useful.
**Mitigation + trigger:** ship a fast **manual add / edit / remove** path from day one and treat OCR
as "assist," not "only way in." Design the parser against **transcribed real-menu
fixtures** (§5, §8), not remembered formatting. *Trigger:* if a real menu parses < ~70% of
priced lines, prioritize the manual-entry UX over parser cleverness.
**Progress (2026-08-27):** first on-device scan of a two-column bar menu exposed the single-column
`LineAssembler` gluing left+right items together. Fixed with pre-parse **column detection** (gutter
histogram, guarded against single-column false-splits), plus name-cleanup (`ABV x%`/size stripped
from names) and `drafts`/`cans` header recognition — all pure and unit-tested. **Residual:** genuine
3+ column or free-form layouts still fall back to fewer columns; the manual add/remove path (now
shipped) is the backstop. Bring failing photos + their OCR lines to tune `LineAssembler`/`MenuParser`.

## R2 — Estimates can be badly wrong · **Trust**
**Threatens:** user trust in the ranking (craft cocktails, unknown pours, house wine).
**Counter-case:** the app only ever promises "best value *given these assumptions*," and
says so visibly — an honest estimate is still useful.
**Mitigation + trigger:** flag every estimate via `Provenance` (§11), one-tap correction,
show the assumption ("assumed 16 oz pint"). *Trigger:* if users correct the same category's
default repeatedly, retune `StaticBeverageKnowledge`.
**Note (2026-09-09):** amber is the single visual signal for "this is an estimate" and is now
formally reserved. The supporter badge and the paywall's messages deliberately do **not** use amber
or the `Notice` component, so an amber element anywhere in the app still means exactly one thing.

## R3 — App Review + ads in an alcohol context · **Schedule / Existential**
**Threatens:** getting listed at all, and the ad revenue path.
**Counter-case:** framed as an informational **price-comparison** tool (not "get drunk
cheapest") with a 21+ gate, this is a defensible category.

**Resolved for v1 (2026-09-09) — the ad half of this risk is retired by removing ads.** The
investigation the original mitigation called for produced two findings that made the ad path
impossible in v1 rather than merely risky:

- **RevenueCat Ads is not an ad network.** It is a beta analytics feature with experimental APIs
  that reports impressions and revenue alongside an ad SDK you already have. It serves nothing.
  `Architecture.md` §A described a product that does not exist.
- **AdMob cannot serve before the app is live.** Google's help requires the app to be published,
  listed in a supported store, and linked in AdMob before it fully serves ads; new iOS apps do not
  show Google ads until listed, and linking is widely reported to lag by days. There is a documented
  rejection pattern where an AdMob-gated feature does nothing pre-launch and is returned as "not
  working as intended."

**v1 ships with no ad SDK.** This retires the alcohol-inventory question, the fill-rate question,
the ATT prompt, the UMP consent form, `app-ads.txt`, and the AdMob restricted-category setup, and it
**preserves "no data collected" on the privacy labels**, which is true because Vision is on-device.
That story is an asset for an app built on honesty and should not be traded away casually. Ads move
to v1.1; see `AdsPlan.md`.

**Still live for v1:** the App Review framing itself. Informational price-comparison language in the
listing, the 21+ gate on first launch (shipped), an age rating reflecting the alcohol reference, and
**product descriptions and paywall copy that stay on the price-transparency side of the line.**
"Dollars per standard drink" is consumer information; "more booze per dollar" is the reading Apple
is wary of. *Not legal advice — confirm the current App Review guideline wording when writing the
listing.*

**New sub-risk:** selling an entitlement whose described benefit does not exist in the build. This is
why the product is `supporter` and not `remove_ads`, and why v1 copy must not mention ads. See
`MonetizationPlan.md` §3.

## R4 — calories/$ is a much softer estimate than alcohol/$ · **Trust**
**Threatens:** the v2 metric's credibility (sugar/mixers aren't modeled).
**Counter-case:** shipping it as an explicit **alcohol-only kcal lower bound** is honest and
still directionally useful.
**Mitigation + trigger:** v2 only; heavily flagged as a lower bound; don't model mixers in
v1. *Trigger:* defer entirely if the window tightens (it's on the cut-first list).

## R5 — the window incl. review · **Schedule**

**Progress (2026-09-09) — materially reduced, and partly hedged.** Monetization is no longer at
zero. The pure layer and the paywall UI are built and tested (316 green): revised
`PurchaseController`, `PaywallFlow`, `SupporterPrompt`, `SupporterStore`, `PaywallView`,
`SupporterBadge`, and the prompt wired into `ResultsView`. Remaining: the SDK dependency, the one
`Infrastructure` conformer, the review screenshots, and a sandbox purchase.

**Two hedges now exist that did not before:**

1. **Ads are out of scope**, which removes the largest and least controllable block of work from the
   critical path along with an entire second vendor account and review process.
2. **Next Gen applies and is not exclusive.** It is judged on a video and open-source code with no
   store listing required, so a late rejection no longer means no entry. See
   `ShipatonSubmission.md`.

**The one thing still outside our control:** the Paid Apps Agreement is signed, but banking must
reach status **"Clear"** before any purchase can be tested, including in sandbox. Expected
2026-09-10. Nothing about the purchase path can be verified until it lands.

**Threatens:** shipping inside the Aug 1 – Sep 30 window at all. Note the rules require the first
public version to be **released**, not submitted, inside the window.
**Counter-case:** the pure pipeline proves the value with zero UI, so the risky UI/review
work sits on a proven base.
**Mitigation + trigger:** submit ~Sep 18-20 with a resubmit buffer. *Trigger:* if behind by Sep 15,
cut in this order — the share card, the 1948 demo, then paywall refinement. **Do not cut
`ValueFigure`/`PourLine` or the `isLowConfidence` `Notice`**: they are already written and they are
the Design Award submission.

## R6 — App Store Connect will not let the first IAP reach review · **Schedule**
*New 2026-09-09.*
**Threatens:** the submission, at the worst possible moment.
**The mechanism:** for a brand-new app whose first version has never been approved, Apple requires
the first in-app purchase to be reviewed **together with an app binary**, and the only way to attach
it is the "In-App Purchases and Subscriptions" section on the version page. There are many reports of
that section simply **not rendering**, with all prerequisites satisfied, which makes the instruction
impossible to follow and produces a Guideline 2.1(b) rejection returning the products because the
required binary was not submitted.
**Counter-case:** it is a known platform behaviour with a known workaround path, and App Store
Connect support can act on it — given time.
**Mitigation + trigger:** **archive and upload a throwaway build early**, well before submission, and
confirm the section appears and lets the three products be selected. *Trigger:* if the section is
missing, contact App Store Connect support immediately rather than retrying browsers. Finding this
on Sep 12 costs an afternoon; finding it on Sep 19 costs the window.

## R7 — the RevenueCat credential is easy to get wrong and fails silently · **Trust / Schedule**
*New 2026-09-09.*
**Threatens:** customers paying and receiving nothing, which is the worst available failure.
**The mechanism:** SDK 5.x uses StoreKit 2 and requires an **In-App Purchase Key** (Issuer ID, Key
ID, `.p8`). The older App-Specific Shared Secret is for StoreKit 1. With the wrong credential or none,
transactions **fail to be recorded** and the entitlement never activates. Separately, a product
identifier typo between App Store Connect and RevenueCat produces an **empty paywall with no error**.
**Mitigation + trigger:** upload the In-App Purchase Key before any purchase test; verify a Test
Store purchase appears in the RevenueCat dashboard, not just in the app; and treat "the paywall shows
no tiers" as a configuration mismatch first, not a code bug. Because the app's own state machine
distinguishes `.unavailable` from `.ready`, an empty offering surfaces as a retry rather than a blank
screen. Also: **a Test Store key must never ship**; gate the key by build configuration.

---

## R-invariant — the price rule (structural, not a risk to accept)
Not a probabilistic risk but the invariant R1/R2 lean on: **a guessed price must never be
rankable.** Enforced by type — `ValueRanker` takes `[PricedDrink]`, and `PricedDrink` is
only constructible with a real read price, so no future edit can rank a fabricated price
(§10). Backed by an explicit invariant test (§8).

**Extended 2026-09-09 to our own prices.** The rule was written about menu prices; it applies with
more force to a number shown to somebody immediately before charging them. Three consequences, each
tested:

- `SupporterTier.displayPrice` is a **`String` from the store, never a number.** There is no numeric
  price anywhere in `Core`, so nobody can format one and no locale can be got wrong.
- `purchase(_ tier:)` takes the tier that was **displayed**, rather than re-resolving the product
  internally, so the amount charged is provably the amount shown.
- `PaywallFlow` has **no state meaning "showing prices I do not have."** A failed offering fetch
  becomes `.unavailable` with a retry, never a plausible-looking default.
