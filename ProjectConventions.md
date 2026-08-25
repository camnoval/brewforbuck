# Project Conventions & Architecture Playbook

*A portable, project-agnostic guide to setting up a codebase that stays legible as it
grows. Attach this to any new project's README or handoff doc. It encodes the
organizational patterns — layered modules, a pure/impure split, tests that mirror
code, verb-named tooling, and a documentation set that acts as a system — so a new
project (or a new person, or an agent) can pick up the same discipline from day one.*

> This is written to be **language-agnostic in its principles** with **iOS/Swift-flavored
> examples**. It is a **per-app template**: apply it independently to each app you build.
> Where a rule reads generically, the Swift mapping is in a callout. Adapt the file names;
> keep the shape.

---

## 0. How to use this document

Read §1 and §2 once. They set the two habits that make everything else fall into
place: **state the system in one paragraph before you build it**, and **maintain a
small set of documents that each do exactly one job.** The rest are conventions you
copy in and adjust per project.

The single most important idea: **every "add a new thing" should be localized to one
place, behind one contract.** If adding a screen, a data source, or a feature forces
edits scattered across ten files, the architecture has failed regardless of how clean
each file looks.

---

## 1. The one-paragraph mental model (write this first, keep it at the top)

Before any code, write one short paragraph that answers: *what does this system do,
what is the one core concept everything hangs off of, and what are the (few) flows
through it?* Put it at the top of the architecture doc and the codebase reference, and
open both with **"Mental model (read this first)."**

A good mental model names:

- **The one job** — one sentence. If it takes three sentences, the scope is unclear.
- **The spine / join key** — the single concept everything else is organized around
  (an ID, a canonical entity, a store, a domain object). Everything reduces to it.
- **The flows** — usually two or three named paths through the system (e.g. a *build*
  flow and a *query* flow; or an *ingest* flow and a *render* flow). Name them and
  never let a fourth sneak in unnamed.

> **iOS mapping.** The "spine" is usually your domain model layer + its single source of
> truth (a store / repository). The flows are typically **data-in** (fetch → decode →
> persist → publish) and **user-action** (intent → state change → view update). If you
> ship two apps, the spine is a **shared Swift package** both apps depend on.

Two or three *load-bearing rules* usually emerge here too — invariants that appear
everywhere. Write them down explicitly (§10). Example from a well-run project: *"the
safety layer annotates and re-orders output but is never summed into the score,"* and
*"measured data always overrides derived data, and derived data is always flagged."*

---

## 2. The documentation set (docs as a system, not a pile)

Keep a **small cluster of documents, each with one role.** The discipline is that a
reader always knows which file answers their question. Recommended set:

| File | Role | Rule of thumb |
|---|---|---|
| `README.md` | Entry point. What it is, how to run it, where to go next. | Shortest doc. Links out. |
| `Architecture.md` | The design and data flow. Diagrams of the named flows. | "Start here for design." |
| `CodebaseReference.md` | File-by-file, function-by-function map. Opens with the mental model + a layer table. | The map you jump around in. |
| `Handoff.md` | Decision history + "start here" carry-on context for whoever picks it up next. | What was built, what to do next, and *why*. |
| `Risks.md` | The load-bearing assumptions that could still break it, with severity tiers. | Cross-referenced from code (§13). |
| `Changelog.md` | Session-by-session / release-by-release history. | Moved *out* of Handoff to keep it lean. |
| `PlainLanguageGuide.md` | Non-technical overview for stakeholders. | No jargon. |

Conventions that make this set work:

- **Handoff stays lean by exporting history to the Changelog.** The Handoff is a live
  "here's where we are"; the Changelog is the append-only log. Don't let them merge.
- **Most-recent-first, with an explicit supersede line.** New session notes go at the
  top and say plainly *"this supersedes the note below / the body where they conflict."*
  Never silently contradict an old note — call out that it's overridden and why.
- **Every doc points at the others.** "Read `Risks.md` alongside this." A reader should
  never wonder which file has the answer.

> Each app gets its **own** doc set — don't try to share docs across independent apps.
> Keep the two clusters small and parallel so switching between the projects feels the
> same; a decision that turned out well in one app can be copied into the other by hand.

---

## 3. Directory layout

Group by **role/layer**, not by file type. A newcomer should read the top-level folder
listing and understand the system's shape.

### Generic template
```
project/
  docs/            # the doc set from §2
  src/
    <package>/     # the importable library — the real system
      foundation/  # identity, storage, the core contracts
      sources/     # one module per external data source / integration
      domain/      # the modeling / business logic
      services/    # things that act on domain objects (scoring, transforms)
      orchestration/  # the top layer that wires it all together
      ui/          # apps / interfaces (kept thin; logic lives below)
  scripts/         # verb-named tooling (§9) — build_, inspect_, validate_, ...
  tests/           # test_<module>.py mirrors src 1:1 (§8)
  data/            # inputs & artifacts — GITIGNORED, never committed
  config.yaml      # a single registry for what-maps-to-what (§9)
```

### iOS / Swift template (one app — repeat this shape per app)
```
App/
  docs/                         # this app's own doc set (§2)
  Core/                         # a LOCAL Swift Package — the app's spine, no UIKit/SwiftUI
    Sources/
      CoreModel/                # domain entities + the ONE source of truth
      CoreContracts/            # protocols every integration implements (§6)
      CoreServices/             # pure business logic (§7 — no I/O, no framework)
    Tests/
      CoreModelTests/           # mirrors CoreModel
      CoreServicesTests/        # mirrors CoreServices
  AppTarget/
    Sources/
      Features/<Feature>/       # one folder per feature: View + ViewModel + wiring
      Infrastructure/           # the impure shell: networking, persistence, adapters
    Tests/
  Tooling/                      # scripts: fixtures, codegen, lint gate, release checks
```

The `Core/` package is **local to this app** — it's not shared with your other app. Its
only job is to force the pure/impure split (§7) and keep the layer directions honest
(§4): `Core` compiles with no SwiftUI/UIKit import, and `AppTarget` depends on `Core`,
never the other way around. Your second app gets its own identical-shaped `Core`.

Rules:

- **`data/` and build artifacts are never committed.** Put them in `.gitignore` on day
  one. (For iOS: derived data, `.xcuserstate`, secrets/plists with keys.)
- **The importable library is the product; the app/UI is a thin driver on top of it.**
  You should be able to exercise almost everything without launching the UI.

---

## 4. Layered architecture (and the table that documents it)

Stack the system in layers, **each with a single job, each depending only on layers
below it.** Then document the stack as a table at the top of the codebase reference —
this table is the fastest onboarding artifact you can produce.

| Layer | Depends on | Job |
|---|---|---|
| **Foundation** | nothing | Identity, storage, the contracts everyone implements. |
| **Sources / Integrations** | Foundation | Each ingests one external thing into the domain. |
| **Domain / Modeling** | Foundation | The core business logic and derived values. |
| **Services / Scorers** | Domain | Act on domain objects to produce outputs + advisories. |
| **Orchestration** | all above | Wire the flow end to end; read the store, run the pipeline. |
| **Apps / UI** | Orchestration | The interface a user touches. Kept thin. |
| **Scripts / Tooling** | any | Drivers to build, inspect, validate, and gate. |
| **Tests** | any | One test module per source module. |

The dependency direction is the whole point: **lower layers never import upper ones.**
Foundation knows nothing about the UI. This is what lets you test the core in
isolation and reuse it across both apps.

> **iOS mapping.** Enforce the direction with **package boundaries**: `CoreModel` and
> `CoreServices` compile without importing SwiftUI/UIKit/Foundation-networking. If a
> core file needs `URLSession`, that logic belongs in the app's Infrastructure layer
> behind a protocol (§6), not in Core.

---

## 5. Inspect before you build (never trust a remembered schema)

Before writing a parser, decoder, or integration against any external data, **write a
tiny throwaway script that dumps the real shape first** — columns, sample rows,
response JSON, field types. Keep these as `inspect_*` scripts (§9). Half of all
integration bugs are "the schema wasn't what I remembered."

> **iOS mapping.** Before writing a `Codable` model, capture a real API response into a
> fixture file and inspect it. Then write the decoder *against the fixture* and keep the
> fixture as a test input. Never hand-write a `Codable` from memory of the docs.

---

## 6. The contract pattern (this is what makes it modular)

For every category of pluggable thing — a data source, an integration, a strategy — define
**one interface (a base class / protocol) with a small, fixed set of methods.** Then each
concrete implementation is *one file* that satisfies the contract. Adding a new source
becomes: implement the contract, register it, done. No surgery elsewhere.

Example contract shape (from a real, well-organized project):

```
Source (abstract):
    fetch()      -> locate/prepare the raw input
    normalize()  -> raw -> a tidy in-memory structure
    to_domain()  -> tidy structure -> domain records (this is where identity is assigned)
    run()        -> the concrete driver: fetch -> normalize -> to_domain
```

The orchestration layer just calls `.run()` on each registered source in order. That's
why adding a source is localized to one new file plus one registry line.

> **iOS mapping.** This is protocol-oriented design + dependency injection:
> ```swift
> protocol DataSource {
>     func fetch() async throws -> RawPayload
>     func normalize(_ raw: RawPayload) throws -> [DomainRecord]
> }
> ```
> Each integration is one type conforming to `DataSource`. The app injects a concrete
> conformer; tests inject a fake. The ViewModel depends on the *protocol*, never the
> concrete network client — so it's testable and swappable.

**"Localized change" is the acceptance test for this pattern.** If adding the second
kind of a thing required editing the first kind's file, the contract is leaking.

---

## 7. Pure core, impure shell

Split every module into a **pure layer** (logic, transforms, parsing, business rules —
*no I/O, no heavy dependencies, no framework imports*) and an **impure layer** (the thing
that touches the network, disk, database, or a heavy native library).

In the reference project this is literally two files: `<thing>_parse.py` (pure — imports
no database driver, no chemistry engine, testable on any machine in milliseconds) and
`<thing>.py` (the ingester, which *lazy-imports* the heavy dependency inside the method
that needs it). The payoff:

- The pure layer is **unit-testable anywhere**, fast, deterministic, and doesn't drag in
  a native extension just to run one assertion.
- The impure layer is thin and mostly untested-by-design (it's just wiring), so the
  hard-to-test surface is minimized.

> **iOS mapping.** Keep decoding, validation, formatting, and business rules as **pure
> functions / value types** in `CoreServices` — no `URLSession`, no Core Data, no SwiftUI.
> The impure shell (networking client, persistence store) lives in app Infrastructure and
> is reached only through a protocol. Rule of thumb: **if a function needs `await` on the
> network or a database, it's shell, not core.** Push the decision-making down into pure
> code and hand it the already-fetched data.

---

## 8. Testing conventions

- **Tests mirror modules 1:1.** `test_<module>` targets the module of the same name. A
  reader knows exactly where a module's tests live without searching.

  > iOS: `CoreServicesTests` mirrors `CoreServices`; `<Feature>Tests` mirrors `<Feature>`.

- **Every pure parser/decoder gets an invariant test** — feed it a known fixture, assert
  the known result. These are your fastest and most valuable tests.

- **Test the load-bearing invariants explicitly** (§10). If a rule is "the safety layer
  never enters the score," there is a test that constructs an object with safety fields
  set and asserts the score is unchanged. Rules that matter get a test that fails loudly
  if someone breaks them.

- **Run the whole suite before every build/release.** Stale-file skew (a module drifting
  from its caller) is exactly what a mirrored suite catches.

---

## 9. Tooling & scripts (name by verb; one gate to rule them)

Keep operational scripts in `scripts/` (or `Tooling/`), named by a **verb prefix** so the
purpose is legible from the filename alone. The reference project's prefixes, worth
copying:

- `inspect_*` — profile raw data / an API response *before* writing a parser (§5).
- `build_*` — produce the main artifact / do the heavy assembly.
- `precompute_*` — cache expensive work so day-to-day runs are fast.
- `validate_*` — prove the output is worth trusting (beat a baseline, check against
  ground truth).
- `diagnose_*` / `explain_*` — trace *why* a number is what it is; document known
  non-bugs so nobody "fixes" expected behavior.
- `check_*` — small sanity/smoke checks.

Then have **one gate script** (`run_checks`) that runs the full pre-flight in order: the
whole test suite, a compile check, and any smoke tests. Green gate = safe to build/ship.

**A single config registry.** Keep a `config.yaml` (or equivalent) that maps
what-belongs-to-what — which source produces which capability, which are derived vs
measured. One file, read by the audit/coverage tooling, so the mapping is declared once
and inspected rather than scattered through code.

> **iOS mapping.** `Tooling/` holds: a fixture-refresh script, any codegen, a lint/format
> gate (SwiftLint/SwiftFormat), and a release pre-flight that runs `xcodebuild test` for
> both app schemes + the Core package. Wire the gate into CI so it can't be skipped.

---

## 10. Enforce invariants structurally, not by convention

The strongest rules are the ones the structure (or the compiler) protects, so they
*can't* be violated by a careless edit:

- If "the safety layer must never affect the score," make the score function **physically
  unable to read** the safety fields — the fields exist on the object, but the scoring
  path never receives them. A comment saying "don't use these here" is weaker than a
  boundary that doesn't pass them in.

  > iOS: give the scoring function a **narrower input type** that literally doesn't
  > contain the forbidden fields. Use `private`/`internal` access control and separate
  > modules so the wrong dependency won't compile.

- Write down the two or three load-bearing invariants in the architecture doc, tag them,
  and back each with a test (§8).

---

## 11. Provenance & honesty (flag derived vs measured; report loss)

Whenever a value can be either **ground truth** or **derived/estimated**, carry which one
it is, and:

- **Measured/authoritative always overrides derived.**
- **Every derived or imputed value is flagged** (a tag, an enum case, an asterisk in the
  UI) so no one mistakes a guess for a fact.
- **Report loss honestly.** When a step drops or fails to resolve some inputs, surface
  the count and the reason, decomposed — not a single opaque "N processed."
- **Respond to numbers, not vibes.** Keep an audit/coverage view that shows *which* part
  of the pipeline collapses coverage, so decisions are driven by the funnel rather than a
  hunch.

> iOS: model this as an enum on the value — `.measured(x)` vs `.estimated(x, confidence:)`
> — and let the view render estimated values distinctly. Log resolution/decoding failures
> with categories, not just a total.

---

## 12. Safety rails on destructive operations

Any operation that overwrites or rebuilds a live artifact gets two rails:

- **A preflight** that checks all prerequisites (dependencies present, required inputs
  exist) and **fails before touching anything.**
- **An atomic swap** — write to a temporary artifact, and replace the live one **only on a
  clean finish.** A crash mid-operation then leaves the previous good state intact instead
  of a half-built one.

> iOS: write to a temp file / staging store, `fsync`/flush, then atomically move into
> place. Never mutate the live store in place during a migration or rebuild.

---

## 13. The risk register & the `R#` cross-reference habit

Maintain `Risks.md` as a **living register of load-bearing assumptions** — the things that,
if wrong, break the project — each with:

- a **severity tier** (e.g. *Existential* / *Safety* / *Quality-Trust*),
- what it threatens,
- the honest counter-case (why it might be less bad than it looks),
- concrete **mitigations with triggers** (do X when Y happens).

Then **tag each risk (`R1`, `R2`, …) and reference the tag from code comments and other
docs.** When a comment says `// composition-only fallback (R4)`, a reader can jump straight
to the assumption behind that line. This ties the reasoning to the code without bloating
the code with prose. Keep `Risks.md` open next to the code and the cross-references make
the whole design traceable.

---

## 14. "How to add a new ___" recipes (put these in the Handoff)

The clearest sign of a healthy architecture is that "add a new X" is a short, localized
recipe. Write one per pluggable category. Template:

**Add a new data source / integration**
1. `inspect_*` the raw input to learn its real shape (§5).
2. Write the **pure parser/decoder** + an invariant test against a fixture (§7, §8).
3. Implement the **contract** in one new file (§6).
4. Register it (one line in the config registry / DI container, §9).
5. Run the gate; re-run the audit.

**Add a new feature (iOS)**
1. New folder under `Features/` with `View` + `ViewModel` + wiring.
2. ViewModel depends only on **protocols** from Core (§6); inject the real service in the
   app, a fake in tests.
3. Business logic goes in **CoreServices as pure code** (§7), not the ViewModel.
4. Add `<Feature>Tests` mirroring the folder (§8).

---

## 15. Day-0 checklist for a new project

- [ ] Write the **one-paragraph mental model** — one job, one spine, the named flows (§1).
- [ ] Create the **doc set** stubs: README, Architecture, CodebaseReference, Handoff,
      Risks, Changelog (§2).
- [ ] Lay out folders **by layer/role**, with the importable core separate from the UI (§3).
- [ ] Put `data/` + build artifacts + secrets in `.gitignore` immediately (§3).
- [ ] Define the **core contracts/protocols** before the first concrete implementation (§6).
- [ ] Establish the **pure/impure split** as a rule from file one (§7).
- [ ] Stand up the **test folder mirroring src**, plus the **gate script** wired into CI (§8, §9).
- [ ] Write down the **two or three load-bearing invariants** and back each with a test (§10).
- [ ] Start `Risks.md` with at least the existential risk, tagged `R1` (§13).
- [ ] Write the first **"how to add a new ___" recipe** in the Handoff (§14).

---

### Applying this to each app

The two apps are independent, so treat this as a **template you stamp out twice**, once
per app, with no shared code between them. Within each app, the highest-leverage move is a
**local `Core` Swift Package** (not shared with the other app): it holds the domain model
(the spine), the contracts (protocols), and the pure services, and it compiles with **no
SwiftUI/UIKit import**. That package boundary is what forces the pure/impure discipline
(§7) and enforces the layer directions (§4) — it's the cleanest tool iOS gives you for it,
and it costs almost nothing to set up per app. The app itself is then a thin Features +
Infrastructure shell on top of its own `Core`.

Because the two apps share this *structure* but no *code*, the payoff is consistency: once
you've internalized the shape on the first app, the second one is muscle memory, and a
pattern that worked well in one can be copied over deliberately rather than entangled by a
shared dependency.
