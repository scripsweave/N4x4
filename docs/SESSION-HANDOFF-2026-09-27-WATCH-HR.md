# Watch heart-rate delivery and adaptive workout screen

Branch: `fix/watch-heart-rate-and-layout`. Unreleased; version remains 5.4.
The branch includes the preceding App Store submission automation commit.
Do not push main without a new version: Xcode Cloud delivers every main push.

## Feedback and diagnosis

A user on 5.4 (40), iOS 27.0 reported the phone losing Watch heart rate while
the Watch still showed readings and the timer appeared synchronized. Watch
model and watchOS version are unknown. The exact device failure is unconfirmed.

The old Watch sender dropped readings whenever WCSession was unreachable and
ignored send errors. There was no resend on reconnect or foreground. The phone
also ignored the payload's measurement timestamp. A synchronized countdown does
not prove a working live connection: the Watch projects the phone's timer locally.

## Delivery changes

- `Shared/WatchHeartRateStream.swift` contains a pure, injected transport policy
  and timestamp-validating inbox. It compiles into both shipping targets.
- Retain only the latest fresh reading; retry a failed live send once after
  two seconds and fall back to latest-only application context. Never enqueue
  live readings via transferUserInfo. Application context is opportunistic,
  not a guaranteed real-time channel.
- Resend fresh HR on activation, reconnect, Watch foreground, or a phone refresh
  request. Phone foreground also consumes cached context and asks for fresh HR.
- Keep the HealthKit measurement date, reject duplicates/out-of-order/stale
  deliveries, and expire readings ten seconds after measurement, not receipt.
  Allow up to two seconds of future clock skew; clamp to receipt before ingestion.
- Generation guards prevent old send failures/retries overwriting newer data.
  Session/builder identity guards and stop/reset cancel abandoned callbacks.
- Everything still enters the VM's HR funnel. Configurable source priority,
  single phone Health saver and explicit Watch builder discard remain intact.

## Adaptive Watch UI

Layout responds to available width, not model names. Below 184 pt, the larger
ring contains the coaching cue. Wider displays put the cue below and show the
numerical target inside the ring. The passive display uses available space near
the bottom; the controls page retains its usual safe area and native scrolling.
Countdown and live HR scale with the ring. The central stack is inset from
the curved bezel, with narrower lower rows and tighter font line boxes so
target text has more clearance from the ring. Paused sessions no longer say
"Speed up". Explicit VoiceOver labels identify countdown and live HR.

DEBUG screenshot mode accepts `-demoHeartRate 0` (or a valid BPM) with
`-demoState workout|paused|controls`; no sensor or HealthKit session is started.

Design review using the ios-hig-design rubric: 7/10 provisionally. Layout,
dark presentation, native controls/gestures and SF Symbols are retained and
reviewed. To reach 10/10, add a full Dynamic Type layout (the ring still uses
proportional fixed fonts and the existing palette) and complete physical Watch
VoiceOver task testing. This is not a claim of full accessibility certification.

## Verification

- Xcode Watch scheme build passed, including phone/Watch/Live Activity targets.
  `/tmp/N4x4-watch-feedback-build.log`, derived data `/tmp/N4x4-watch-feedback-build`.
- 49 selected tests passed: WatchHeartRateStreamTests (10 new transport/inbox
  regressions), HeartRateAggregatorTests, WatchStandaloneTests.
  `/tmp/N4x4-watch-feedback-tests.xcresult` and matching `.log`.
- Simulator layout inspection: 40 mm SE, 44 mm SE, 46 mm Series 11 and 49 mm
  Ultra, watchOS 26.5. Workout, paused, missing HR and controls states checked.
  Final previews are in `~/Desktop/N4x4 Watch Review/`.
- `git diff --check` and project plist validation passed.

Still needs a physical paired Watch/iPhone workout: test with phone locked,
wrist lowered, both apps foregrounded again, and a temporary loss of connection.
Verify latest HR resumes, old readings clear, other HR source priorities work,
and only one workout is saved in Health. Simulator demo HR cannot validate
radio delivery, background HealthKit callbacks, or the user's iOS 27 setup.

Apple transport reference:
https://developer.apple.com/documentation/watchconnectivity/wcsession
