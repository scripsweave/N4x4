# Version 2.0 Fixes

Post-release code review fixes applied after v2.0 launch. Issues identified by static analysis
and manual review; no user-facing crashes were reported but several notification paths were
completely non-functional and streak values were stale.

---

## Notification Fixes

### N1 — CRITICAL: Reminders never actually scheduled on app launch

**File:** `TimerViewModel.swift` — `init()`

**Problem:** `refreshNotificationPermissionState()` is async — it dispatches to the main queue
via a completion block. Both `rescheduleRemindersOnAppLaunch()` and `scheduleWorkoutReminder()`
were called synchronously immediately after it returned, so `notificationPermissionState` was
still `.unknown` at the point of the call. Every permission guard failed silently. The weekly
repeating night-before reminder persisted in the system (set up once at onboarding), but the
morning-of and all daily follow-up notifications never worked after the first launch.

**Fix:** Moved `rescheduleRemindersOnAppLaunch()` and `scheduleWorkoutReminder()` into the
completion block of `refreshNotificationPermissionState()`, where the state is current.
Also added `refreshOnForeground()` which uses the same pattern for foreground re-entry.

---

### N2 — HIGH: Daily follow-up notifications accumulated and were never cancelled

**File:** `TimerViewModel.swift` — `cancelMissedWorkoutFollowUpReminder(for:)`

**Problem:** `scheduleRecurringFollowUp` created notification identifiers in the form
`workoutReminderFollowup_N_daily_DD` (where DD = day of month). The cancel function only
cancelled the base identifier `workoutReminderFollowup_N`. So:
- When a workout was logged, the daily nag notifications remained scheduled and kept firing
- On every launch/foreground, new daily notifications were stacked on top of old ones
- The iOS per-app limit of 64 pending notifications could be reached, silently dropping later
  scheduled notifications (including the important weekly repeating ones)

**Fix:** `cancelMissedWorkoutFollowUpReminder` now builds the full set of `_daily_1` through
`_daily_31` identifiers and cancels them in one batch call alongside the base identifier.

---

### N3 — MEDIUM: Reminder message content is static (cosmetic)

**File:** `TimerViewModel.swift` — `scheduleWeeklyWorkoutReminder(weekday:)`

**Problem:** `UNCalendarNotificationTrigger` with `repeats: true` bakes the notification content
in at scheduling time. Every future occurrence delivers the exact same randomly-chosen message.

**Status:** Accepted limitation. Cannot be fixed without a `UNNotificationServiceExtension`.
Partially mitigated by N4 fix below, which now replaces the morning-of content on each
foreground via `refreshOnForeground()`.

---

### N4 — MEDIUM: Morning-of reminder was a one-shot trigger that never repeated

**File:** `TimerViewModel.swift` — `scheduleMissedWorkoutFollowUpReminder(forScheduledWeekday:)`

**Problem:** The morning-of (8 AM on workout day) notification used a one-shot
`UNCalendarNotificationTrigger(repeats: false)` anchored to a specific date. Since the
rescheduling on launch was broken (N1), this notification effectively fired at most once — for
the first upcoming workout after setup — and never again.

**Fix:** Changed to a weekly repeating `UNCalendarNotificationTrigger` (weekday + hour + minute,
`repeats: true`), stored under the new identifier `workoutReminderMorningOf_N`. This identifier
is separate from the daily follow-up base, allowing independent cancellation:
- Morning-of repeating: cancelled only when the user disables all reminders (`cancelAllWeeklyReminders`)
- Daily follow-ups: cancelled when a workout is logged (`cancelMissedWorkoutFollowUpIfCompletedToday`)
The content is refreshed on each foreground (via `rescheduleRemindersOnAppLaunch` →
`scheduleMissedWorkoutFollowUpReminder`), rotating the random message.

`cancelAllWeeklyReminders` updated to also cancel `workoutReminderMorningOf_N` identifiers.

---

### N5 — MEDIUM: `scheduleRecurringFollowUp` checked workout status on a future date

**File:** `TimerViewModel.swift` — `scheduleRecurringFollowUp(from:weekday:)`

**Problem:** The function called `hasLoggedWorkout(on: scheduledDate)` where `scheduledDate`
was always the *next future occurrence* of the workout weekday. You can't have logged a
workout in the future, so this check was always `false` — dead code that never prevented
unnecessary follow-up scheduling.

**Fix:** Replaced with: "if today IS a workout day and the user already logged one, return early."
This is the actually useful guard — it prevents scheduling follow-ups on the rare occasion the
user opens the app after completing their workout on a workout day.

---

### N6 — LOW: `scheduleNotification` guard mixed interval and reminder flags

**File:** `TimerViewModel.swift` — `scheduleNotification(identifier:title:body:in:repeats:)`

**Problem:** The guard was `notificationsEnabled || workoutRemindersEnabled`. This function is
only used for in-workout interval cues (`scheduleNextIntervalNotification`). The `||` meant
interval cues would fire even when the user had explicitly disabled them, as long as workout
reminders were on.

**Fix:** Changed guard to `notificationsEnabled` only.

---

## Streak Fixes

### S1 — HIGH: `currentStreak` in AppStorage was never decremented

**File:** `TimerViewModel.swift` — `updateStreakOnWorkoutComplete()`, `init()`, `refreshOnForeground()`

**Problem:** `updateStreakOnWorkoutComplete` only ever *increased* `currentStreak`. If a user
built a 5-week streak and then missed two weeks, the app still displayed 5. The value would
only update if the user completed enough new workouts to exceed the stale number.

**Fix:**
- `updateStreakOnWorkoutComplete` now unconditionally sets `currentStreak = calculateCurrentStreak()`
- New `refreshStreak()` method recalculates and syncs on demand
- Called in `init()` after `loadWorkoutLogEntries()` so the first frame is always correct
- Called in `refreshOnForeground()` so the value is fresh each time the user opens the app

---

### S2 — HIGH: ISO week year / calendar year mismatch at year boundaries

**File:** `TimerViewModel.swift` — `WorkoutLogEntry.year`, `calculateCurrentStreak()`

**Problem:** `WorkoutLogEntry.year` used `Calendar.current.component(.year, ...)` while
`WorkoutLogEntry.weekOfYear` used `Calendar.current.component(.weekOfYear, ...)`. The ISO week
calendar means Dec 29–31 can belong to week 1 of the *next* year. Example: a workout on
Dec 30, 2024 would give `weekOfYear = 1` but `year = 2024`. The streak calculator would
look for `(year: 2024, week: 1)` which is a different key from `(year: 2025, week: 1)`,
breaking any streak that crossed the year boundary in late December.

The same `.year` bug existed in `calculateCurrentStreak` for `currentYear`.

**Fix:** Changed `WorkoutLogEntry.year` and `currentYear` in `calculateCurrentStreak` to use
`.yearForWeekOfYear`, making both sides use the same ISO week calendar.

---

### S3 — MEDIUM: Hardcoded 52 weeks per year in streak calculation

**File:** `TimerViewModel.swift` — `calculateCurrentStreak()`

**Problem:** The `else if` (one-week-gap-at-head) branch of the streak loop set
`currentWeek = 52` when stepping back past week 1. Some years have 53 ISO weeks
(e.g., 2020, 2026, 2032). A workout in week 53 of a long year would fail to connect
to week 1 of the next year, incorrectly breaking the streak.

**Fix:** Extracted a `stepBackOneWeek()` nested function that uses `calendar.date(from:
DateComponents(year: currentYear, month: 12, day: 28))` for the dynamic last-week lookup
(Dec 28 is always in the final ISO week of its year). Applied to both branches of the loop.

---

### S4 — LOW: Force-unwrap in year-boundary streak calculation

**File:** `TimerViewModel.swift` — `calculateCurrentStreak()`

**Problem:** `calendar.date(from: DateComponents(year:month:day:))!` was force-unwrapped.
Safe in practice (Dec 28 always exists) but bad habit.

**Fix:** Replaced with `if let` and a fallback to 52 (now inside the extracted
`stepBackOneWeek()` helper, alongside the S3 fix).

---

## General Robustness Fixes

### G1 — LOW: `AudioManager.swift` was dead code

**Files:** `AudioManager.swift` (deleted), `N4x4.xcodeproj/project.pbxproj` (updated)

**Problem:** `AudioManager` was a singleton class that was never called anywhere.
`TimerViewModel` had its own `var player: AVAudioPlayer?` and `playAlarm()` method
that duplicated the logic. The file added confusion about which audio path was active.

**Fix:** Deleted `AudioManager.swift` and removed all four references from `project.pbxproj`
(PBXBuildFile, PBXFileReference, group children, Sources build phase).

---

### G2 — LOW: `@ViewBuilder` incorrectly applied to `String`-returning function

**File:** `TimerView.swift` — `timeString(time:)`

**Problem:** `@ViewBuilder` is a result builder for SwiftUI View-returning functions. Applying
it to a `-> String` function is semantically wrong. It compiled because the body was a single
return expression (no result-builder transformations needed), but it was misleading and flagged
by the Swift compiler as an inappropriate use.

**Fix:** Removed the `@ViewBuilder` attribute.

---

### G3 — LOW: Calendar view showed first (not most recent) workout on a given day

**File:** `TimerView.swift` — `workoutOnDay(_:)` in `StreakHistoryView`

**Problem:** The function iterated and returned the first matching entry. If a user logged
multiple workouts on the same day (e.g., reset mid-session and finished again), the calendar
would show the earlier, incomplete entry.

**Fix:** Changed to `filter` + `max(by: { $0.completedAt < $1.completedAt })` so the most
recent workout on the day is always shown.

---

### G4 — LOW: `scheduleWorkoutReminder` could silently disable reminders during async race

**File:** `TimerViewModel.swift` — `scheduleWorkoutReminder()`

**Problem:** The permission guard set `workoutRemindersEnabled = false` for *any* non-granted
state, including `.unknown` and `.notDetermined`. Before N1 was fixed, this guard was reached
frequently during the async race, which meant enabling reminders and then immediately losing
the setting without the user doing anything.

**Fix:** The guard now only sets `workoutRemindersEnabled = false` when permission is
definitively `.denied` or `.unavailable`. Unknown/notDetermined states return early without
modifying the setting.

---

### G5 — LOW: `persistWorkoutLogEntries` failed silently

**File:** `TimerViewModel.swift` — `persistWorkoutLogEntries()`

**Problem:** If JSON encoding failed (unlikely but possible after a future model change), the
function silently did nothing — workout data would be lost with no indication in logs.

**Fix:** Added a `print("[N4x4] Warning: ...")` in the `else` branch so the failure is
visible during development/TestFlight.

---

## Summary of Files Changed

| File | Changes |
|------|---------|
| `TimerViewModel.swift` | N1, N2, N4, N5, N6, S1, S2, S3, S4, G1, G4, G5 |
| `TimerView.swift` | N1 (scenePhase), S1 (scenePhase), G2, G3 |
| `AudioManager.swift` | Deleted (G1) |
| `N4x4.xcodeproj/project.pbxproj` | Removed AudioManager.swift references (G1) |
