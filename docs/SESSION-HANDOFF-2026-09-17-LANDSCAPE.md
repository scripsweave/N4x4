# Landscape, larger heart rate, and workout cleanup

Release version **5.2** for iPhone, Watch and Live Activity (all six shipping
configurations). Builds on the 5.1 autosave release documented in
[`SESSION-HANDOFF-2026-09-17.md`](SESSION-HANDOFF-2026-09-17.md).

## Interface

- Both landscape directions are enabled. Home places the Start ring beside
  the plan; an active workout places the countdown ring and timeline beside
  the heart-rate panel and controls. Rotation changes presentation only, never
  timer ownership or elapsed time.
- The HR readout moves out of the countdown ring into a dedicated panel:
  60-point rounded digits in portrait, 72 in landscape, scaled with Dynamic
  Type. The shared instant zone tint, target range and optional coaching cue
  remain together. Absent readings show a dash, not a fabricated zero.
- Compact portrait layouts make room for the live reading and controls;
  accessibility text sizes use a scrolling stack. Home and onboarding also
  scroll when necessary. Completion/history detail use NavigationStack so
  landscape does not accidentally expose an empty split-view column.
- The existing chrome ring, palette and birthday controller are retained.
  The birthday ball's measured frame follows its adaptive size. The egg's
  timing, gestures and motion rules have not been changed.
- For simulator layout tests only, Debug builds accept environment variable
  `N4X4_DEMO_HEART_RATE=166`. Samples enter the normal HR funnel at each timer
  reconciliation; pausing stops the fixture stream, so stale readings expire
  normally. This fixture is compiled out of device and Release builds.

## Stopping workouts

- `stopTimer()` invalidates and cancels interval cues. Reset, End and completion
  also end all app Live Activities, including those no longer held by the VM.
  Pause retains a paused Live Activity; resume schedules a fresh cue.
- Interval notification add/cancel operations are serialized. A generation token
  rejects an old queued add, and cleanup runs again after an in-flight add
  completes. A subsequent workout waits for this cleanup before scheduling.
- Pending and delivered `nextInterval` notifications are removed. Weekly
  reminders and birthday nudges keep their separate lifecycles.
- Live Activity updates/end operations are ordered, with queued updates checking
  the current activity ID. The list to end is captured before starting an async
  task, so launch cleanup cannot accidentally capture a newly started workout.
- Launch and idle/completed foreground entry remove abandoned system surfaces.
  Disabling interval cues cancels them; disabling Live Activities ends them.
  A completed workout cannot restart its timer before review/reset.
- Small injected system interfaces in TimerViewModel let tests deliberately
  suspend notification adds and activity updates. Business logic stays in the
  ViewModel; there is no new singleton or external dependency.

## Verification

- All **149 unit tests passed**, including seven new system-cleanup tests:
  suspended add → End → new workout; pause/reset/completion; late activity
  updates; orphan cleanup; disabling interval cues; launch cleanup; and guarding
  against restarting a completed workout.
- Five UI scenarios passed on iPhone 17 Pro (iOS 26.5): rotating in both
  directions while paused, live/no-HR displays, landscape completion, largest
  Dynamic Type, and the existing autosave/history/delete regression flows.
- The three layout scenarios also passed on iPhone SE (3rd generation).
  Screenshot review then caught a wrapped Pause label at accessibility sizes;
  controls and the workout header now stack at those sizes. Targeted layout
  checks were rerun after that adjustment.
- Simulator fixtures verify rendering and state transitions, not real HR
  hardware. The release build compiles the phone app, embedded Watch app and
  Live Activity; built product plists report version 5.2 and both landscape
  orientations.
- Result bundles: `/tmp/N4x4-landscape-Pro-final.xcresult` (149 units + 5 UI),
  `/tmp/N4x4-landscape-SE-final.xcresult` (3 UI), and
  `/tmp/N4x4-layout-polish-SE.xcresult` (targeted final layout checks).
  Release build log: `/tmp/N4x4-release-final.log`.
- Design review: **8/10** against the native iOS checklist for the changed
  screens. The remaining work toward 10/10 is a full physical-device VoiceOver
  audit and replacing remaining legacy fixed text/colour styling with semantic
  tokens across the surrounding screens. The established dark palette is
  intentionally retained for this release.
- `git diff --check` and the six shipping version values were checked.
Physical rower-holder use, live HR hardware, and locked-device notification /
Live Activity delivery require a real iPhone and have not been exercised here.
