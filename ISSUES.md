# Outstanding Issues

## 1. Legacy reminder migration never fires
- **File:** `N4x4/TimerViewModel.swift:338-344`
- **Problem:** The legacy `workoutReminderWeekday` migration compares against `oldValue` instead of the current value, so existing users never have their saved weekday moved into `workoutReminderWeekdays`. After updating, the picker shows no days selected and reminders default to "today" every time.
- **Fix idea:** Compare the new value (e.g. `if workoutReminderWeekday > 0 && workoutReminderWeekdays.isEmpty`) and immediately seed both AppStorage/string and `selectedWeekdaysList` so prior schedules survive.

## 2. Follow-up nags trigger before the first scheduled workout
- **File:** `N4x4/TimerViewModel.swift:1121-1177`
- **Problem:** When reminders are enabled midweek, `scheduleRecurringFollowUp` looks at the previous occurrence of the weekday and, if no workout is logged, schedules daily "you missed it" nags starting today—even though the user never had a workout scheduled yet. This creates false-positive shaming notifications.
- **Fix idea:** Track when reminders became active (or the next actual scheduled occurrence) and only schedule follow-ups after that day passes without a logged workout.

## 3. Idle-timer suppression never activates on initial appearance
- **Files:** `N4x4/TimerView.swift:180-201`
- **Problem:** `updateIdleTimer()` only runs when `isRunning`/`preventSleep` change. If the timer is already running when `TimerView` appears (e.g. launching mid-session or starting right after onboarding), the view never disables the idle timer, so the phone can lock mid-interval despite `preventSleep` being true.
- **Fix idea:** Call `updateIdleTimer()` inside `.onAppear` (and/or from `startTimer()`) to sync `UIApplication.shared.isIdleTimerDisabled` immediately.

## 4. Reminders are enabled with zero weekdays selected
- **Files:** `N4x4/ContentView.swift:399-405`, `N4x4/ContentView.swift:560-603`, `N4x4/TimerViewModel.swift:910-917`
- **Problem:** Onboarding flips `workoutRemindersEnabled = true` even if the user doesn't pick any days. `scheduleWorkoutReminder()` then falls back to "today" but never records it, so every scheduling pass uses the current weekday. The UI still shows no days selected and the reminder day drifts unpredictably.
- **Fix idea:** Require at least one selection before enabling reminders, or persist the fallback day into `selectedWeekdaysList` so the schedule is stable and visible.

## 5. Workout log timestamps drift when the summary sheet stays open
- **File:** `N4x4/TimerViewModel.swift:984-993`
- **Problem:** `saveWorkoutLogEntryAndResetSession()` sets `completedAt: Date()` when the user taps "Done". If they leave the summary sheet open for hours (or overnight), the workout is recorded on the wrong day, which breaks streak calculations and prevents follow-up cancellation.
- **Fix idea:** Capture the completion timestamp in `finishWorkout()` (or store `workoutCompletionDate`) and reuse that value when saving.
