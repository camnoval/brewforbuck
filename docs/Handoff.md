# Handoff

*Live "here's where we are" + carry-on context (§2). History lives in `Changelog.md`, not
here — keep this lean. Newest note on top; each new note says plainly what it supersedes.*

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

**Naming:** canonical name is `BangForBuck` (per the design doc); "brewforbuck" is the
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
