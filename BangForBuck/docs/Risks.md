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

## R3 — App Review + ads in an alcohol context · **Schedule / Existential**
**Threatens:** getting listed at all, and the ad revenue path. Apple is wary of apps that
appear to encourage excessive drinking; ad networks restrict alcohol-adjacent inventory.
**Counter-case:** framed as an informational **price-comparison** tool (not "get drunk
cheapest") with a 21+ gate, this is a defensible category.
**Mitigation + trigger:** informational framing in the listing; **21+ age gate** on first
launch; verify the ad network's alcohol policy *before* relying on the revenue; the $0.99
Remove-Ads IAP is qualification insurance regardless. *Not legal advice — confirm the
current App Review guideline wording when writing the listing.* *Trigger:* if ads are
rejected, ship banner-free and lean on the IAP.

## R4 — calories/$ is a much softer estimate than alcohol/$ · **Trust**
**Threatens:** the v2 metric's credibility (sugar/mixers aren't modeled).
**Counter-case:** shipping it as an explicit **alcohol-only kcal lower bound** is honest and
still directionally useful.
**Mitigation + trigger:** v2 only; heavily flagged as a lower bound; don't model mixers in
v1. *Trigger:* defer entirely if the window tightens (it's on the cut-first list).

## R5 — the five-week window incl. review · **Schedule**
**Progress (2026-09-05) — this is now the live risk.** The value engine, capture flow, editable
results, and the store calculator are all in; **monetization is not started at all** (no RevenueCat
conformer, no `remove_ads` product wired, no Paywall screen). RevenueCat integration is a Shipaton
*qualification* requirement, not a feature, and the IAP has to clear review alongside the build
against a ~Sep 18–20 submission target. *Trigger fires now:* stop adding features and do §A.

**Threatens:** shipping inside the Aug 1 – Sep 30 window at all.
**Counter-case:** the pure pipeline proves the value with zero UI, so the risky UI/review
work sits on a proven base.
**Mitigation + trigger:** value engine ships and is tested **first** (this is why Phases
1–5 are headless); scope cut to the bone; submit ~Sep 18–20 with a resubmit buffer.
*Trigger:* if behind by Sep 15, invoke the cut-first list — calories/$, interstitials, live
camera preview, any menu-format cleverness beyond "line with a price."

---

## R-invariant — the price rule (structural, not a risk to accept)
Not a probabilistic risk but the invariant R1/R2 lean on: **a guessed price must never be
rankable.** Enforced by type — `ValueRanker` takes `[PricedDrink]`, and `PricedDrink` is
only constructible with a real read price, so no future edit can rank a fabricated price
(§10). Backed by an explicit invariant test (§8).
