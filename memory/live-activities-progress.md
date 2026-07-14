# Live Activities Implementation — Progress Notes

## Status: ALL COMMITS DONE — needs Xcode Signing & Capabilities step
Last updated: 2026-02-24

## Plan document
`docs/Live Activities Plan.md` — full architecture, API notes, view sketches.

## Commit sequence

### Commit A — Shared data model ✅ DONE (73b1d43)
- [x] Create `N4x4/N4x4LiveActivityAttributes.swift`
- [x] Add to main app target in project.pbxproj (PBXBuildFile + PBXGroup)
- [x] Push

### Commit B — Widget Extension target + views ✅ DONE (b6164b9)
- [x] Add Widget Extension target to project.pbxproj (all sections)
- [x] Create `N4x4LiveActivity/` folder
- [x] Create `N4x4LiveActivity/N4x4LiveActivityBundle.swift`
- [x] Create `N4x4LiveActivity/N4x4LiveActivityView.swift`
- [x] Add named colors (phaseBlue, phaseRed, phaseGreen) to Assets.xcassets
- [x] N4x4LiveActivityAttributes.swift added to widget extension Sources in pbxproj
- [x] Embed Foundation Extensions CopyFiles phase added to app target
- [x] PBXTargetDependency: app builds after widget extension
- [x] Push

### Commit C — TimerViewModel integration ✅ DONE (14f3e06)
- [x] Add `import ActivityKit` to TimerViewModel.swift
- [x] Add `private var liveActivity: Activity<N4x4LiveActivityAttributes>?`
- [x] Add `liveActivityContentState(isRunning:)` helper
- [x] Add `startLiveActivity()`, `updateLiveActivity(isRunning:)`, `endLiveActivity()`
- [x] Wire `startLiveActivity()` into `startTimer()`
- [x] Wire `updateLiveActivity(false)` into `pause()` pause branch
- [x] Wire `updateLiveActivity(true)` into `pause()` resume branch
- [x] Wire `updateLiveActivity(true)` into `moveToNextInterval()`
- [x] Wire `endLiveActivity()` into `finishWorkout()`
- [x] Wire `endLiveActivity()` into `reset()`
- [x] Push

### Commit D — Entitlement + Info.plist ✅ DONE (9b21de6)
- [x] Add `INFOPLIST_KEY_NSSupportsLiveActivities = YES` to both Debug + Release in pbxproj
- [x] Add `com.apple.developer.activitykit = true` to N4x4.entitlements
- [x] Push

## ⚠️ Remaining manual step (requires Xcode UI)
In Xcode, select the N4x4 target → Signing & Capabilities → + Capability → Live Activities.
This registers the provisioning profile correctly for App Store distribution.
The entitlement is already in the .entitlements file; this step just syncs it with the portal.

## Architecture summary

### File membership
- `N4x4LiveActivityAttributes.swift` → BOTH app target AND widget extension target
- All other `N4x4LiveActivity/*.swift` files → widget extension target only

### Key types
```swift
struct N4x4LiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var intervalName: String
        var phase: WorkoutPhase      // warmup / highIntensity / rest
        var intervalEndTime: Date    // drives Text(timerInterval:) — no per-sec updates
        var isRunning: Bool
        var currentInterval: Int
        var totalIntervals: Int
        var hrLow: Int
        var hrHigh: Int
    }
    var workoutStartTime: Date
}

enum WorkoutPhase: String, Codable, Hashable {
    case warmup, highIntensity, rest
    // .color (asset name), .label, .icon (SF Symbol)
}
```

### Update trigger points in TimerViewModel
| Method | Action |
|--------|--------|
| `startTimer()` | `startLiveActivity()` (guarded: `liveActivity == nil`) |
| `pause()` pause branch | `updateLiveActivity(isRunning: false)` |
| `pause()` resume branch | `updateLiveActivity(isRunning: true)` |
| `moveToNextInterval()` interval-changed branch | `updateLiveActivity(isRunning: true)` |
| `finishWorkout()` | `endLiveActivity()` |
| `reset()` | `endLiveActivity()` |

### project.pbxproj UUIDs (fill in when created)
- Widget extension target UUID: TBD
- N4x4LiveActivityBundle.swift file ref UUID: TBD
- N4x4LiveActivityView.swift file ref UUID: TBD
- N4x4LiveActivityAttributes.swift file ref UUID (app target): TBD
- N4x4LiveActivityAttributes.swift build file UUID (widget ext): TBD

## Known constraints
- Live Activities cannot be tested on Simulator reliably — need physical device
- Widget Extension must be signed with same team (8VG9JUJ855)
- Bundle ID for extension: `Jan-van-Rensburg.N4x4.LiveActivity`
- iOS deployment target for extension: 16.2 minimum (app currently targets 26.0)
