# AGENTS.md — N4x4 Coding Agent Guide

Guidelines for AI agents working on this codebase. Derived from real bugs found in v2.0.

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

`N` = weekday integer (1–7, where 1 = Sunday).
`DD` = day of month (1–31).

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
| Re-adding manual `broadcastStateToWatch()` calls | The broadcast is reactive (see Apple Watch below) — don't hand-place it |

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
  `onChange`). HR only works on a physical Series 4+ Watch, never the Simulator.

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
  `saveWorkoutLogEntryAndResetSession`, cleared in `reset`.
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
