# Watch heart-rate reliability and diagnostics — 1 November 2026

A user on 5.14 reported intermittent Watch HR: phone shows "waiting for heart
rate", watch-started workouts, repeated Health prompts, Heart Rate read access
found switched off. Their screenshots and email are private and untracked under
`tmp/` (not gitignored — never `git add -A` there).

Submitted as **5.15 (55)** on 2 November 2026 (WAITING_FOR_REVIEW, automatic
release after approval; details in `AppStore/SUBMISSIONS.md`) at the user's request, without the
physical-device checks below (no Watch available while traveling). 5.14 was
live (READY_FOR_DISTRIBUTION) before the bump. Release notes:
`AppStore/release-notes-5.15.txt`; review notes: `AppStore/review-notes-5.15.txt`.

## Evidence from the report

Copy Diagnostics: 35 Watch readings accepted, **0 rejected**, measurement →
arrival about 1 s. If the Watch had sent anything during the failed tests, even
late context, the phone would have counted a rejection. So the failure was
upstream of sending: no sensor session, a session without HR samples, or a
Watch-side drop. A Fitness Focus "On" appeared about 2.5 minutes after the last
reading. That suggests a new Watch workout session started, and nothing arrived
from it. It could also have been Apple's Workout app.

## Causes found in code, and fixes

| Finding | Change |
| --- | --- |
| Heart Rate **read** was requested only by the Watch's on-wrist prompt. The iPhone sheet never listed it, so allowing everything on the iPhone left the Watch's live builder blind. In-app help also omitted it. | `TimerViewModel.healthKitReadTypes` adds Heart Rate. The iPhone only requests from onboarding, the toggle, Review Health Access and reconnect, so this adds no launch prompt. Help copy updated. |
| Startup (authorization + abandoned-session cleanup) had no timeout. A missing callback left `isPreparing` true forever: no sensor session for the process, no error, and a Retry that did nothing. | `WatchSessionPreparation` (Shared, tested). After 15 s a stall shows an error + Retry, and a retry supersedes the stalled attempt. Superseded recovery callbacks do nothing. |
| A running session with no readings looked identical to "waiting" and had no remedy. | 30 s silence detection: the ring shows "NO HR ↓", the controls page explains Heart Rate read and fit. Retry restarts the sensor session (`lifecycle.restart()`) without ending the workout. |
| Watch-side failures were invisible to Copy Diagnostics. | `WatchSensorDiagnostics` (no BPM) is sent as a message and nested in application context. The phone prints Watch app/OS version, session state/mode, readings, too-old readings, last usable reading, acknowledgements, error, and a hint. Also adds "Phone workout active". |
| Health & Devices said "reachable · waiting for heart rate" when no workout was running. | Says "heart rate streams during a workout" unless a workout is expected. Shows a sensor-silent status when the Watch reports it. |
| Watch START used a cached reachability flag, so a stale `false` made a phone-led start Watch-only. | Reads WCSession live at START. |
| From 5.12, each five-second phone HR request re-announced the open calorie report (`transferUserInfo` + `sendMessage`). Every HR send also read the report from disk. | One announcement per report per launch. The energy-session start is cached in memory. |

## Validation

- 294/294 iOS unit tests pass (iPhone 17 simulator), including 9 new tests:
  lifecycle restart, preparation stall/supersede, diagnostics round trip and
  silence, malformed payloads, phone latest-only diagnostics + summary, idle
  vs expected HR, and Heart Rate in the read set.
- Watch app builds for the 40 mm SE simulator. `-demoState workout|controls
  -demoSensorSilent` screenshots checked: the cue fits, guidance scrolls.
- 5.15 release prep: same 294/294 unit tests, generic-device Release build
  with phone, Watch and Live Activity bundles all reporting 5.15, release
  tooling 6 tests / 21 assertions.
- **Not verified on a device** (no Watch available). Shipped without these;
  run them on the first 5.15 build available on a Watch:
  1. Turn N4x4 Heart Rate read off, start from the Watch: "NO HR" after about
     30 s. Copy Diagnostics shows the sensor-silent hint with 0 readings. Turn
     it back on, tap Retry: HR returns in the same workout.
  2. Normal phone-led and Watch-led workouts: HR streams, diagnostics show
     readings increasing, no extra Health workouts saved.
  3. Start Apple Workout during an N4x4 workout: error + Retry shown, and
     diagnostics say "stopped with an error".
  4. Calories still arrive for a normal workout (announcement de-duplication).

## Open

- Reply draft for the user: [`USER-REPLY-WATCH-HR.md`](USER-REPLY-WATCH-HR.md) (not sent).
- The 10 s Watch freshness rule is unchanged. The new "too old to use" counter
  will show whether late batches occur in the field before anyone relaxes it.
