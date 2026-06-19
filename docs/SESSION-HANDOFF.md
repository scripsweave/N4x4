# N4x4 — Session Handoff

Authoritative status for resuming work. Last updated 2026-06-19.

> **Hard constraint:** none of the work below has been compiled or run. There
> was no Swift toolchain in the working environment and Xcode was unavailable.
> Everything is written and reviewed (brace-balanced, symbols cross-checked)
> but must be built in Xcode before it can be trusted. **Build the iOS app
> scheme first**, then the Watch scheme.

---

## Feature 1 — Apple Watch app + real-time HR zone feedback

**Status:** all Swift written and committed. Blocked on one-time Xcode target
setup that an agent cannot perform.

What it does: a paired Apple Watch streams live heart rate during a workout.
When the wearer drifts out of the target zone for the current interval, N4x4
nudges them back through three independent, user-togglable channels — haptic
(Watch, fired locally), voice (iPhone), visual (colour-coded HR on both
devices). HR is shown prominently whenever a Watch is streaming it.

Anti-nag design (shared pure engine, `Shared/ZoneFeedback.swift`): 60 s settling
window after each interval starts, ~10 s sustained deviation before alerting,
and at most one alert per minute.

**Before it compiles, do the Xcode setup in:**
- `docs/Watch App - Manual Xcode Steps.md` (create targets, capabilities, file
  memberships) — **with the two corrections** in
- `docs/Watch App - HR Zone Feedback Handoff.md` (watchOS **10.0** target, not
  9.0; Info.plist handling; full new-file → target-membership table).

Key commits: `Add Apple Watch app...` and `Harden Watch HR feedback...`
(the latter adds `Shared/ZoneFeedbackStyle.swift`, makes the state broadcast
reactive via Combine, and fixes a paused-countdown bug). HEAD-side ref `a0291eb`.

---

## Feature 2 — Per-modality performance logging (e.g. treadmill speed)

**Status:** Phases 1-4 complete and committed (`1a7a2fe` → `08204e9`). No Xcode
target work needed — all in existing files. Still needs a compile + UX run.

Origin: a user asked to log treadmill speeds to track progress. Generalised to
per-modality performance (speed / cadence / stroke rate / level), driven by the
modality the workout's Type picker maps to (`WorkoutType.trainingModality`).

- **Phase 1 — model/persistence/units.** `IntervalPerformance` (primary value +
  reserved `secondary`), `ModalityMetric` descriptor per modality, `WorkoutLogEntry`
  gains optional `modality` + `intervalPerformances` (old logs decode untouched).
  Speed stored canonically in km/h, converted for display. `UnitPreference`
  (System/Metric/Imperial). 6 tests.
- **Phase 2 — capture UI.** Post-workout summary "Performance" section: a
  "Set all" field stamps every work interval; a disclosure fine-tunes each;
  blank = skipped; pre-fills from the last session of the same modality. 4 tests.
- **Phase 3 — trend chart.** Per-modality "Performance Trend" card in the
  weekly-streaks sheet (session-average line). `chartXSelection` lets a tap pick
  a session; the detail card lists that session's per-interval values.
- **Phase 4 — Units control.** Measurement picker in Settings.

### One UX judgment to review on device
Phase 2 **pre-fills** the form from the last same-modality session, so a repeat
session can be saved in one tap. The risk: if the user ran different speeds and
doesn't notice, stale values get logged. If that feels wrong on device, switch
pre-fill to placeholder-only (show last values greyed, log only what's typed).

---

## Pending / fast-follows (discussed, not built)

- **Outdoor-run pace** as mm:ss min/km input (v1 treats all distance metrics as
  speed in km/h-equivalent).
- **HR-at-same-speed** overlay on the trend chart (needs accumulated Watch HR).
- **`ISSUES.md`**: #5 (timestamp drift) is already fixed; #1-4 remain open and
  cluster in the notification code — worth a dedicated pass.

## How to verify once Xcode is available
1. Build the **N4x4** (iOS) scheme. It must compile without the Watch.
2. Run the unit tests (`N4x4Tests`) — 10 new tests cover the performance model.
3. Do the Watch Xcode setup, then build the **N4x4Watch** scheme.
4. HR + zone feedback require a physical Apple Watch (Series 4+), not the Simulator.
