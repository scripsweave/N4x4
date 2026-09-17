# AGENTS.md — N4x4 Coding Agent Guide

Guidelines for AI agents working on this codebase. Derived from real bugs found in v2.0.

**Start here:** [`docs/SESSION-HANDOFF.md`](docs/SESSION-HANDOFF.md) always points
at the current session handoff, which is where "what changed last and what is
still unverified" lives. Feature docs worth reading before touching their area:
[`Birthday-Easter-Egg.md`](docs/Birthday-Easter-Egg.md) (the 2 August egg — has
locked design decisions, don't re-litigate them casually),
[`Bluetooth HR Monitor Plan.md`](docs/Bluetooth%20HR%20Monitor%20Plan.md),
[`Watch App - HR Zone Feedback Handoff.md`](docs/Watch%20App%20-%20HR%20Zone%20Feedback%20Handoff.md).

---

## Architecture Essentials

- **Single ViewModel**: All business logic lives in `TimerViewModel.swift`. Views are thin.
- **Persistence**: `@AppStorage` for settings/streaks; JSON string in UserDefaults for workout log (`workoutLogEntriesData`).
- **No external dependencies** — only Apple frameworks (SwiftUI, Combine, AVFoundation, UserNotifications, HealthKit).
- **Audio**: `TimerViewModel` owns `var player: AVAudioPlayer?` directly. Do not introduce a separate audio singleton.

---

## Async / Threading Rules

### Never call async-result code synchronously and expect it to be ready

`UNUserNotificationCenter.getNotificationSettings` and `requestAuthorization` deliver their
results on the main queue via a completion block — they return *immediately*, before the result
is available.

**Wrong pattern (causes silent failures):**
```swift
refreshNotificationPermissionState()           // returns instantly
scheduleWorkoutReminder()                       // notificationPermissionState is still .unknown
```

**Correct pattern:**
```swift
refreshNotificationPermissionState { [weak self] in
    guard let self else { return }
    // notificationPermissionState is now current
    self.scheduleWorkoutReminder()
}
```

The same applies to any `HealthKit` authorization call. Always place downstream work in
completion blocks, not immediately after the initiating call.

---

## Notification System

### Identifier naming scheme

| Type | Identifier pattern | Repeats | Cancelled by |
|------|--------------------|---------|--------------|
| Night-before weekly | `workoutReminder_N` | ✅ weekly | `cancelAllWeeklyReminders()` |
| Morning-of weekly | `workoutReminderMorningOf_N` | ✅ weekly | `cancelAllWeeklyReminders()` |
| One-shot daily follow-up | `workoutReminderFollowup_N_daily_DD` | ❌ | `cancelMissedWorkoutFollowUpReminder(for:)` |
| Interval cue | `nextInterval` | ❌ | Explicit remove before each reschedule |
| Birthday nudge (2 Aug, everyone) | `birthdayNudge_0802` | ✅ yearly | Never — re-registered on foreground |
| Birthday nudge (user's own) | `birthdayNudge_user` | ✅ yearly | Removed when the user's birthday IS 2 Aug |

`N` = weekday integer (1–7, where 1 = Sunday).
`DD` = day of month (1–31).

The two birthday nudges (06:00 local, `BirthdayEasterEgg.scheduleMorningNudges`)
sit **outside** the `workoutRemindersEnabled` families on purpose: they fire once
a year and they are the only thing that stops the easter egg being missed by a
phone that stays in a pocket all day. They still require notification permission
and never request it.

### Always cancel the full identifier family

When cancelling follow-up notifications, cancel **all** variants — both the base identifier
and the `_daily_DD` one-shot identifiers for days 1–31. Cancelling only the base identifier
leaves up to 31 stale notifications in the system that continue to fire.

```swift
// WRONG — only cancels the base ID:
UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["workoutReminderFollowup_2"])

// CORRECT — cancel base + all daily variants:
var ids = ["workoutReminderFollowup_2"]
for day in 1...31 { ids.append("workoutReminderFollowup_2_daily_\(day)") }
UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
```

### Use repeating calendar triggers for recurring reminders

For anything that should fire weekly, use `UNCalendarNotificationTrigger` with
`repeats: true` and a `DateComponents` that specifies only weekday/hour/minute (no year/month/day).
One-shot date-based triggers work only once and require the app to launch to reschedule them.

### Notification content is baked in at scheduling time

`UNCalendarNotificationTrigger` with `repeats: true` uses the content set at the moment
`UNUserNotificationCenter.current().add(request)` is called. All future repetitions of that
request deliver the same title/body. If you want to vary the message (e.g., random motivational
strings), you must replace the notification request (same identifier, new content) on each
app foreground — or use a `UNNotificationServiceExtension`.

### The 64-notification system limit

iOS caps pending notifications per app at 64. With multiple workout days and up to 6 daily
follow-ups each, it is easy to approach this limit. Always cancel old notifications before
adding new ones; never accumulate without cleaning up.

### `scheduleNotification` helper is for interval cues only

The shared `scheduleNotification(identifier:title:body:in:repeats:)` helper guards on
`notificationsEnabled`. Do not route workout reminder scheduling through it — use
`UNUserNotificationCenter.current().add()` directly (as the existing reminder functions do).

---

## Workout system cleanup (5.2+)

- All `nextInterval` add/cancel operations go through TimerViewModel's serialized
  task and generation token. Never call `UNUserNotificationCenter.add` directly
  for interval cues: an in-flight add can otherwise outlive End or pause.
- `stopTimer()` cancels interval cues; End/reset/completion also end Live
  Activities. Cancel pending **and delivered** interval alerts, without touching
  weekly reminders or birthday nudges.
- Live Activity updates/end requests are ordered. End captures **all current
  app activities synchronously**, including orphans, before awaiting anything.
  Enumerating activities inside a launch cleanup task can accidentally capture
  and end a newly started workout. Pause retains a paused activity.
- Tests inject system boundaries and suspend adds/updates to exercise these
  races; keep lifecycle logic in TimerViewModel.

---

## Streak Calculation

### Use `.yearForWeekOfYear`, not `.year`

ISO week numbering means Dec 29–31 can belong to week 1 of the *following* year. If you
use `.year` for the calendar year and `.weekOfYear` for the ISO week, they will disagree
on those dates, silently corrupting year-boundary streak counts.

```swift
// WRONG:
Calendar.current.component(.year, from: date)

// CORRECT:
Calendar.current.component(.yearForWeekOfYear, from: date)
```

Both sides of any week-based comparison (`WorkoutLogEntry.year` and the `currentYear`
variable in `calculateCurrentStreak`) must use the same system.

### Some years have 53 ISO weeks

Years like 2020, 2026, 2032 have 53 ISO weeks. Never hardcode `52` as the last week of a
year. Use the dynamic lookup: `calendar.component(.weekOfYear, from: <Dec 28 of that year>)`.
Dec 28 is always in the final ISO week of its year — a reliable anchor.

### Stored streak vs calculated streak

`currentStreak` is persisted in `@AppStorage`. It must be refreshed against the live log
on every app launch and foreground — not just when a workout is completed. If you only update
it on workout completion you can only ever *increase* the stored value, meaning missed weeks
are never reflected until the user beats their old record.

Call `refreshStreak()` in `init()` (after `loadWorkoutLogEntries()`) and in `refreshOnForeground()`.

---

## Permission State Guards

Do not turn off user-facing toggles (e.g. `workoutRemindersEnabled = false`) when the
permission state is `.unknown` or `.notDetermined`. These states mean the async check hasn't
returned yet — the permission may well be granted. Only disable toggles when state is
definitively `.denied` or `.unavailable`.

---

## AppStorage ↔ @Published Sync

`workoutReminderWeekdays` (`@AppStorage` String) and `selectedWeekdaysList` (`@Published [Int]`)
are kept in sync via a `isSyncingFromPublished` flag. If you add new properties that need the
same pattern:

1. Set `isSyncingFromPublished = true` before writing to `@AppStorage` from a `@Published` setter
2. Set `isSyncingFromPublished = false` immediately after
3. Guard the `@AppStorage` `didSet` with `guard !isSyncingFromPublished else { return }`

---

## Xcode Project File

When deleting a Swift file, also remove its entries from `N4x4.xcodeproj/project.pbxproj`:
1. `PBXBuildFile` section — `<uuid> /* Foo.swift in Sources */`
2. `PBXFileReference` section — `<uuid> /* Foo.swift */`
3. Group children array — `<uuid> /* Foo.swift */`
4. Sources build phase files array — `<uuid> /* Foo.swift in Sources */`

Failing to do this leaves a "missing file" red warning in Xcode but does not prevent building.

---

## Testing Notifications Without a Device

The notification system cannot be fully tested in the Simulator (push delivery is limited).
To verify:

1. Enable reminders in Settings, select workout days.
2. Check pending notifications with:
   ```swift
   UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
       requests.forEach { print($0.identifier, $0.trigger ?? "no trigger") }
   }
   ```
3. Confirm identifiers match the scheme above.
4. Use `UNCalendarNotificationTrigger` with a near-future time for manual spot-testing.
5. After logging a workout, verify daily follow-ups are cancelled by re-running step 2.

---

## Common Pitfalls Summary

| Pitfall | Rule |
|---------|------|
| Calling scheduling code after `refreshNotificationPermissionState()` returns | Always put scheduling in the completion block |
| Cancelling only the base notification ID | Also cancel all `_daily_DD` variants (days 1–31) |
| Using `.year` with `.weekOfYear` | Use `.yearForWeekOfYear` for both sides |
| Hardcoding `52` as the last ISO week | Use dynamic Dec-28 lookup |
| Only incrementing stored streak | Always recalculate from scratch; call `refreshStreak()` on launch and foreground |
| Disabling user toggles on `.unknown` permission | Only disable on `.denied` / `.unavailable` |
| Using `@ViewBuilder` on non-View functions | `@ViewBuilder` is only for `some View`-returning functions |
| Indexing a session draft array inside a SwiftUI `Binding` after reset | Guard the index inside BOTH the getter and setter. SwiftUI retains bindings during sheet dismissal even after the view's outer index check stops passing (autosave review tests caught an `IntervalCard` crash on Done) |
| Re-adding manual `broadcastStateToWatch()` calls | The broadcast is reactive (see Apple Watch below) — don't hand-place it |
| A particle cap checked as `count < cap` before appending a whole burst | Check `count + n <= cap`. The old birthday firework guard admitted a burst that then appended up to 210 sparks, so the documented 2600 ceiling was really 2809 (found 2026-07-25 by `testSparkCapHoldsUnderAContinuousShow`) |
| Additive "light spill" layers drawn over the object throwing the light | Clip the source out (`clip(to:options: .inverse)`). Laying the ball's own bloom over the ball washed the facets pale and the sphere lost its dark base |
| `min(0.05, now - last)` as a frame-delta clamp | Clamp both ends: `min(0.05, max(0, …))`. The clock does run backwards in the field (local-midnight zone change, NTP correction, the documented manual date edit for testing the egg) and a negative dt runs simulations in reverse |
| `PreferenceKey.reduce` that assigns `value = nextValue()` | Every sibling that doesn't set the preference contributes the default and overwrites the real value. Guard: `if next != defaultValue { value = next }` (found 2026-07-23: zeroed ball frame silently disabled four birthday-egg features at once) |
| Trusting `swiftc -parse` (Linux sessions) as a compile check | It misses access-control violations (public-ish member exposing a `private` type), lost tuple labels in array literals, and type-checker timeouts on large literal expressions. First Xcode build of parse-checked code needed 5 such fixes on 2026-07-23 — always budget a fix round |

---

## Apple Watch (WatchConnectivity)

> Status: integrated and shipping. The `N4x4Watch Watch App` target is a real
> watchOS application, embedded into the phone app and driven over
> WatchConnectivity. Background on the design lives in
> `docs/Watch App - HR Zone Feedback Handoff.md` and `docs/SESSION-HANDOFF.md`.

- **Phone is the source of truth.** It runs the timer and broadcasts state; the
  Watch renders and sends back commands + streamed heart rate. `Shared/` files
  (`WatchMessage.swift`, `ZoneFeedback.swift`, `ZoneFeedbackStyle.swift`) compile
  into **both** targets.
- **`intervalEndTime` is the sync anchor.** The Watch derives `timeRemaining`
  locally from the absolute end-time, so no per-second messages are needed — but
  **only while running**. When paused, the phone's authoritative `timeRemaining`
  is used (the Watch would otherwise count past the pause).
- **The state broadcast is reactive.** A debounced Combine subscription in
  `TimerViewModel.init()` observes `isRunning`, `currentIntervalIndex`,
  `highIntensityCount`, `showPostWorkoutSummary` and calls `broadcastStateToWatch()`.
  Do **not** sprinkle manual broadcast calls at mutation sites — that was the old,
  fragile pattern and was deliberately removed.
- **`WorkoutPhase` is the cross-target type.** Never put `IntervalType` in a
  WatchConnectivity message — it has no `rawValue`. `WorkoutPhase` is `Codable`.
- **Watch deployment target is watchOS 10.0** (the UI uses two-parameter
  `onChange` and `.tabViewStyle(.verticalPage)`). HR only works on a physical
  Series 4+ Watch, never the Simulator.
- **Watch lifecycle lives in the root, not a screen.** `WatchRootView`
  (`N4x4WatchApp.swift`) owns the HKWorkoutSession start/stop, interval and
  countdown haptics and the foreground re-sync, and routes on the phone's
  state: `workoutComplete` → `WatchCompleteView`, `sessionStarted` →
  `WatchTimerView`, else `WatchHomeView`. Never hang those `onChange`s on a
  screen view again — 4.16 did, and the screen was unmounted exactly when
  the final state arrived, so the session leaked and HR never started until
  the first interval boundary.
- **Watch design tokens mirror the phone.** `WatchTheme.swift` repeats
  `Palette` as `WatchPalette` plus `NeonRing` / `WatchTimelineBar` /
  `WatchPulsingHeart` / `WatchControlButtonStyle` (the iOS `Palette`,
  `MetalRing`, `IntervalTimelineBar` are iOS-target only). Change colours in
  both places together.
- **Home extras in the state payload:** `streak`, `planPhases`,
  `planDurations` (parallel arrays) let the Watch draw the streak header and
  the timeline bar. Defaults are safe for an older phone build.
- **Watch demo mode (DEBUG only):** launch the Watch app with
  `-demoState home|offline|workout|paused|controls|complete|local|localComplete`
  to see any screen in the Simulator with no phone and no HK session
  (`WatchDemoState`). Use it for layout checks on the 40 mm SE — it's the
  tightest screen. Relaunching with no arguments after `local` proves the
  Watch-led workout restores from disk.

## Standalone Watch workouts (4.18+)

- **Who leads is decided at START, never mid-workout.** Phone reachable →
  the phone's `TimerViewModel` leads exactly as before (mirror mode). Phone
  unreachable → the Watch runs `Shared/WatchWorkoutEngine.swift` itself
  (local mode). There is no hand-over in either direction; two engines
  leading the same workout was the failure mode to avoid.
- **The engine is pure Foundation and shared.** `WatchWorkoutPlan` /
  `WatchWorkoutEngine` / `CompletedWatchWorkout` compile into both targets
  and are tested in `N4x4Tests/WatchStandaloneTests.swift`. Absolute-time
  model: `reconcile(now:)` walks every boundary that has passed, so a
  suspended or relaunched app catches up. Add behaviour there, with a test.
- **Mirror mode projects.** Between phone messages (and with the phone out
  of range) `WatchTimerState.projected(at:)` advances the phone's last state
  through the synced plan so intervals, haptics and zone targets keep
  moving. The next phone message re-seeds it. The payload therefore carries
  the full plan plus per-phase targets (`planPhases`, `planDurations`,
  `workHRLow/High`, `recoveryHRLow/High`).
- **Controls are never queued.** `sendCommand` only uses `sendMessage` while
  reachable; the old `transferUserInfo` fallback is gone because a pause or
  reset landing minutes later is a hazard. Offline in mirror mode the
  controls are disabled and END merely stops showing the phone's workout.
- **Watch-led state persists.** The live engine is written to UserDefaults
  (`watchLocalEngine`, boundaries immediately, HR samples throttled to 30 s)
  and restored in `WatchSessionManager.init`. The cached plan
  (`watchCachedPlan`) is what a standalone run uses; `WatchWorkoutPlan.fallback`
  is the protocol default for a Watch that has never synced.
- **Completed records sync via `transferUserInfo` and stay pending until
  acked.** `pendingWorkouts` (`watchPendingWorkouts`) is flushed on
  completion, activation, reachability and foreground, skipping ids already
  in `outstandingUserInfoTransfers`. The phone (`WatchWorkoutImport.swift`)
  imports idempotently by record id, remembers discarded ids, and always
  acks — even for duplicates — so the Watch queue drains.
- **The Watch still never saves to Health.** The phone's
  `saveWorkoutToHealthKit(start:end:)` writes the imported workout with the
  Watch's real start/end. Keep the single-saver rule.

## Heart-rate zone feedback

- The decision logic lives once in `Shared/ZoneFeedback.swift` (pure Foundation,
  testable): grace window, sustained-deviation debounce, one-alert-per-minute.
  Both devices run their own engine instance (Watch → haptics, phone → voice) so
  the rules never drift.
- Presentation (hint strings + status colour) lives in `Shared/ZoneFeedbackStyle.swift`
  (`ZoneFeedbackCopy.hint`, `HRZoneStatus.tint`). Keep logic and presentation split.

## Performance logging

- `WorkoutLogEntry` gained optional `modality` and `intervalPerformances`. They
  are **optional on purpose**: synthesized `Codable` decodes missing keys as nil,
  so older logs load untouched. Follow this pattern for any new entry field.
- Values are stored **canonically** (speed in km/h) and converted for display via
  `usesImperialUnits` + `PerformanceUnits`. Never persist display-unit values.
- The metric per modality comes from one place: `TrainingModality.performanceMetric`.
  Modality is derived from the user-facing Type picker via
  `WorkoutType.trainingModality` (one picker, not two). Add new metrics there.

## Bluetooth heart rate monitors (Core Bluetooth)

- All CoreBluetooth code lives in `N4x4/Bluetooth/BluetoothHeartRateManager.swift`
  — nothing else may import CoreBluetooth. The packet parser
  (`HeartRateMeasurementParser`) and source arbitration (`HeartRateAggregator`)
  are pure Foundation and unit-tested in `N4x4Tests/HeartRateBluetoothTests.swift`.
- **Never instantiate `CBCentralManager` at launch for users who haven't paired
  a monitor** — creating it is what fires the system Bluetooth permission
  prompt. `startIfRemembered()` is the only launch-time entry point and no-ops
  without a remembered device.
- **One HR funnel**: every source calls
  `TimerViewModel.ingestHeartRate(_:from:)`. Do not write `currentHeartRate`
  directly — the aggregator (BLE beats Watch, 10 s staleness window) is the only
  thing allowed to decide the displayed value, and the staleness sweep
  (`scheduleHeartRateStalenessSweep`) is what clears frozen readings.
- **The strap connection is independent of the workout lifecycle.** Never
  disconnect on workout end/reset; a pending `connect()` is free and completes
  when the strap is worn. Only `forgetMonitor()` (user action / settings reset)
  disconnects.
- Readings with the sensor-contact bit reporting "no contact" must never reach
  the funnel (`HeartRateReading.isUsable`) — they are garbage and fire false
  zone alerts.
- User-initiated disconnects are tracked per peripheral identifier
  (`userInitiatedDisconnects: Set<UUID>`), consumed **before** the
  current-peripheral guard — a plain bool gets stranded when callbacks arrive
  out of order and silently kills auto-reconnect.

---

## Heart-rate session recording (post-workout charts)

- All in `N4x4/HeartRateSeries.swift`: `HeartRateSeriesRecorder` (accumulates
  2 s-bucketed samples + the interval timeline as it actually happened),
  `HeartRateSeries` (the persisted document), `HeartRateSeriesAnalytics` (pure
  in-zone %, time-to-zone, summary), and `HeartRateSeriesStore` (one JSON file
  per workout under Application Support, keyed by the log-entry UUID).
- **The full series is NOT in the UserDefaults log blob** — only a small
  `HRSessionSummary` (avg/max, work in-zone %, 40-pt sparkline) lives inline on
  `WorkoutLogEntry`. ~840 samples/session would balloon the blob and slow every
  history render. Keep it that way.
- Recorder lifecycle is wired in `TimerViewModel`: created on workout start,
  `recorderBeginCurrentInterval()` on every interval advance (start +
  `moveToNextInterval` + the multi-advance path in `reconcileTimerState`),
  sealed into `completedSeries` in `finishWorkout`, saved in
  that same completion path before showing the summary, cleared in `reset`.
- **Completed workouts save automatically.** `completedWorkoutEntryID` keeps
  review edits attached to the original entry; `completeWorkoutReview()` must
  never insert a second workout. `reset()` keeps saved workouts. Only an
  explicit deletion (`deleteCurrentWorkoutAndResetSession()` or
  `deleteWorkoutLogEntry(id:)`) removes them.
- Always persist the series, even without enough HR samples for
  `HRSessionSummary`. The interval timeline is useful without a monitor.
- Both summary sheets call `postWorkoutSummaryDidDismiss()` so swipe dismissal
  preserves review edits and follow-up sheets wait until dismissal completes.
- UI is `N4x4/SessionDetailViews.swift` (charts, interval pager, share card),
  shared by `PostWorkoutSummaryRedesignView` and history's `SessionDetailSheet`.
- Pure logic is unit-tested in `N4x4Tests` (`HeartRateSeriesTests`).

## Zone colour is shared, and instant

- The one source of truth for zone colour is `HRZoneStatus.tint` in
  `Shared/ZoneFeedbackStyle.swift`: **orange = below zone, red = above, green =
  in zone.** Phone (`HomeWorkoutRedesign.swift`), legacy `TimerView`, and watch
  (`WatchTimerView.swift`) all read it, so they can't drift. Change the mapping
  in one place only.
- The **colour is instant** (computed from the current reading). The
  spoken/haptic nudges are debounced/sustained-deviation — do not conflate them
  in copy or code.

## Background audio (voice prompts under lock)

- `Info.plist` `UIBackgroundModes` includes `audio`. `SpeechManager` keeps the
  app alive during a workout with a zero-volume in-memory silent loop
  (`.mixWithOthers`), started/stopped from `TimerViewModel`
  (start/resume → `beginWorkoutAudio`, pause/finish/reset → `endWorkoutAudio`).
  Without this iOS suspends the app and cues never fire with the screen locked.
  Teardown defers to the speech-finished callback so the final "workout
  complete" phrase isn't cut off.

## Releasing & versioning (Xcode Cloud)

- **Xcode Cloud builds and delivers to App Store Connect on every push to the
  branch it watches (`main`)** — configured in App Store Connect, not in the
  repo. Assume every push to `main` attempts an App Store delivery.
- Once a version is submitted/approved its train closes; re-uploading the same
  `MARKETING_VERSION` is rejected (ITMS-90186 / ITMS-90062). Bump the version
  **in all 6 shipping configs** (app, watch, Live Activity × Debug/Release) in
  `project.pbxproj` for a release, and never reuse a number once uploaded.
- Apple compares version components **numerically**: `4.21` > `4.9`. Avoid
  leading zeros and decimal-style thinking.
- Recommended: move the workflow trigger to tag-based (`v*`) so routine commits
  (docs/website/assets) don't ship. Not yet done as of 2026-07-20.

## App icon (case-sensitive CI)

- The app-icon file must match `AppIcon.appiconset/Contents.json` **exactly by
  case**. Local macOS is case-insensitive so a mismatch builds fine, but Xcode
  Cloud checks out case-sensitively and the archive ships with no icon
  (ITMS-90022 / ITMS-90713). Keep tracked asset filenames case-correct.

## Workout types vs the protocol name (4.6+)

- **"Norwegian 4x4" is the protocol, never a workout type.** The
  `WorkoutType.norwegian4x4` case exists only so pre-4.6 logs decode; every
  picker must use `WorkoutType.selectableCases`, not `allCases`.
- The default workout type (`defaultWorkoutTypeRaw`) and the guidance modality
  (`preferredModalityRaw`) must stay in sync — always change them through
  `setDefaultWorkoutType(_:)` / `setPreferredModality(_:)`, never raw.

## Reminder family toggles (4.6+)

- Three per-family flags (night-before / morning-of / comeback nudges) sit
  under the `workoutRemindersEnabled` master. **Invariant: master == any
  family on.** It's maintained by a one-time migration
  (`reminderFamilyFlagsSynced`), `raiseFamilyFlagsIfAllOff()` in the master's
  didSet, and explicit alignment in `resetSettingsToDefaults`. If you add a
  path that sets the master directly, keep the invariant or the Settings
  toggles will lie.
- Each scheduler family guards on its own flag (`scheduleWeeklyWorkoutReminder`,
  the morning-of block in `scheduleMissedWorkoutFollowUpReminder`,
  `scheduleRecurringFollowUp`). Rescheduling always cancels the full
  identifier family first (see the notification table above).

## Haptics are their own channel (4.6+)

- Interval haptics are independent of `audioMode` and fire on BOTH iPhone and
  Watch (`hapticsEnabled`, mirrored to the Watch as `intervalHapticsEnabled`).
- Pattern: two short taps at T-3s/T-2s (tick path in `reconcileTimerState`),
  one long CoreHaptics buzz when a NEW interval starts, taps only at workout
  end (no completion buzz). Don't reintroduce a buzz at completion without
  Jan's say-so — the taps-only ending is deliberate spec.

## Heart-rate source arbitration (4.7+)

- `HeartRateAggregator` owns ALL source arbitration; its `priority` array is
  user-configurable (Settings → Heart Rate Sources, stored raw
  `hrSourcePriorityRaw`). Never hardcode "bluetooth wins" outside it.
- AirPods Pro 3 stream ONLY via the iOS 26 iPhone `HKWorkoutSession`
  (`PhoneWorkoutSessionManager`, @available(iOS 26)) — they do not broadcast
  standard Bluetooth HR (Powerbeats Pro 2 do).

## One workout per session in Apple Health (4.8+)

- `saveCompletedWorkoutToHealthKit()` (phone, in `finishWorkout`) is the ONLY
  place a workout is saved. Both live `HKWorkoutSession`s (watch
  `WorkoutManager`, phone `PhoneWorkoutSessionManager`) exist purely to stream
  heart rate.
- **Ending a session is NOT enough to prevent a save** — on-device, watchOS
  finalizes an ended-but-unfinished live builder as a workout (found 2026-07-22
  as duplicate watch+phone entries in Health). Every live builder must be
  explicitly `discardWorkout()`ed on `.ended` AND on `didFailWithError`.
- The watch also discards crash-abandoned sessions at launch
  (`discardAbandonedSession()` via `recoverActiveWorkoutSession`) so they can't
  resurface as stray workouts. Keep that call in `N4x4WatchApp.onAppear`.

## Editing project.pbxproj by hand

- Only the Watch app folder is a synchronized group; **iOS-target files need
  explicit pbxproj entries** (PBXBuildFile, PBXFileReference, group child,
  Sources build phase). The repo already uses hand-made synthetic UUIDs
  (`C4E0…`, `5EA1…`, `3DFEED…`, `5E52…`) — follow that pattern and keep the
  four entries consistent.

## Marketing screenshot system (4.7+)

- Every phone card wears the iPhone 16 Pro-style frame. Cropped-at-bottom
  cards get it in CSS (`make-summary-screenshot.html`,
  `make-hr-sources-screenshot.html`); the full-body composed cards (01/02/04)
  get it painted by `AppStore/make-iphone-frame.py`. Change the geometry in
  both places together, and keep mockups matching the real UI (05 ↔
  `PostWorkoutSummaryRedesignView`).
- **Headless Chrome clamps its window to ~500×500 minimum.** Any render
  smaller than that (all watch sizes) lays out for a 500px viewport and gets
  cropped — content lands off-centre/clipped. Always render at 2× with
  `--force-device-scale-factor=2` and `sips` down (commands in
  `AppStore/README.md`).
- `assets/watch-ultra-framed.png` is built ONLY by `AppStore/make-framed-watch.py`
  (flood-fill mask of the frame's screen opening; face can't poke past the
  bezel). Never hand-composite with cutout percentages. After a face change,
  re-run it, then `make-watch-screenshot.py` (03) and the 06 render + 6.7in
  resizes.
