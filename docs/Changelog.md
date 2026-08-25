# Changelog

*Append-only history (§2). Newest on top. The Handoff is the live "where we are"; this is
the log — don't let them merge.*

## 2026-08-25 · Tooling — auto-generated structure doc
- Added `Tooling/print_structure.sh` → regenerates `docs/ProjectStructure.md` from the real tree
  (portable: no `tree`, no GNU `find -printf`). Wired into `run_checks` step [0/2] so it refreshes
  on every gate run and can't drift. Added to the README doc-set index.

## 2026-08-25 · Phase 2 — CoreModel (the spine)
- Built the spine in `Core/Sources/CoreModel`: `Provenance<T>`, `Price`, `Volume`,
  `BeverageCategory`, `MenuItem`, `DrinkOption`, `PricedDrink`, `RankedDrink`, `ValueMetric`.
- Two invariants enforced structurally, not by comment:
  - **Price (§10):** `Price`'s only init is failable and rejects non-positive amounts; `DrinkOption.price`
    is a non-optional `Price`. A priceless line yields no `Price`, so it can't build a `DrinkOption`.
  - **Change B:** `PricedDrink.init?` refuses `.nonAlcoholic`, so a priced mocktail can never be ranked.
- Business math kept OUT of the model: the value formulas live in `ValueRanker` (Phase 4).
- `CoreModelTests` mirror the module 1:1, incl. `PricedDrinkInvariantTests`.
- **Exit:** spine complete; suite expected green (`cd Core && swift test` on your Mac).

## 2026-08-25 · §5 inspection — 16 real menus transcribed
- Transcribed 7 format-diverse menus into `Tooling/Fixtures/` + wrote `INSPECTION_FINDINGS.md`.
- Two design changes surfaced (see findings): **(A)** `MenuParser` must be a section-state
  machine, because some menus price only on the category header (Rullo's `Elixirs | $14`);
  **(B)** `.nonAlcoholic` becomes a first-class `BeverageCategory` case, excluded from ranking
  before the metric (priced mocktails/sodas otherwise pollute results).
- Confirmed printed ABV/size is common on beer & wine menus → the `.read` provenance path is
  well-exercised, not a rare branch.

## 2026-08-25 · Phase 1 — Foundations & scaffolding
- Created repo laid out by layer/role (§3): `Core/` (local SPM package), `Tooling/`, `docs/`.
- `Core/Package.swift`: target graph with dependency directions CoreModel ← CoreContracts ←
  CoreServices (§4); platform-agnostic so `swift test` runs on Linux and macOS.
- Placeholder sources + trivial tests so the package compiles and the suite is green.
- `.gitignore`: build artifacts, secrets/keys, `data/` excluded from day one (§3).
- `Tooling/run_checks.sh`: the single pre-flight gate (§9).
- Full §2 doc set: README, CodebaseReference (mental model + layer table), Handoff, Risks
  (R1–R5 tagged), PlainLanguageGuide, this Changelog. Placed the two authored design docs
  (`Architecture.md`, `ProjectConventions.md`) verbatim.
- **Exit:** tree compiles, doc set complete. Awaiting Phase 1 approval before CoreModel.
