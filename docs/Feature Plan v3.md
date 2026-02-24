# N4x4 Feature Plan v3

## Already Planned / In Progress

The feature expansion plan (Health, VO2 chart, reminder scheduling) and bug fixes (N1–G5) are solid and should ship first. They fix real problems.

---

## Genuinely Awesome Ideas (prioritized)

### 1. Live Activities + Dynamic Island (highest impact)
During a workout, your phone is in your pocket. Live Activities lets the interval timer live on the Lock Screen and Dynamic Island — users can glance or feel a tap and see `HIT 2:34 remaining` without unlocking. This is the single feature that would most transform the workout experience. Requires `ActivityKit` (iOS 16.2+).

### 2. Haptic Feedback at Interval Transitions
A strong `UIImpactFeedbackGenerator` burst when an interval switches. Free, simple, and critical for users with earbuds in or phone in a pocket. Currently the app relies entirely on audio for transitions.

### 3. Apple Watch Companion App
Mirror the timer + interval name + HR zones on wrist. Add wrist haptics (`.taptic`) at interval changes. For a HIIT app where form matters, glancing at a watch >> fumbling with a phone. Big effort but transforms the product.

### 4. Home Screen & Lock Screen Widgets
A widget showing current streak + days since last workout. Keeps the habit loop alive without opening the app. `WidgetKit` is well-suited for this.

### 5. Siri / App Intents
`"Hey Siri, start my N4x4 workout"` — one `AppIntent` conformance. Very Apple-native, zero ongoing maintenance.

### 6. Always-On Screen During Workout
`UIApplication.shared.isIdleTimerDisabled = true` while the timer is running. Prevents screen sleep mid-workout. One line of code, huge UX win.

### 7. Shareable Completion Cards
After a workout, generate a nice image (SwiftUI → `ImageRenderer`) with streak count, workout type, date. One-tap share sheet. Organic marketing + user satisfaction.

### 8. Custom Workout Variants
Let users do 3×3, 5×4, etc. beyond the fixed 4×4. The `Interval` model already exists — it's mostly a settings UI addition. Broadens the audience significantly.

---

## Quick Wins (low effort, real value)

- **Screen always on** during workout (one line, see #6)
- **Haptic feedback** at transitions (5-10 lines)
- **StandBy mode support** — test and optimize the UI for iPhone on its side while charging

---

## Recommended Order

1. Screen always-on — 1 line, ships today
2. Haptic transitions — an hour's work
3. Live Activities — week of work, huge payoff
4. Widget — 2-3 days, great retention driver
