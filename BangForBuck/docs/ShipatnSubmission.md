# Shipaton 2026 submission

*Written 2026-09-09. The competition requirements, the categories actually in reach, and the
pre-flight checklist for making the repo public. Verified against the official rules and FAQ on
2026-09-09; re-check before submitting, since rules pages change.*

---

## The requirements that decide whether this counts

1. **A brand-new app.** Updates to previously released apps do not qualify. ABV is a new App Store
   Connect record; the existing free app is untouched.
2. **The first public version must be *released* between Aug 1 and Sep 30, 2026.** Released, not
   submitted, not "in review". This is the constraint that sets the submission target.
3. **The RevenueCat SDK must be integrated**, powering at least one in-app or web purchase, **or**
   serving ads through RevenueCat Ads. The purchase path qualifies on its own; see
   `MonetizationPlan.md` §2.
4. **Judges must be able to download and review the app**, which is why the main track needs a live
   listing. The exception is Next Gen, below.

**Submission target: Sep 18-20.** Everything before that is buffer for a rejection and a resubmit,
and the buffer exists because the deadline is a release deadline.

## Next Gen changes the risk profile

Next Gen is a student category judged on a **video submission and open-source code**. It requires no
App Store listing and no paid developer account, and needs a verifiable academic email on Devpost.

Two things make it strategically important rather than a consolation prize:

**It is not exclusive.** Next Gen projects remain in the running for the wider prize lineup.

**It de-risks R5.** R5 has been deferred five times. If App Review rejects on, say, Sep 24 and the
app cannot get live before Sep 30, the main entry dies and the Next Gen entry survives, because it
needs a repo and a video rather than a listing. Register with the academic email early and treat the
video and the public repo as deliverables, not as a fallback to scramble for.

**The repo is the strongest asset here, not the app.** Judged on source code, this project has 316
tests, a pure core that builds on Linux, a tagged risk register cross-referenced from code comments,
an architecture doc explaining the pure/impure boundary, and codegen tooling with a documented data
provenance audit trail. Most student submissions are a single SwiftUI file.

## Before making the repo public

Open-sourcing is the one step that is hard to undo. Four blockers, all real:

- [ ] **No `LICENSE` file exists** at the repo root. Add one.
- [ ] **BC Open Government Licence attribution.** `StoreCatalogSources.md` records that the store
      catalog carries an attribution requirement. A public repo and a shipping app both need that
      attribution somewhere visible: the README, and probably the app's calculation explainer.
- [ ] **`BangForBuck/photos/` holds real menu photos.** Photos taken at bars carry EXIF GPS. That is
      a location history in a public repo, and it identifies specific venues. Strip EXIF or exclude
      the directory.
- [ ] **No API keys in source.** The RevenueCat public SDK key is public by design, but keep it out
      of the repo via xcconfig anyway, and never let a Test Store key reach a tagged release.

## Categories in reach

There are 21 categories. Four are realistic.

### Design Award — best shot

For product craft, design and animation. The panel is indie-craft people.

**Two components already written and still unused are the whole submission:**

- `ValueFigure` / `PourLine` — `RankedValueRow` still renders a plain accent-coloured number. The
  Handoff's own words: this is "the piece that makes the ranking look designed rather than themed."
- The `isLowConfidence` thin-read `Notice` — `Notice` was built for it and nothing shows it. A
  visible caveat on a badly-read menu is exactly the kind of restraint this panel notices.

**These are no longer "polish if there is slack".** They are the highest-leverage change in the repo
for a category that is winnable, and the code exists. Promote them ahead of paywall refinement.

### HAMM (Help Apps Make Money)

For the smartest use of RevenueCat to earn revenue. The story has a mechanism in it rather than a
price point:

- The tip jar is **denominated in the unit the app measures** — a well shot, a pint, a round, priced
  in drinks because the whole product is dollars per standard drink.
- The ask is **gated on the app's own quality signal**: no prompt on a thin read, because asking for
  money on a job the app is not confident it did well is the wrong instinct.
- It **asks once and remembers the no.**
- The tiers come from a RevenueCat Offering, so they are repriced and reordered from the dashboard
  without a build.

"$0.99 remove ads" would not have placed. The mechanism is the entry.

### Next Gen

Video plus public repo. See above.

**Video beats most students cannot hit:** this app worked before it had a UI. Show `swift test` at
316 green, then the app on device. Then the chip-truncation bug as the honesty beat, since the badge
carrying the app's core promise was silently abbreviating to "estimat…" depending on whether an ABV
had a decimal point.

### #BuildInPublic

Three posts, about an hour. The material is unusual and already written down:

- The confidence anti-correlation table: mean OCR confidence runs *opposite* to menu readability,
  with the two worst menus reading at 0.937 and 1.000.
- The chip truncation bug, above.
- The 1948 Roosevelt Hotel list, where withdrawing four absurd prices left a $1.00 decanter of
  whiskey as the honest best value.

### Grand Prize

Traction and growth momentum. Nine days live will not produce it. Enter anyway; it costs nothing.

### Skip these

- **Catvertising** needs ads, which structurally cannot serve pre-launch. See `AdsPlan.md`.
- **Peace Prize** is biggest positive impact. Winning it would mean writing a public-health framing
  nobody here believes, which reads worse than not entering.
- **Best Game**, **Conflict of Interest** do not apply.

## Two cheap wins worth building

**Make the 1948 Roosevelt list a built-in demo.** `SampleMenus` already exists. Judges will open the
app once, indoors, with no bar menu in front of them, and whatever the demo does is what they think
the app is. That list shows the price invariant working, in twenty seconds, and it is funny. Highest
value-per-minute change available.

**A share card.** After a scan, one tap renders the ranked top three plus the price-per-standard-drink
spread as an image, via `ImageRenderer` over a SwiftUI view built from existing `Theme` tokens. It is
the only thing in the plan that touches Grand Prize, and it is a Design Award artifact in its own
right. Roughly half a day, no new design decisions. This is the only remaining use for
`MenuValueSpread`; if the card is not built, delete that type and its tests.

## Deliverables checklist

- [ ] Devpost registration, with the academic email for Next Gen
- [ ] Live App Store listing, released before Sep 30
- [ ] Public repo with `LICENSE`, attribution, EXIF stripped
- [ ] Video, 2-3 minutes
- [ ] Writeup targeting Design and HAMM explicitly, using the pure/impure boundary and the 316 tests
      as the craft evidence
- [ ] Three #BuildInPublic posts
