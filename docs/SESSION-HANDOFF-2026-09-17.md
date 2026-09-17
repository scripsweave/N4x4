# Workout autosave and history access

Release version **5.1** for the iPhone app, Watch app and Live Activity
(Debug and Release). Pushing `main` triggers the Xcode Cloud delivery workflow;
App Store submission and availability are separate steps.

## Why

A client reported that workout data was visible at completion but inaccessible
later. Investigation found that phone-led workouts were only persisted after
tapping Done. In addition, saving required at least five HR samples before
writing the detailed series, and History hid the detail screen for workouts
without an HR summary. Its calendar only selected the latest workout per day.

Jan requested automatic saving on completion and easy deletion afterwards.

## Behavior

- `finishWorkout()` writes the workout and full series before presenting the
  summary and updates streaks/reminders immediately. A completion guard prevents
  duplicate saves, including duplicate Apple Health writes.
- `completedWorkoutEntryID` keeps optional review edits attached to the original
  record. Done or swipe dismissal saves those edits, then resets the timer.
  The original workout survives app termination before either action.
- Resetting the timer retains a completed workout. Explicit Delete removes its
  log entry and series, then recalculates the streak. Deletion affects N4x4
  history; it does not remove an Apple Health workout.
- History lists every workout, including multiple sessions on one day. Calendar
  days, workout rows and performance-chart selections open the same detail
  sheet, which includes Delete with confirmation. Older logs without series
  still show their stored breakdown, interval settings and notes.
- Full series are saved even with zero HR samples, including standalone Watch
  imports. The HR-summary threshold still governs statistics, not persistence.
- Follow-up history/milestone presentation runs from the summary's `onDismiss`.
  History no longer clears its own presentation flag from `onDisappear`, which
  could interfere with nested detail sheets.
- The Watch's existing discard command now removes the automatically saved
  phone workout. Watch completion copy calls this Delete and no longer tells
  the user they must save on the phone.
- Interval editor bindings guard their indices during dismissal. The new UI
  test caught an out-of-bounds read when reset cleared the draft while SwiftUI
  was still closing the summary.

## Verification

- Xcode 26.6 compiled the iPhone app, embedded Watch app and Live Activity.
- All **142 unit tests passed**, including autosave before review, sparse/no HR,
  idempotent completion/review, swipe dismissal, deletion, same-day sessions and
  standalone Watch import/deletion.
- Both new UI tests passed on an isolated iPhone 17 Pro simulator (iOS 26.5).
  They cover termination before Done, persistent deletion after relaunch,
  Done → History → nested detail, two same-day sessions, and cancelling Delete.
  The Done test initially caught the retained-binding crash described above;
  its targeted rerun passed after the fix.
- Summary and history-list screenshots were inspected. No physical-device or
  live HealthKit/WatchConnectivity delivery testing was performed.
- Local result bundles: `/tmp/N4x4-autosave-final.xcresult` has the passing full
  unit suite and same-day UI test; `/tmp/N4x4-autosave-dismissal.xcresult` has the
  passing Done/relaunch/deletion rerun after the binding fix.
- `git diff --check` passed. The release version was bumped from 5.0 to 5.1
  in all six shipping configurations; test-target versions remain unchanged.
