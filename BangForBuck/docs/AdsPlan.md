# Ads plan (v1.1, after release)

*Written 2026-09-09. Split out of `MonetizationPlan.md`, which now covers the purchase only. Nothing
in this document happens before v1 is live on the App Store, and that is not a scheduling preference.*

---

## Why this cannot be in v1

Two findings, verified 2026-09-09 against vendor documentation.

**RevenueCat Ads does not serve ads.** It is a beta feature with experimental APIs that sits
alongside an existing ad SDK and reports impressions, clicks and revenue to RevenueCat, so ad income
appears next to purchase income in one dashboard. There is no RevenueCat banner. Serving ads means
Google AdMob, or AppLovin MAX / ironSource / Unity Ads.

**AdMob will not serve until the app is live.** Google's help states the app must be published and
available to users, listed in a supported store, and linked in AdMob, before it can fully serve ads.
New iOS apps do not show Google ads until listed on the App Store, and the linking step is widely
reported to lag by days after going live. New publisher accounts also get a limited ad-serving
period of roughly 30 days.

So a banner in the submitted build would be an empty frame. There is a documented rejection pattern
where an AdMob-gated feature does nothing pre-launch and App Review returns the build as "not
working as intended" — which would cost the resubmit buffer for revenue that could not have arrived
anyway.

## What v1 deliberately does not have

Worth listing, because every one of these is a cost that arrives with the ad SDK and a thing to
re-check when it does:

| Not in v1 | Arrives with the ad SDK |
|---|---|
| IDFA collection | Google Mobile Ads uses the IDFA |
| ATT prompt | `NSUserTrackingUsageDescription` + wait on the ATT callback before loading ads |
| UMP consent form | required for EEA users |
| `app-ads.txt` | mandatory for AdMob |
| Restricted-category config | alcohol needs explicit AdMob configuration |
| Privacy label changes | "no data collected" becomes false |

**The privacy labels are the one to think hardest about.** v1 can honestly claim no data collected,
because Vision runs on-device and nothing leaves the phone. The Google Mobile Ads SDK's privacy
manifest declares device and advertising data collection **even if the person declines ATT**. You
can serve without ATT consent and the SDK then withholds the IDFA, but the collection declaration
does not go away.

For an app whose entire pitch is that it tells you the truth about where its numbers came from,
trading "no data collected" for banner revenue is a real decision and not an obvious one. Make it
deliberately.

## The order that works

Each step gates the next. Nothing here can be parallelized past step 2.

1. **v1 goes live** on the App Store.
2. **Create the AdMob account** if it does not exist. Payment and tax info required.
3. **Link the app** in AdMob to the live App Store listing. Expect this to lag; it is the step
   people report taking days to weeks.
4. **Wait out approval** and the new-publisher limited-serving window.
5. **Configure the alcohol restricted category** in AdMob, and publish `app-ads.txt`.
6. **Integrate UMP consent** and the ATT prompt, in that order, waiting on the ATT completion
   callback before requesting an ad.
7. **Update the privacy nutrition labels honestly**, before the build that contains the ad SDK is
   submitted.
8. **Then** write the banner, and only then design a protocol for it.

## Design constraints for whoever builds it

**Do not resurrect `AdPresenter`.** It was deleted for a reason: it was designed against a product
that does not exist. Write the protocol *after* integrating the SDK, not before.

**The banner view has no `Core` representation.** AdMob's banner is a `UIView`, so the SwiftUI
wrapper is a `UIViewRepresentable`. A protocol in `CoreContracts` cannot return one without `Core`
importing SwiftUI, which breaks the Linux build and the pure/impure split (§7). `Core`'s only stake
in ads is one boolean.

**Gate at construction, not at render.** If `supporterStatus()` is active, the app must never
construct the ad SDK's objects at all. There must be no code path where a paying customer's device
initializes an ad SDK and then hides the result. This is the §A rule and it is the reason
`supporterStatus()` fails closed rather than open.

**The entitlement already exists.** The ad gate checks `supporter`. Everyone who bought a tier in v1
is already covered. Do not create a `remove_ads` product.

**The paywall copy can change now.** Once ads exist, the product descriptions and the paywall may
mention ad-free, because by then it is true. Until then they must not; see `MonetizationPlan.md` §3.

## Optional: RevenueCat's ad tracking

Once real ads are serving, RevenueCat Ads can be layered on top so ad revenue reports next to
purchase revenue. It is beta with experimental APIs and requires access to be granted, so treat it
as a reporting nicety rather than a dependency. It replaces nothing.

## The competition angle

The Catvertising Award goes to the most creative and effective use of ads. It is unreachable for v1
for the reasons above. If v1 goes live around Sep 22 there is a narrow chance of shipping ads before
Sep 30, but the AdMob linking lag makes that a bet rather than a plan. Do not stake anything on it.
See `ShipatonSubmission.md` for the categories that are actually in reach.
