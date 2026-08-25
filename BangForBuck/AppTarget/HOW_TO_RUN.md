# Run the app on your phone

This is a minimal SwiftUI app that runs the **real** value engine (the `Core` package) on bundled
sample menus — no camera yet, so you can see the ranking on your phone today. Camera + Apple Vision
is the next step.

Xcode generates the fragile project scaffolding, so the reliable path is: make a blank SwiftUI app,
point it at the local `Core` package, then drop in these three files. ~5 minutes.

## Steps

1. **New project.** Xcode → File ▸ New ▸ Project… ▸ iOS ▸ **App** ▸ Next.
   - Product Name: **BangForBuck**
   - Interface: **SwiftUI**, Language: **Swift**
   - Save it anywhere (e.g. `~/Documents/BangForBuckApp`). This is separate from the `Core` package.

2. **Add the local Core package.** File ▸ Add Package Dependencies… ▸ **Add Local…** ▸ select
   `~/Documents/bfb/BangForBuck/Core` ▸ Add.
   - When prompted (or via the target's **General ▸ Frameworks, Libraries, and Embedded Content ▸ +**),
     add all three library products to the **BangForBuck** app target:
     **CoreModel**, **CoreContracts**, **CoreServices**.

3. **Drop in the app files.** In the new project you'll have a generated `BangForBuckApp.swift` and
   `ContentView.swift`. Replace their contents with the versions in this folder, and drag
   `SampleMenus.swift` into the project (check "BangForBuck" under Target Membership when adding).
   - Files: `BangForBuckApp.swift`, `ContentView.swift`, `SampleMenus.swift`.

4. **Sign it.** Select the **BangForBuck** target ▸ Signing & Capabilities ▸ set **Team** to your
   Apple ID (a free personal team is fine for running on your own device).

5. **Run on your iPhone.** Plug it in (or set up wireless debugging), pick it as the run destination
   at the top, press **⌘R**.
   - First run: on the phone, trust the developer under Settings ▸ General ▸ VPN & Device Management.
   - Free-account builds expire after 7 days; just re-run to reinstall.

## What you'll see

A "Bang-for-Buck" screen with two pickers (sample menu; rank by Drinks/$ or Calories/$) and:
- **Best value first** — each drink with its value, a `$/drink` figure, its ABV, and a badge:
  green **menu** (printed) or orange **est** (estimated) with the note explaining the assumption
  (brand match, style chart, or category fallback).
- **Needs a price** — items we couldn't read a price for (never guessed).
- **Not alcoholic (excluded)** — priced items that aren't alcohol (mocktails, Heineken 0.0, Athletic).

## Next step (camera)

Swap the bundled `SampleMenus` for a real capture: add a `VisionTextRecognizer` (implements the
`TextRecognizer` contract) using `VNRecognizeTextRequest`, a photo picker / camera, a 21+ gate, and
feed the recognized lines into the same `MenuPipeline`. The engine doesn't change — only the source
of the lines does.
