# Apple Watch + Real-Time HR Zone Feedback — Handoff

All Swift is written (but not yet compiled — see `SESSION-HANDOFF.md`). This
supplements `Watch App - Manual Xcode Steps.md` with what's specific to this
implementation. Read both before opening Xcode.

> **Update (2026-06-19):** after the initial implementation, a follow-up commit
> (a) moved the zone hint strings + status colour into `Shared/ZoneFeedbackStyle.swift`
> (added to the table below), (b) made the phone→Watch state broadcast reactive
> (a debounced Combine subscription replaces hand-placed `broadcastStateToWatch()`
> calls), and (c) fixed a bug where the Watch kept counting down after a pause
> (the phone now sends its authoritative `timeRemaining`; the Watch uses the
> live end-time only while running). None of these change the Xcode setup steps.

## What was built

A paired Apple Watch streams live heart rate to the phone during a workout. When
the wearer drifts out of the target zone for the current interval, N4x4 nudges
them back through up to three channels (any combination, user-togglable):

- **Haptic** (Watch) — a distinct wrist tap: "push" (HR too low) vs "ease off"
  (HR too high). Fired locally on the Watch for zero latency.
- **Voice** (iPhone) — a short spoken cue. Off by default.
- **Visual** — the HR readout is colour-coded (green in zone / yellow below /
  red above) on both devices, with a one-line coaching hint.

Heart rate is always shown prominently when a Watch is streaming it. The iPhone
has no HR sensor, so without a Watch the app behaves exactly as before.

### The anti-nag design (the part that makes it usable)

All three channels share one pure evaluator — `Shared/ZoneFeedback.swift` — so
the rules can't drift between devices:

- **60 s settling window** after each interval starts. HR lags effort, so early
  readings are ignored.
- **~10 s sustained** deviation required before any alert. Single stray
  optical-sensor spikes are ignored.
- **Max one alert per minute**, enforced globally (an interval boundary can't be
  used to bypass it).

Work and recovery intervals get alerts; warm-up and cool-down stay silent.

## New files (assign target membership in Xcode)

| File | Target(s) |
|---|---|
| `Shared/WatchMessage.swift` | **N4x4** + **N4x4Watch** |
| `Shared/ZoneFeedback.swift` | **N4x4** + **N4x4Watch** |
| `Shared/ZoneFeedbackStyle.swift` | **N4x4** + **N4x4Watch** |
| `N4x4/PhoneSessionManager.swift` | **N4x4** only |
| `N4x4Watch/N4x4WatchApp.swift` | **N4x4Watch** only (replace any Xcode-generated `@main` file) |
| `N4x4Watch/WatchSessionManager.swift` | **N4x4Watch** only |
| `N4x4Watch/WorkoutManager.swift` | **N4x4Watch** only |
| `N4x4Watch/WatchTimerView.swift` | **N4x4Watch** only |
| `N4x4Watch/N4x4Complication.swift` | **N4x4Complication** only |
| `N4x4Watch/Info.plist` | reference — see note below |

`Interval.swift` and `N4x4LiveActivityAttributes.swift` must also be members of
**N4x4Watch** (per the original manual steps).

## Modified files (already done, no action needed)

- `N4x4/N4x4LiveActivityAttributes.swift` — `ActivityKit` wrapped in
  `#if canImport(ActivityKit)`; `WorkoutPhase` left outside it for the Watch.
- `N4x4/TimerViewModel.swift` — session manager, `currentHeartRate`, zone
  settings, `broadcastStateToWatch()` at every action site, voice engine.
- `N4x4/TimerView.swift` — prominent colour-coded HR readout + hint.
- `N4x4/SettingsView.swift` — "Apple Watch" + "Heart-Rate Zone Alerts" sections.
- `N4x4/Info.plist` — `workout-processing` background mode.

## Two corrections to the original plan — read these

1. **Watch deployment target must be watchOS 10.0, not 9.0.** The Watch UI uses
   the two-parameter `onChange(of:) { _, new in }` (matching the iOS app, which
   targets iOS 17.5). That API is watchOS 10.0+. watchOS 10 runs on Series 4 and
   later — the same hardware the HR sensor already requires — so no audience is
   lost. Set **N4x4Watch → General → Minimum Deployments → watchOS 10.0**.
   (Update Step 2 of the manual-steps doc accordingly.)

2. **Watch HealthKit usage strings.** The main app sets its `NSHealth*` strings
   via build settings (`INFOPLIST_KEY_*`) with `GENERATE_INFOPLIST_FILE = YES`.
   Do the same for the Watch, OR point the target's `INFOPLIST_FILE` at the
   provided `N4x4Watch/Info.plist`. Don't do both, or you'll hit a
   "multiple commands produce Info.plist" build error. Easiest: open the
   **N4x4Watch target → Info** tab and add:
   - `NSHealthShareUsageDescription`
   - `NSHealthUpdateUsageDescription`
   (text is in the provided `N4x4Watch/Info.plist` as reference.)

## Build & test

1. Build the **N4x4** scheme first (⌘B) — it must compile without the Watch.
2. Build the **N4x4Watch** scheme. If it complains about missing symbols, add
   `WatchConnectivity.framework` to the Watch target (General → Frameworks).
3. HR only works on **physical hardware** (iPhone + Apple Watch Series 4+), not
   the Simulator. To verify zone feedback end to end:
   - Start a workout; confirm HR appears on both devices within ~10 s.
   - During a work interval, ease right off for >70 s → expect one "push" wrist
     tap + (if voice on) one spoken cue, then silence for ~a minute.
   - Confirm no alert fires in the first 60 s of any interval.
   - Toggle each channel in Settings and confirm it takes effect.
