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
