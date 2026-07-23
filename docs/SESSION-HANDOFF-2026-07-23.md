# N4x4 — Session Handoff (birthday easter egg, Linux session)

_Last updated 2026-07-23._ Covers the 2 August birthday easter egg
(design → mockup → Swift implementation → reliability hardening → tests)
and the 4.10 bump. Supersedes
[`SESSION-HANDOFF-2026-07-22b.md`](SESSION-HANDOFF-2026-07-22b.md) for
current state.

Current marketing version: **4.10** (4.9 was the Guide-tab bump).

> **Hard constraint, same as every Linux session:** none of the SwiftUI in
> this session has been compiled by Xcode. Everything parses under
> `swiftc -parse` (Swift 6.1/Linux) and the pure date logic is unit-tested
> and green, but the first real build happens on your Mac / Xcode Cloud.

---

## TL;DR

- **New feature: annual 2 Aug easter egg** — home ring becomes a spinning
  disco ball, fireworks, rising "Happy birthday to 🫧" message. Full spec,
  architecture, decisions and test plan: **`docs/Birthday-Easter-Egg.md`**
  (read that first).
- **Files:** `N4x4/BirthdayEasterEgg.swift` (visuals + engine, new),
  `N4x4/BirthdayActivation.swift` (pure date logic, new),
  `N4x4Tests/BirthdayEasterEggTests.swift` (6 tests, new),
  small diffs in `HomeScreen` (HomeWorkoutRedesign.swift) and
  `SettingsView.swift` (DEBUG-only "Birthday Preview" toggle).
  pbxproj entries follow the synthetic-UUID pattern
  (`B1DA5E99…D15C–D15F`, `B1E0…F6/C2`).
- **Reliability pass found and fixed 3 real bugs** before they shipped:
  non-Gregorian device calendars, midnight crossover while the app is open
  (now handled via `significantTimeChangeNotification`), and the preview
  UserDefaults key leaking into Release (now `#if DEBUG`-guarded read).
- **Deadline:** the feature only matters if a build containing it is
  **approved and installed on her phone by 1 Aug**. Ten days at time of
  writing. This push (4.10) starts Xcode Cloud on exactly that build.

## What to do on the Mac (in order)

1. Pull `main`. Build the **N4x4** scheme (iOS). This is the first Xcode
   compile of ~600 new SwiftUI lines — expect it to be clean (parse-checked),
   but if anything fails it will be here, not in the logic.
2. Run **N4x4Tests** — `BirthdayEasterEggTests` (6) must be green alongside
   the existing suites.
3. Debug-run on your iPhone → Settings → General → **Birthday Preview** →
   ON → back to Home. Work through the visual checklist in
   `docs/Birthday-Easter-Egg.md` §Testing (message position, spark trails,
   finale frame rate, beams/wire alignment). Long-press the ball; tap around;
   start a workout to confirm the START contract.
4. Turn the preview toggle **off**. Then the honest test: Release config to
   device, iPhone date set to 2 Aug, cold launch.
5. Xcode Cloud will already be building 4.10 from this push. After the
   on-device pass, submit 4.10 for review (pick the 4.10 build in ASC).
   **Keep the App Store notes generic — no spoilers.**
6. Before 2 Aug: confirm her phone has auto-updated (or update it yourself,
   discreetly).

## Watch out for

- **`whats_new.txt` / ASC notes:** don't mention the egg.
- **Preview key hygiene:** if you ever see birthday mode on a normal day on
  your own device, it's a Debug build with the toggle left on — Release
  builds cannot enter preview mode by construction.
- **If visuals need tuning** (likely candidates: message parking height
  `0.16`, spark streak length `0.06`, ambient launch cadence `0.9...1.7`):
  they're plain constants in `BirthdayEasterEgg.swift`, commented.
- 4.6/4.7 remain burned version numbers; 4.9 shipped the Guide tab. Never
  reuse numbers (AGENTS.md).

## Addendum — Mac session, 23 Jul afternoon

The first Xcode compile found four errors `swiftc -parse` couldn't
(access levels vs the file-private `RGB`, dropped tuple labels in
`roomLights`, a type-checker timeout on `spots`) — fixed, no behavior
change. Then three feature changes on Jan's direction:

- **Interactive spin** (`DiscoBallSpin`): drag grabs the ball (hold =
  stop), flick throws it (±10 rad/s cap), motor+friction relaxes it back
  to 0.8 rad/s (τ = 4 s). Room-light spots follow the real rotation.
- **Message parks above the ball**, computed from the reported ball frame
  (48 pt clearance, floored at 10% height) — the fixed 0.16 fraction
  overlapped the sphere on device.
- **Manual trigger replaced the DEBUG Settings toggle**: Guide → Advanced
  → hold the last tile 2 s → success haptic → next arrival at Home runs
  birthday mode once (flag self-clears; works in all build configs).

Tests: 101/101 green on the iPhone 17 Pro simulator (4 new: one-shot
consume-once, flick relaxation, grab-stop-respool, velocity clamp).
Feature doc updated. Steps 3–4 of the checklist above now use the Guide
trigger instead of the Settings toggle.

## Linux toolchain note (for future agent sessions)

The date-logic tests were run on this box via the scratch-SPM recipe
(Swift 6.1 Ubuntu 24.04 toolchain + libxml2.so.2/libicu74 compat libs,
`LD_LIBRARY_PATH`, symlinked source + sed'd `@testable import`). Recipe
lives in the agent memory (`linux-swift-toolchain-recipe`) and in
`SESSION-HANDOFF-2026-07-20.md`.
