# Outstanding Issues

_No open issues. The notification-scheduling bugs previously tracked here (#1–#4)
were fixed; details retained below for reference._

---

## Resolved

### 1. Legacy reminder migration never fires — RESOLVED
- **File:** `N4x4/TimerViewModel.swift`
- **Was:** The legacy `workoutReminderWeekday` migration compared against `oldValue`,
  so existing users never had their saved weekday moved into `workoutReminderWeekdays`.
- **Fix:** The `didSet` now tests the current value
  (`workoutReminderWeekday > 0 && workoutReminderWeekdays.isEmpty`, ~line 680). Because
  `@AppStorage` does not fire `didSet` on load, a launch-time seed was added in `init()`
  (~line 1161) so existing users' saved day survives.

### 2. Follow-up nags trigger before the first scheduled workout — RESOLVED
- **File:** `N4x4/TimerViewModel.swift` (`scheduleRecurringFollowUp`, ~line 1945)
- **Was:** Enabling reminders midweek scheduled "you missed it" nags starting today,
  even though the user never had a workout scheduled yet.
- **Fix:** Guards on `reminderActivationDate`, returns when the last occurrence predates
  activation, and only starts follow-ups the day *after* a scheduled workout day.

### 3. Idle-timer suppression never activates on initial appearance — RESOLVED
- **File:** `N4x4/TimerView.swift`
- **Was:** `updateIdleTimer()` only ran on `isRunning`/`preventSleep` changes, so a
  timer already running when the view appeared never disabled the idle timer.
- **Fix:** `updateIdleTimer()` is now called in `.onAppear` (~line 307) alongside the
  existing `.onChange` handlers.

### 4. Reminders enabled with zero weekdays selected — RESOLVED
- **File:** `N4x4/ContentView.swift` (`saveReminderWeekdayAndContinue`, ~line 856)
- **Was:** Onboarding flipped `workoutRemindersEnabled = true` even with no days picked,
  so scheduling silently drifted to "today".
- **Fix:** A `hasSelection` guard only enables reminders when days are selected;
  otherwise `workoutRemindersEnabled` is set to `false` across every permission branch.

### 5. Workout log timestamps drift when the summary sheet stays open — RESOLVED
- **File:** `N4x4/TimerViewModel.swift`
- **Fix:** `finishWorkout()` stamps `workoutCompletionDate = Date()` at completion, and
  `saveWorkoutLogEntryAndResetSession()` uses `workoutCompletionDate ?? Date()` rather
  than a fresh `Date()` at Done-tap, so leaving the summary open no longer shifts the
  recorded day.
