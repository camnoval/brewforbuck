# ABV: A Better Value

*Formerly "Bang-for-Buck". The repo directory, Xcode target and bundle
identifier may still carry the old name; see the Handoff for which of those have been renamed.*

**Take a picture of a drink menu, get the alcoholic options ranked by value — how much
alcohol you get per dollar — so you can pick the best deal at a glance.** (v2 adds a
calories-per-dollar ranking on the same pipeline.)

Built for the **Shipaton 2026** window (first public version live Aug 1 – Sep 30, 2026),
integrating the RevenueCat SDK.

## Run it

The value engine is a pure, framework-free Swift package that builds and tests anywhere:

```bash
cd Core
swift test        # the whole value engine, headless — no camera, no simulator
```

Or run the full pre-flight gate:

```bash
./Tooling/run_checks.sh
```

The iOS app (`AppTarget/`) — camera/library → Vision OCR → editable, ranked results behind a 21+
gate — opens in Xcode on macOS against the local `Core` package (needs `NSCameraUsageDescription`;
iOS 16+). Monetization (RevenueCat) is the only remaining step; see `MonetizationPlan.md`.

## Where to go next

| If you want… | Read |
|---|---|
| The design & data flow | [`Architecture.md`](./Architecture.md) — **start here for design** |
| The portable playbook this app instantiates | [`ProjectConventions.md`](./ProjectConventions.md) |
| A file-by-file map of the code | [`CodebaseReference.md`](./CodebaseReference.md) |
| The current directory tree (auto-generated) | [`ProjectStructure.md`](./ProjectStructure.md) |
| Current state + what to do next | [`Handoff.md`](./Handoff.md) |
| **The next session: ads + IAP** | [`MonetizationPlan.md`](./MonetizationPlan.md) — **start here** |
| The plan for the menu-reading test pass (done) | [`MenuTestingPlan.md`](./MenuTestingPlan.md) |
| The assumptions that could break it | [`Risks.md`](./Risks.md) |
| Where the ABV/size numbers come from | [`BeverageDataSources.md`](./BeverageDataSources.md) |
| A non-technical overview | [`PlainLanguageGuide.md`](./PlainLanguageGuide.md) |
| Session-by-session history | [`Changelog.md`](./Changelog.md) |

> Read `Architecture.md` and `ProjectConventions.md` together — the former instantiates the
> latter, and their `§` numbers line up so you can jump between them.
