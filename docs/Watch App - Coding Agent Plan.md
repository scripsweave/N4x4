# Apple Watch App — Coding Agent Implementation Plan

## Before You Start

The human has already completed the manual Xcode steps (`Watch App - Manual Xcode Steps.md`). That means:
- The `N4x4Watch` watchOS target exists in the project
- The `N4x4Complication` Widget Extension target exists
- `Interval.swift` and `N4x4LiveActivityAttributes.swift` are members of the `N4x4Watch` target
- HealthKit capability is on the Watch target
- Background Modes → Workout processing is on the iOS target

**Your job is to write all the code.** Do not attempt to modify `project.pbxproj` directly. All file creation and modification is pure Swift.

---

## Project Facts

- **iOS bundle ID**: `Jan-van-Rensburg.N4x4`
- **Watch bundle ID**: `Jan-van-Rensburg.N4x4.watchkitapp`
- **Swift version**: 5.0
- **iOS deployment target**: 17.5
- **Watch deployment target**: 9.0
- **Project root**: wherever the agent is run from — all paths below are relative to the repo root

### Key existing types (do not redefine)

- `WorkoutPhase` — enum in `N4x4/N4x4LiveActivityAttributes.swift`. Cases: `.warmup`, `.highIntensity`, `.rest`. Has `.color: Color`, `.shortLabel: String`, `.symbolName: String`. Already `Codable` and `Hashable`.
- `Interval` — struct in `N4x4/Interval.swift`. Has `name: String`, `duration: TimeInterval`, `type: IntervalType`.
- `IntervalType` — enum. Cases: `.warmup`, `.highIntensity`, `.rest`.
- `TimerViewModel` — `ObservableObject` in `N4x4/TimerViewModel.swift`. Key properties listed below.

### Key `TimerViewModel` properties and methods

```
@Published var isRunning: Bool
@Published var currentIntervalIndex: Int
@Published var timeRemaining: TimeInterval
@Published var intervalEndTime: Date?
@Published var highIntensityCount: Int
@Published var restCount: Int
@Published var numberOfIntervals: Int
@Published var showPostWorkoutSummary: Bool
var intervals: [Interval]
var highIntensityTargetRange: ClosedRange<Int>   // computed
var recoveryTargetRange: ClosedRange<Int>         // computed

func startTimer()
func pause()
func skip()
func finishWorkout()
func reset()
```

---

## Implementation Order

Work through the steps **in this exact order**. Each step builds on the previous one. After each step, verify the code compiles before moving on.

```
Step 1  →  Modify N4x4LiveActivityAttributes.swift (conditional import)
Step 2  →  Modify N4x4/Info.plist (background modes)
Step 3  →  Create Shared/WatchMessage.swift
Step 4  →  Create N4x4/PhoneSessionManager.swift
Step 5  →  Modify N4x4/TimerViewModel.swift (wire in session manager + HR)
Step 6  →  Modify N4x4/TimerView.swift (HR display on phone)
Step 7  →  Modify N4x4/SettingsView.swift (Watch section)
Step 8  →  Create N4x4Watch/N4x4WatchApp.swift
Step 9  →  Create N4x4Watch/WatchSessionManager.swift
Step 10 →  Create N4x4Watch/WorkoutManager.swift
Step 11 →  Create N4x4Watch/WatchTimerView.swift
Step 12 →  Create N4x4Watch/N4x4Complication.swift
Step 13 →  Create N4x4Watch/Info.plist (Watch-specific plist entries)
Step 14 →  Build check + review
```

---

## Step 1 — Modify `N4x4/N4x4LiveActivityAttributes.swift`

**Why:** This file is shared between the iOS and Watch targets. `ActivityKit` doesn't exist on watchOS. Wrap the import and the `ActivityAttributes` conformance in a conditional compile block so the Watch only gets `WorkoutPhase`.

**What to do:** Read the file first. Then:

1. Replace `import ActivityKit` (at the top) with:
```swift
#if canImport(ActivityKit)
import ActivityKit
#endif
```

2. Find the `struct N4x4LiveActivityAttributes: ActivityAttributes` declaration and wrap the entire struct (opening brace to closing brace) in:
```swift
#if canImport(ActivityKit)
// ... existing struct content ...
#endif
```

3. The `WorkoutPhase` enum must stay **outside** the `#if` block. It should already be at the bottom of the file — verify it is not nested inside the struct or inside the `#if`.

**Verification:** After editing, the file should have this rough structure:
```swift
#if canImport(ActivityKit)
import ActivityKit
#endif
import Foundation
import SwiftUI

#if canImport(ActivityKit)
struct N4x4LiveActivityAttributes: ActivityAttributes {
    // ... unchanged ...
}
#endif

enum WorkoutPhase: String, Codable, Hashable {
    // ... unchanged ...
}
```

---

## Step 2 — Modify `N4x4/Info.plist`

**Why:** The iOS app needs `workout-processing` in `UIBackgroundModes` to receive Watch commands while in the background during a workout.

**What to do:** Read the file. Find the `UIBackgroundModes` key. If it exists and has an empty array, add `workout-processing` to it. If the key doesn't exist, add the entire block.

The result should contain:
```xml
<key>UIBackgroundModes</key>
<array>
    <string>workout-processing</string>
</array>
```

If other entries already exist in `UIBackgroundModes`, add `workout-processing` alongside them — do not remove existing entries.

---

## Step 3 — Create `Shared/WatchMessage.swift`

**Target membership:** iOS (`N4x4`) and Watch (`N4x4Watch`)
> Note for agent: The human must manually add this file to both targets in Xcode. Create it at the path and note this requirement.

**Full file content:**

```swift
// WatchMessage.swift
// Shared between iOS and watchOS targets.
// All WCSession dictionary keys and message type constants.
// No logic — only static string constants.

import Foundation

enum WatchMessageKey {

    // Every message must include this key
    static let messageType          = "type"

    // ── Commands: Watch → Phone ──────────────────────────────
    static let cmdStartPause        = "cmd_startPause"
    static let cmdSkip              = "cmd_skip"
    static let cmdRequestState      = "request_state"

    // ── State sync payload: Phone → Watch ────────────────────
    static let stateSync            = "state_sync"
    static let isRunning            = "isRunning"            // Bool
    static let currentIntervalIndex = "currentIntervalIndex" // Int
    static let intervalEndTime      = "intervalEndTime"      // Double (timeIntervalSince1970)
    static let intervalName         = "intervalName"         // String
    static let intervalDuration     = "intervalDuration"     // Double (seconds)
    static let phase                = "phase"                // WorkoutPhase rawValue String
    static let highIntensityCount   = "hitCount"             // Int
    static let totalIntervals       = "totalIntervals"       // Int
    static let hrLow                = "hrLow"                // Int (BPM)
    static let hrHigh               = "hrHigh"              // Int (BPM)
    static let workoutComplete      = "workoutComplete"      // Bool

    // ── Heart rate: Watch → Phone ─────────────────────────────
    static let heartRate            = "hr_update"
    static let hrBPM                = "hrBPM"                // Double
    static let hrTimestamp          = "hrTimestamp"          // Double (timeIntervalSince1970)
}
```

---

## Step 4 — Create `N4x4/PhoneSessionManager.swift`

**Target membership:** iOS (`N4x4`) only

**Full file content:**

```swift
// PhoneSessionManager.swift
// iOS side of WatchConnectivity.
// Owned by TimerViewModel. Sends timer state to Watch; receives commands and HR from Watch.

import WatchConnectivity
import Foundation

final class PhoneSessionManager: NSObject, WCSessionDelegate {

    weak var timerViewModel: TimerViewModel?

    // MARK: - Activation

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Send state to Watch

    func sendStateUpdate(to vm: TimerViewModel) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isWatchAppInstalled else { return }

        // Use intervalEndTime (absolute date) as the sync anchor.
        // The Watch computes timeRemaining from this value locally — no per-second messages needed.
        let endTime = vm.intervalEndTime?.timeIntervalSince1970
            ?? Date().addingTimeInterval(vm.timeRemaining).timeIntervalSince1970

        let interval = vm.intervals.indices.contains(vm.currentIntervalIndex)
            ? vm.intervals[vm.currentIntervalIndex] : nil

        let phase: WorkoutPhase = {
            switch interval?.type {
            case .highIntensity: return .highIntensity
            case .rest:          return .rest
            default:             return .warmup
            }
        }()

        let payload: [String: Any] = [
            WatchMessageKey.messageType:            WatchMessageKey.stateSync,
            WatchMessageKey.isRunning:              vm.isRunning,
            WatchMessageKey.currentIntervalIndex:   vm.currentIntervalIndex,
            WatchMessageKey.intervalEndTime:        endTime,
            WatchMessageKey.intervalName:           interval?.name ?? "",
            WatchMessageKey.intervalDuration:       interval?.duration ?? 0.0,
            WatchMessageKey.phase:                  phase.rawValue,
            WatchMessageKey.highIntensityCount:     vm.highIntensityCount,
            WatchMessageKey.totalIntervals:         vm.numberOfIntervals,
            WatchMessageKey.hrLow:                  vm.highIntensityTargetRange.lowerBound,
            WatchMessageKey.hrHigh:                 vm.highIntensityTargetRange.upperBound,
            WatchMessageKey.workoutComplete:        vm.showPostWorkoutSummary,
        ]

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil) { [weak self] _ in
                // Fallback: store in applicationContext so Watch gets it on next connection
                try? WCSession.default.updateApplicationContext(payload)
                _ = self // suppress unused capture warning
            }
        } else {
            try? WCSession.default.updateApplicationContext(payload)
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        guard activationState == .activated else { return }
        DispatchQueue.main.async { [weak self] in
            guard let vm = self?.timerViewModel else { return }
            self?.sendStateUpdate(to: vm)
        }
    }

    // Required on iOS (for Watch hardware switching)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.handle(message) }
    }

    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async { [weak self] in self?.handle(message) }
        replyHandler([:])
    }

    // MARK: - Incoming message routing

    private func handle(_ message: [String: Any]) {
        guard let vm = timerViewModel,
              let type = message[WatchMessageKey.messageType] as? String else { return }

        switch type {
        case WatchMessageKey.cmdStartPause:
            if vm.isRunning { vm.pause() } else { vm.startTimer() }
        case WatchMessageKey.cmdSkip:
            vm.skip()
        case WatchMessageKey.cmdRequestState:
            sendStateUpdate(to: vm)
        case WatchMessageKey.heartRate:
            if let bpm = message[WatchMessageKey.hrBPM] as? Double {
                vm.currentHeartRate = bpm
            }
        default:
            break
        }
    }
}
```

---

## Step 5 — Modify `N4x4/TimerViewModel.swift`

Read the full file before making changes. Make the following additions — do not remove or restructure any existing code.

### 5a — Add `PhoneSessionManager` and `currentHeartRate` property

Find the block of `@Published` properties near the top of the class (around the `showPostWorkoutSummary` and `showWeeklyStreaks` declarations). Add immediately after them:

```swift
// Apple Watch
let phoneSessionManager = PhoneSessionManager()
@Published var currentHeartRate: Double? = nil
```

### 5b — Activate the session manager in `init()`

Find the `init()` method. After the last line in init (likely `loadWorkoutLogEntries()` or `setupIntervals()`), add:

```swift
phoneSessionManager.timerViewModel = self
phoneSessionManager.activate()
```

### 5c — Add `broadcastStateToWatch()` method

Add this method anywhere in the class (near the other helper methods is fine):

```swift
func broadcastStateToWatch() {
    phoneSessionManager.sendStateUpdate(to: self)
}
```

### 5d — Call `broadcastStateToWatch()` at action sites

Add `broadcastStateToWatch()` as the **last line** inside each of these functions. Read each function carefully to find the correct closing brace before adding.

- `startTimer()` — add at the very end, just before the closing `}`
- `pause()` — the function has two branches (isRunning true/false). Add one call at the end of each branch, OR add a single call at the very end of the function after both branches complete.
- `skip()` — add at the very end
- `moveToNextInterval()` — add at the very end
- `finishWorkout()` — add at the very end
- `reset()` — add at the very end

### 5e — Clear `currentHeartRate` on workout end

In `finishWorkout()`, add `currentHeartRate = nil` near the top of the function (before `broadcastStateToWatch()`).

In `reset()`, add `currentHeartRate = nil` near the top of the function (before `broadcastStateToWatch()`).

---

## Step 6 — Modify `N4x4/TimerView.swift`

Read the file first. Make two additions.

### 6a — Add HR display during workout

Find the main workout display area in `TimerView` — likely inside a `VStack` that contains the progress circle and time display. Add the following block somewhere visible below the main timer display (after the heart rate zone text if it exists, otherwise after the countdown):

```swift
// Watch heart rate display
if let hr = viewModel.currentHeartRate, viewModel.isRunning {
    HStack(spacing: 6) {
        Image(systemName: "applewatch.watchface")
            .font(.system(size: 13))
            .foregroundColor(.secondary)
        Image(systemName: "heart.fill")
            .font(.system(size: 13))
            .foregroundColor(watchHRZoneColor(hr))
        Text("\(Int(hr)) BPM")
            .font(.system(size: 20, weight: .semibold, design: .monospaced))
            .foregroundColor(watchHRZoneColor(hr))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(Color(UIColor.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 10))
    .transition(.opacity)
}
```

### 6b — Add `watchHRZoneColor` helper

Add this private helper method inside `TimerView` (not inside `body`):

```swift
private func watchHRZoneColor(_ bpm: Double) -> Color {
    guard viewModel.intervals.indices.contains(viewModel.currentIntervalIndex) else {
        return .secondary
    }
    let interval = viewModel.intervals[viewModel.currentIntervalIndex]
    switch interval.type {
    case .highIntensity:
        let r = viewModel.highIntensityTargetRange
        return bpm >= Double(r.lowerBound) && bpm <= Double(r.upperBound) ? .green : .red
    case .rest:
        return bpm <= Double(viewModel.recoveryTargetRange.upperBound) ? .green : .orange
    case .warmup:
        return .blue
    }
}
```

---

## Step 7 — Modify `N4x4/SettingsView.swift`

Read the file first. Add a new `Section` near the top of the `Form` (after any existing top sections but before the less important ones):

```swift
// Apple Watch section
Section("Apple Watch") {
    Toggle("Stream heart rate from Watch", isOn: $viewModel.watchHeartRateEnabled)

    if WCSession.isSupported() {
        Label(
            WCSession.default.isWatchAppInstalled
                ? "Watch app installed"
                : "Watch app not installed",
            systemImage: WCSession.default.isWatchAppInstalled
                ? "applewatch.watchface"
                : "applewatch.slash"
        )
        .foregroundColor(.secondary)
        .font(.footnote)
    }
}
```

Also add `import WatchConnectivity` at the top of the file if it's not already there.

Then add this property to `TimerViewModel.swift`:

```swift
@AppStorage("watchHeartRateEnabled") var watchHeartRateEnabled: Bool = true
```

Add it near the other `@AppStorage` settings properties.

Also add `watchHeartRateEnabled = true` to `resetSettingsToDefaults()` if that function exists.

---

## Step 8 — Create `N4x4Watch/N4x4WatchApp.swift`

**Target membership:** `N4x4Watch` only

```swift
// N4x4WatchApp.swift
import SwiftUI

@main
struct N4x4WatchApp: App {

    @StateObject private var sessionManager = WatchSessionManager()
    @StateObject private var workoutManager = WorkoutManager()

    var body: some Scene {
        WindowGroup {
            WatchTimerView()
                .environmentObject(sessionManager)
                .environmentObject(workoutManager)
                .onAppear {
                    sessionManager.activate()
                    workoutManager.requestAuthorization { _ in }
                }
        }
    }
}
```

> **Important:** If Xcode already created a default `N4x4WatchApp.swift` when you added the target, replace its contents entirely with the above.

---

## Step 9 — Create `N4x4Watch/WatchSessionManager.swift`

**Target membership:** `N4x4Watch` only

```swift
// WatchSessionManager.swift
// watchOS side of WatchConnectivity.
// Receives timer state from phone. Sends control commands to phone.

import WatchConnectivity
import Foundation

// MARK: - WatchTimerState

struct WatchTimerState: Equatable {
    var isRunning: Bool
    var intervalEndTime: Date
    var intervalName: String
    var intervalDuration: Double
    var phase: WorkoutPhase
    var highIntensityCount: Int
    var totalIntervals: Int
    var hrLow: Int
    var hrHigh: Int
    var workoutComplete: Bool
    var currentIntervalIndex: Int

    /// Computed live from the absolute end-time. No per-second messages needed.
    var timeRemaining: TimeInterval {
        max(0, intervalEndTime.timeIntervalSinceNow)
    }

    var progressValue: CGFloat {
        guard intervalDuration > 0 else { return 0 }
        return CGFloat(min(1, max(0, timeRemaining / intervalDuration)))
    }

    static let idle = WatchTimerState(
        isRunning: false,
        intervalEndTime: Date(),
        intervalName: "Ready",
        intervalDuration: 0,
        phase: .warmup,
        highIntensityCount: 0,
        totalIntervals: 4,
        hrLow: 0,
        hrHigh: 0,
        workoutComplete: false,
        currentIntervalIndex: 0
    )
}

// MARK: - WatchSessionManager

final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {

    @Published var timerState: WatchTimerState = .idle

    // MARK: - Activation

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Commands to phone

    func sendStartPause() { sendCommand(WatchMessageKey.cmdStartPause) }
    func sendSkip()        { sendCommand(WatchMessageKey.cmdSkip) }

    func requestStateFromPhone() {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            [WatchMessageKey.messageType: WatchMessageKey.cmdRequestState],
            replyHandler: nil,
            errorHandler: nil
        )
    }

    private func sendCommand(_ type: String) {
        guard WCSession.isSupported() else { return }
        let msg: [String: Any] = [WatchMessageKey.messageType: type]
        if WCSession.default.activationState == .activated, WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: nil) { _ in
                WCSession.default.transferUserInfo(msg)
            }
        } else {
            WCSession.default.transferUserInfo(msg)
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}

    /// Real-time message from phone (phone is reachable)
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.applyStatePayload(message) }
    }

    /// Stored context — received when Watch was not reachable at send time
    func session(_ session: WCSession,
                 didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.applyStatePayload(applicationContext) }
    }

    /// Background user info delivery
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.applyStatePayload(userInfo) }
    }

    // MARK: - State parsing

    private func applyStatePayload(_ p: [String: Any]) {
        guard (p[WatchMessageKey.messageType] as? String) == WatchMessageKey.stateSync else { return }

        timerState = WatchTimerState(
            isRunning:            p[WatchMessageKey.isRunning]            as? Bool   ?? false,
            intervalEndTime:      Date(timeIntervalSince1970:
                                    p[WatchMessageKey.intervalEndTime]    as? Double ?? 0),
            intervalName:         p[WatchMessageKey.intervalName]         as? String ?? "",
            intervalDuration:     p[WatchMessageKey.intervalDuration]     as? Double ?? 0,
            phase:                WorkoutPhase(rawValue:
                                    p[WatchMessageKey.phase]              as? String ?? "")
                                    ?? .warmup,
            highIntensityCount:   p[WatchMessageKey.highIntensityCount]   as? Int    ?? 0,
            totalIntervals:       p[WatchMessageKey.totalIntervals]       as? Int    ?? 4,
            hrLow:                p[WatchMessageKey.hrLow]                as? Int    ?? 0,
            hrHigh:               p[WatchMessageKey.hrHigh]               as? Int    ?? 0,
            workoutComplete:      p[WatchMessageKey.workoutComplete]      as? Bool   ?? false,
            currentIntervalIndex: p[WatchMessageKey.currentIntervalIndex] as? Int    ?? 0
        )
    }
}
```

---

## Step 10 — Create `N4x4Watch/WorkoutManager.swift`

**Target membership:** `N4x4Watch` only

```swift
// WorkoutManager.swift
// watchOS only.
// Manages an HKWorkoutSession for real-time heart rate collection.
// Streams HR samples to the iPhone via WCSession.

import Foundation
import HealthKit
import WatchConnectivity

final class WorkoutManager: NSObject, ObservableObject {

    private let healthStore  = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    @Published var heartRate: Double = 0
    @Published var isSessionActive: Bool = false

    // MARK: - Authorization

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }
        let hrType     = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        healthStore.requestAuthorization(
            toShare: [HKObjectType.workoutType(), energyType],
            read:    [hrType, energyType, HKObjectType.workoutType()]
        ) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }

    // MARK: - Session lifecycle

    func startWorkout() {
        guard !isSessionActive else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = .highIntensityIntervalTraining
        config.locationType = .indoor

        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            builder = session?.associatedWorkoutBuilder()

            session?.delegate = self
            builder?.delegate = self
            builder?.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: config
            )

            let startDate = Date()
            // IMPORTANT: startActivity must come before beginCollection
            session?.startActivity(with: startDate)
            builder?.beginCollection(withStart: startDate) { _, error in
                if let error = error {
                    print("[WorkoutManager] beginCollection error: \(error)")
                }
            }
            isSessionActive = true
        } catch {
            print("[WorkoutManager] Failed to start HKWorkoutSession: \(error)")
        }
    }

    func stopWorkout() {
        guard isSessionActive else { return }
        session?.end()
        // isSessionActive is set to false via the delegate callback
    }

    // MARK: - HR streaming to phone

    private func streamHeartRate(_ bpm: Double) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }

        WCSession.default.sendMessage(
            [
                WatchMessageKey.messageType: WatchMessageKey.heartRate,
                WatchMessageKey.hrBPM:       bpm,
                WatchMessageKey.hrTimestamp: Date().timeIntervalSince1970,
            ],
            replyHandler: nil,
            errorHandler: nil
        )
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {
        DispatchQueue.main.async {
            self.isSessionActive = (toState == .running)
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didFailWithError error: Error) {
        print("[WorkoutManager] session error: \(error)")
        DispatchQueue.main.async { self.isSessionActive = false }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {

        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(hrType) else { return }

        let unit = HKUnit.count().unitDivided(by: .minute())
        guard let bpm = workoutBuilder
                .statistics(for: hrType)?
                .mostRecentQuantity()?
                .doubleValue(for: unit) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.heartRate = bpm
            self?.streamHeartRate(bpm)
        }
    }
}
```

---

## Step 11 — Create `N4x4Watch/WatchTimerView.swift`

**Target membership:** `N4x4Watch` only

```swift
// WatchTimerView.swift
// Main Watch UI: progress arc, countdown, HR, start/pause/skip controls.

import SwiftUI
import WatchKit

struct WatchTimerView: View {

    @EnvironmentObject var sessionManager: WatchSessionManager
    @EnvironmentObject var workoutManager: WorkoutManager

    // Local 1-second tick drives the countdown re-render
    @State private var tick = Date()
    @State private var lastIntervalIndex = 0
    @Environment(\.scenePhase) private var scenePhase

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var state: WatchTimerState { sessionManager.timerState }

    var body: some View {
        VStack(spacing: 6) {

            // ── Interval label ──────────────────────────────
            Text(intervalLabel)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(state.phase.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // ── Progress ring ───────────────────────────────
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.gray.opacity(0.25), lineWidth: 6)

                // Coloured progress arc — same formula as the phone app
                Circle()
                    .trim(from: 0, to: state.progressValue)
                    .stroke(style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .foregroundColor(state.phase.color)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: state.timeRemaining)

                // Countdown + HR
                VStack(spacing: 2) {
                    Text(timeString(state.timeRemaining))
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)

                    if workoutManager.heartRate > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 9))
                            Text("\(Int(workoutManager.heartRate))")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        }
                        .foregroundColor(hrColor)
                    }
                }
            }
            .frame(width: 130, height: 130)

            // ── Controls ────────────────────────────────────
            HStack(spacing: 16) {
                // Start / Pause
                Button {
                    sessionManager.sendStartPause()
                } label: {
                    Image(systemName: state.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 52, height: 44)
                        .background(Color.gray.opacity(0.3),
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                // Skip interval
                Button {
                    sessionManager.sendSkip()
                } label: {
                    Image(systemName: "forward.end.alt.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 52, height: 44)
                        .background(Color.gray.opacity(0.3),
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .onReceive(ticker) { tick = $0 }  // drives timeRemaining recompute

        // ── Start / stop HKWorkoutSession with timer ────────
        .onChange(of: state.isRunning) { _, isRunning in
            if isRunning, !workoutManager.isSessionActive {
                workoutManager.startWorkout()
            } else if !isRunning, workoutManager.isSessionActive, state.workoutComplete {
                workoutManager.stopWorkout()
            }
        }

        // ── Haptics on interval change ───────────────────────
        .onChange(of: state.currentIntervalIndex) { _, newIndex in
            guard newIndex != lastIntervalIndex else { return }
            lastIntervalIndex = newIndex
            WKInterfaceDevice.current().play(.notification)
        }

        // ── Haptic on workout complete ───────────────────────
        .onChange(of: state.workoutComplete) { _, complete in
            if complete { WKInterfaceDevice.current().play(.success) }
        }

        // ── Sync on app foreground ───────────────────────────
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { sessionManager.requestStateFromPhone() }
        }
    }

    // MARK: - Helpers

    private var intervalLabel: String {
        switch state.phase {
        case .highIntensity: return "Work \(state.highIntensityCount)/\(state.totalIntervals)"
        case .rest:          return "Recovery"
        case .warmup:        return "Warm Up"
        }
    }

    /// HR zone color: green = in target, yellow = below target, red = above target
    private var hrColor: Color {
        let bpm = workoutManager.heartRate
        guard state.hrLow > 0 else { return .white }
        if bpm < Double(state.hrLow)  { return .yellow }
        if bpm > Double(state.hrHigh) { return .red }
        return .green
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60 % 60, Int(t) % 60)
    }
}
```

---

## Step 12 — Create `N4x4Watch/N4x4Complication.swift`

**Target membership:** `N4x4Complication` (the Widget Extension target) only — NOT `N4x4Watch`

```swift
// N4x4Complication.swift
// watchOS Widget Extension — Watch face complication.
// Tap the complication to launch N4x4Watch.

import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct N4x4ComplicationEntry: TimelineEntry {
    let date: Date
}

// MARK: - Provider

struct N4x4ComplicationProvider: TimelineProvider {

    func placeholder(in context: Context) -> N4x4ComplicationEntry {
        N4x4ComplicationEntry(date: Date())
    }

    func getSnapshot(in context: Context,
                     completion: @escaping (N4x4ComplicationEntry) -> Void) {
        completion(N4x4ComplicationEntry(date: Date()))
    }

    func getTimeline(in context: Context,
                     completion: @escaping (Timeline<N4x4ComplicationEntry>) -> Void) {
        // Static complication — never needs to update
        let entry = N4x4ComplicationEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

// MARK: - Views

struct N4x4ComplicationView: View {
    var entry: N4x4ComplicationEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ZStack {
            switch family {
            case .accessoryCircular:
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.orange)

            case .accessoryCorner:
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.orange)

            case .accessoryRectangular:
                HStack(spacing: 6) {
                    Image(systemName: "bolt.heart.fill")
                        .foregroundStyle(.orange)
                    Text("N4x4")
                        .font(.headline.weight(.bold))
                }

            default:
                Image(systemName: "bolt.heart.fill")
                    .foregroundStyle(.orange)
            }
        }
        .widgetURL(URL(string: "n4x4watch://open"))
    }
}

// MARK: - Widget

struct N4x4Complication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "N4x4Complication",
            provider: N4x4ComplicationProvider()
        ) { entry in
            N4x4ComplicationView(entry: entry)
        }
        .configurationDisplayName("N4x4 Timer")
        .description("Quick-launch your N4x4 interval session.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
        ])
    }
}

// MARK: - Entry point
// Note: this @main is for the Widget Extension target.
// The Watch App target has its own @main in N4x4WatchApp.swift.

@main
struct N4x4ComplicationBundle: WidgetBundle {
    var body: some Widget {
        N4x4Complication()
    }
}
```

---

## Step 13 — Create `N4x4Watch/Info.plist`

The Watch target needs HealthKit usage descriptions. If the target already has an `Info.plist`, add these keys to it. If not, create it.

Add the following key-value pairs:

```xml
<key>NSHealthShareUsageDescription</key>
<string>N4x4 reads your heart rate during workouts to show your training zones in real time.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>N4x4 saves your interval training session to Apple Health.</string>
```

---

## Step 14 — Build Check and Review

After completing all steps, do the following:

### Check 1 — Read back every modified file
Before declaring done, re-read each file you modified and verify:
- No duplicate property declarations in `TimerViewModel`
- `WorkoutPhase` is outside the `#if canImport(ActivityKit)` block in `N4x4LiveActivityAttributes.swift`
- `broadcastStateToWatch()` is called in all 6 locations: `startTimer`, `pause`, `skip`, `moveToNextInterval`, `finishWorkout`, `reset`
- `currentHeartRate = nil` is in both `finishWorkout` and `reset`

### Check 2 — Verify no iOS-only APIs in Watch files
The Watch files must not import or use:
- `UIKit` (use `SwiftUI` only)
- `ActivityKit`
- `AVFoundation` / `AVSpeechSynthesizer`
- `UIImpactFeedbackGenerator` (use `WKInterfaceDevice.current().play()` instead)

### Check 3 — Verify no watchOS-only APIs in iOS files
- `WKInterfaceDevice` is watchOS only — must not appear in any `N4x4/` file
- `HKWorkoutSession` in `WorkoutManager.swift` is fine on watchOS; the iOS app uses `HKWorkoutSession` differently (for saving, not for live collection)

### Check 4 — Imports
Each new file needs the correct imports. Summary:
| File | Required imports |
|---|---|
| `PhoneSessionManager.swift` | `WatchConnectivity`, `Foundation` |
| `WatchSessionManager.swift` | `WatchConnectivity`, `Foundation` |
| `WorkoutManager.swift` | `Foundation`, `HealthKit`, `WatchConnectivity` |
| `WatchTimerView.swift` | `SwiftUI`, `WatchKit` |
| `N4x4Complication.swift` | `WidgetKit`, `SwiftUI` |
| `WatchMessage.swift` | `Foundation` |
| `N4x4WatchApp.swift` | `SwiftUI` |

### Check 5 — SettingsView import
`SettingsView.swift` needs `import WatchConnectivity` at the top. Verify it's there.

---

## Common Pitfalls to Avoid

1. **Do not call `WCSession.default.activate()` more than once per side.** The `activate()` function in `PhoneSessionManager` guards with `WCSession.isSupported()`. Do not add duplicate calls elsewhere.

2. **`startActivity` before `beginCollection`.** The order inside `WorkoutManager.startWorkout()` is critical — `session.startActivity(with:)` must happen before `builder.beginCollection(withStart:)`.

3. **`WorkoutPhase` is the shared type.** Never use `IntervalType` in cross-target communication — it has no `rawValue` and cannot be serialised. `WorkoutPhase` maps cleanly to it.

4. **`sessionDidBecomeInactive` and `sessionDidDeactivate` are iOS-only.** Do not add these to `WatchSessionManager`.

5. **HR only shows when `> 0`.** The Watch optical sensor takes 5–10 seconds to first read. The UI already guards with `if workoutManager.heartRate > 0` — keep this guard in place.

6. **Do not put `@main` in both the complication and the Watch app in the same target.** The `@main` in `N4x4Complication.swift` must be in the `N4x4Complication` Widget Extension target. The `@main` in `N4x4WatchApp.swift` must be in the `N4x4Watch` app target. If Xcode created a default app file with `@main`, replace it entirely.

---

## Notes for the Human After Agent Finishes

Tell the human to follow **Step 10** in `Watch App - Manual Xcode Steps.md` to:
1. Assign each new file to the correct target in Xcode's File Inspector
2. Add `WatchConnectivity.framework` to the Watch target if the build complains about missing symbols
3. Build and test on physical hardware for HR
