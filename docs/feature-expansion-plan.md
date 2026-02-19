# N4x4 Feature Expansion Plan (Jan 2026)

## Scope
1. Reminder notifications every X days (default 7).
2. Apple Health integration.
3. VO₂ max improvement graph when Apple Health VO₂ max data exists.

---

## 1) UX / Product Behavior Spec

### A. Workout Reminder Notifications (Every X Days)
- Add **Settings → Workout Reminders** section.
- Controls:
  - `Reminder Notifications` toggle (off by default unless user enables).
  - `Every X day(s)` stepper (1–30), default `7`.
- Behavior:
  - If enabled, app schedules recurring reminder notification every X days.
  - Reminder copy: “Time for your N4x4 session. It’s been X day(s). Ready for your next workout?”
  - If permission denied, toggle automatically turns off.

### B. Apple Health Integration
- Add **Settings → Apple Health** section.
- Controls:
  - `Enable Apple Health` toggle.
  - `Refresh VO₂ max Data` action.
  - Connection status text (Connected / Not connected).
- Behavior:
  - On enable, request HealthKit authorization.
  - On workout completion, save HIIT workout summary to Health.
  - Load VO₂ max samples after authorization and when app returns active.

### C. VO₂ Max Improvement Graph
- In main timer view, show a VO₂ section when Apple Health is enabled.
- Behavior:
  - If at least 2 VO₂ points exist, show trend chart.
  - If data unavailable, show explanatory fallback text.
  - If Charts framework unavailable, show non-chart fallback message.

---

## 2) Technical Implementation Plan (Swift/SwiftUI)

### Notifications (`UNUserNotificationCenter`)
- Add persistent settings in `@AppStorage`:
  - `workoutRemindersEnabled: Bool`
  - `workoutReminderDays: Int = 7`
- Add methods in `TimerViewModel`:
  - `scheduleWorkoutReminder()`
  - `cancelWorkoutReminder()`
  - `scheduleNotification(identifier:title:body:in:repeats:)`
- Use fixed identifiers:
  - `nextInterval`
  - `workoutReminder`

### HealthKit
- Import `HealthKit` in `TimerViewModel`.
- Add `HKHealthStore` and authorization flow:
  - Read: `vo2Max`, `workoutType`
  - Write: `workoutType`
- Add methods:
  - `requestHealthKitAuthorizationIfNeeded()`
  - `fetchVO2MaxSamples()`
  - `saveCompletedWorkoutToHealthKit()`
- Save workout at session completion with activity `.highIntensityIntervalTraining`.

### VO₂ Graph UI (SwiftUI + Charts)
- Add `VO2DataPoint` model.
- In `TimerView`, conditionally render chart:
  - `LineMark` + `PointMark` over date/time.
- Use fallback copy if insufficient data or Charts unavailable.

---

## 3) Data Model + Permissions / Privacy Design

### Local Persistence
Use `@AppStorage` for user-level flags:
- `workoutRemindersEnabled`
- `workoutReminderDays`
- `healthKitEnabled`
- Existing notification/interval settings remain unchanged.

### Runtime/Derived Data (in-memory `@Published`)
- `healthAuthorizationGranted: Bool`
- `vo2DataPoints: [VO2DataPoint]`
- `workoutStartDate: Date?`

### Privacy
- No external backend required.
- Health data remains on-device via HealthKit APIs.
- Only explicitly requested data types are accessed.
- Added Info.plist purpose strings:
  - `NSHealthShareUsageDescription`
  - `NSHealthUpdateUsageDescription`

---

## 4) Edge Cases + Fallback Behavior

1. **Notification permission denied**
   - Disable reminder and interval notification toggles.
   - Avoid scheduling failures from UI state mismatch.

2. **HealthKit unavailable (device unsupported/restricted)**
   - Keep Apple Health disabled.
   - Show “Not connected”.

3. **Health authorization denied**
   - Keep integration off and show fallback copy.
   - VO₂ section displays unavailable message.

4. **No VO₂ max samples**
   - Show “No VO₂ max trend yet…” helper message.

5. **Only one VO₂ sample**
   - No trend line; same fallback text as above.

6. **Charts framework unavailable**
   - Display text fallback rather than chart.

7. **Reminder days edited while enabled**
   - Re-schedule reminder with new interval.

8. **Workout ends with HealthKit enabled but save fails**
   - Non-fatal; app flow continues.

---

## 5) Prioritized Rollout Order

### Phase 1 (High impact, low risk)
1. Reminder notifications (toggle + day interval + scheduling).
2. Notification permission handling and UX safeguards.

### Phase 2 (Core integration)
3. Apple Health authorization and workout write.
4. VO₂ max read and refresh action.

### Phase 3 (Experience polish)
5. VO₂ trend chart in main UI.
6. Error states, messaging polish, QA hardening.

---

## 6) Concrete File-Level Changes Started

Implemented edits:
- `N4x4/N4x4/TimerViewModel.swift`
  - Added reminder settings, scheduling, cancel logic.
  - Added HealthKit auth/read/write flow.
  - Added VO₂ data model and data loading.
- `N4x4/N4x4/SettingsView.swift`
  - Added Workout Reminder and Apple Health sections.
- `N4x4/N4x4/TimerView.swift`
  - Added VO₂ max trend section with chart/fallback behavior.
- `N4x4/N4x4/Info.plist`
  - Added HealthKit privacy usage descriptions.

---

## 7) Commit-by-Commit Patch Plan

1. **Commit A: Reminder scheduling**
   - Add `workoutRemindersEnabled`, `workoutReminderDays`.
   - Add reminder scheduling/cancel paths and settings UI.

2. **Commit B: HealthKit foundation**
   - Add HealthKit entitlements/principals (if needed in Xcode Capabilities).
   - Add authorization + workout write + VO₂ query.
   - Add Info.plist privacy keys.

3. **Commit C: VO₂ chart UI**
   - Add chart rendering in `TimerView` with fallback copy.
   - Add refresh control and status indicators.

4. **Commit D: QA pass**
   - Fix compile/runtime warnings and edge-case regressions.
   - Add tests for pure logic (e.g., reminder interval validation) where feasible.

---

## Notes for Next Pass
- Confirm target iOS version for `Charts` compatibility.
- Enable HealthKit capability in target signing settings if not already enabled.
- Validate repeated `UNTimeIntervalNotificationTrigger` behavior against desired product semantics.
