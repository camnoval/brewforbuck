# Handoff

*Live "here's where we are" + carry-on context (§2). History lives in `Changelog.md`, not
here — keep this lean. Newest note on top; each new note says plainly what it supersedes.*

---

## ⇢ STATUS (2026-09-27 part 4) — Rescan measured; four fixes from what it showed

**Adds to part 3.** The rescan settled the open questions. Nothing compiled.

### 1. The old menu is solved, and it was the capture

`RECTIFY` fired: 765×1020 → 569×1449, corner displacement 0.243. Aspect went 0.75 → 0.393 and the
page curl went with it. Result on the ROTATING tap list:

    # quality: 20/21 priced (95.2%)
    # ABV provenance among ranked: 20 read, 0 estimated

From 0 of 22 to 20 of 22, **every ABV read rather than estimated**. The document camera wasn't even
needed — rectifying a library photo was enough, which means the camera path will do at least this
well. The never-overwrite rule in `adoptingAttributes` also earned its place: two orphaned name rows
were absorbed as descriptions into the beer above, and Yuengling kept its own 4.5% instead of taking
Sam Adams' 6%.

### 2. Vision had the right price in candidate 2 all along

The log settles part 3 §2 in favour of candidate selection, and against the leading-`5` heuristic:

    [1] ANGRY ORCHARD CRISP APPLE 39   [2] ...59        [3] ...$9
    [1] COLD BREW MARTINI 313          [2] ...$13
    [1] IC UGHT 59                     [2] IC UGHT $9
    [1] QUINNESS 14                    [2] QUINNESS $4

`VisionTextRecognizer.preferredCandidate` now promotes a lower-ranked reading **only** when the top
one has no currency-anchored price and a lower one does. It can never invent a price — only promote
a reading Vision already produced — and it cannot touch a line whose top reading already has a `$`.
Where no candidate has one (`STRAWBERRY DAIQUIRI 31 / 30 / 39`) nothing changes.

This is why the heuristic wasn't built: a leading-`5`-strip would have to decide on its own that
`59` means `$9`, and a real `$59` bottle would be its victim.

### 3. The selector was optimizing a proxy that rewarded wrong prices

It picked the no-correction reading 40 priced to 37 — but several of those 40 were `$38`, `$39`,
`$31`, `$4`, which are what OCR made of `$8`, `$9`, `$3`, `$14`. More prices is not more correct
prices. `MenuReadSelection.Score` now leads with `anchored`: lines carrying a `$` attached to a
number, which is the only evidence available that a number was meant as money. Then priced, then
leaner, then first candidate.

### 4. Nearest member, not last member

Rows 4 and 6 of the rectified list lost their price by **0.0086 and 0.0091** against a tolerance of
0.00825. Chaining to the row's rightmost box let drift accumulate across the row, and a right-aligned
price doesn't sit on the drifted baseline — it sits near where the row *started*. Row 4's price is
0.0028 from `ADAMS` and 0.0086 from `ABV`. Chaining now links to the **nearest** member of a row,
which is what Docstrum actually does; taking the last member was the simplification that cost two
prices. Corpus effect unchanged: 6/8, same two non-regressions as part 2 §3.

### 5. Headerless pages: `CategoryInference`

The tap list has no section header, so everything that didn't brand-match came out `.unknown`, whose
default pour is a generic 6 oz. Platform Martian at 8.6% and $9 ranked **#18 of 20** on an assumed
six-ounce pour. Sixteen items on that page *were* classified, twelve of them beer, by brand match
alone — the page had already said what it was.

When a **majority** of classified items agree, unknowns inherit that category. A plurality would let
a four-beer/three-wine/three-cocktail page impose beer on everything unrecognized, which is a guess
dressed as knowledge; a majority means it only fires where the subject is evident and the header was
missing rather than absent. Floor of four classified items. `.nonAlcoholic` is never inherited —
that distinction has to be read, not inferred. Classified items are never reclassified.

### 6. Naming: one exact word pays for its neighbour's edit

`BUO LIGHT` is Bud Light off a 574 px menu. `LIGHT` folds exactly, so `windowDistance` now allows a
word to exceed its own cap when **another word in the window matched exactly** and the total still
fits the brand budget. The exact anchor is the guard: `BUD`→`BUSCH` is two edits, over budget, so
beers still can't cross into each other, and a window with no exact word anywhere is refused rather
than assembled from guesses. Also gains `STELLA AXTOIS` and `QUINNESS`. Re-measured: 0 false
positives across the 27-line non-brand set plus the new menu's cocktails.

### 7. `RecognizeDocumentsRequest` lost, decisively

**0 tables on both menus.** 117 and 44 paragraphs, 2 lists, no tables. Its readings scored 33/98 and
1/6 and lost both times. Part 1 §3's argument — "the tap list *is* a three-column table" — was wrong
about what Apple's model reports. It currently costs an extra on-device Vision pass per scan for
nothing, twice per scan. **Left in deliberately, not yet gated**, because it might still win on a
menu that really is a grid and that is a product call, not a code one.

### 8. Still open

- The new Shorty's card is capped by its source: 574 px wide for three columns gives
  `SEIALAMHCAD LLTRA`, `MARO UNDER PRESSURE`, `SMOR "TEA"`. No parser fixes that, and
  `OCRNameRepair` correctly declines to reach that far. **It needs a full-resolution camera scan
  before anything else is tuned against it.** Real structural progress there though: `ON TAP` is now
  recognized, the columns separated, and the `wineGlass` contamination is gone — every beer is
  `draftBeer` and the 12% ABV / 5 oz nonsense from part 2 is gone.
- `Tooling/Data/beverages.json` is missing beers this app will keep meeting: IC Light, IC Light
  Mango, Brewdog Elvis AF, Victory Sour Monkey, Penn Brewery Weizen, Platform, Helltown, Evergrain,
  North Country, East End. That is lexicon coverage, not menu-specific tuning — but it is data work
  and should be done as data work.
- Breuel gutters and Docstrum-derived tolerances (part 3 §6) remain the real generalization.
- The pre-existing word-boundary bug in the brand tier (part 3 §5) is still there.

---


**Adds to part 2; supersedes nothing.** Went looking for how document analysis and other scanning
apps solve these problems before implementing my own fixes, which was the right order: two of my
fixes turned out to be compensating for a bad input, and both geometry fixes turned out to be crude
versions of well-cited algorithms. Everything below is free (system APIs and code already in the
binary — no SDK, no service, no per-scan cost). Still nothing compiled.

### 1. The capture was the wrong tool — `DocumentScanner.swift`

`CameraPicker` takes a plain photo via `UIImagePickerController.originalImage`.
`VNDocumentCameraViewController` (VisionKit, iOS 13+, free) is the scanner from Notes: live edge
detection with a quad on the viewfinder, automatic capture, cropping, **perspective correction**,
document enhancement (deskew, flatten, contrast), and multi-page. A photo records the angle, the
lighting and the curl; a scan records a normalized page.

This attacks part 2 §2 (page curl) and the `$`→`5` glyph errors at the source instead of teaching
the reader to tolerate them, and the live quad tells someone at a bar that they're too far or too
skewed, which nothing currently does. `CameraPicker` stays as the fallback when `isSupported` is
false. **Multi-page is on**: menus are two-sided constantly, each page is recognized separately
(geometry must not be mixed across pages) and the lines concatenate in page order.

### 2. Vision's alternative readings were being thrown away

`topCandidates(1)` appears in both places in `VisionTextRecognizer`, so the second and third
readings of every line are discarded unseen. Given that `$9` came back as `59`, inventing a
leading-`5` repair rule is guesswork if the right string was in candidate 2 all along.

The dump now logs the top 3 for every line containing a digit. **Nothing selects among them yet —
deliberately.** What the rescan shows decides whether candidate selection is a two-line change or a
dead end, and building the repair first would be fitting a rule to a symptom.

### 3. Language correction is now an A/B the page decides

`usesLanguageCorrection = true` biases recognition toward dictionary words on a page that is almost
entirely brand names. Rather than pick, `MenuTextRecognizer` runs the page both ways and lets
`MenuReadSelection` score them. Costs one extra on-device pass; needs no judgement from us.

### 4. `OCRNameRepair` — the lexicon was already in the binary

The garbled names are all one glyph-shape confusion from a brand in `generatedBrandTable`
(655 curated entries with vetted ABVs):

    MICHELOS ULTRA  →  Michelob Ultra          S for B
    BUSCHUGHT       →  Busch Light             LI read as one U, space lost
    DOGRSH HEAD     →  Dogfish Head            FI read as one R
    TRUEY           →  Truly                   L for E
    GUINESS         →  Guinness                dropped letter

Lexicon-constrained correction is the standard answer in OCR pipelines. Two folds — single-glyph
classes (`0/O/Q`, `1/I/l`, `5/S/$`, `8/B`, `6/G`, `2/Z`) and **ligature collapses** where two kerned
capitals read as one glyph (`LI→U`, `FI→R`, `RN→M`, `VV→W`, `CL→D`) — then a length-scaled edit
distance. The ligature fold is the load-bearing half: `BUSCHUGHT` and `Busch Light` fold to the
*same string*, distance zero, no fuzziness required.

**Matching is per word, not per character.** A floating character window finds `press` inside
`MARG UNDER PRESSURE` and `beck's` two edits from `BUCKSHORT`; word alignment doesn't. Measured
against the real dump: **15 of 15 garbled names repaired, 0 false positives across 27 non-brand
lines.** Wired as tier 1b in `StaticBeverageKnowledge` — after the exact brand tier, so clean names
behave exactly as before, and before the style chart, so a repaired brand beats a chart average.
The note names the brand it landed on, so the person can see and reject it.

**Two deliberate misses.** `SREWDOG ELVIS AF` stays unmatched: the nearest entry is Brewdog Elvis
Juice at 6.5%, but Elvis AF is the alcohol-free one, so a confident partial match would be worse
than none. `IC UGHT` too — `ic light` is not in `Tooling/Data/beverages.json`. When the table is
missing a beer the fix is the table, not a looser threshold. **Worth adding to beverages.json:**
IC Light, IC Light Mango, Brewdog Elvis AF, Victory Sour Monkey, Penn Brewery Weizen, Platform,
Helltown, Evergrain, North Country — all Pittsburgh taps this app will meet again.

### 5. A pre-existing precision bug, not fixed, flagged

The existing brand tier matches by raw substring containment with no word boundary, so
`MARG UNDER PRESSURE` already resolves to the seltzer brand **Press** today, before any of this.
`OCRNameRepair` avoids that class by construction, but tier 1 still has it. Fixing it means
word-anchoring a load-bearing matcher with 655 keys and a lot of tests behind it — worth doing,
worth doing on purpose, not as a side effect of this batch.

### 6. What the prior art says to do next (not built)

Both part 2 geometry fixes are crude versions of published algorithms, and the published versions
delete tuned constants rather than adding them:

- **Breuel 2002**, *Two Geometric Algorithms for Layout Analysis*: cover the page background with
  maximal empty rectangles and score them as column separators, then use those gutters as
  **obstacles** in text-line finding. Reported as not sensitive to font size, font style, or scan
  resolution — exactly what `minGutterGap` lacks, and it is `minGutterGap` being 0.0032 off that
  turned Shorty's beer column into wine. Under ~100–200 lines. Also a better architecture than
  ours: obstacles are recoverable, a bad block split isn't.
- **O'Gorman 1993**, *The Document Spectrum* (Docstrum): nearest-neighbour clustering with a
  distance histogram whose peaks *are* the within-word, within-line and between-line spacings.
  Claimed independent of skew angle, of text spacing, and tolerant of differing local orientations
  in one image — which is literally the tap list, curling one way at the top and the other at the
  bottom. Our baseline chaining is a degenerate Docstrum; the histogram makes the tolerance a
  measurement instead of `0.5 × medianHeight`.
- Shafait's comparison found no single winner but the three best performers were constrained
  text-line finding, Docstrum, and Voronoi — i.e. the two above.

Do these *after* the rescan. If the document scanner removes the curl, the chaining fix may be all
that's needed and the Docstrum upgrade becomes optional rather than load-bearing.

### 7. Running the rescan — `Tooling/ingest_dump.py`

Save the whole console to a file and run `python3 ingest_dump.py rescan.txt --name shortys`. It
splits every scan into a replayable fixture, then reports shipping vs gutter-veto vs chaining vs
both, with **complete rows** (name + ABV + price on one line) as the headline number — 0 of 22 on
the tap list before, 22 of 22 with both fixes. It also surfaces the alternative-candidate lines, the
ranking summary, the read-selection scores, and warns when a scan is under 1200 px wide.

---


**Supersedes part 1's §1 and §4 diagnosis.** Two real dumps arrived (`ROTATING` tap list and the new
three-column Shorty's card) plus four screenshots of the ranking. Part 1's price-gutter bug is
**confirmed on real coordinates**, but it was never the failure reported from the bar, and the tap
list turns out to have a *second*, independent geometry bug that had to be fixed for the first fix
to be worth anything. Still nothing compiled.

`Tooling/Fixtures/shortys_rotating.txt` holds the 209 real observations. `faithful.py` reproduces the
device output exactly — 55 lines, line for line — so the bench can now be trusted on this page. The
synthetic `rotating_fixture.py` is deleted; it was right about the shape and wrong about the cause.

### 1. What each symptom actually was

| What the person saw | Cause |
|---|---|
| ROTATING: "0 of 16 lines priced", nothing to rank | price-gutter cut (part 1 §1) **plus** rows torn in half by page curl |
| New menu: beers at 12% ABV / 5 oz | every beer inherited `wineGlass` — one missed column gutter |
| New menu: `$59.00`, `$58.00` menu prices | Vision read `$9` as `59` and `$8` as `58` |
| New menu: "BAZY UFTLE THING", "DOGRSH HEAD", "SREWDOG" | 574 px wide source image (see §5) |

Note what is *absent*: no phantom `(BELGIAN WHEAT)`-style items on this dump, because the continuation
rows read as `(LAGER) 5% AB4` and similar and still became items — part 1 §2's fix does apply, but
it was not the headline problem.

### 2. Page curl breaks rows, and deskewing cannot fix it

`assembleRows` pinned `anchorMidY` to a row's topmost box and held every later box to *that* anchor,
to "prevent cumulative drift". On a paper strip held in the hand the drift is real: row 1 of the tap
list runs y = 0.8304 → 0.8172, a drift of 0.0132 against a tolerance of 0.0088, so `1 - IC LIGHT`
and `4.2% ABV` came out as separate lines and the printed strength never reached the beer.

**This is not skew.** On that one page rows 1–8 slope down to the right (to −0.096 dy/dx), rows 13
and 22–27 are dead flat, and row 28 slopes *up* (+0.023). No single angle describes it, so
`ImageDeskew` — pending for five sessions — would not have helped.

What is stable is the step between neighbours: the largest gap between adjacent words *inside* a row
on that page is 0.0044, half the tolerance, while the gap to the row above is ~0.032. So rows now
chain each box onto whichever open row's rightmost member is nearest in y. Same tolerance; only what
it is measured *from* changed, so nothing new to tune. The anchor's real job — stopping a chain
walking down a price column — is still done, by x, and there's a test for it.

### 3. Measured, on real coordinates

| | ROTATING lines | complete `name + ABV + price` rows |
|---|---|---|
| shipping | 55 | 5 of 22 |
| price-gutter veto only | 33 | 12 of 22 |
| baseline chaining only | 45 | 5 of 22 |
| **both** | 23 | **22 of 22** |

Neither fix is sufficient alone, which is worth remembering before either gets reverted as
"unnecessary".

**Corpus effect of chaining: 6/8 byte-identical, and the two differences are not regressions.**
Menu 7 improves (`cocktails` + `in a souvenir cup +5` becomes one line). Menu 2 is the 1948 card that
`MenuQuality` already condemns; one line there gets better (`Sparkling Water .90 45 20` now carries
its own prices) and one gets worse (`Old old Smuggler Smugi Royal`). Both were junk before. This is
the first change in the project that is **not** output-identical on the corpus, so it wants a look
before it ships.

### 4. The wine contamination: one threshold, 0.0032 of a page

On the new menu the left column's rightmost edge is **0.4077** and the middle column's leftmost is
**0.4495** — a gutter of **0.0418** against `minGutterGap = 0.045`. It misses by 0.0032, so columns 1
and 2 were never separated, `WINES` (middle column) landed in the y-stream between
`SREWDOG ELVIS AF $9` and `IC LIGHT MANGO 16 OZ $10` (both left column), and every item after it
inherited `wineGlass` — including the entire ON TAP column, which is a *later block*, because the
parser's section state is global across blocks. Hence 12% ABV and 5 oz on forty beers.

That gutter is **~4× the page's median text height**; on the tap list, `0.045` is only 2.6 text
heights. So the same absolute threshold means "how many text heights" differently by a factor of 1.8
between two photos of the same bar's menus. `Tooling/assembler.py`'s unit change — measured three
times now, never ported — is no longer a tidiness argument: it is the difference between reading
Shorty's beer column as beer and reading it as wine.

**Two fixes are needed, not one.** Even with the gutter found, the ON TAP column would inherit `WINES`
from the middle column, because `ON TAP` was never recognized by Vision at all (it is absent from all
93 line candidates). So section state must also be **scoped to its block**, with the exception that a
header in a page-wide block still governs the columns beneath it. `LineAssembler` already computes
blocks and then throws the boundaries away; they need to survive into `MenuParser`.

### 5. Before anything else is tuned: re-dump at full resolution

Both dumps are of **574×1020** and **765×1020** images — the compressed copies, not camera originals.
The capture path does not downscale (`UIImagePickerController.originalImage` → `pngData()`), so this
is the source files. A three-column menu at 574 px wide is why `Hazy Little Thing` came back as
`BAZY UFTLE THING` and why `$` became `5` and `S`.

The geometry findings above are resolution-independent and stand. The glyph findings may not, and
the `$`→`5` repair should not be built until it's known whether it survives a full-resolution scan —
the existing leading-`S` strip already handles `S9`, `S10`, `SS`; adding a leading-`5` strip is
riskier (a genuine `$58` bottle) and belongs in `PricePlausibility`, judged against the menu's own
price distribution, not in the parser.

---


**Supersedes nothing; the 09-09 part 2 note still describes monetization accurately.** Triggered by
a live failure at Shorty's on 09-26 on two menus, neither of which is in the corpus. **Nothing here
has been compiled.** Run `swift test` (319 green before this; +17 test functions added).

### 1. The failure was geometric, and reproducible

`LineAssembler` cut a single-column tap list down its own price gutter and stranded **every price on
the page**. Reproduced in `Tooling/rotating_fixture.py`, which reconstructs the ROTATING list in
assembler coordinates: 22 priced beers in, 22 unpriced beers plus 22 orphan `$5` lines out.

Root cause is a real limit of pure geometry, not a bad threshold: **a column of right-aligned prices
is the same shape as a second column.** A blank vertical channel that nearly every row respects.
`minColumnSpan` passes it (ragged name-ends push the right side to 0.197 vs the 0.18 floor) and the
votes-vs-crossers veto passes it (every row genuinely votes). Tier 3 fires, `guardedSplit` accepts.

Fix: **`minNameFraction`** in `guardedSplit`, so it covers all three detector tiers at once. A
column carries names; a price gutter carries prices and a stray ABV. Measured on all eight dumps,
every side of every accepted split is 0.33–0.97 name-bearing; the tap list's gutter is 0.03. Set at
0.20. Output is byte-identical on all eight at every threshold from 0.05 to 0.40.

**An absolute floor is the trap here.** `len(names) >= minSideCount` reads as the more conservative
rule and costs one of the eight menus: deep in the recursion a legitimate leaf can hold one
name-bearing observation out of three. Fraction only. It was measured, then written into
`experiment_pricegutter.side_is_column`'s doc comment so nobody re-adds it.

### 2. Continuation lines were throwing away the printed ABV

`BLUE MOON $6` / `(BELGIAN WHEAT) 5.4% ABV` is two printed rows, so the second became a **phantom
priceless item named "BELGIAN WHEAT"** and the 5.4% was discarded — on a forty-tap list, forty
phantoms in the "Not sure" bucket and forty beers ranked on an estimate, on a menu that prints the
real number for every tap. `MenuParser.isAttributeLine` recognizes it structurally rather than by
style vocabulary: once parentheticals, measurements and separators are removed, nothing is left.
ABV/size are harvested onto the item above, never overwriting what that item printed for itself.
New `ATTR` trace line. The `DESC` path now harvests ABV too (not size — cocktail recipes are full
of `1 oz` build quantities).

Scanned every fixture, test and sample in the tree: this absorbs exactly the two Thirsty Duck lines
(`(Wheat Ale) - 4.0%ABV`, `(English Strong Ale) - 8.2%ABV`), which the recorded trace shows the
shipping parser turning into `ITEM`s, and nothing else.

Also: `dropEnumerator` keeps tap numbers out of names (`1 - `, `12.`, `#3`), guarded so `10 Barrel`,
`151 Rum Punch` and `2019 Cabernet` are untouched; `_` is now a separator, so underscore leader
rules don't survive into the title.

### 3. `RecognizeDocumentsRequest` (iOS 26) is now a second reader, chosen by score

The deeper fix for §1 is not to *infer* the table. Apple reports it. A numbered tap list is a
three-column table and a two-row item is a paragraph.

`DocumentStructureRecognizer` emits two independent readings (the document's own page text, and one
line per table row) rather than interleaving tables with prose, which would need each element's
bounding region and a reading-order sort — exactly the geometry this is meant to stop hand-rolling.
`MenuTextRecognizer` runs the geometric path **and** the structured one and keeps whichever reading
scores better, via the new pure `MenuReadSelection`: most priced drinks wins, leaner wins at equal
yield, first candidate wins a full tie (the geometric reading is passed first, so ties change
nothing). Scored through `MenuParser` + `PricePlausibility`, the same two steps `MenuPipeline`
applies, so a junk reading can't win on withdrawn prices.

Preferring one engine by OS version is a coin flip per photo; scoring both is a decision. Cost is
one extra on-device pass per scan.

**⚠️ Seven Vision API names in that file rest on Apple's docs, not on a compile** — they're listed
in a block comment at the top of the file, confined to one function, behind `#available` with a
total fallback to today's behaviour. Verify them in Xcode first.

### 4. A dump for the half of the pipeline nothing could see

The 09-26 report was "garbage answers next to the drinks — fake drinks with fake $ and ABV", which
is a **precision** failure and therefore *not* §1: a stranded price column produces an empty
ranking, not a populated one. §2 is the prime suspect (a continuation row becomes a phantom drink,
and every real beer loses its printed ABV to a category default), but the existing console export
stops at `[MenuItem]`, and between there and the screen sit three unobserved steps —
`PricePlausibility` withdrawing a price, `DrinkResolver` resolving ABV/size through
`BeverageKnowledge`, and `ValueRanker` ordering the result.

`ObservationFixture.sessionDump` closes it: per ranked row, the metric value, price, category, and
**ABV/size with provenance**. `read` vs `est` is the diagnostic that matters here — a podium built
out of `est` ABVs on a menu that prints its ABVs on every line means the printed numbers were lost
upstream, which is a parser bug; the same podium with `read` ABVs and silly values is a
knowledge-table or metric bug. One glance separates them.

Wired into `CaptureHomeView` behind `#if DEBUG`, printed straight after `viewModel.load`. It reads
the view model's **own** session rather than rebuilding one: `MenuPipeline()`'s default is
`StaticBeverageKnowledge` while the screen resolves through `CatalogBackedKnowledge` over the
bundled catalog, so a rebuilt session would disagree with the ranking it exists to explain.

**Apply order matters.** The dump is behaviour-neutral, so take it *first*
(`step1-ranking-dump.patch`), capture both Shorty's menus on otherwise-unchanged code, and only then
apply the fixes (`step2-…`, which contains step 1). Capturing after the fixes loses the failing
baseline and with it any way to show the fixes worked.

### 5. Known residuals

- **`console.txt` is still pre-veto** (the 09-07 part 3 note said so). `verify.py`'s 8/8 therefore
  validates the pre-change baseline, which is the right thing for the bench and the wrong thing to
  quote as proof of current behaviour. Both Shorty's menus need dumping; the §1 evidence rests on a
  *reconstruction*, not on real coordinates.
- **`Tooling/assembler.py`'s unit change was measured again and still not ported.** Aspect ratio
  across the dumps runs 0.386–0.751, so `minSectionGap`/`minGutterGap`/`minColumnSpan` — all page
  fractions — mean different physical distances per crop. Expressed in median text heights, mean
  fragmentation goes 0.261 → ~0.228. Deferred deliberately: it moves every geometry decision at
  once and should land against fresh dumps, not stale ones.
- **~350 hand-curated English word literals across twelve vocabularies** in `MenuParser`, and box
  height is still read exactly once (row tolerance) even though header-vs-item and
  item-vs-description are typographic facts sitting in the geometry. That is the standing
  generalization debt; §1–§3 above deliberately add no new vocabulary.
- `DetectLensSmudgeRequest` (iOS 26) gives a 0–1 smudge confidence and would make a decent "clean
  your lens / retake" hint. Untouched. `ImageDeskew` is still not in `Infrastructure/`, five
  sessions on.

---

## ⇢ STATUS (2026-09-09, part 2) — RevenueCat is integrated and proven on device

**Supersedes the "Next" list in the 2026-09-07 part 3 note.** Monetization is done except for the
Apple-side steps. `swift test` is **319 green** (316 + 3; see §4).

**Read this first: the 2026-09-09 part 1 note does not exist.** The docs from that session were all
saved (`Risks.md`, `MonetizationPlan.md`, `Architecture.md`, `ProjectConventions.md`,
`CodebaseReference.md`, `Changelog.md` all carry 17:13–17:26 timestamps) but `Handoff.md` was not
(14:29). The code matched those docs exactly — 316 test functions, the revised four-method
`PurchaseController`, no `AdPresenter` — so the work was real and only the note was lost. The 09-07
note's lesson runs backwards here: that one over-reported work absent from the tree, this one
under-reported work present in it. **Grep before believing either direction.**

### 1. The SDK

`AppTarget/Infrastructure/RevenueCatPurchases.swift`, new, an `actor`, and the only file that may
import RevenueCat. `ABVApp.swift` calls `RevenueCatPurchases.configure()` in `init()` and builds
`SupporterStore` around the real conformer. `ContentView.swift` deleted (unreferenced, superseded by
`CaptureHomeView`, still compiling because the Xcode group is synchronized).

**SDK 5.88.0** via SPM, mirror repo `https://github.com/RevenueCat/purchases-ios-spm`, Up to Next
Major from 5.88.0. Product `RevenueCat` only — **not** `RevenueCatUI` (their prebuilt paywall; we
have `PaywallFlow` + `PaywallView`), not `ReceiptParser`, and emphatically not
`RevenueCat_CustomEntitlementComputation`, which is the variant for computing entitlements on your
own backend.

**Three API findings, verified against RevenueCat's docs and `purchases-ios` `main` on 2026-09-09.**
Re-verify before trusting; this note is a record, not an authority.

- **`.pending` and `.cancelled` arrive by `throw`, not in the result.** Ask to Buy throws
  `ErrorCode.paymentPendingError` (case 20); a dismissed sheet throws `.purchaseCancelledError`. The
  contract already had both cases, so nothing in `Core` moved — they just come out of the `catch`.
- **`userCancelled` is a hint, never the truth.** RevenueCat documents it as a convenience over the
  error, and purchases-ios issue #4903 reported it reading `true` on ~22% of *successful* production
  transactions on 5.17.0 (now closed, resolution not publicly visible). Per `ProjectConventions.md`
  §8 the entitlement is the state: the flag is consulted **only** when `supporter` is inactive. That
  ordering prevents the expensive failure, which is somebody paying and getting the paywall back.
- **`Purchases.shared` traps when unconfigured**, so every method guards on `isConfigured`.

**Not verified:** every SF Symbol still rests on my reading rather than the SF Symbols app.
`mug.fill`, `wineglass.fill`, `drop.fill`, `heart.fill`, `drop.triangle`, `xmark` all render on
device, so they exist; nothing else was checked.

### 2. Everything R7 warned about happened

Both failure modes fired, in the order the risk predicted, and the code caught both.

- **The identifier mismatch was real.** App Store Connect had `supporter.shot/.pint/.round`;
  RevenueCat had `support.shot/.pint/.round`. Missing three letters. Fixed on the RevenueCat side
  (ASC identifiers cannot be changed after creation and the localizations were already written), and
  fixed by **importing** the products from ASC rather than retyping them, which makes the class of
  mistake impossible to repeat. Note the app code would have survived it silently:
  `SupporterTierKind.resolve` matches on the `.shot`/`.pint`/`.round` suffix, so the badge would have
  read correctly while the paywall sat empty.
- **Test Store products are separate objects from the App Store products**, even sharing an
  identifier, and the entitlement had only the Apple three attached. So a Test Store purchase
  recorded fine and granted nothing. `RevenueCatPurchases` threw `EntitlementNotGranted` rather than
  thanking anybody, which is exactly the intended behaviour, and the fix was attaching the three
  Test Store products to `supporter` as well. **Six associated products, not three.**

Lesson for the register: the app refusing to say thank you was the *only* signal that the dashboard
was wrong. Had the conformer trusted `userCancelled` or assumed success, this would have shipped as
an app that thanks people while granting nothing.

### 3. What is proven, and on what

On device, Test Store key, SDK 5.88.0, iOS 26.4.2. Offerings fetch, three tiers at the right prices
in shot/pint/round order, a recorded purchase (`POST /v1/receipts` 200, transaction finished, visible
in the RevenueCat dashboard), a real user cancel, two simulated failures, the thank-you state, the
home-screen badge, and the entitlement surviving relaunch.

**Ask to Buy is the one branch never exercised.** It needs sandbox, which needs banking at "Clear".

**Banking was still not "Clear"** at the end of this session, and it did not block anything: the
Test Store involves Apple not at all. Only sandbox waits on it. That took the one uncontrollable item
off the critical path, which is worth remembering next time — the instinct was to treat banking as a
blocker for the whole purchase path, and it is a blocker for one step of it.

### 4. Three reversals, all deliberate

**a. The earned prompt moved from a list row to a timed sheet.** `SupporterPromptRow` sat below the
ranking, the needs-price bucket, the add-a-drink row and the excluded section. On the Southside menu
that is roughly forty rows down, and `markAsked()` fired on the row merely *appearing*, so the one
ask anybody ever got was being spent on something almost nobody scrolled to. It now presents
`PaywallView` five seconds after a qualifying scan, from `ResultsView.offerSupportIfEarned()`.
Leaving inside the window cancels the task, so `markAsked()` never fires and the ask survives.
`SupporterPromptRow` is **unreferenced but kept** — unlike `AdPresenter` it was written against
something real, and it is the obvious component if a quieter second surface is ever wanted.

**b. "Never ask twice" became a three-scan cadence.** `hasAlreadyAsked: Bool` →
`scansSinceLastAsk: Int`, with `SupporterPrompt.scansBetweenAsks = 3`. `SupporterStore` persists the
counter, starts a fresh install **at** the interval so the first qualifying scan still asks, counts
every results screen including thin reads, and resets to 0 when the sheet shows. Asks land on scans
1, 4, 7. Rule 1 still means a supporter is never asked again.

This is a reversal of a settled `MonetizationPlan.md` §6 decision and it changes a promise that was
public in `PlainLanguageGuide.md`. That doc is now corrected; if the cadence is ever tuned, correct
it again, because it ships with the open-source entry.

Tests: `testItNeverAsksTwice` deleted (it asserted the opposite of the new rule) and five added —
the reset, the whole interval, the ask returning, an overshooting counter, and a thin read still
refusing however many scans have passed. **316 → 319.**

**c. A permanent Support entry point in the home-screen toolbar.** Not a second ask: it exists
because **`PaywallView` is where Restore Purchases lives**, and with a one-shot prompt the restore
path was reachable exactly once per install. App Review exercises restore on a non-consumable, so
that was a 2.1 rejection waiting to happen. Labelled "Support", not "Donate": Apple treats
charitable donation collection differently from tipping a developer, and R3 already puts this app
under extra scrutiny.

### 5. Also landed

- **The `isLowConfidence` `Notice` is wired** (`ResultsView.thinReadSection`), which closes the
  largest residual in the 09-07 note. Says what was missed with real counts rather than the phrase
  "low confidence", and offers two actions: rescan, or push `QuickCompareView`, which is the honest
  recommendation because two hand-typed drinks have no estimates at all.
- **The paywall's dismiss is an X**, not "Done" — the sheet arrives uninvited, so the exit should read
  as dismiss rather than confirm. Header is two short lines: free promise first, "just a tip jar"
  second.
- **The thank-you state is a large tier mark.** `ContributorMark` in `SupporterBadge.swift`: 68pt
  glyph plus "Shot/Pint/Round Contributor" in that tier's metal. The **round is two `mug.fill`
  mirrored and leaning**, because SF Symbols has no clinking-mugs glyph (searched; the 🍻 emoji
  exists but cannot be tinted). Tiers read as a progression: a drop, a mug, two mugs.
- **The metals moved to `Theme`.** `gold`/`silver`/`bronze` were raw literals inside `RankMedal`,
  which broke "Theme.swift is the only place colours live". Same three values, named once, nothing
  renders differently. Kept **non-adaptive** deliberately: an adaptive gold drifts toward
  `Theme.amber` in light mode, which is the muddying the comment on `amber` exists to prevent.

### 6. Known residuals

- **The metals now carry two meanings**, rank and supporter tier. They never share a screen, so the
  signal stays legible, but this is the second-meaning problem §11 warns about and a third use would
  be one too many.
- **Menu reading is worse than the 09-07 note recorded**, in one case consequentially. The `F`
  residual (`sparkling peach pear` opening a wine section) reaches **two** items on the Braintree
  cocktail menu, not one, and changes a category. Worse: on a Bristol club menu, a dotted leader line
  `WINES...... ....50` inherits **$50 to six wines** as a by-the-glass price. That is a wrong price
  that *ranks*, and `isLowConfidence` stays false at 13/20 priced, so nothing flags it. Everything
  else observed is cosmetic: `Southsidg`/`BRAINT` (a logo) become needs-price items,
  `Miller 64` → `Miller` at **$64.00**, `ATHLETIC BREWING CO. NON ALCOHOLIC` swallowed as a
  description, and a stray `8` dropped as `empty-name-after-clean`.
- **`SupporterPromptRow` is unreferenced** (above).
- **The `ABV-INVITE` DEBUG trace in `ResultsView` is still in.** Useful; `#if DEBUG` so it does not
  ship. It names values but not which rule failed, which cost a round trip — worth improving if the
  cadence is ever debugged again.
- **Testing the ask now costs four scans and an app delete.** `UserDefaults` survives an Xcode
  reinstall, so only deleting the app resets the counter and the age gate. A DEBUG-only reset was
  offered and not built.

### 7. Next, in order

1. **R6, and it is the only thing that can still cost days.** Archive, upload, and confirm the
   "In-App Purchases and Subscriptions" section renders on the version page and lets all three
   products be selected. Verify from the TestFlight console that the Test Store warning is **gone** —
   that is evidence the `#if DEBUG` split works, where checking the scheme is only an assumption.
2. **`ValueFigure` / `PourLine` into `RankedValueRow`.** Still built and unused; the row still draws
   a plain accent-coloured number. R5 says do not cut these.
3. Screenshot the paywall, attach to all three products' Review Information, submit the products
   **with** the build.
4. Listing copy, privacy labels (still "no data collected" — no ad SDK, Vision on-device), age
   rating, submit.
5. Sandbox purchase and Ask to Buy, once banking says "Clear".

---

## STATUS (2026-09-07, part 3) — Rebrand to ABV, a real design layer, chip-wrap fix

**Supersedes the "Next" list in part 2.** Menu reading is closed out for this pass. The next session
is **monetization only** — see `MonetizationPlan.md`, which carries the conversation opener.

`swift test` is **264 green** (263 + the one test of mine that asserted the wrong thing; the code was
right, the assertion was wrong — see below).

### 1. The product is now "ABV: A Better Value"

Displayed as **ABV**. What changed and what deliberately did not:

| Name | Value | Note |
|---|---|---|
| App Store listing name | `ABV: A Better Value` | typed into App Store Connect at submission; nothing in the repo has to match it |
| Home-screen display name | `ABV` | `INFOPLIST_KEY_CFBundleDisplayName` |
| `@main` type | `ABVApp` | `BangForBuckApp.swift` deleted |
| Bundle identifier | `NovalCo.BangForBuck` | **unchanged on purpose** |
| Xcode target, project, source folder, repo | `BangForBuck` | **unchanged on purpose** |

**Why the identifiers stayed.** These are four independent names and only the listing name is
customer-facing. A bundle-ID change is free *only* until an App Store Connect record and a
RevenueCat product exist; after that it means a new record and a re-created IAP. It was briefly
changed to `NovalCo.ABV` during this session and then reverted, because it buys nothing a user sees
and adds a reconciliation step in the week before submission. `Tooling/rename_to_abv.sh` exists and
is **dry-run verified** (26 pbxproj references → 0) if a full rename is ever wanted; it is not
needed and should not be run casually. The four references it has to move together are documented
in its header — Xcode's own Rename refactor misses three of them, which is why it is a script.

### 2. A design layer, in `AppTarget/Design/Theme.swift`

The app was stock SwiftUI throughout: system fonts, `.borderedProminent`, grey opacity chips.

**The idea:** this gets used standing at a bar, in dim light, to decide what is worth buying. So the
palette is glass and liquid, and the darks are **green-tinted** (`#0D1411`) rather than neutral
charcoal, which follows from the `#1D6F4C` accent the project had already picked "to read as glass".
Type is **SF Rounded** — casual, a bit chunky, closer to a chalkboard than a wine list. An earlier
pass used New York serif and it read as a sommelier's tool; that was wrong for the audience and was
replaced.

Tokens: `canvas` / `surface` / `glass` / `amber` / `ink` / `inkMuted`, a 4pt spacing scale, two
radii. Components: `Wordmark`, `ValueFigure`, `PourLine`, `Notice`, `PourButtonStyle`,
`ActionCardStyle` + `ActionCardLabel`, `ChipFlow`.

**Colour allocation is deliberate and worth preserving:**
- **amber means exactly one thing — "this number is an estimate" (§11).** Nothing else wears it, so
  an amber chip anywhere in the app means the same thing.
- **the value figure is bottle green, not amber**, because the rank medals are gold and gold beside
  amber muddies both.
- gold/silver/bronze medals were removed in one pass and **restored on request**; they live in
  `ValueChips.swift`. Their return is what pushed the value figure off amber.

**Home screen rebuilt.** No longer a `ScrollView`: the four ways in are full-height cards that
divide the screen, each with an icon, a title and a line saying what it does. The photo card is
filled green, the other three outlined, so it stays a hierarchy rather than four equal doors. Trade:
nothing can overflow, so a fifth way in won't fit without reworking the layout.

Copy: the tagline is "See which drink gives you the most for your money." — not a question (the
person already opened the app) and avoiding the word "value", which the wordmark directly above
says twice. "No menu on you?" became "Try a demo below".

### 3. The chip truncation bug — a real §11 failure, not cosmetic

The provenance badge was rendering as "estimat…", but **only when the ABV carried a decimal**:
`4.2% ABV` is about 10pt wider than `5% ABV`, and a plain `HStack` distributes its available width
across children, so it **compresses rather than wraps**. SwiftUI then truncated whichever child it
liked, and it picked the badge.

So the honesty badge — the load-bearing §11 promise — was being abbreviated based on whether a
number happened to have a decimal point. Worth calling that out plainly: an invariant the whole app
is built around was failing intermittently in the UI.

Fixed with `ChipFlow`, a `Layout` (iOS 16+) that wraps to a new line instead of squeezing, plus
`.lineLimit(1).fixedSize()` on `MetaChip` and `ProvenanceChip` so neither can be compressed at all.

**It was in five places, not one.** `ResultsView` has its own copy of the chip row with the same
bug. And pinning `MetaChip` meant the three meta-only rows in `CompareView` and `QuickCompareView`
would have *overflowed* rather than truncated, so those were converted too. All five chip rows now
wrap.

`ChipFlow` needs a bounded width to wrap — it falls back to `.infinity` when the proposal has no
width. Every current call site is inside a bounded row, but a chip row inside a horizontal
`ScrollView` would silently stop wrapping.

### 4. C now flags instead of withholding

Reversed from part 2 on request, and the request was right. C used to suppress the ranking entirely
on a thin read. The 1948 Roosevelt list is the counter-example: once `PricePlausibility` withdraws
its four absurd prices, the top of its podium is `Individual Decanter Service` at **$1.00**, a real
line for a decanter of whiskey and genuinely the best value on the page. Withholding gave the person
nothing when a flagged, imperfect answer was available.

`MenuQuality.isRankable` → `isLowConfidence` (inverted), the `guard` in `rankedDrinks` is gone,
`hasManualPrice` is deleted as dead machinery. Thresholds unchanged: 25% of items priced, 8-item
floor, same measured 11.3% → 36.1% gap.

**The flag stays set after manual price entry**, on purpose: it is a verdict on the OCR read, not on
the current state of the list. Recomputing it live would make the banner flicker off as the person
edits, which reads as the app changing its mind about the photo.

### 5. Fresh device dumps confirmed two things

- **The gutter veto works, and `Tooling/Fixtures/console.txt` is stale.** Its menu-1 block was
  captured *before* the veto shipped: the recorded lines show the cocktail block torn in half
  (`BAR MANHATTAN RITTEN HOUSE` … `COCKTAILS` … `RYE, SWEET VERMOUTH, ANGOSTURA BITTERS`). A new
  dump of the identical 357 observations produces 73 whole lines where the old one produced 84 torn
  ones. **`faithful.py`'s "8/8" has therefore been validating a pre-veto baseline.** Replace
  `console.txt` with fresh dumps before trusting the bench again.
- **The priced-description residual did not fire** on either new dump. Still unmeasured on Rullo's,
  but the evidence so far is on the good side.

### Known residuals

- **`MenuQuality.isLowConfidence` has no UI.** `Notice` is built for it and unused. Without it, a
  badly-read menu presents a ranking with no caveat — the honest behaviour C exists to produce is
  computed and then not shown.
- **`ValueFigure` / `PourLine` are built and unused.** `RankedValueRow` still renders a plain
  accent-coloured number.
- `console.txt` is pre-veto (above).
- Menu-reading residuals from part 2 all stand: the priced-description case, menu 1 losing its whole
  wine list to a column mismatch, `COORS LIGHT $02` → $2.00, `CANS` classifying as seltzer.

### A note on my own test

`testVesselIsFillerInsideARealLabel` failed on the first run. The **code was right and the
assertion was wrong**: `bottle` has been in `sectionWords` since long before D, so
`isPureSectionLabel("Glass 12 Bottle 40")` is legitimately `true`. What keeps that row out of the
header path is `pureLabelCategory` returning `nil`, because vessel singulars are deliberately absent
from `labelCategories`. The test now pins that distinction instead of asserting the wrong mechanism,
since conflating the two is the easy way to break D later.

### Next

**Monetization, and nothing else.** `MonetizationPlan.md` has the opener and the order of work.
R5 has now been deferred across five sessions; the window closes Sep 30 and App Review sits inside
it.

---

## STATUS (2026-09-07, part 2) — D and C shipped; menu reading is done for this pass

**Supersedes the "Next, in order" list in part 1.** D and C are in; the only remaining item on that
list is **RevenueCat (R5)**, which is now the whole of the critical path.

### 1. D — priced section labels

`WHITES - $9 GLASS / $82 BOTTLE` split into two ranked drinks called "WHITES (glass)" at $9 and
"WHITES (bottle)", while every wine underneath stayed unpriced. Rullo's `Red | $11/ $40` did the
same, producing "Red (glass)" $11 and "Red (bottle)" $40. Confirmed straight off the device traces,
not inferred.

The parser was already inconsistent, as part 1 noted: `Rosé | $10 / $35` inherited correctly because
"rosé" was in `headerKeywords` while `red`/`white` were not.

**The fix is a token-exact pure-label path**, `pureLabelCategory(_:)`, checked before the substring
keyword loop and only for lines `isPureSectionLabel` accepts. Two halves, both load-bearing:

- **Token-exact, because a colour cannot be a substring.** `red` and `white` sit inside
  `Allagash White`, `Fire Red Ale`, `White Claw` and `Wente Mt. Diablo Red Blend`. Adding them to
  `headerKeywords` would turn a beer list into wine sections. They live in `labelCategories` and
  deliberately **not** in `headerKeywords`. `labelCategories` walks the same group order, so
  `BOTTLES CANS` still resolves to bottled beer rather than seltzer.
- **A vessel is filler, not a category.** `isPureSectionLabel` now accepts `sizeOnlyWords`, which is
  what lets the menu-8 label parse at all. But `bottle`, `can` and `glass` are **absent from
  `labelCategories`**, so menu 5's `Bottle 25` and `Glass 12 Bottle 40` stay size/price rows instead
  of opening a Bottled Beer section priced at $25. Getting this backwards is the obvious trap.

`red`/`white` were also added to `wineSubLabels`, so a bare colour under a priced Wine section does
not reset the shared by-the-glass price. `isWineSubLabel` now runs `replaceSeparators` first.

**Measured across all eight dumps and lowercased copies: zero existing header verdicts change.**
Seven lines newly become headers — the four target lines, plus three incidental improvements
(menu 7's bare `red`/`white`, which were ranking as junk needsPrice items, and menu 6's `cocktail`,
which was already unrankable).

### 2. C — whole-menu quality gate

**Read this before touching the threshold: the plan in part 1 was wrong, and the data says so.**
That plan proposed "mean confidence + priced-line ratio + withdrawn-price count". Mean OCR
confidence is not merely weak here, it is **anti-correlated**:

| Menu | mean Vision confidence | priced items |
|---|---|---|
| 1 | 0.946 | 45.2% |
| **2 (1948 list)** | **0.937** | **11.3%** |
| 3 (Rullo's) | **0.625** | 36.2% |
| 4 | 0.985 | 50.0% |
| 5 | 0.986 | 43.2% |
| 6 | 0.991 | 51.4% |
| 7 | 1.000 | 36.1% |
| **8 (Thirsty Duck)** | **1.000** | **5.3%** |

The two menus that must be condemned read at 0.937 and **1.000** — Vision resolved their glyphs
perfectly and attached them to the wrong things. The *lowest* confidence on the corpus, 0.625,
belongs to Rullo's, which parses well. **Any confidence threshold that catches menus 2 and 8
destroys menu 3 first.** The part-1 note also claimed the 1948 list ranks "from confidences as low
as 0.30"; only 3 of its 129 lines are below 0.5. Do not re-derive this.

The **priced fraction** separates cleanly: bad at 5.3% and 11.3%, good starting at 36.1%. A 3.2×
gap with nothing in it, so the threshold is not finely tuned — anywhere from 12% to 36% gives
identical verdicts on all eight. `minimumPricedFraction = 0.25`, set nearer the good side because
wrongly condemning a real menu costs the whole feature while wrongly passing one costs a list the
person can see is junk.

It also means something rather than being a fitted statistic: the ranking claims to describe *the
menu*. If three quarters of the lines that parsed as drinks carry no price, it describes the quarter
that did, and there's no reason that quarter is representative.

**`PricePlausibility` feeds this for free** — a withdrawn price becomes a `needsPrice` item, which
lowers the fraction by construction. That is why this is one signal and not three.

Wiring:
- `MenuQuality` + `MenuQualityGate.assess(_:)` in CoreServices, pure, judged on the parser's own
  `[MenuItem]` output (the thing that was measured), before enrichment drops non-alcoholic items.
- `MenuSession.quality` defaults to `.trusted`, so **every hand-built session and every existing
  test is behaviourally unchanged** — the gate judges an OCR read, and there isn't one there.
- `rankedDrinks` returns `[]` when not rankable. **Nothing is discarded:** the drinks stay in
  `drinks` and `needsPriceDrinks` for review, per §10's "never silently dropped".
- `MenuAnalysis.quality` added so `analyze` and the session agree.
- `minimumItemsToJudge = 8`: below that the ratio is one or two lines wide. Verified that **no
  existing `analyze`/`makeSession` call site in the suite reaches 8 items**, which is why nothing
  else moved.

**`setPrice` sets `hasManualPrice`, which lifts the suppression.** Once the person has supplied a
price they have taken over from the OCR, and withholding a ranking they can see is correct would be
obstructive rather than honest. This is a judgment call, not a measurement — flagging it as the one
part of C that is design rather than evidence.

### The UI still needs a line of copy

`MenuSession.isRankable == false` currently renders as an empty ranking with a populated "Not sure
about these" bucket. That reads as a bug. Results needs to say something like "couldn't read enough
prices off this menu to rank it — add a price below, or retake the photo straighter". **Not done**;
it is view work and the part-1 note's house rule keeps logic out of views. This is the one loose end
in menu reading.

### Tooling

`Tooling/sections.py` gains `section_header_d` alongside the untouched `section_header`, the same
split `faithful.py` / `experiment.py` uses: the baseline port stays byte-faithful to the *device
trace* and still verifies 8/8, while the candidate lives beside it. `verify_sections.py --measure`
covers F; `measure_d()` covers D.

Note that after D ships, the recorded traces are **pre-D**, so `validate()` continues to check the
baseline port, not the shipping parser. When the next dump is captured, re-point it.

### Known residuals

- **The part-1 residual stands and is now more likely to bite.** Killing a header match sends the
  line down the item path, and under a *priced* section `looksLikeDescription` is gated on
  `headerPrice == nil`, so a bulleted ingredient run becomes a priced item. D adds more priced
  sections, so this fires more often. Still unmeasured, still needs a `MenuParser` port. **This is
  the first thing to look at if the next scan shows junk in the ranking.**
- `minimumItemsToJudge = 8` and `minimumPricedFraction = 0.25` rest on **two bad menus**. The gap is
  wide, but two is two.
- Everything in the 09-06 residual list is untouched.

### Next

**RevenueCat, and nothing else.** R5 has been the stated critical path since 2026-09-05 and has now
been deferred across four sessions. Menu reading is good enough: F, D and C together fix the largest
wrong-rank-1 classes, and R1's own trigger says a partial read plus fast manual edit is the design,
not a failure. The remaining menu work (the priced-description residual, the UI copy above) is
smaller than the qualification risk.

---

## STATUS (2026-09-07) — F (prose section headers) shipped; two dangling items from 09-06 completed

**Supersedes nothing.** Adds to the 2026-09-06 note. **R5 (RevenueCat) is untouched and remains
the live risk** — nothing here went near monetization.

### Read this first: the 09-06 note over-reported

Two of the five items that note describes as shipped were not, in fact, in the tree. This was found
by grepping for them rather than trusting the note, and it matters because the note also claims
`swift test` was green at 214/214, which **could not have been observed**:

| 09-06 item | Actual state at `46054af` |
|---|---|
| 1. DEBUG OCR trace | shipped, committed |
| 2. `gutterSupport` crossing-row veto | shipped, committed |
| 3. `splitAtPriceToNameBoundaries` | shipped, committed |
| 4. `PricePlausibility` | file present but **never wired** — nothing in `Core/Sources` referenced it |
| 5. `ABVEstimator` ABV ceilings | **absent entirely**; `ABVEstimator.swift` was the original 11 lines |

`PricePlausibilityTests.swift` contains an `ABVPlausibilityTests` class calling
`ABVEstimator.abvCeiling(for:)` and `ABVEstimator.isPlausible(_:for:)`. Neither existed, so **the
test target could not compile.** Items 4 and 5 were dangling working-tree changes.

Lesson worth keeping: a handoff note is a claim, not evidence. Grep for each shipped item before
building on it.

### What shipped this session

**1. `ABVEstimator` ABV ceilings (completes 09-06 item 5).** Written to satisfy the tests that were
already committed against it. Ceilings are **derived, not tuned**: the error is a lost decimal
point, which always multiplies by exactly ten, so a ceiling works while it sits above the strongest
product really sold and below ten times the weakest. Table in the doc comment.

An implausible printed value is **discarded, not corrected** — the read is dropped and the knowledge
estimate used, badged `.estimated`. Dividing by ten would be a fabrication wearing a `.read` badge
(§11); we cannot distinguish a misplaced decimal from a genuinely strong pour.

`.unknown` deliberately has **no** ceiling: it is the category assigned *because* the line could not
be classified, so it carries no expectation to violate.

The spirit-forward categories sit high on purpose (cocktail 45, frozen 40, martini 50) — a Sazerac
or a barely-diluted stirred martini really is most of the way to neat spirit, and printed ABVs are
rare outside beer, so the cost of a low ceiling is a discarded real read. **45 is the maximum for
`cocktail`, not a preference:** anything higher stops catching 50%, the tenfold misread of a 5%
highball. Beer is the tight one — Utopias at 28% against a ceiling of 30 means a dropped decimal on
a sub-3% session beer gets through, which is the right way round to fail.

**2. `PricePlausibility` wired (completes 09-06 item 4).** Into `MenuPipeline.makeSession`, the
single path `analyze` delegates to, so both paths see identical data by construction.

**3. F — section headers firing on prose.** The largest remaining wrong-rank-1 class. Keyword
matching was a substring test, so any line *mentioning* a style became that style's header and reset
the category.

`MenuParser.isPlausibleHeader(_:keyword:)` gates the match. A header is a **label**, and a label
differs from a sentence in three ways that survive lowercasing (casing is deliberately not a signal
— real bars lowercase their menus):

- **no comma and no bullet** — both punctuate a list or a sentence; no real header in the corpus
  carries either;
- **no printed ABV** — a percentage is something an item states about itself (`Mighty Dry Cider
  (6%)` is a cider, not the Cider section);
- **at most `maxHeaderModifiers` (2) modifiers around the head noun** — `CRAFT BOTTLES`,
  `TALL BOY CANS`, `BIG BREWERY BOTTLES`, `house brews on tap` are labels with one or two
  qualifiers; `Rotating flavors of world class unfiltered ciders.` has five and is a sentence.
  Words of the matched keyword and of the section vocabulary are not modifiers, and neither are
  prices, sizes or filler, so priced headers keep working.

**Measured: 59 keyword matches → 43. 16 prose/item false positives dropped on 7 of 8 menus, zero
real headers lost.** Identical on lowercased copies of all eight (0 of 16 runs differ). Menu 4's
named bug is fixed: `sparkling water, honey` no longer resets the category, so OLD FASHIONED,
MANHATTAN, NERONI and SCOTCH HIGHBALL stay cocktails instead of ranking as 12% wine. Menu 7's
beach-house list stays `cocktail` instead of `frozenCocktail`.

Four residuals still fire, all now harmless: `sparkling peach pear` reaches one item instead of
four, and `3. Roget Sparkling Wine`, `Nutrl Vodka Seltzer 4.5ABV` and `liquot Sparkling` land on the
category they would have been given anyway.

### The second bench — `sections.py` / `verify_sections.py`

Same discipline as `faithful.py`, and it exists for the same reason: a threshold conclusion drawn
from an unfaithful port is noise.

Every dump records the **`MenuParser trace`** as well as the assembled lines, so the `SECT` lines in
that trace are ground truth for what the device decided. `verify_sections.py` replays each dump's
lines through the port and requires the firing set to match exactly.

```
python3 Tooling/verify_sections.py Tooling/Fixtures/console.txt             # must print 8/8 exact
python3 Tooling/verify_sections.py Tooling/Fixtures/console.txt --measure   # effect of the gate
python3 Tooling/verify_sections.py Tooling/Fixtures/console.txt --measure --lower
```

**If that does not say 8/8, nothing measured in Python means anything about the device.** It
reproduced all 59 device firings before any rule was measured. `Tooling/dumplines.py` extracts the
assembled-lines block; anything downstream of `LineAssembler` can use it directly, since `verify.py`
already proves those lines are what the device produced.

Also swept: all 582 string literals in `CoreServicesTests`. The only three lines whose header
classification changes are XCTest **assertion messages**, not menu lines.

### Known residuals

- **Killing a header match sends the line down the item path, and under a *priced* section that can
  create a bogus item.** `looksLikeDescription` is gated on `headerPrice == nil`, so on Rullo's
  `• Pineapple • Lime • Egg Whites` now becomes a bogus $14 cocktail instead of a bogus Wine header.
  Both are wrong; the new failure is **visible and removable** while the old one silently
  mis-categorized every drink below it, so this is the better direction. **But the item-count effect
  across the corpus was not measured** — that needs a `MenuParser` port, which does not exist. Do
  not assume it is neutral.
- Everything in the 09-06 residual list stands: `headerWidthFraction` dead code, `minColumnSpan`
  refusing single-word columns, Rullo's `Bramble` siblings fusing, menu 7's mocktails strip,
  `PABST BLUE RIBBON 1602.` deliberately uncaught, `Miller 64` / `dates back to 1806` needing the
  whole-menu quality gate.

### Honest limits of the evidence

The eight dumps are all from the **untested** menu set by construction. F's gate is measured on all
eight plus lowercased copies, which is better coverage than `PricePlausibility` got (it fires on
only 2 of 8) — but "no real header lost" is a statement about **43 headers on eight menus**, not
about menus nine and up. The modifier ceiling of 2 is the one number to distrust: real headers in
this corpus top out at exactly 2, so the margin above it is zero, and the first menu with a
three-word qualified header (`SMALL BATCH CRAFT BOTTLES`) will lose it. If that shows up, the fix is
a different mechanism, not a bigger number — the same lesson `minColumnSpan` already taught.

### Next, in order

1. **D — priced section headers.** `WHITES - $9 GLASS / $82 BOTTLE` should set a section price
   rather than become two items. The parser is already inconsistent here: Rullo's `Rosé | $10 / $35`
   inherits correctly because "rosé" is in `wineSubLabels` while `red`/`white`/`whites`/`reds` are
   not. Four words, two menus.
2. **C — whole-menu quality gate.** Menus 2 and 8 should rank *nothing*, like El Perrito. The 1948
   list produces a confident podium of "Gun", "SALTY DOG!", "Created at the Roosevelt" from
   confidences as low as 0.30; the Thirsty Duck menu prints no beer prices at all, so its only
   ranked items are OCR artifacts. Mean confidence + priced-line ratio + withdrawn-price count.
3. **Then stop and do RevenueCat.** R5 has already fired, and has now been deferred across three
   sessions.

### Housekeeping

`docs/Handoff.md` was still the menu-testing plan in the tree — the 09-06 note describes restoring
it, but that restore was never committed either. Restored from `65e957b`; the plan now lives at
`docs/MenuTestingPlan.md`, which is where `README.md` already pointed.

---

## STATUS (2026-09-05, part 7) — Build cleanup from the first compile of parts 5 and 6

Small fixes, all from real compiler output.

**Errors:**
- `(any BeverageKnowledge)? = nil` in `CompareViewModel` and `QuickCompareViewModel`. Written as
  `any BeverageKnowledge?`, which parses as "any of `Optional<BeverageKnowledge>`" rather than an
  optional existential; the parentheses are required.
- **`BundledStoreCatalog.shared` is now `nonisolated`.** This target builds with
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so the enum was main-actor-isolated, and a **default
  argument is evaluated in a nonisolated context** — which is exactly how all three view models use
  it. Safe to mark nonisolated: an immutable `let` of a `Sendable` value, read once. Worth
  remembering as a pattern, since anything else this target exposes as a default argument will hit
  the same wall.

**Warnings:** the two `onChange(of:perform:)` sites (`CaptureHomeView`, `ContentView`) moved to the
two-parameter closure, deprecated since iOS 17 against an 18.6 target.

**`AccentColor` added** (`Assets.xcassets/AccentColor.colorset`). `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`
pointed at a colour set that didn't exist, so every `Color.accentColor` in the app — the value
figures, the "tap to correct" hints, the size chips, the buttons — was rendering as stock system
blue. Now a bottle green, `#1D6F4C` light / `#45AD73` dark, chosen to read as glass and to stay
clear of the gold/silver/bronze rank medals rather than competing with them. Change the two colour
values if you want a different identity; nothing in code names a colour.

---

## STATUS (2026-09-05, part 6) — Menu scanner uses the big catalog too; metric sizes

**1. Both surfaces now draw on the same 16,730-product library.** New in CoreServices:
- `CatalogMatcher.specificMatch(for:in:)` — a **strict** menu-line-to-product rule, deliberately
  stricter than the store search. A match counts only when one name contains the other whole
  (either direction, so "Josh Cellars Cabernet" matches "Josh Cellars Cabernet Sauvignon"), the
  menu line has at least two words, and the shared words include at least one non-generic word.
  That last guard is the important one: "Cabernet Sauvignon", "House Red" and "Draft IPA" are made
  entirely of style and vessel words, so a catalog hit on them would add nothing the style chart
  already says while risking a wrong producer. Those keep falling through to the chart.
- `CatalogBackedKnowledge` — a `BeverageKnowledge` decorator with the tier order: curated brand
  table (hand-vetted, wins where it matches) → store catalog → style chart → category fallback.
  Reported as `.brandMatch(matched:)` so the existing honesty note explains itself.
- **The catalog's container size is never used for a menu.** A catalog row's 750 mL is a bottle on a
  shelf; a menu line means a pour. Size still comes from the category. There's a test for that.
- Wired via `MenuPipeline(knowledge:)`, which already took an injectable knowledge, so no signature
  changed. `ResultsViewModel`, `CompareViewModel` and `QuickCompareViewModel` all default to it, so
  the three screens can't be pointed at different libraries by accident. An empty catalog is a
  provable no-op (also a test), which is what makes this safe before the bundled file exists.
- `CatalogBackedKnowledgeTests` (11 cases), mostly negative: the false-precision cases are the ones
  worth pinning. Rule validated in Python against realistic menu lines before porting.
- Also fixed while in there: `ResultsViewModel` was constructing a second `MenuPipeline` in its
  init and throwing it away.

**2. Metric sizes where the trade uses metric.** `ValueFormat.volume(_:)` prints a bottle size in
mL/L and everything else in ounces: a wine bottle reads "750 mL", a handle "1.75 L", a split
"187 mL", while a 12 oz can, a 5 oz pour and a 1.5 oz shot stay in ounces, which is how a bar states
a pour. Detection is by **volume, not category**, because a bottle of wine is metric while a glass
of the same wine is a 5 oz pour and only the volume distinguishes them.

Two collisions found and fixed by giving a clean whole number of ounces priority: a 60 oz pitcher
was reading as "1.75 L" (1,774 mL is within tolerance of 1,750) and a 24 oz can as "700 mL". No real
metric bottle size lands on a whole ounce, so the two rules never fight. Verified across 18 real
sizes.

Applied to the size chips on all three screens, the package totals ("six 750 mL bottles" now reads
"4.5 L", not "152.2 oz"), and the **edit field itself**, which now switches to mL for a bottle size
and converts both ways, so nobody types 25.4 for a wine bottle.

**Priority reminder, now six features deep:** RevenueCat remains untouched and remains the only
thing that can disqualify the Shipaton entry.

---

## STATUS (2026-09-05, part 5) — Search performance on the real 16,730-product catalog

*The catalog shipped and typing was laggy. Two separate causes, both fixed.*

**1. Search allocated instead of computing.** `InMemoryStoreCatalog` lowercased and re-split every
product name *inside* the query loop: `Array(haystack)` per product per call, plus a fresh word
split for the word-prefix tier. Over 16,730 products that is roughly 50,000 array allocations per
typed character. It read as lag with a near-idle CPU gauge and 45 MB of memory, because the cost was
allocation churn, not arithmetic.

Rewritten to precompute everything at init: each product is stored as a **folded byte array**
(`[UInt8]`) with its **word-start offsets** already marked, so a query folds once and then every
tier check is index comparison with zero allocation. Same five tiers, same ordering, same public
API; `search` and `product(withUPC:)` are unchanged from the outside.

**2. Name folding, which also fixed real search misses.** The folded form is lowercase ASCII:
accents stripped, apostrophes and periods *deleted*, everything else a word break. That was needed
for correctness as much as speed:
- `moet` now finds "Moët & Chandon" (and so does `moët`).
- `titos` now finds "Tito's Handmade Vodka". Previously the apostrophe became a word break, folding
  the name to `tito s`, and the search returned nothing.
- `vsop` finds "St. Remy - V.S.O.P.", while "St. Remy" still folds to `st remy` because the space
  after the period supplies the break.
- `chateau margaux` finds "MARGAUX - CHATEAU MARGAUX 2014". This matters generally: BC names lead
  with the appellation, so the " - " separator has to fold to a plain space or every producer search
  fails.
Six new folding tests in `StoreCatalogSearchTests` (18 cases total), all verified in Python against
the real ranking before porting.

**3. The console noise.** "The variant selector cell index number could not be found" is a benign
CoreText message, but it fires because catalog names carry invisible characters. The importer now
has a `sanitize` step stripping variation selectors, zero-width spaces and joiners, directional
marks, the BOM, soft hyphens, and control characters, plus normalizing curly quotes and en/em dashes.
**Re-run the importer to clear it.**

**4. Compare now requires 2 characters** before searching, matching the quick comparison. One letter
over 17,000 products returns a list nobody reads.

**Catalog build results (for the record):** 16,730 products, 2.0 MB, ABV on 11,090 (66%). BC
contributed 8,250 rows with 8,236 percentages. The barcode join filled only 134, because PLCB and BC
stock different products and list different package barcodes where they overlap. The uncovered 34%
is mostly PLCB wine, which has no ABV or proof column and falls back to the varietal style chart.

**No project changes needed for the catalog:** the target uses an Xcode 16 synchronized group over
the whole `BangForBuck/` folder, so `AppTarget/Resources/store_catalog.json` is a member as soon as
it exists on disk. **Worth checking before submission:** that same synchronization means `photos/`
(~4 MB of test menus), `docs/`, and `Tooling/` are also in the target and may be shipping in the
bundle. Move them out of `BangForBuck/` or add target-membership exceptions.

---

## STATUS (2026-09-05, part 4) — Found a real ABV source; catalog importer rebuilt around it

**The wine-ABV problem is solved, and by a better source than expected.** British Columbia's Liquor
Distribution Branch publishes its **entire retail catalog** as open data, monthly CSV, and every row
carries an alcohol percentage. Schema verified against the live April 2026 resource:
`PRODUCT_LONG_NAME`, `PRODUCT_ALCOHOL_PERCENT`, `PRODUCT_LITRES_PER_CONTAINER`,
`PRD_CONTAINER_PER_SELL_UNIT` (the pack count), `PRODUCT_BASE_UPC_NO`, plus a three-level category
taxonomy. About 10,000 SKUs, thousands of them wine, with real percentages. Retail sites do not
publish wine ABV; a liquor board does, because it has to.

**The join that makes it useful for a PA shopper:** the PLCB wholesale catalogs say what is on a
Pennsylvania shelf (name, size, UPC, no ABV, no beer); BC says how strong it is (ABV, keyed by UPC).
`enrich_by_upc` matches them on barcode and reports how many percentages it filled. Open Food Facts
stays opt-in for beer, because it is ODbL and carries share-alike obligations that a
`--bcldb --plcb` build avoids.

- `Tooling/build_store_catalog.py` rewritten: `--bcldb` (with `--bcldb-url` / `--bcldb-file`),
  `--plcb`, `--off`, `--drop-without-abv`, `--dry-run`. Emits name, category, ABV, container mL,
  pack count, UPC. **Run end to end here against real BC rows**: 13/13 parsed, 12 with an ABV,
  categories mapped, pack counts read (36-can Coors case, 4-pack tall cans), barcodes zero-padded.
  Name prettifier handles SHOUTED catalog names, apostrophes ("Tito's" not "Tito'S"), and roman
  numerals ("Louis XIII" not "Louis Xiii").
- `docs/StoreCatalogSources.md` (new): every source, the verified BC schema as a table, the licence
  position on each, the rebuild commands, and why the store catalog is a separate artifact from the
  curated menu brand table.
- Cross-check on accuracy: BC lists High Noon at 4.5%, matching the label independently. Good sign
  for the dataset generally.

**Still not imported: price.** Local, weekly, store-specific. A bundled price would be the one
fabricated number in the app (§10).

**Dependency note (fixed after a failed first run):** the importer was written against `requests`,
which is not in the standard library and is not on a stock macOS Python. Both `build_store_catalog.py`
and `inspect_store_catalog.py` now use `urllib.request` with a browser User-Agent (some government
hosts 403 the default Python one), so **`--bcldb` runs with zero `pip install`**. Only `--plcb`
needs `pandas`/`openpyxl`, and it now says so with a clear message instead of a traceback. Also
worth knowing: `zsh` does not treat `#` as a comment interactively, so a trailing explanatory
comment on a pasted command arrives as an argument and argparse rejects it.

**Ran it (2026-09-05): 16,730 products, 2.0 MB, ABV on 66%.** BC contributed 8,250 rows with 8,236
percentages; PLCB added wine 6,293 / spirits 4,651 / RTDC 290. The barcode join filled only 134
missing ABVs, fewer than expected, because PLCB and BC stock different products and list different
package barcodes where they overlap. 2 MB needs no indexing and 16,730 rows is fine for the
in-memory ranked search. **Real PLCB headers turned out to be `Item Description`, `UPC`, `Proof`,
with no size column at all**, so the importer now derives spirits/RTDC ABV from proof ÷ 2 and parses
the container size (and pack count, from the "4/187ML" form) out of the description, stripping it
off the display name. PLCB wine has neither ABV nor proof, which is why its rows fall back to the
varietal style chart. Both fixes are in the attached importer; re-run to pick them up.

**What is left to do on this:** run the importer on the Mac (it needs a network, which this
environment lacks), check the resulting file size, and add it to the Xcode target's Resources. If it
is large enough to slow launch, index it rather than parsing it whole. Then the barcode scanner,
which now has both a seam (`StoreCatalog.product(withUPC:)`) and a barcode-bearing dataset.

**Priority reminder:** RevenueCat is still untouched and still the only thing that can disqualify
the Shipaton entry.

---

## STATUS (2026-09-05, part 3) — Quick comparison (third feature); shared row + edit sheet

*Supersedes nothing; adds a feature and de-duplicates the two comparison screens. Still uncompiled.*

**Quick comparison (`AppTarget/Features/Quick/`).** Holding a menu, weighing two or three things:
type each drink, take the price off the menu, see which is the better value. No photo, no shelf.
- Defaults to a **single serving**, which is the whole difference from the store calculator: a wine
  opens at a 5 oz pour rather than a 750 mL bottle, a whiskey at 1.5 oz rather than a handle. "How
  many you'd order" is there for a round without pretending that's the common case.
- **Autofill from the same catalog.** Typing shows up to six live suggestions; picking one fills in
  the label ABV and the pour. Typing something the catalog has never heard of *also* fills in, via
  the style chart, because most cocktails on a real menu are in no product database and the chart
  still has an opinion about a margarita. Either way the strength is flagged `.estimated` with a
  note, and overtyping it promotes it to `.read` (§11).
- **Sizes change with one tap:** `SizeChipPicker` is a scrolling strip of pour presets (1.5 oz shot,
  3 oz double, 5 oz wine pour, 12, 16, 20, 22, 24, 60 oz pitcher) writing into the same ounces field
  the text box edits, so the two controls can't disagree. Also on the edit sheet.
- **Soft cap of 5**, per the ask. Past that the add button disables and the footer points at the
  store calculator, which has no cap.

**It runs on the same pure `StoreSession` as the store calculator.** A priced volume of alcohol is a
priced volume of alcohol: `unitVolume × count × abv ÷ price` is identical whether the volume is a
12 oz can in a six pack or a 5 oz pour of wine. Sharing the session means the two screens can never
rank the same numbers differently, and the price invariant lives in exactly one place (§10). What
differs is defaults and wording, which is `QuickCompareViewModel` and the view.

**New in Core:**
- `CoreServices/PourDefaults.swift`: the single-serving twin of `PackageDefaults`. Reads a pour off
  the menu wording ("16 oz", "pitcher", "double", "shot", "pint", and `pitchor`, Vision's misread of
  pitcher, so a scanned line and a typed line agree), else takes `BeverageKnowledge.typicalSize` so
  it can't disagree with the menu scanner about what a wine pour is, else 12 oz. "Glass" and "bottle"
  are only trusted where the category settles the volume: a wine bottle is 25.4 oz, a beer bottle is
  12, and a "glass" of beer is ignored entirely.
- `ContainerSize.pourPresets` + `closest(toFluidOunces:among:)`, so serving sizes snap to serving
  labels and nobody is offered a 1.75 L handle as a single drink.
- `PourDefaultsTests` (14 cases).

**Shared UI, extracted rather than copied** (`AppTarget/Features/Shared/RankedValueRow.swift`):
`RankedValueRow` (rank, name, chips, provenance badge, detail line, value, price pill),
`ProductEditSheet` (size chips + exact size + count + ABV + price + remove, with caller-supplied
labels because "how many" means cans-in-the-pack in a store and rounds-at-the-bar on a menu), and
`SizeChipPicker`. `PriceText` and `ValueFormat.editable` moved into `Shared/ValueChips.swift`.
`CompareView` was refactored onto all of it and lost its private duplicates, so it is now ~160 lines
lighter and the two screens share one look by construction.

**Home screen** now offers four ways in: take a photo, choose from library, **Quick comparison**,
Compare store prices.

**Next, still unchanged:** RevenueCat is the critical path and remains untouched.

---

## STATUS (2026-09-05, part 2) — Search-first store calculator; the catalog import path

*Supersedes the part-1 note below re: the add flow, which was brand-picker-behind-a-button and is
now search-first. Everything else in part 1 still stands. `swift test` was green at 146/146 after the
part-1 fix; these additions are again uncompiled.*

**Search first (owner's call).** `AddProductFlow` opens on a focused search field over the whole
catalog; results rank live, and picking one pushes a form already filled in except the price. New in
Core so the logic is tested rather than living in a view:
- `CoreContracts/StoreCatalog.swift` (new): `CatalogProduct` (name, category, optional ABV, optional
  size, optional pack count, optional **UPC**) + the `StoreCatalog` protocol. Fifth contract (§6).
  The UPC field is unused today and exists so the barcode step is a data question, not a redesign.
- `CoreServices/InMemoryStoreCatalog.swift` (new): ranked search in five tiers (exact, name-prefix,
  word-prefix, substring, all-words-any-order), length tiebreak, precomputed lowercased names, and
  digits-only UPC lookup that reconciles a 12-digit UPC-A with the 14-digit GTIN form. Ranking, not
  filtering, because with a large catalog a substring filter buries the obvious answer.
- `CoreServices/PackageDefaults.swift` (new): the "if it knows it's wine, make it 750 mL" logic, in
  three tiers (catalog-stated → read off the name → category default). Wine and spirits open at
  750 mL × 1, beer at 12 oz × 6, seltzer at 12 oz × 12; names carrying "1.75 L", "16oz 12pk",
  "handle", "magnum", "tallboy", "30 rack", "14.9oz" are read exactly. Size matching is on
  unit-normalized **tokens**, not substrings, which is what stops "Josh Cellars **200**7 Cabernet"
  becoming a 200 mL bottle and "Hand**le**y Cellars" becoming a handle. Both are regression tests.
- `ContainerSize` gained `ml50`/`ml200`, `closest(toMilliliters:)` and `closest(toFluidOunces:)`, so
  an unlisted real size (14.9 oz Guinness, 11.2 oz Peroni, 5 L box) keeps its own label instead of
  snapping to the nearest preset. Snap tolerance is 1% by volume.
- Tests: `PackageDefaultsTests` (23 cases incl. the negative ones above), `StoreCatalogSearchTests`
  (16 cases incl. tier ordering and barcode normalization).

**Em-dashes removed from every user-facing string** in `ResultsView`, `ValueChips`, `CompareView`,
and `BeverageKnowledge.abvNote` (that one renders in the app, so it counted). The em-dash characters
still in `MenuParser` are menu text it matches *on* and must stay.

**The big catalog: sourced, with an import path, not yet imported.** Two public sources cover the
shelf between them, and neither can be fetched from this environment (no network), so the work here
is the pipeline plus honest reporting rather than a bundled dataset:
- **PLCB wholesale catalogs** (`pa.gov/agencies/lcb/.../item-catalogs`): full .xlsx catalogs for
  wine, spirits, and ready-to-drink cocktails, every SKU sold in PA, with a retail size and a
  **UPC** (their own instructions confirm the UPC column, with leading zeros stripped). No beer,
  because PA doesn't sell beer through these stores.
- **Open Food Facts**: nightly JSONL/Parquet dump, barcode-keyed, alcohol percentage on most beers
  and wines. Covers the beer gap. **ODbL licensed**, so attribution plus share-alike obligations on
  the database; `--plcb`-only is the clean-license build. Not legal advice.
- `Tooling/inspect_store_catalog.py` (new, §5): prints the real headers, fill rates, and sample rows
  before anything is parsed. **Run this first** and correct `COLUMN_CANDIDATES` if the fuzzy header
  matching guessed wrong; the PLCB has renamed columns before and I could not see the live file.
- `Tooling/build_store_catalog.py` (new): both sources → `AppTarget/Resources/store_catalog.json`,
  with ABV derived from proof when only proof is given, size parsed from the retail-size text,
  UPC zero-padded, dedupe by barcode preferring the richer record, and `--dry-run` to check the
  mapping without writing. Helpers unit-checked in Python here; the download paths were not run.
- **Price is deliberately not imported.** Shelf prices are local and weekly, and a stale bundled
  price would be the one dishonest number in the app (§10). Name, ABV, size, and UPC only.
- `AppTarget/Infrastructure/BundledStoreCatalog.swift` (new) loads that JSON if it's in the bundle
  and **falls back to the curated 655-brand list** otherwise, so the app works today and improves
  the moment the file is added to the target. A malformed file degrades to the fallback rather than
  crashing someone mid-aisle.

**Why the store catalog is bundled JSON and not codegen'd Swift:** `GeneratedBrandTable` is the
*menu* matcher, where a small curated list is a feature (a 30,000-SKU list would match menu text
like "Chardonnay" against one specific winery's bottling). Different job, different data, separate
artifact. Also, 30,000 `BrandEntry` literals would be wretched to compile.

**Next, unchanged in priority:** RevenueCat is still the critical path and still untouched. After
that: run the import, check `store_catalog.json` size on device (if it's large, consider a
prefix-indexed format or SQLite before shipping it), then the barcode scanner via
`StoreCatalog.product(withUPC:)`, which is already the seam it needs.

---

## STATUS (2026-09-05) — Store calculator (Goal 2) is built; **RevenueCat is now the critical path**

*Supersedes the 09-02 status note below re: next steps. The parser situation is unchanged — that note
is still accurate about OCR; ignore only its numbered next-step list, which items 3 and 4 have now
consumed.*

**Landed this session (Compare / store calculator, per owner's call):**
- `CoreServices/StoreSession.swift` (new, pure): `EditableProduct` (id, unit volume, count,
  `Provenance<Double>` ABV, optional `Price`) + `StoreSession` with `rankedProducts` /
  `needsPriceProducts` / add / setPrice / correctABV / setPackage / remove. Deliberately the same
  shape as `EditableDrink`/`MenuSession`, so both invariants read identically on the store side:
  a priceless package waits in its own bucket (§10), and a brand-seeded ABV is `.estimated` with a
  note until the shopper types the number off the can (§11).
- `StoreComparison` refactored to expose the shared `StoreValue` / `value(totalStandardDrinks:
  dollars:)` / `sortsBefore(...)` primitives; `rank` and `StoreSession.rankedProducts` both call
  them, so the one-shot and interactive paths can't drift. `ContainerSize` gained
  `Hashable`/`Identifiable` (so the app needs no retroactive conformance for its picker).
  **Behaviour is unchanged — the existing `StoreComparisonTests` should still pass verbatim.**
- `Tests/CoreServicesTests/StoreSessionTests.swift` (new, 12 cases): worked example (6× 12 oz at
  5% = 6.0 standard drinks → 0.60/$ → $1.67 per drink), the handle-beats-wine ordering, **parity
  with `StoreComparison.rank`**, name tiebreak, zero-alcohol → infinite $/drink, the two invariants,
  id stability across removal, stale-id no-ops.
- `AppTarget/Features/Shared/ValueChips.swift` (new): `SectionHeader`/`RankMedal`/`MetaChip`/
  `ProvenanceChip`/`PricePill` lifted out of `ResultsView` (they were `private`, so Compare couldn't
  reuse them) plus a `ValueFormat` namespace. `ProvenanceChip` now takes its labels, and `PricePill`
  its caption, so each screen names its own thing ("menu price" vs "pack price").
- `AppTarget/Features/Compare/` (new): `CompareViewModel` (thin `@MainActor` shell over
  `StoreSession`, same shape as `ResultsViewModel`) and `CompareView` — ranked shelf list reusing the
  Results row vocabulary, add-product form with a searchable **655-brand** picker off
  `BrandCatalog.all`, `ContainerSize.presets` + an "Other…" custom-ounces path, count stepper,
  per-row edit sheet, "Waiting on a price" bucket, and a store-flavoured calculation explainer.
  Entry point: a "Compare store prices" button on `CaptureHomeView` → `navigationDestination`.
- **Brand table regenerated** — `beverages.json` was already valid (the `2/.4` bug is fixed, 655
  brands) but `GeneratedBrandTable.swift` was still the stale **161-brand** build, so the picker and
  every brand-tier ABV lookup were missing ~494 products. Re-ran `Tooling/generate_brand_table.sh`.
  Checked first: all eight brand ABVs pinned by `BrandTableTests` resolve identically at 655.
  **One consequence, fixed:** `StaticBeverageKnowledgeTests.testSectionRefinesCategoryButChartKeepsABV`
  used "Community Mosaic IPA" as a stand-in for a *generic* IPA, but that beer is now a real entry in
  the 655-brand table at its true 7.5% — so the brand tier correctly beat the 6.5% IPA style chart
  and the test failed at 7.5 ≠ 6.5. The engine was right; the fixture was stale. Renamed to
  "Nonesuch Placeholder IPA" (verified absent from `beverages.json`) and the test now asserts
  `.styleChart` as the *tier*, so if a future JSON edit shadows it the failure says so instead of
  looking like a bad ABV. Watch for this whenever the dataset grows: two other fixtures
  ("Guinness Draught", "Weihenstephan") now resolve via the brand tier rather than the chart, but
  their ABVs agree (4.2 / 5.4) so those tests still pass on the same numbers.
- **`INFOPLIST_KEY_NSCameraUsageDescription` added** to both build configs. It was absent from
  `project.pbxproj` and there's no `Info.plist`, so "Take a photo" would have trapped on
  presentation — the camera path was never actually exercised on device.
- Cosmetic fix from the old list: the size chip now prints `1.5 oz` for a shot instead of rounding to
  `2 oz` (`ValueFormat.ounces`, one decimal only when the value isn't whole).

**⚠ Nothing here has been compiled** — it was written without a Swift toolchain. Run
`cd Core && swift test` and build `AppTarget` in Xcode first; the Core additions are pure and
inline-fixture tested, the SwiftUI is the part to eyeball. `Features/` is inside a
`fileSystemSynchronizedGroups` root group, so the two new folders need no `.xcodeproj` surgery.

**Suggested next steps (new session), in priority order:**
1. **RevenueCat — this is the schedule risk, not a feature.** Week 2 of the plan (Sep 8–14) is
   `remove_ads` IAP + entitlement gating + RevenueCat Ads + a Paywall screen, and *none* of it
   exists: no `Features/Paywall/`, no conformer for `PurchaseController`/`AdPresenter`. It's a
   Shipaton **qualification** requirement, the IAP has to be approved alongside the build, and the
   plan submits ~Sep 18–20. Everything else below is optional next to this.
2. Store-side polish if it survives device testing: the comparison doesn't persist across launches
   (no storage layer exists) — decide whether an aisle list should survive backgrounding.
3. `ImageDeskew` — **the file described in the 09-02 (part 6) note was never committed**; it isn't in
   `Infrastructure/`. It has to be written, not wired. Pair with the "retake straighter" capture hint.
4. Run 3–5 brand-new menus through the DEBUG OCR export; triage by failure class before coding.
5. Store screenshots + listing copy (informational price-comparison framing, R3).

---

## STATUS (2026-09-02) — OCR/parse pipeline is good enough; pivoting to breadth + other features

All five test menus now parse acceptably. M/G (the hard one) is confirmed on device: horizontal
banding done (part 7), superscript-cent prices + shared-grid inheritance (part 8), cocktail
back-fill + `$1s`/`gloss` fixes (part 9). IPAs rank ~0.26/0.21 std-drinks/$; beers keep prices;
cocktails back-fill from their own price lines. Owner's call: **stop tuning the parser on M/G** and
(a) test the pipeline on NEW menus to find the next real failure class, and (b) start building out
other app functionality.

**Known residuals (accepted, low value — don't chase without a new failing menu):**
- Fully OCR-shredded price tokens (`Sis"`, `Sir"`, `glass Sir"`) stay unpriced → "Not sure".
- The happy-hour beer mini-grid `16oz $5" | 220z 59*` isn't recognized (OCR typo'd `22oz`→`220z`,
  price `59*`), so those 3 happy-hour beers don't inherit.
- Occasional recipe line with 0 recipe-keywords (e.g. "tito's vodka ruby red grapefruit") lands in
  the "Not sure" bucket as a priceless item — harmless, never ranks.

**Suggested next steps (new session):**
1. Run 3–5 brand-new menus through the DEBUG OCR export; triage by failure class before coding.
2. Wire `ImageDeskew.flattened` into `VisionTextRecognizer` + a "retake straighter" capture hint
   (El Perrito angled-photo case — still PENDING from earlier).
3. Fix `Tooling/Data/beverages.json` `"abv": 2/.4` → `2.4` (blocks the brand-table generator).
4. Build the `AppTarget/Features/Compare/` store-calculator screen (StoreComparison is ready in Core).
5. Optional cosmetic: ResultsView size chip shows 1.5 oz (one decimal), not "2 oz", for shots.

Everything below is the detailed parser/assembler history; read newest-first as needed.

---

## 2026-09-02 (part 9) — Cocktail back-fill vs grid forward-inherit; $1s repair; gloss vessel

Second M/G device pass (post part 8): IPAs now rank correctly (~0.26, 0.21 std/$), but two bugs from
the part-8 grid change surfaced, both fixed in `MenuParser`:

**1. `Strawberry Fields $1` (price leaked forward).** The part-8 grid handler always set the section
`headerPrice` forward. That's right for DRAFTS (grid *leads* a list) but wrong for the Specialty
cocktails, which are laid out *name-then-price* (`Strawberry Fields` line, then `glass $14 | pitcher
$49`). Each cocktail's price line set a forward price that leaked onto the *next* cocktail's name.
Fix: the bare-grid branch now **back-fills** the smallest price onto the immediately-preceding
priceless, rankable name (`backfillIndex`) when one is waiting; it only forward-inherits when a
section header just started the block (DRAFTS, happy-hour). `backfillIndex` is cleared by any header
and by any priced emit, so a price never crosses a section or item boundary. Validated on the real
sequence: DRAFTS/happy-hour forward ($7/$9), every Specialty cocktail back-fills its own price
(Paloma $13, Full Bloom $15, Strawberry Fields $14, Espresso Martini $15).

**2. `gloss (pitcher) $13` ranked as a drink.** `gloss`/`pitchor` are Vision's misreads of
`glass`/`pitcher`; added them to `sizeWordTable` + `sizeOnlyWords` so the price line is a nameless
grid (→ back-fill) instead of a "gloss" item.

**Also:** `$1s"` (a superscript `5` read as `s`) now repairs to `$15` via `repairPriceDigits`
(`s→5`, `o→0`, applied only after the `$`); `barePriceGridSmallest` ignores stray `"`/`*`/`°` tokens
and requires a size cue or ≥2 prices; and a pure wine sub-label (`whites`/`reds`/`bubbles`) no longer
resets the shared `glass $14 | bottle $58` wine price (so those wines inherit ~$14 instead of falling
to "Not sure"). `Moët Impérial Brut` correctly stays $150 (ranks low, as it should).

New tests in `MenuParserConfidenceTests` (back-fill vs forward, `$1s` repair, `gloss` suppression).
Residual unchanged: OCR-shredded lines like `Sis"`/`Sir"` stay unpriced; the `16oz $5" | 220z 59*`
happy-hour beer grid isn't recognized (OCR typo'd size/price).

---

## 2026-09-02 (part 8) — Superscript-cent prices, bare grids, section-price inheritance (M/G)

Device re-dump of M/G after part 7 confirmed the banding fix (clean 138-line assembly; beers keep
prices, DRAFTS grid intact). Three follow-on parser bugs it exposed, all now fixed in `MenuParser`:

**1. Superscript-cent price garble.** M/G prints cents as tiny superscripts; Vision returns them as
junk (`$8°5`, `$10$5`, `$1055`, `$12"`, or bare `1025 1325 2825`). Old scanner took the *last* `$`/
number, so `$10$5` → $5 (with `$10` stranded in the name) and bare `2825` → $2825. New helpers
`leadingDigitString` / `normalizedDollars` / `dollarValue`: read the **first** `$`-anchored price,
tolerate a `$`→`S` misread and glued garble, and interpret a **4-digit** run as dollars-and-cents
(`1055`→$10.55, `1025`→$10.25, `2825`→$28.25). 1–3 digit runs stay face value so a real `$150`
champagne isn't halved (a 3-digit price is ambiguous; a mispriced pitcher just sinks harmlessly).
`parseItem` also gained a bare-4-digit path (`firstBarePriceToken`) so Guinness `…1025 1325 2825` →
$10.25 with name `Guinness Stout`. `classifyToken` now uses `dollarValue`.

**2. Known name freed.** Fixing `$10$5` also strips `$10` from the name, so `High Noon Pineapple`
resolves to the brand cleanly (was `High Noon Pineapple $10`).

**3. Shared size/price grid → section price.** DRAFTS lists each beer with no per-item price; the
`16oz $7 | 22oz $12 | Pitcher $25` grid prices them all. `barePriceGridSmallest` detects a nameless
size/price-only line and adopts its **smallest** (single-serving) price as the section `headerPrice`,
which the listed drafts inherit (Blue Moon, Stella, Michelob Ultra, etc. now rank instead of →"Not
sure"); the grid line itself is dropped. Guard: `isRankableName` now rejects a name made only of
section words, and `sectionWords` gained `bubbles`/`rosé`/`rose`/`rosados`, so a bare `whites`/`reds`
sub-label under an inherited wine price does **not** rank as a phantom $14 drink.

All paths validated in Python against the exact device lines and against regression lines (Southside
`BUDWEISER ABV 5% - 5.50`→$5.50, `Dogfish Head 60 MIN IPA … - 7.50`→$7.50 with `60` kept in name,
`House Cabernet glass $9 bottle $32`→2-size split). New tests in `MenuParserConfidenceTests`.
Residual (left, low value): the happy-hour mini-grid `16oz $5" | 220z 59*` isn't recognized (OCR
typo `220z`/`59*`), and OCR-shredded cocktail-price lines like `Sir"`/`Sis"` stay unpriced.

---

## 2026-09-01 (part 7) — Horizontal section banding (X-Y cut completed) for dense menus

**Problem.** Dense multi-section menus (the "M/G" case) stack different layouts in one vertical
strip — a `name │ size │ price` bottle grid above a specialty-cocktail list above a wine list, with a
shared-price draft grid on the right. The vertical-only cut sliced the bottle prices into a separate
pseudo-column (beers → priceless → "Not sure") and tore the draft price-grid apart.

**Fix (`LineAssembler`).** The recursive cut now alternates axes: `layoutBlocks` peels a **horizontal
section band** first (top-then-bottom) whenever a strong section-sized vertical gap exists, then falls
to the existing **vertical gutter** cut within each band. Isolating a section before column detection
means the confusing wide content from *other* sections is gone, so within the bottle band no vertical
cut fires (narrow price column fails the span guard) and each beer keeps `name size price` on one
line; the draft grid stays whole. New: `bestHorizontalSplit` + constants `minSectionGap` 0.03,
`sectionGapMultiple` 2.2 (gap must clear both the absolute floor AND 2.2× the region's median row
gap), `minBandRows` 2. `columnGroups` (vertical-only) is retained but no longer the entry point.

**Why it won't regress the working menus.** The horizontal cut only fires on a gap clearly larger
than a section's own line spacing, so a uniform single-section column (max gap ≈ median gap, ratio ~1)
never bands, and a lone-title top band fails the min-observation guard. Validated in Python
(`xycut.py`/`xycut2.py`) against a faithful full-structure M/G transcription (`mg_full.txt`, 192 obs):
M/G now segments correctly — every BOTTLES beer keeps its price, the DRAFTS grid + all draft names
survive (`Pacifico Clara`, `Guinness Stout...1025 1325 2825`), cocktails keep glass/pitcher price
lines, and Wine/Happy-hour/Food band cleanly. All 7 existing `LineAssemblerColumnTests` fixtures and
the Southside/Reservoir/Exclusive real-menu outputs are **unchanged**. New regression test:
`LineAssemblerRealMenuTests.testDenseMultiSectionMenuKeepsPricesWithSectionBanding` (real M/G coords;
asserts beers keep prices, draft grid intact, and no orphaned bare-price line).

**⚠ MUST device-verify.** This is the one change validated partly on hand-transcribed data (the M/G
full transcription is faithful but compressed; the Reservoir/Southside/Exclusive checks used earlier
*subsets*, whose omitted rows create phantom vertical gaps that don't perfectly mirror a full device
dump). Before trusting: re-run the DEBUG OCR export on **all five** menus on device and confirm none
of the four working menus regressed. If any do, this is a single self-contained commit — revert
`layoutBlocks`→`columnGroups` in `lines(from:)` to fall straight back to vertical-only.

---

## 2026-09-01 (part 6) — Food/URL dropped; cocktail math audited

**Food dropped entirely (`MenuParser`).** A food-section header ("FOOD", "KITCHEN", "Small Plates",
"Shareables" — `isFoodSectionHeader`, size adjectives allowed as filler) starts a drop region that any
drink-section header ends; plus a drink-SAFE dish gazetteer (`looksLikeFood`, exact-token match:
fries/cheeseburger/quesadilla/nachos/wings/tenders/parmesan/chicken/bites/…) drops stray dishes even
with no header. `taco`/`beer`/`tea`/`cheese` are deliberately excluded so the real beer *Off Color
"Beer for Tacos"* survives. Food is dropped outright (not shown for review). Fixes M/G ranking "Fries"
as a 12% ABV $8 drink.

**URLs/emails dropped (`looksLikeURL`).** Lines containing www./.com/.net/.org/:// are dropped — fixes
El Perrito ranking "WWW.ELFERRITOATX.COM" as a 40% shot.

Both are new drop paths at the top of `parse`, before item emission. Validated in Python against every
dump: all food lines + the URL drop, all 22 sampled real drinks (incl. Off Color Beer for Tacos, Sun
Cruiser Iced Tea, Twisted Tea) are kept. Tests added to `MenuParserConfidenceTests`.

**Cocktail-math audit (no code change — it's correct).** `standardDrinks = size × abv/100 ÷ 0.6`
(NIAAA 0.6 fl oz ethanol per standard drink). Cocktail estimate = 5 oz × 12% = **1.00** standard
drink, identical to a single 1.5 oz shot of 40% spirit (0.6 oz ethanol); shot estimate = 1.5 oz × 40%
= **1.00**; martini = 3.5 oz × 25% = 1.46. So "assume one shot" holds and value math is sound.
COSMETIC ONLY: the size *chip* in `ResultsView` rounds a 1.5 oz shot to "2 oz" (display formatting);
the calculation correctly uses 1.5. Consider formatting sub-2 oz sizes with one decimal.

*On-device re-scan: Reservoir, Southside, Exclusive all rank correctly now. Remaining problems were
the dense promo-heavy **M/G** menu (recipe/promo/header lines ranking) and the angled **El Perrito**
(bad OCR). Both addressed generalizably — validated the classifier across all 5 real dumps, not just
M/G, so it can't regress the working three.*

**Rank-eligibility gate (`MenuParser`), generalizable + casing-independent.** Two additions:
1. **Pure section labels are headers even when priced.** `sectionHeader` no longer bails just because
   a line has a price; `isPureSectionLabel` treats a line whose only substantive tokens are section
   words (+ a price / "each") as a header. Fixes "SHOTS 4" ranking as a $4 drink.
2. **`isRankableName` — decided by structure, NOT capitalization.** An early version gated on
   Title-Case, which would have broken on any bar that lowercases its menu (a real, common style).
   Reworked to a casing-independent predicate: a priced line ranks unless it is a *fragment* (no real
   word, or only vessel words like "glass"/"pitcher"), an *imperative/promo* line (lead word in
   `promoLeadWords`: make/add/ask/get/for/with/any/…), or a *recipe* (≥2 words in `recipeWords`:
   juice/syrup/fresh/squeezed/puree/…). A failing line keeps no price → visible "Not sure" bucket,
   never deleted. New sets: `sizeOnlyWords`, `recipeWords` (+ existing `promoLeadWords`).
Validated in Python against every dump's assembled lines **and lowercased copies of them**: output is
identical capitalized vs lowercased (Southside's beers rank either way), all promo/recipe/section junk
drops, and the working three don't regress. Because ranking needs a price and priceless lines already
route to review, the gate only had to catch *priced* junk. Tests: `MenuParserConfidenceTests`
(incl. `testLowercaseStyledMenuStillRanks`). El Perrito still ranks nothing (unreadable, all priceless
→ review) — correct.

**On identity / ML (design decision, keep it simple).** Evaluated using the 655-brand
`beverages.json` gazetteer + `StaticBeverageKnowledge` styles (all matched case-insensitively) and, as
an option, Apple's on-device `NLEmbedding`. Finding: the gazetteer + structural signals already handle
identity case-independently, so **embeddings were not adopted** — they'd add a framework dependency and
nondeterminism to help only novel un-listed cocktail names, which already degrade to a flagged
"estimated" rank (acceptable per product intent: guesses are fine when the menu is hard). If future
real menus show a systematic gap on un-gazetteered craft names, revisit with an on-device Core ML
line-classifier trained on labeled OCR exports — not an LLM (offline is a hard requirement). No change
to min iOS (NL/CoreML/`NLEmbedding` all back-compatible; nothing new was added).
DATA BUG found in `Tooling/Data/beverages.json`: `"abv": 2/.4` (Budweiser Select 55) is invalid JSON —
should be `2.4`; the brand-table generator will choke until it's fixed.

**Angled photos — perspective de-skew.** New shell file `Infrastructure/ImageDeskew.swift`
(compile-on-device; uses Vision + Core Image, untestable in sandbox): `VNDetectDocumentSegmentation`
finds the menu quad, `CIPerspectiveCorrection` flattens it, run BEFORE `recognizeObservations`. This
"twists" a tilted menu back to rectangular and recovers perspective-distorted text; it does not fix
genuine blur/low-res from a bad shot, so pair it with a "hold straight / retake" capture hint. Wire it
in `VisionTextRecognizer` by mapping the input image through `ImageDeskew.flattened(_:)` first.

---

## 2026-08-30 (part 4) — Real OCR dumps: word-level confirmed, gutter detector rebuilt

*Exported real word-level `[TextObservation]` from all 5 menus on device (via the DEBUG console dump
added to `VisionTextRecognizer`). This supersedes part 3's "word-level is the fix" as incomplete: it
fixed Southside but not the Reservoir. Every change below is validated in Python against the **real**
coordinates and ported.*

**Confirmed from the dumps:**
- **Word-level extraction works** — Vision returns clean per-word boxes (not degenerate whole-line),
  so the gutter geometry is real.
- **Southside**: assembles into ~47 clean columned lines. Fixed. ✓
- **Reservoir**: was still fusing DOMESTIC+IMPORT. Root cause: its gutter is crossed by a centered
  `BEER` title, a `bottles & cans` subtitle, and a full-width `MISC` section, so the coverage
  histogram never sees an empty channel. ✗ → now fixed (below).
- **El Perrito**: columns actually split fine; failure is pure OCR quality from the **angled** photo
  (`Sauza…fresh` → `chu8…tresh`). Not a code bug — needs a straight-on shot.
- **Exclusive**: single column correct, but `$` prices were OCR'd as letters (`......S13`,
  `BEER.....S-`); partially recovered (below), but fancy-font price glyphs remain unreliable.

**New gutter detector (`LineAssembler`), the core fix.** `bestVerticalSplit` now has two tiers:
1. **Coverage corridors / central** (primary, unchanged): a clean empty-corridor cut (any number of
   columns) or a central-gutter fallback. This correctly prefers the true inter-column gutter over a
   within-column name/price gap — the widest *passing* empty corridor is the one between columns —
   so it keeps the word-level two-column and N-column synthetics intact.
2. **Per-row gap voting** (fallback): used only when coverage finds nothing — i.e. when the gutter is
   bridged by centered text (Reservoir's `BEER` title, `bottles & cans` subtitle, full-width `MISC`
   section) so there's no empty corridor. Each visual row votes at the midpoint of every blank gap ≥
   `minGutterGap` (0.045) between adjacent words; votes are clustered and ranked, first passing the
   column guards wins. Centered/full-width rows are contiguous → cast no vote → can't hide the gutter.
   New helpers: `rankedGutters`, `rows(of:)`.
(Order matters: an earlier pass ran per-row-gap first and mis-split the word-level test by picking a
within-column name/price gap that was wider than the true gutter; coverage-first fixes that.)
Validated in Python against real Reservoir → 2 cols (DOMESTIC|IMPORT split), real Southside → 2 cols,
real Exclusive → 1 col, the word-level two-column test (lines intact), and synthetic 1/2/3/4-col,
title-spanning, and single-col-with-right-prices. Residual: a full-width section crossing the gutter
(Reservoir's MISC) gets its centered rows chopped at the split — acceptable (those items are mostly
N/A → excluded).

**Also:** `pureNumber` now tolerates `$`→`S` misreads (`S13` → 13) for trailing price tokens.

**Tests:** `LineAssemblerRealMenuTests` gains `testReservoirRealOCRSeparatesDomesticFromImport` (real
coords). Regenerate/verify with `cd Core && swift test`.

**Still open / next:** angled-photo OCR (El Perrito) — guidance is shoot straight-on; consider a
"retake straighter" hint when confidence is low. Fancy-font price glyphs (Exclusive) — hard. The
`Features/Compare` store-calculator UI and the token-noise/confidence pass remain queued.

---

## 2026-08-30 (part 3) — Real-menu testing: root-caused the multi-column failure

*Tested the build against 5 real menu photos. Only Southside "worked" — and even it was silently
broken (see below). This entry supersedes the R1 status in part 1.*

**The big finding: Vision merges columns before Core sees them.** On a two-column menu Apple Vision
reads straight across the gutter and returns each *physical row* as one line observation — so a
left-column draft and a right-column bottle arrive fused ("COORS LIGHT … 5 BUDWEISER ABV 5%"). No
amount of `LineAssembler` column logic can split a box that already contains both columns' text. This
is why every multi-column menu produced chimera rows (Southside's ranked list looked plausible but
every entry was two drinks mashed together; the Reservoir fused DOMESTIC with IMPORT).

**Fix — word-level bounding boxes (`VisionTextRecognizer`).** Instead of one observation per Vision
line, we now emit one per **word** via `candidate.boundingBox(for: range)`, with a whole-line
fallback if per-word geometry is unavailable. This restores the true x-positions, the inter-column
gutter reappears, and the existing X-Y cut separates the columns; `LineAssembler` rejoins words on a
row by vertical position. Shell code — **compile/behavior only verifiable on device.** Pure-side
proof: `LineAssemblerColumnTests.testWordLevelBoxesKeepTwoColumnsApart` feeds word-level boxes for a
Southside-like layout and asserts no cross-column fusion. NOTE residual risk: right-aligned prices
create a coverage-0 "canyon" between names and prices within a column that can rival a narrow
inter-column gutter; the widest+central heuristic handled every test case but watch real dumps.

**Parser fixes (pure, tested — `MenuParserSectionTests`):**
- **Dotted section totals** ("COCKTAILS........$13"): `sectionHeader` now treats a dot-leader run
  (2+ '.') like a pipe, so the price becomes the section header price and the drinks under it inherit
  it (fixes Exclusive Drink Menu, where WINES had become a $50 item and the cocktails fell to
  needsPrice). `hasDotLeaderRun` added.
- **Singular headers**: added DOMESTIC/IMPORT/CIDER/SELTZER to the lexicon (the Reservoir). Safe
  because the price guard still rejects priced item lines as headers.
- **`/` separator**: `replaceSeparators` now maps `/`→space, so "Miller High Life 16oz / 6" prices
  and cleans correctly.
- **N/A exclusion**: `looksNonAlcoholic` flags "N/A", "non-alcoholic", "zero proof" (NOT bare "zero" —
  "Mike's Zero Sugar" is alcoholic) on the raw line and tags the item `.nonAlcoholic`; `DrinkResolver`
  now hard-excludes any `.nonAlcoholic` item up front, before brand/style matching can re-rank it
  (fixes "Gruvi IPA N/A beer" ranking as a 6.5% IPA).

**Still limited:** angled/rotated photos (El Perrito) — Vision's axis-aligned word boxes get a
sloped baseline, so rows mis-group and OCR text degrades ("Sauza blanco, Cointreau, fresh" →
"chu8 blanco Cointreau tresh"). Guidance: shoot straight-on. The dense M/G menu is still hard.

**Next:** rebuild, re-scan the 5 menus. The DEBUG long-press OCR export now dumps **word-level**
observations — send those for any menu still failing and they become fixtures directly.

---

## 2026-08-30 — N-column OCR + multi-price rows; store-calculator pure core landed

*Supersedes the 08-27 note re: R1 column bound and re: the calculator being unstarted. Everything
here is pure `Core` code with `swift test` coverage; two shell pieces are deliberately deferred
(below).*

**Robustness (Goal 1, R1):**
- **`LineAssembler` now does a recursive X-Y cut** (was 1-or-2 column only). Handles 1/2/3/4-column
  and free-form layouts; splits at truly-empty corridors, suppressing spanning **headers/titles**
  from gutter detection (a full-width title no longer bisects the middle column), with a central
  fallback for a 2-column gutter bridged by a modest title. Guards (per-side count ≥ 3, span ≥ 0.18)
  still guarantee it never over-splits a single column at a name/price gap. Validated in Python
  against 7 layouts before porting; new tests: `testThreeColumnSplit`, `testFourColumnSplit`,
  `testSingleWideColumnNotSplit`, `testThreeColumnsUnderFullWidthTitle`. Added `TextBox.width`.
- **Multi-price rows → one ranked drink per size** (Decision, supersedes INSPECTION_FINDINGS §5's
  "smallest pour"). `MenuParser.splitMultiPrice` turns "Cabernet glass $9 bottle $32" into two items
  and "Bud Light 12oz $4 16oz $6 22oz $8" into three, each with its own price + size, ranked
  separately. Binds a size label before **or** after its price; two-price wine with no cue → smaller
  glass / larger bottle. Fires only on ≥2 `$`-prices, else the single-price path is untouched. Each
  emitted item carries a real `Price`, so the price invariant holds. Tests:
  `MenuParserMultiPriceTests`.

**Store calculator (Goal 2) — pure core done, UI deferred.** Per the design decision it's a
**separate** type sharing only the value formula:
- `ValueRanker.standardDrinks(sizeFloz:abvPercent:)` is now the one shared ethanol→standard-drinks
  primitive (the `PricedDrink` path delegates to it).
- `StoreComparison.swift` (new, CoreServices): `StoreProduct` (unitVolume × count, abv, packagePrice
  as a failable `Price`), `StoreComparison.rank` → `[RankedProduct]` sorted by standard-drinks-per-
  dollar, also surfacing **$/standard drink**; zero-alcohol sorts last without div-by-zero.
  `ContainerSize.presets` (12/16/19.2/24/25 oz, 187/375/500/750 mL, 1/1.5/1.75 L) for the picker.
- `BrandCatalog.all` (new, CoreContracts): public `[KnownBeverage]` (label/category/abv, alphabetical,
  de-duped) projecting the internal `generatedBrandTable` for the brand dropdown.
- `Volume` gained a pure `liters` bridge. Tests: `StoreComparisonTests`, `BrandCatalogTests`.

**Deferred to next session (shell-only, not sandbox-testable — need device + visual iteration):**
1. **`AppTarget/Features/Compare/`** SwiftUI screen: add-product form (brand dropdown from
   `BrandCatalog.all`, size from `ContainerSize.presets`, count/abv/price fields) → `StoreComparison`
   ranked list reusing `ResultsView`'s `RankRow`/chips; entry point button/tab on `RootView`.
2. **Token/OCR-noise + per-line confidence** pass (price ranges, O↔0, more size spellings, header
   lexicon, low-confidence → "Not sure" bucket) — now unblocked by the export affordance below; do it
   fixture-by-fixture against real dumps.

**OCR-export debug affordance — DONE (this session, part 2).** `ObservationFixture` (new, CoreServices,
pure + tested) serializes `[TextObservation]` into a paste-ready Swift literal for a `LineAssembler`
test plus a readable dump (positions + current assembled lines). Shell: `VisionTextRecognizer` now
exposes `recognizeObservations(in:)`; `CaptureHomeView` keeps the last scanned image and, in **DEBUG
only**, a 0.8s **long-press on the menucard logo** re-runs Vision and opens `OCRDebugExportSheet`
(share/copy). Release builds don't include the trigger.

**Workflow for the ~5 sample-menu photos (how to turn them into regression tests):**
1. In a DEBUG build, scan/pick a photo, then long-press the logo → Share/Copy the export.
2. Paste the `let observations: [TextObservation] = [...]` block into a new test in
   `LineAssemblerColumnTests.swift` (or a per-menu file); assert `LineAssembler.lines(from:)` groups
   the rows/columns correctly — this is what locks in the X-Y-cut behavior against real geometry.
3. The dump's "LineAssembler.lines output" section shows the current result, so a bad split is
   visible immediately and tells you whether it's a column bug (fix `LineAssembler`) or a parse/size
   bug (fix `MenuParser`). Feed recurring OCR noise into the deferred token-noise pass (#2 above).

**Verify:** `cd Core && swift test` (all new tests are pure/inline-fixture). Files touched:
`CoreModel/TextBox.swift`, `CoreModel/Volume.swift`, `CoreServices/LineAssembler.swift`,
`CoreServices/MenuParser.swift`, `CoreServices/ValueRanker.swift`, `CoreServices/StoreComparison.swift`
(new), `CoreContracts/BrandCatalog.swift` (new), + 4 test files.

---

## 2026-08-27 — Capture flow live on device; results editable; OCR hardened

*Supersedes the notes below re: current state and next step.*

**State:** the app runs end-to-end on device. Point the camera (or pick from the library) → Apple
**Vision** OCR (`VisionTextRecognizer` behind `TextRecognizer`) → `LineAssembler` reassembles rows
(and now **columns**) → `MenuParser` → `MenuSession` → a ranked, **editable** list behind a 21+ gate.
Estimates are one-tap correctable, prices are editable, priceless/low-confidence lines sit in a **"Not
sure about these"** bucket, and the user can **add a drink the scan missed** or **remove** a misread
one. Results now show the menu price alongside a clearly-labelled per-standard-drink cost, with a
formulas explainer.

**Verify (engine):** `cd Core && swift test` — now also covers `LineAssembler` column detection,
`MenuParser` name-cleanup + `drafts`/`cans` headers, the editable `MenuSession`, and manual add/remove.
**Run (app):** build `AppTarget` in Xcode against the local `Core` package; needs
`NSCameraUsageDescription` in `Info.plist`. iOS 16 target.

**R1 status:** OCR is materially better — two-column layouts split correctly and item names are clean.
Still bounded v1: genuine 3+ column or free-form layouts fall back to fewer columns, and the manual
add/edit path remains the safety net. Tunable knob if rows merge/over-split on a specific photo:
`LineAssembler.lines(rowToleranceFraction:)` (default 0.5).

**Next — monetization (Week 2):** RevenueCat `remove_ads` IAP + RevenueCat Ads, implemented in
`AppTarget/Infrastructure/` behind the existing `PurchaseController` / `AdPresenter` contracts — no
`CoreServices` change. Owner-only setup first: App Store Connect record, RevenueCat project +
`remove_ads` product, ad-network alcohol-policy check (R3). Then the App Store listing (informational
price-comparison framing, 21+ gate already in place) and submission with a resubmit buffer (R5).

**Icon:** iOS uses a 1024×1024 PNG in `Assets.xcassets/AppIcon` (single-size), not `.ico` — flatten
any alpha before shipping (App Store rejects alpha).

---

## 2026-08-25 — Phase 5 + demo app landed (end-to-end)

*Supersedes the notes below re: current state and next step.*

**State:** the pure value engine is complete — `MenuParser` → `ABVEstimator`/`SizeEstimator` →
`ValueRanker`, assembled by `MenuPipeline` (`[String] → MenuAnalysis`). A minimal SwiftUI **demo
app** in `AppTarget/` runs that pipeline on bundled sample menus and shows the ranking, provenance
notes, and the needsPrice / excluded-non-alcoholic buckets — runnable on device via
`AppTarget/HOW_TO_RUN.md` (no camera yet).

**Verify (engine):** `cd Core && swift test`. **Run (app):** follow `AppTarget/HOW_TO_RUN.md`.

**Parser is bounded v1 (R1).** It handles the common menu shapes (see `MenuParserTests`), not every
layout; the manual add/edit path is the intended safety net for misreads.

**Next — the real capture flow (Week 1):** `VisionTextRecognizer` implementing `TextRecognizer`
(`VNRecognizeTextRequest`, on-device), a camera/photo picker, the **21+ gate** (R3), and inline
correction that promotes an estimate to `.read` and re-ranks. The engine doesn't change — only the
source of the OCR lines. Then monetization (Week 2): RevenueCat `remove_ads` + RevenueCat Ads behind
the existing `PurchaseController`/`AdPresenter` contracts.

---

## 2026-08-25 — Phase 4 landed (ValueRanker)

*Supersedes the notes below re: current state and next step.*

**State:** `ValueRanker` (CoreServices) computes standard-drinks-per-dollar (v1) and
calories-per-dollar (v2) and sorts best-first, taking `[PricedDrink]`. The doc's worked example is a
test. The whole value engine is now provable headless: brand/style/fallback knowledge → priced,
alcoholic drinks → ranking.

**Verify:** `cd Core && swift test`.

**Next (Phase 5 — parser + estimators):** the section-state `MenuParser` (Change A: header-priced
sections), `ABVEstimator`/`SizeEstimator` wiring `StaticBeverageKnowledge` (read-if-printed, else
estimate), the `needsPrice` split, and the description-line suppression (Finding 4). Designed against
`Tooling/Fixtures/` + a Vision-noise pass (real OCR is messy, per your note). This is the last pure
phase; after it the value engine is end-to-end from OCR lines to a ranked list, still with no UI.

---

## 2026-08-25 — Brand table added (data-driven, 161 brands)

*Supersedes nothing structural; extends Phase 3.*

Brand data now lives in `Tooling/Data/beverages.json` (script-readable) and is codegen'd to
`GeneratedBrandTable.swift` by `Tooling/generate_brand_table.sh`. Lookup order is now **brand →
style → category fallback**, each flagged via `EstimateSource` (`.brandMatch` / `.styleChart` /
`.categoryFallback` / `.unclassifiedFallback`). To change the data: edit the JSON, run the generator,
`swift test`.

---

## 2026-08-25 — Phase 3 landed (CoreContracts + sourced knowledge)

*Supersedes the notes below re: current state and next step.*

**State:** four protocols in `CoreContracts` (Foundation-free), the sourced `StaticBeverageKnowledge`
(style chart → category fallback, flagged by `EstimateSource`), and test doubles. New `CoreContractsTests`
target. Data provenance is documented in `docs/BeverageDataSources.md`.

**Design note (per your ask):** ABV/size are sourced (NIAAA + BJCP/Wine Folly), and the app is honest
about confidence — `.styleChart(matched:)` when a style/varietal matched, `.categoryFallback` when it
didn't. The menu's printed value still wins over both.

**Verify:** `cd Core && swift test` — now includes `CoreContractsTests`.

**Next (Phase 4 — ValueRanker):** the standard-drinks-per-dollar metric + sort, taking `[PricedDrink]`,
with the worked-example test and the price-invariant test (§8). No photos needed.

**Then Phase 5 (parser + estimators):** wires `StaticBeverageKnowledge` into `ABVEstimator`/`SizeEstimator`
and adds the section-state `MenuParser` (Change A), designed against the fixtures + a Vision-noise pass.

---

## 2026-08-25 — Phase 2 landed (CoreModel spine)

*Supersedes the notes below re: current state and next step.*

**State:** the spine is built in `Core/Sources/CoreModel` — `Provenance<T>`, `Price`, `Volume`,
`BeverageCategory`, `MenuItem`, `DrinkOption`, `PricedDrink`, `RankedDrink`, `ValueMetric` — with
`CoreModelTests` mirroring it 1:1. Two invariants are now enforced by type:
- **Price (§10):** non-positive/absent amounts can't make a `Price`; `DrinkOption.price` is
  non-optional, so a priceless line can't become a rankable drink.
- **Change B:** `PricedDrink.init?` rejects `.nonAlcoholic` — a priced mocktail can't be ranked.

The value *formulas* are deliberately NOT in the model — they land in `ValueRanker` (Phase 4).

**Verify:** `cd Core && swift test` on your Mac (I can't run Swift in my environment).

**Next (Phase 3 — CoreContracts):** the four protocols (`TextRecognizer`, `BeverageKnowledge`,
`PurchaseController`, `AdPresenter`) + a pure `StaticBeverageKnowledge` seeded from
INSPECTION_FINDINGS §Finding 3, and a `FakeTextRecognizer` test double.

**Still waiting:** nothing blocking Phases 3–4. Phase 5 (parser) will use the fixtures + a
Vision-noise pass (per your note that real input is on-device OCR, not clean transcription).

---

## 2026-08-25 — §5 inspection done; two design changes folded in

*Supersedes the Phase-1 note below only re: the Phase 2/5 plan (adds Changes A & B).*

16 real menus transcribed to `Tooling/Fixtures/` (`INSPECTION_FINDINGS.md` has the full
write-up). R1's main input is now real, not remembered. Two changes to carry forward:

- **Change A (Phase 5):** `MenuParser` is a **section-state machine**, not a per-line map —
  some menus price only on the section header (Rullo's `Elixirs | $14`). Still pure/testable.
- **Change B (Phase 2):** add `.nonAlcoholic` to `BeverageCategory`; those items are dropped
  before ranking (they have a price, so the price invariant won't catch them). Everything
  else in the spine is unchanged.

Also confirmed printed ABV/size is common (beer/wine), so the `.read` path is well-used.
**Next unchanged:** Phase 2 (CoreModel) — now including the `.nonAlcoholic` case.

---

## 2026-08-25 — Phase 1 landed (scaffolding + doc set)

*Supersedes nothing (first note).*

**State:** repo skeleton is up, laid out by layer/role (§3). `Core` SPM package compiles and
`swift test` is green on placeholder sources. Full §2 doc set exists. `.gitignore` and the
`run_checks` gate are in place. The two authored design docs (`Architecture.md`,
`ProjectConventions.md`) are placed verbatim in `docs/`.

**Environment note:** the value engine is being generated as source to build on a Mac (and
`swift test` runs on plain Linux since `Core` is framework-free). No Xcode/iOS SDK was used
to produce it.

**Next (Phase 2 — CoreModel):** implement the spine — `Provenance<T>`, `Volume`,
`BeverageCategory`, `MenuItem`, `DrinkOption`, `PricedDrink`, `RankedDrink`, `ValueMetric`
— with `CoreModelTests`. Then Phase 3 (contracts), Phase 4 (ValueRanker + metric).

**Blocked / waiting:** **Phase 5 (MenuParser + estimators) needs real menu photos** to
transcribe into `Tooling/Fixtures/` (§5, R1). Upload them any time before we reach Phase 5;
Phases 2–4 don't need them.

**Open decisions deferred to Week 1:** AppTarget Xcode-project generation approach
(`.xcodeproj` vs XcodeGen/Tuist vs SPM-app); min iOS version; then account actions only the
owner can do — App Store Connect record, RevenueCat project + `remove_ads` product, Devpost
registration.

**Naming (superseded 2026-09-07):** the product is now **ABV: A Better Value**, displayed as
`ABV`. Historical note follows: canonical name was `BangForBuck` (per the design doc); "brewforbuck" was the
marketing tagline from the original README.

---

## Recipes — "how to add a new ___" (§14)

### Add a new ranking metric (the one you'll reuse — Architecture §14)
1. Add a case to `ValueMetric` (e.g. `.caloriesPerDollar`).
2. Add the pure formula to `ValueRanker` (it already has `pure_ethanol_floz`).
3. Add a `ValueRankerTests` case with a worked example.
4. Add a segmented toggle in the Results feature. **No other layer changes.**

### Add / swap an external dependency (OCR engine, purchase backend, ad network)
1. It already has a protocol in `CoreContracts`. Write one new type conforming to it in
   `AppTarget/Infrastructure/` (§6).
2. Inject the real conformer at app startup; inject a fake in tests.
3. No `CoreServices` change — the core depends on the protocol, never the concrete impl.
