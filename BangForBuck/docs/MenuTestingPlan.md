# Menu testing plan (next session)

*Written at the end of the 2026-09-05 session so the next one opens with a plan instead of a
re-explanation. The 20 test menus are already in `BangForBuck/photos/`; none has been run through
the app yet, so there are no OCR dumps and no known failures at the time of writing.*

---

## Paste this to open the next conversation

> I'm working on BangForBuck (brewforbuck), an iOS app that photographs a drink menu and ranks the
> alcoholic options by standard drinks per dollar. The zip is the repo.
>
> **Read `BangForBuck/docs/Handoff.md` first** (newest note on top, each note says what it
> supersedes), then `Architecture.md` and `CodebaseReference.md` for the design and the file map.
>
> **This session's goal: make menu reading work across the 20 test menus in `BangForBuck/photos/`.**
> I have not run them through the app yet, so we start from zero known failures.
>
> **The hard constraint: rules must generalize.** Twenty menus fixed one at a time would give twenty
> special cases and a parser that breaks on menu twenty-one. Every change must be validated against
> *all* available OCR dumps at once, plus lowercased copies of them (real bars lowercase their
> menus), plus the five existing real-menu regressions, before it goes in. If a rule only helps one
> menu, treat that as evidence it's the wrong rule and look for the class behind it. I'd rather fix
> 16 of 20 with four generalizable rules than 20 of 20 with fifteen.
>
> **Your environment:** no Swift toolchain and no network in bash. Validate parser and geometry
> changes in Python against real coordinates first, then port to Swift; I run `swift test` and build
> on my Mac and send you the output. This is how the existing `LineAssembler` and `MenuParser` work
> got done, and it works well.
>
> **How I get you data:** a DEBUG build has a 0.8s long-press on the menucard logo that dumps
> word-level `[TextObservation]` as a paste-ready Swift literal plus the currently assembled lines.
> That text becomes a regression fixture directly. It only keeps the *last* scanned image, so it's
> one menu at a time. If a batch export would save us both effort, say so early and we'll build it
> before the triage.
>
> **Start here, before writing any code:**
> 1. Read the docs.
> 2. Look at the 20 photos and inventory them: layout (single column, two column, dense
>    multi-section), price format (per item, section header, size grid, superscript cents), and
>    anything that looks likely to break the current parser. Say what you expect to fail and why.
> 3. Tell me which 5 or 6 menus to run through the DEBUG export first, chosen to cover the widest
>    range of failure classes rather than the worst single menu.
> 4. Then we triage by class, fix classes rather than menus, and add a test per class.
>
> **Don't start new features.** RevenueCat integration is the actual schedule risk (see the Handoff)
> and is untouched; menu reading is this session, monetization is next.
>
> House style: no em-dashes in user-facing copy, business logic goes in pure `CoreServices` with
> tests rather than in views, and both load-bearing invariants hold (a price is never fabricated, an
> estimate never presents as measured).

---

## What to send per menu, once we're triaging

Expected versus actual is far more diagnostic than the photo alone, because the wrong output names
the broken stage:

| Symptom | Likely stage |
|---|---|
| Two drinks fused into one line | `LineAssembler` column or banding |
| A real drink sitting in "Not sure about these" | `MenuParser` price scan, or a section price not inheriting |
| Junk ranked as a drink (a dish, a promo line, a section label) | `MenuParser` rank-eligibility gate |
| Right drink, wrong price | price token repair, or a multi-price row split |
| Right drink, wrong strength | the knowledge layer (`CatalogBackedKnowledge` → style chart) |
| Nothing ranked at all | OCR quality; check whether the photo is angled |

So: "should rank the IPAs around 0.25/$, actually ranked Fries as a 12% $8 drink" is worth more than
a screenshot.

## Known-good baseline (don't regress these)

Five real menus already parse acceptably and have regression tests: Southside, Reservoir, Exclusive,
M/G (the dense one), and El Perrito (which correctly ranks nothing, because the photo is angled and
unreadable). `LineAssemblerRealMenuTests` and `MenuParserConfidenceTests` pin them. A change that
fixes a new menu and breaks one of these is not a fix.

## Already-known residuals, for reference

From the M/G work: fully OCR-shredded price tokens stay unpriced, and one happy-hour mini-grid isn't
recognized because OCR typo'd both its size and its price. Both accepted as low value. Don't spend
this session on them unless a new menu shows the same class more clearly.

## Still pending from earlier, related to menu reading

`ImageDeskew` was described in the 2026-09-02 notes but **never committed** and is not in
`Infrastructure/`. If several of the 20 menus are shot at an angle, writing it (Vision's
`VNDetectDocumentSegmentation` + `CIPerspectiveCorrection`, run before `recognizeObservations`) plus
a "hold straight / retake" capture hint may be higher leverage than any parser rule, because it
fixes the input rather than compensating for it downstream.
