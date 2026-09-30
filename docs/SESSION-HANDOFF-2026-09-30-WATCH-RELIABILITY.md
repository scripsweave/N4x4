# Watch heart-rate reliability investigation — 30 September 2026

User authorized a detailed investigation and fixes after Gowen reported that
5.5 still loses Watch heart rate with the iPhone app open. The Watch displays
heart rate and an iPhone-disconnected icon; the phone can report connected but
waiting for HR. Reported hardware/software: Series 11, watchOS 27; original
phone feedback was iPhone13,1 on iOS 27.

Work is on `fix/watch-session-reliability`, based on the existing uncommitted
Health HR export feature. That feature remains intact. After the investigation,
the user authorized version 5.7, commit and App Store release. See the main
session handoff for current release status.
The pre-investigation tracked diff is `/tmp/N4x4-before-watch-reliability.patch`.
Private user screenshots and Xcode local-user files remain untouched/untracked.

## Confirmed defects and corrections

| Finding in shipped code | Correction |
| --- | --- |
| Root considered nonzero intervalDuration an active workout. Idle phone payloads contain the upcoming interval duration, so simply opening the Watch could start a sensor workout. | Require sessionStarted and not workoutComplete. Paused, genuinely started workouts retain their sensor session. |
| Root startup could race asynchronous recoverActiveWorkoutSession cleanup, which could end the newly started session. | Authorization, recovery, and ending/discarding a recovered session complete before the latest requested workout may start. |
| A new workout could arrive while an old session was ending; isSessionActive alone could lose the new start or allow overlapping sessions. | Pure token-bound WatchWorkoutSessionLifecycle serializes desired workout IDs and waits for .ended. Old callbacks cannot end a newer logical session. |
| Send failures wrote the failed timer payload into application context, potentially replacing a newer pause/end/reset. Cross-channel delivery was unordered. | Update context with current state before live send. Never mutate context in an error callback. Persist a monotonic revision with wall-time baseline; reject duplicate/older state on Watch. |
| HR sends had no acknowledgement or timeout. Multiple readings could accumulate behind delayed callbacks; false reachability only cached a reading with no retry. | Coalesce pending readings, await an explicit timestamp acknowledgement, time out after two seconds, and allow one retry. Fall back to newest-only context. Late completions are token-guarded. Retry a transient unreachable result; phone also requests fresh HR every five seconds while an expected stream is missing. |
| Watch BPM stayed visible indefinitely after callbacks stopped. | Clear stale readings after ten seconds and refresh expiry on foreground. Error/ended sessions show an error and a Retry Heart Rate action in controls. |
| Watch recording/haptics used SwiftUI onChange of BPM, dropping equal-valued new readings and depending on view updates. | Root installs a direct per-sample callback into the Watch manager, using the original measurement date. |
| Live HR had no workout identity, so a fresh late packet could enter a different phone workout. | Modern packets carry workoutID; phone rejects another active workout's ID. Legacy packets remain compatible. |
| Phone recorder timestamped delivery, and a lower-priority callback could record an older preferred reading again. | Record the selected aggregator sample with its original measurement date. Skip pre-resume samples; the recorder deduplicates by its existing time buckets. |
| Watch help used the selected HR value, potentially calling Bluetooth HR Watch data, and blamed permission when reachable but missing HR. | Use Watch freshness separately. Explain reachability vs receiving data; interrupted streams get connection/diagnostic guidance. |

## Invariants and recovery limits

- All HR still enters TimerViewModel's existing aggregator; user priority is
  unchanged. Ten-second freshness remains measured from the sensor timestamp.
  Duplicate acknowledgements never refresh an old reading or record it twice.
- No live HR or controls are queued through transferUserInfo. Completed Watch
  records keep the existing durable import/ack path.
- The phone remains the timer authority in mirror mode. Standalone Watch mode
  remains decided at start. No mid-workout leadership change was introduced.
- Watch and AirPods live builders still discard; the phone Health export queue
  remains the single saver. New sensor lifecycle code discards old builders on
  ended/failure as well as during recovery.
- Unexpected sensor-session end/failure does not automatically fight another
  workout app. Retry happens on Watch foreground or Retry Heart Rate. Preparation
  errors remain visible and do not trigger repeated permission prompts per tick.
- Context delivery is opportunistic, not guaranteed real-time. An actual radio
  outage still prevents live HR; the app must show loss and recover honestly.
- iPhone diagnostics add accepted/rejected counts, packet age, measurement age,
  and rejection reasons, never BPM values. Reading cached application context
  is not misreported as a new packet arriving from the Watch.

## Transport decision

Apple documents WatchConnectivity reachability during an active background
workout; losing/accidentally ending that sensor session is directly relevant to
this failure path. This change fixes the concrete lifecycle/transport defects
without introducing HealthKit mirroring simultaneously. Mirroring remains a
possible follow-up, not a claimed fix or a guarantee against radio failures.
It would require lifecycle testing with the existing iPhone AirPods session,
standalone mode, and reconnect-created mirrored sessions.

References: [WatchConnectivity reachability](https://developer.apple.com/documentation/watchconnectivity/wcsession/isreachable),
[workout mirroring disconnect/reconnect](https://developer.apple.com/documentation/healthkit/hkworkoutsessiondelegate/workoutsession(_:diddisconnectfromremotedevicewitherror:)).
The installed watchOS SDK's HKHealthStore.h confirms recovery returns nil when
no abandoned session exists, and supplies a separate error for actual failure.

## Verification

Final validation:

- **227 unit tests passed**, zero failures, including 16 additional tests across
  delivery, lifecycle/ordering, and phone receipt/recording. Final artifact:
  `/tmp/N4x4-watch-reliability-final-result.xcresult`, corresponding `.log`.
- **Two UI checks passed** on iPhone SE 3 / iOS 26.5: Health & Devices opens
  without permission prompts, and largest Dynamic Type/search navigation works.
  These are the UI results in `/tmp/N4x4-watch-reliability-verified.xcresult`.
  That earlier combined bundle also contains unit assertion failures; the final
  unit artifact above supersedes those. Timestamp round-trip assertions now
  allow sub-microsecond precision loss and use a whole-second test clock for
  exact expiry-boundary checks.
- **Unsigned Release build passed**, including iPhone, Watch (arm64/arm64_32),
  and Live Activity: `/tmp/N4x4-watch-reliability-release-final.log`.
- **Watch Simulator build passed**:
  `/tmp/N4x4-watch-reliability-watch-final.log`.
- Project plist validation and `git diff --check` passed. The 40 mm Watch
  simulator used for inspection was shut down afterward; the previously running
  Ultra simulator was left alone.

Pure tests inject transport replies/timeouts, clocks, and lifecycle completion;
they do not exercise a physical Watch radio or HealthKit sensor. Simulator and
SDK version is 26.5, not the user's OS 27.

Small-Watch controls screenshot: `/tmp/N4x4-watch-reliability-controls.png`.
Controls remain scrollable on the 40 mm simulator with the new delivery status.

Outstanding physical-device validation (user authorized release with this limitation
known): use a paired Series 11 and iPhone on OS 27:

1. Open Watch with phone idle: no sensor workout starts. Start, pause/resume,
   finish, then immediately start another workout. HR resumes for the new ID.
2. Keep phone open and lower wrist; repeat with phone locked. Confirm fresh HR
   continues, and confirm loss is displayed if the sensor stops producing data.
3. Briefly separate devices or disable their connection; reconnect without
   restarting apps. Fresh HR returns, stale data never appears as new.
4. Relaunch Watch during an active session to exercise abandoned cleanup. Start
   Apple Workout separately to verify N4x4 doesn't continually restart over it.
5. Run standalone Watch and Bluetooth-priority sessions; verify recording, later
   import, and exactly one saved Health workout.
6. If a dropout persists, copy Health & Devices diagnostics while it is occurring
   and note the Watch controls' delivery status/error and whether BPM changes.

No physical devices were connected (`devicectl list devices`: none). Gowen's
precise cause is unconfirmed; these are code-supported fixes, not an on-device
reproduction or certification of OS 27 behaviour.
