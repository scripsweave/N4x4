# Live Activities + Dynamic Island — Implementation Plan

## What the User Sees

### Dynamic Island — Compact (phone in use, another app in foreground)
```
┌─────────────────────────────────┐
│  🔴  HIT 2/4          2:34      │
└─────────────────────────────────┘
   ^leading             ^trailing
```
- **Leading**: phase color dot + interval label + progress (e.g. "HIT 2/4")
- **Trailing**: live countdown timer

### Dynamic Island — Expanded (user long-presses the island)
```
┌──────────────────────────────────────┐
│  ●●○○  High Intensity  Interval 2/4  │  ← top
│                                      │
│           2:34                       │  ← center (large timer)
│                                      │
│      Target: 161–181 bpm             │  ← bottom
└──────────────────────────────────────┘
```

### Dynamic Island — Minimal (two Live Activities active simultaneously)
- Trailing slot: countdown timer only

### Lock Screen Banner
```
┌────────────────────────────────────────┐
│  N4x4                                  │
│  ┌──────────┐  High Intensity  2/4     │
│  │  2:34    │  Target: 161–181 bpm     │
│  └──────────┘                          │
│  ●●○○  ████████████░░░░░  4 min        │
└────────────────────────────────────────┘
```

---

## Architecture Overview

```
N4x4 (main app)
├── N4x4LiveActivityAttributes.swift   ← shared between app + extension
│
└── [Xcode] Widget Extension target: "N4x4LiveActivity"
    ├── N4x4LiveActivityBundle.swift   ← @main WidgetBundle
    └── N4x4LiveActivityView.swift     ← all Dynamic Island + Lock Screen views

TimerViewModel.swift                   ← starts / updates / ends the activity
```

Live Activities require a Widget Extension target. The `ActivityAttributes`
struct must be defined in a file belonging to **both** the main app target
and the widget extension target (set via Xcode target membership checkbox).

---

## Step 1 — Xcode Project Setup

### 1a. Add Widget Extension target
- Xcode → File → New → Target → Widget Extension
- Name: `N4x4LiveActivity`
- Uncheck "Include Configuration Intent"
- Uncheck "Include Live Activity" (we'll write it manually for control)
- Deployment target: match the main app (iOS 16.2 minimum for ActivityKit;
  current project is iOS 26.0 so no availability guards needed)

### 1b. Enable ActivityKit capability on main app target
- Main app target → Signing & Capabilities → + Capability → Live Activities
- This adds `NSSupportsLiveActivities = YES` to the main app's Info.plist

### 1c. Add entitlement to main app
In `N4x4.entitlements`, add alongside the existing HealthKit entry:
```xml
<key>com.apple.developer.activitykit</key>
<true/>
```

### 1d. Add `ActivityKit` to the widget extension's framework imports
The widget extension needs `import ActivityKit` and `import WidgetKit`.
The main app needs `import ActivityKit`.

---

## Step 2 — Shared Data Model (`N4x4LiveActivityAttributes.swift`)

This file is added to **both** the main app target and the widget extension target.

```swift
// N4x4LiveActivityAttributes.swift
import ActivityKit
import Foundation

struct N4x4LiveActivityAttributes: ActivityAttributes {

    // Static data set when the activity starts (never changes during the workout)
    struct ContentState: Codable, Hashable {
        var intervalName: String        // "Warmup", "High Intensity", "Recovery"
        var phase: WorkoutPhase         // for color + icon
        var intervalEndTime: Date       // used for native .timer countdown — no per-second updates
        var isRunning: Bool
        var currentInterval: Int        // 1-based (e.g. 2)
        var totalIntervals: Int         // e.g. 4
        var hrLow: Int                  // e.g. 161
        var hrHigh: Int                 // e.g. 181
    }

    // Static (set at start, never changes)
    var workoutStartTime: Date
}

enum WorkoutPhase: String, Codable, Hashable {
    case warmup
    case highIntensity
    case rest

    var color: String {           // use named colors in asset catalog
        switch self {
        case .warmup:        return "phaseBlue"
        case .highIntensity: return "phaseRed"
        case .rest:          return "phaseGreen"
        }
    }

    var label: String {
        switch self {
        case .warmup:        return "Warm Up"
        case .highIntensity: return "HIT"
        case .rest:          return "Rest"
        }
    }

    var icon: String {            // SF Symbol name
        switch self {
        case .warmup:        return "figure.walk"
        case .highIntensity: return "bolt.fill"
        case .rest:          return "heart.fill"
        }
    }
}
```

**Why `intervalEndTime: Date` instead of `timeRemaining: Double`?**
SwiftUI's `Text(timerInterval:)` natively counts down using a `Date` range.
iOS handles it smoothly even from the Lock Screen without the app sending
updates every second. The app only needs to push an update when the
interval *changes* — roughly every 3-4 minutes.

---

## Step 3 — Widget Extension Views (`N4x4LiveActivityView.swift`)

```swift
// N4x4LiveActivityView.swift
import SwiftUI
import WidgetKit
import ActivityKit

struct N4x4LiveActivityView: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: N4x4LiveActivityAttributes.self) { context in
            // Lock Screen / StandBy / Notification banner view
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded (long-press)
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    ExpandedCenterView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottomView(context: context)
                }
            } compactLeading: {
                CompactLeadingView(context: context)
            } compactTrailing: {
                CompactTrailingView(context: context)
            } minimal: {
                MinimalView(context: context)
            }
        }
    }
}
```

### Key sub-views

```swift
// Compact Leading: phase icon + "HIT 2/4"
struct CompactLeadingView: View {
    let context: ActivityViewContext<N4x4LiveActivityAttributes>
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: context.state.phase.icon)
                .foregroundStyle(phaseColor)
            Text("\(context.state.phase.label) \(context.state.currentInterval)/\(context.state.totalIntervals)")
                .font(.caption2.bold())
        }
    }
    var phaseColor: Color { Color(context.state.phase.color) }
}

// Compact Trailing: live countdown timer
struct CompactTrailingView: View {
    let context: ActivityViewContext<N4x4LiveActivityAttributes>
    var body: some View {
        if context.state.isRunning {
            Text(timerInterval: Date.now...context.state.intervalEndTime, countsDown: true)
                .font(.caption2.monospacedDigit())
                .frame(width: 44)
        } else {
            Text(context.state.intervalEndTime, style: .time)  // shows frozen time when paused
                .font(.caption2.monospacedDigit())
        }
    }
}

// Expanded Center: big countdown
struct ExpandedCenterView: View {
    let context: ActivityViewContext<N4x4LiveActivityAttributes>
    var body: some View {
        Text(timerInterval: Date.now...context.state.intervalEndTime, countsDown: true)
            .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(Color(context.state.phase.color))
    }
}

// Expanded Bottom: HR zone
struct ExpandedBottomView: View {
    let context: ActivityViewContext<N4x4LiveActivityAttributes>
    var body: some View {
        Text("Target: \(context.state.hrLow)–\(context.state.hrHigh) bpm")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// Lock Screen: horizontal layout with progress dots
struct LockScreenView: View {
    let context: ActivityViewContext<N4x4LiveActivityAttributes>
    var body: some View {
        HStack {
            // Left: phase icon + timer
            VStack(alignment: .leading) {
                Image(systemName: context.state.phase.icon)
                    .font(.title2)
                    .foregroundStyle(Color(context.state.phase.color))
                Text(timerInterval: Date.now...context.state.intervalEndTime, countsDown: true)
                    .font(.title.bold().monospacedDigit())
            }
            Spacer()
            // Right: interval name + HR + dots
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(context.state.phase.label) \(context.state.currentInterval)/\(context.state.totalIntervals)")
                    .font(.headline)
                Text("Target: \(context.state.hrLow)–\(context.state.hrHigh) bpm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                IntervalDotsView(current: context.state.currentInterval,
                                 total: context.state.totalIntervals,
                                 phase: context.state.phase)
            }
        }
        .padding()
    }
}

// Progress dots: ●●○○
struct IntervalDotsView: View {
    let current: Int
    let total: Int
    let phase: WorkoutPhase
    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...total, id: \.self) { i in
                Circle()
                    .fill(i <= current ? Color(phase.color) : Color.gray.opacity(0.4))
                    .frame(width: 8, height: 8)
            }
        }
    }
}
```

---

## Step 4 — Main App Integration (`TimerViewModel.swift`)

### 4a. Add imports
```swift
import ActivityKit
```

### 4b. Add a stored reference to the active activity
```swift
// Inside TimerViewModel class
private var liveActivity: Activity<N4x4LiveActivityAttributes>?
```

### 4c. Helper: build ContentState from current timer state
```swift
private func liveActivityContentState(isRunning: Bool) -> N4x4LiveActivityAttributes.ContentState {
    let interval = intervals[currentIntervalIndex]
    let phase: WorkoutPhase = {
        switch interval.type {
        case .warmup:        return .warmup
        case .highIntensity: return .highIntensity
        case .rest:          return .rest
        }
    }()
    // Count how many HIT intervals have started (1-based display)
    let hitIndex = intervals[0...currentIntervalIndex].filter { $0.type == .highIntensity }.count
    let totalHIT = intervals.filter { $0.type == .highIntensity }.count

    let endTime = isRunning
        ? (intervalEndTime ?? Date().addingTimeInterval(timeRemaining))
        : Date().addingTimeInterval(timeRemaining)   // frozen when paused

    let maxHR = 220 - userAge
    return N4x4LiveActivityAttributes.ContentState(
        intervalName: interval.name,
        phase: phase,
        intervalEndTime: endTime,
        isRunning: isRunning,
        currentInterval: max(1, hitIndex),
        totalIntervals: totalHIT,
        hrLow:  Int(Double(maxHR) * 0.85),
        hrHigh: Int(Double(maxHR) * 0.95)
    )
}
```

> **Note on interval numbering**: the current UI shows HIT interval count
> (1/4, 2/4…). Warmup and rest phases still show progress dots but label
> them with their own phase name rather than a number. Adjust the display
> logic in the widget views to handle warmup/rest differently if preferred.

### 4d. Start the Live Activity
Call this from `startTimer()`, only once (guard against already active):
```swift
func startLiveActivity() {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    guard liveActivity == nil else { return }

    let attributes = N4x4LiveActivityAttributes(workoutStartTime: workoutStartDate ?? Date())
    let state = liveActivityContentState(isRunning: true)

    do {
        liveActivity = try Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil),
            pushType: nil   // local updates only, no push token needed
        )
    } catch {
        print("Live Activity start failed: \(error)")
    }
}
```

### 4e. Update the Live Activity
Call on **interval change** (`moveToNextInterval`) and on **pause/resume** (`pause()`):
```swift
func updateLiveActivity(isRunning: Bool) {
    guard let activity = liveActivity else { return }
    let state = liveActivityContentState(isRunning: isRunning)
    Task {
        await activity.update(.init(state: state, staleDate: nil))
    }
}
```

### 4f. End the Live Activity
Call from `finishWorkout()` and `reset()`:
```swift
func endLiveActivity() {
    guard let activity = liveActivity else { return }
    Task {
        await activity.end(.init(state: liveActivityContentState(isRunning: false),
                                 staleDate: nil),
                           dismissalPolicy: .after(Date.now.addingTimeInterval(5)))
        liveActivity = nil
    }
}
```
`dismissalPolicy: .after(5s)` keeps the completion state visible briefly
on the Lock Screen before it disappears.

### 4g. Wire up the call sites

| Event | Method to add |
|-------|---------------|
| `startTimer()` — first start | `startLiveActivity()` |
| `pause()` — pause branch | `updateLiveActivity(isRunning: false)` |
| `pause()` — resume branch | `updateLiveActivity(isRunning: true)` |
| `moveToNextInterval()` — interval changed | `updateLiveActivity(isRunning: true)` |
| `finishWorkout()` | `endLiveActivity()` |
| `reset()` | `endLiveActivity()` |

---

## Step 5 — Info.plist

Add to the **main app's** `Info.plist`:
```xml
<key>NSSupportsLiveActivities</key>
<true/>
```
(Xcode adds this automatically if you use the Signing & Capabilities flow,
but confirm it's present.)

---

## Step 6 — Asset Catalog (color aliases)

Add three named colors to `Assets.xcassets` — these must exist in **both**
the main app's asset catalog and be accessible to the widget extension
(add the xcassets to the widget target, or use a shared asset catalog):

| Name | Light | Dark |
|------|-------|------|
| `phaseBlue` | `#3A86FF` (or the existing blue in the app) | same |
| `phaseRed` | `#FF3A5C` | same |
| `phaseGreen` | `#30D158` | same |

---

## Step 7 — Stale Dates & Edge Cases

| Scenario | Handling |
|----------|----------|
| App killed mid-workout | Live Activity persists until `staleDate` (set to `intervalEndTime + 60s`) then shows "stale" UI |
| Phone rebooted | Live Activity is automatically ended by the system |
| Interval skipped | `updateLiveActivity()` fires from `skip()` → `moveToNextInterval()` |
| Workout paused | `isRunning = false` in ContentState; timer display freezes via `isRunning` flag in view |
| Multiple activities | `guard liveActivity == nil` prevents duplicates; system caps at a small number anyway |
| Warmup phase HR zone | Warmup uses `60–70%` HR (rest zone targets) — pass the correct values from `liveActivityContentState` |

---

## Step 8 — Implementation Order (commit by commit)

### Commit A — Shared data model
- Create `N4x4LiveActivityAttributes.swift`
- Add it to both targets
- Add `WorkoutPhase` enum (Codable, Hashable)
- No UI yet — just the model compiles

### Commit B — Widget extension + views
- Create Widget Extension target in Xcode
- Write all Dynamic Island views (compact, expanded, minimal)
- Write Lock Screen banner view
- Add named colors to asset catalog
- Preview in Xcode canvas with sample data

### Commit C — Main app integration
- Add `import ActivityKit` to `TimerViewModel.swift`
- Add `liveActivity` stored property
- Add `startLiveActivity()`, `updateLiveActivity()`, `endLiveActivity()`
- Wire call sites: `startTimer`, `pause`, `moveToNextInterval`, `finishWorkout`, `reset`

### Commit D — Info.plist + entitlement
- Add `NSSupportsLiveActivities = YES` to Info.plist
- Add `com.apple.developer.activitykit` to `N4x4.entitlements`
- Enable Live Activities capability in Xcode

### Commit E — QA pass
- Test on physical device (Simulator has limited Live Activity support)
- Verify countdown freezes correctly on pause
- Verify stale state shows after workout ends
- Verify Dynamic Island compact ↔ expanded transition

---

## Key API Notes

```swift
// Native timer display — no per-second app updates needed
Text(timerInterval: Date.now...endDate, countsDown: true)
    .monospacedDigit()

// Check if Live Activities are allowed (user may have disabled in Settings)
ActivityAuthorizationInfo().areActivitiesEnabled

// Update uses async/await — always wrap in Task { }
await activity.update(ActivityContent(state: newState, staleDate: nil))

// End with a brief display window
await activity.end(finalContent, dismissalPolicy: .after(Date.now + 5))
```

---

## Testing Checklist

- [ ] Live Activity appears in Dynamic Island when workout starts
- [ ] Compact view shows correct phase + countdown while in another app
- [ ] Expanded view shows on long-press with HR zone and dots
- [ ] Lock Screen banner updates when interval changes
- [ ] Timer freezes (doesn't count) when paused
- [ ] Activity ends and fades after workout completes
- [ ] `reset()` correctly ends the activity
- [ ] Works after phone is locked mid-workout
- [ ] No duplicate activities on repeated start/reset
- [ ] Warmup and rest phases show correct colors and HR targets
