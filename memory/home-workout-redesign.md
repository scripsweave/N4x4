---
name: home-workout-redesign
description: Dark premium Home/Workout redesign — where it lives and how to roll it back
metadata:
  type: project
---

Redesign of the iOS Home + Workout screens (dark, premium, blue/amber/lime), started 2026-07-08 from a mockup. Lives on branch `feature/home-workout-redesign`.

**Ring system (both screens):** `MetalRing` in HomeWorkoutRedesign.swift = static `ChromeRing` asset (brushed-metal bezel, black already alpha-transparent) + programmatic neon glow arc on the inner rim (rimRatio ≈ 0.315 of side), tip dot, floor reflection, ambient bloom, and a centre slot. Home = full ring + `Palette.brandGlow` (blue-right/amber-left; startAngle 90° cancels the arc's −90°). Workout = phase-colour glow + progress arc + dot. Chrome asset source: `~/Desktop/n4x4-assets/n4x4-chrome-ring-transparent.png`.

**Colour scheme:** phase colours via `intervalColor()` — warmup blue, **high-intensity amber (brand orange, not red)**, recovery green, cooldown teal; mirrored in `WorkoutPhase.color` (N4x4LiveActivityAttributes.swift) for Live Activity + Watch. Red (`Palette.danger`) reserved for END button, HR heart, and zone Z5. Zone bar: Z1 gray, Z2 blue, Z3 green, Z4 amber, Z5 red.

**Everything else is in ONE file:** `N4x4/HomeWorkoutRedesign.swift` — `Palette` tokens, `RedesignRootView` (native `TabView` glass tab bar Home/History/Settings, always visible incl. during a workout; History/Settings are full tabs, not sheets), `HomeScreen` (week-streak chip, gradient START ring, `>` toggles interval-plan preview, VO₂ history card with +/−/pinch zoom), `WorkoutScreen` (single-phase-color ring + centered progress dot, `IntervalTimelineBar` showing all intervals + "min left", PAUSE/SKIP/END), `HRZoneBar` (5 zones from `maximumHeartRate`, pulsing target zone, live-HR arrow), `IntervalTimelineBar`, `intervalColor()`.

`SettingsView` and `StreakHistoryView` gained an `embedded: Bool = false` param (drops the sheet-style Done button when hosted in a tab); legacy callers unaffected.

**Rollback:** flip `useRedesignedUI` to false in `ContentView.swift` (falls back to legacy `TimerView`, left fully intact), and/or delete the one file. Only other edits: 3 `private`→internal on `StreakHistoryView`/`PostWorkoutSummaryView`/`MilestoneCelebrationView` in TimerView.swift (so the new shell can reuse them), plus the file's 4 pbxproj registration lines.

**Product decisions locked:** streak stays WEEK-based (labeled "WEEK STREAK"); HR zones derived from max HR; no protocol name ("4x4 Classic" dropped). Verified building + rendering on simulator — see [[simctl-blank-screen-debug-dylib]] for the headless-screenshot gotchas.

Open follow-ups: Home START ring still uses the blue→amber gradient (only the workout progress ring went single-phase-color); VO₂ card `+` is repurposed as zoom-in (mockup was ambiguous).
