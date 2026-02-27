# Apple Watch App — Implementation Plan

## Key Architectural Decision

The **phone is the single source of truth**. The Watch renders what the phone tells it and sends back control commands. The critical sync trick: pass `intervalEndTime` (an absolute wall-clock `Date`) in every message — the Watch can compute `timeRemaining` locally without needing a per-second message stream. This is the same technique the Dynamic Island already uses.

---

## Phase 1 — Xcode Setup

**Complexity: Simple | No code, just project config**

### Steps

1. **Add watchOS target**: File → New → Target → watchOS → App → name it `N4x4Watch`. Use SwiftUI `@main` lifecycle. Xcode 14+ gives you a single target with no separate Extension — that's correct.
2. **Deployment target**: watchOS 9.0 minimum (for updated `HKWorkoutSession` APIs).
3. **Add shared file memberships** — these files must compile in both targets:
   - `Interval.swift` — pure Swift, no UIKit, Watch-safe
   - `N4x4LiveActivityAttributes.swift` — wrap the `ActivityKit` import in `#if canImport(ActivityKit)` so the Watch target only gets `WorkoutPhase` (needed for colors and labels)
4. **Capabilities**: Add HealthKit to the Watch target. Add "Background Modes → Workout processing" to the iOS target.
5. **Info.plist (iOS)**: Add `workout-processing` to `UIBackgroundModes`.
6. **Info.plist (Watch)**: Add `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription`.

### Code change — `N4x4LiveActivityAttributes.swift`

```swift
#if canImport(ActivityKit)
import ActivityKit
#endif
import Foundation
import SwiftUI

#if canImport(ActivityKit)
struct N4x4LiveActivityAttributes: ActivityAttributes {
    // ... existing content unchanged ...
}
#endif

// WorkoutPhase stands alone — no ActivityKit dependency
// (already defined here, just ensure it stays outside the #if block)
enum WorkoutPhase: String, Codable, Hashable {
    // ... existing content unchanged ...
}
```

### Gotchas

- The Watch bundle ID must be `<ios-bundle-id>.watchkitapp` — Xcode sets this automatically, don't change it.
- Do NOT add `SpeechManager.swift` to the Watch target — haptics replace audio on the Watch.
- If Xcode gives you a separate "Extension" target inside the Watch app, that is the legacy watchOS 6 pattern. The modern single-target approach (Xcode 14+) is correct.

---

## Phase 2 — WatchConnectivity Protocol

**Complexity: Medium | 3 new files**

### Architecture

```
iPhone (source of truth)           Apple Watch (renderer + input)
───────────────────────            ──────────────────────────────
PhoneSessionManager                WatchSessionManager
  │                                  │
  │── state_sync ──────────────────► │── timerState: WatchTimerState
  │◄─ cmd_startPause ────────────────│
  │◄─ cmd_skip ───────────────────── │
  │◄─ hr_update ──────────────────── │   WorkoutManager
  │◄─ request_state ──────────────── │     └── HKWorkoutSession
```

### File 1: `Shared/WatchMessage.swift` (both targets)

Defines all message type constants and dictionary keys. No logic — just `static let` strings.

```swift
import Foundation

enum WatchMessageKey {
    static let messageType          = "type"

    // Commands: Watch → Phone
    static let cmdStartPause        = "cmd_startPause"
    static let cmdSkip              = "cmd_skip"
    static let cmdRequestState      = "request_state"

    // State sync: Phone → Watch
    static let stateSync            = "state_sync"
    static let isRunning            = "isRunning"
    static let currentIntervalIndex = "currentIntervalIndex"
    static let intervalEndTime      = "intervalEndTime"   // Double (timeIntervalSince1970)
    static let intervalName         = "intervalName"
    static let intervalDuration     = "intervalDuration"
    static let phase                = "phase"             // WorkoutPhase rawValue
    static let highIntensityCount   = "hitCount"
    static let totalIntervals       = "totalIntervals"
    static let hrLow                = "hrLow"
    static let hrHigh               = "hrHigh"
    static let workoutComplete      = "workoutComplete"

    // Heart rate: Watch → Phone
    static let heartRate            = "hr_update"
    static let hrBPM                = "hrBPM"             // Double
    static let hrTimestamp          = "hrTimestamp"       // Double
}
```

### File 2: `N4x4/PhoneSessionManager.swift` (iOS only)

```swift
import WatchConnectivity
import Foundation

final class PhoneSessionManager: NSObject, WCSessionDelegate {

    weak var timerViewModel: TimerViewModel?

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
            WCSession.default.sendMessage(payload, replyHandler: nil) { error in
                try? WCSession.default.updateApplicationContext(payload)
            }
        } else {
            try? WCSession.default.updateApplicationContext(payload)
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if state == .activated {
            DispatchQueue.main.async { [weak self] in
                guard let vm = self?.timerViewModel else { return }
                self?.sendStateUpdate(to: vm)
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()   // Required for Watch-switching support
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.handle(message) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async { [weak self] in self?.handle(message) }
        replyHandler([:])
    }

    private func handle(_ message: [String: Any]) {
        guard let vm = timerViewModel,
              let type = message[WatchMessageKey.messageType] as? String else { return }
        switch type {
        case WatchMessageKey.cmdStartPause:     vm.pause()
        case WatchMessageKey.cmdSkip:           vm.skip()
        case WatchMessageKey.cmdRequestState:   sendStateUpdate(to: vm)
        case WatchMessageKey.heartRate:
            if let bpm = message[WatchMessageKey.hrBPM] as? Double {
                vm.currentHeartRate = bpm
            }
        default: break
        }
    }
}
```

### File 3: `N4x4Watch/WatchSessionManager.swift` (watchOS only)

```swift
import WatchConnectivity
import Foundation

final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {

    @Published var timerState: WatchTimerState = .idle

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendStartPause() { send(WatchMessageKey.cmdStartPause) }
    func sendSkip()        { send(WatchMessageKey.cmdSkip) }

    func requestStateFromPhone() {
        guard WCSession.isSupported(), WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            [WatchMessageKey.messageType: WatchMessageKey.cmdRequestState],
            replyHandler: nil, errorHandler: nil
        )
    }

    private func send(_ type: String) {
        guard WCSession.isSupported() else { return }
        let msg = [WatchMessageKey.messageType: type]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: nil, errorHandler: { _ in
                WCSession.default.transferUserInfo(msg)
            })
        } else {
            WCSession.default.transferUserInfo(msg)
        }
    }

    func session(_ session: WCSession,
                 activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.applyState(message) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext ctx: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.applyState(ctx) }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.applyState(userInfo) }
    }

    private func applyState(_ p: [String: Any]) {
        guard (p[WatchMessageKey.messageType] as? String) == WatchMessageKey.stateSync else { return }
        timerState = WatchTimerState(
            isRunning:            p[WatchMessageKey.isRunning] as? Bool ?? false,
            intervalEndTime:      Date(timeIntervalSince1970: p[WatchMessageKey.intervalEndTime] as? Double ?? 0),
            intervalName:         p[WatchMessageKey.intervalName] as? String ?? "",
            intervalDuration:     p[WatchMessageKey.intervalDuration] as? Double ?? 0,
            phase:                WorkoutPhase(rawValue: p[WatchMessageKey.phase] as? String ?? "") ?? .warmup,
            highIntensityCount:   p[WatchMessageKey.highIntensityCount] as? Int ?? 0,
            totalIntervals:       p[WatchMessageKey.totalIntervals] as? Int ?? 4,
            hrLow:                p[WatchMessageKey.hrLow] as? Int ?? 0,
            hrHigh:               p[WatchMessageKey.hrHigh] as? Int ?? 0,
            workoutComplete:      p[WatchMessageKey.workoutComplete] as? Bool ?? false,
            currentIntervalIndex: p[WatchMessageKey.currentIntervalIndex] as? Int ?? 0
        )
    }
}

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

    // Computed live from the absolute end-time — no per-second messages needed
    var timeRemaining: TimeInterval { max(0, intervalEndTime.timeIntervalSinceNow) }

    var progressValue: CGFloat {
        guard intervalDuration > 0 else { return 0 }
        return CGFloat(min(1, max(0, timeRemaining / intervalDuration)))
    }

    static let idle = WatchTimerState(
        isRunning: false, intervalEndTime: Date(), intervalName: "Ready",
        intervalDuration: 0, phase: .warmup, highIntensityCount: 0,
        totalIntervals: 4, hrLow: 0, hrHigh: 0,
        workoutComplete: false, currentIntervalIndex: 0
    )
}
```

### Changes to `TimerViewModel.swift`

```swift
// Add at class scope:
let sessionManager = PhoneSessionManager()
@Published var currentHeartRate: Double? = nil

// In init(), after setupIntervals():
sessionManager.timerViewModel = self
sessionManager.activate()

// Add this method:
func broadcastStateToWatch() {
    sessionManager.sendStateUpdate(to: self)
}
```

Call `broadcastStateToWatch()` at the end of:
- `startTimer()`
- `pause()` (both branches)
- `skip()`
- `moveToNextInterval()`
- `finishWorkout()`
- `reset()`
- `reconcileTimerState()` when interval index advances

### Gotchas

- `WCSession.isSupported()` returns `false` on simulators with no paired Watch — always guard.
- `sessionDidDeactivate` **must** reactivate on iOS. Omitting this causes a permanent session drop when the user pairs a new Watch.
- Never use `transferUserInfo` for real-time state sync — it has no ordering guarantee. Use it only as a fallback when `isReachable` is false.
- `applicationContext` is limited to 65 KB and is replaced (not queued) on each call. Fine for timer state.

---

## Phase 3 — HKWorkoutSession on Watch (Heart Rate)

**Complexity: Complex | 1 new file**

### File: `N4x4Watch/WorkoutManager.swift` (watchOS only)

```swift
import Foundation
import HealthKit
import WatchConnectivity

final class WorkoutManager: NSObject, ObservableObject {

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    @Published var heartRate: Double = 0
    @Published var isSessionActive: Bool = false

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { completion(false); return }
        let hrType      = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let energyType  = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        healthStore.requestAuthorization(
            toShare: [HKObjectType.workoutType(), energyType],
            read:    [hrType, energyType, HKObjectType.workoutType()]
        ) { success, _ in DispatchQueue.main.async { completion(success) } }
    }

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
            builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                          workoutConfiguration: config)
            let start = Date()
            session?.startActivity(with: start)          // ← MUST come first
            builder?.beginCollection(withStart: start) { _, _ in }
            isSessionActive = true
        } catch {
            print("[WorkoutManager] start error: \(error)")
        }
    }

    func stopWorkout() {
        guard isSessionActive else { return }
        session?.end()
        isSessionActive = false
    }

    private func streamHeartRate(_ bpm: Double) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            [WatchMessageKey.messageType: WatchMessageKey.heartRate,
             WatchMessageKey.hrBPM:       bpm,
             WatchMessageKey.hrTimestamp: Date().timeIntervalSince1970],
            replyHandler: nil, errorHandler: nil
        )
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ session: HKWorkoutSession,
                        didChangeTo to: HKWorkoutSessionState,
                        from: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async { self.isSessionActive = (to == .running) }
    }
    func workoutSession(_ session: HKWorkoutSession, didFailWithError error: Error) {
        print("[WorkoutManager] session error: \(error)")
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(hrType) else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        guard let bpm = workoutBuilder.statistics(for: hrType)?
                .mostRecentQuantity()?.doubleValue(for: unit) else { return }
        DispatchQueue.main.async {
            self.heartRate = bpm
            self.streamHeartRate(bpm)
        }
    }
}
```

### Lifecycle wiring (`N4x4WatchApp.swift`)

```swift
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

### Gotchas

- **`session.startActivity` must come before `builder.beginCollection`**. The reverse crashes on some watchOS versions.
- HR sensor updates every ~5 seconds. Don't show "-- BPM" for the first 5–10s — only show when `heartRate > 0`.
- `HKWorkoutSession` cannot be started from the Watch Simulator. Always test HR on physical hardware.
- HealthKit authorization on Watch is entirely separate from iPhone. The user sees a second auth sheet on the Watch.
- The `HKWorkoutSession` background mode is what keeps the Watch app alive during a workout. No additional entitlement needed beyond HealthKit.

---

## Phase 4 — Watch UI

**Complexity: Medium | 1 new file**

### Layout (`N4x4Watch/WatchTimerView.swift`)

```
  Work 2/4              ← phase label, colored per WorkoutPhase.color
┌──────────────────┐
│     03:47        │    ← countdown, monospaced bold 28pt
│   ♥ 142 bpm      │    ← HR in zone color (green/yellow/red)
└──────────────────┘    ← progress arc: Circle().trim, same formula as phone
      [▶] [⏭]           ← 52×44pt tap targets
```

```swift
struct WatchTimerView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var tick = Date()
    @State private var lastIntervalIndex = 0
    @Environment(\.scenePhase) var scenePhase
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var state: WatchTimerState { sessionManager.timerState }

    var body: some View {
        VStack(spacing: 4) {

            // Interval label
            Text(intervalLabel)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(state.phase.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Progress ring + time + HR
            ZStack {
                Circle().stroke(Color.gray.opacity(0.25), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: state.progressValue)
                    .stroke(style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .foregroundColor(state.phase.color)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: state.timeRemaining)

                VStack(spacing: 2) {
                    Text(timeString(state.timeRemaining))
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
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

            // Controls
            HStack(spacing: 16) {
                Button { sessionManager.sendStartPause() } label: {
                    Image(systemName: state.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 52, height: 44)
                        .background(Color.gray.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button { sessionManager.sendSkip() } label: {
                    Image(systemName: "forward.end.alt.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 52, height: 44)
                        .background(Color.gray.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .onReceive(timer) { tick = $0 }
        .onChange(of: state.isRunning) { _, running in
            if running, !workoutManager.isSessionActive { workoutManager.startWorkout() }
            if !running, workoutManager.isSessionActive, state.workoutComplete { workoutManager.stopWorkout() }
        }
        .onChange(of: state.currentIntervalIndex) { _, newIndex in
            if newIndex != lastIntervalIndex {
                lastIntervalIndex = newIndex
                WKInterfaceDevice.current().play(.notification)
            }
        }
        .onChange(of: state.workoutComplete) { _, complete in
            if complete { WKInterfaceDevice.current().play(.success) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { sessionManager.requestStateFromPhone() }
        }
    }

    private var intervalLabel: String {
        switch state.phase {
        case .highIntensity: return "Work \(state.highIntensityCount)/\(state.totalIntervals)"
        case .rest:          return "Recovery"
        case .warmup:        return "Warm Up"
        }
    }

    private var hrColor: Color {
        let bpm = workoutManager.heartRate
        guard state.hrLow > 0 else { return .white }
        if bpm < Double(state.hrLow) { return .yellow }
        if bpm > Double(state.hrHigh) { return .red }
        return .green
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60 % 60, Int(t) % 60)
    }
}
```

### Watch Complication (watchOS 9+ WidgetKit)

Add a separate **Widget Extension** target (File → New → Target → Widget Extension, uncheck "Include Configuration Intent"). Supports `.accessoryCircular`, `.accessoryCorner`, `.accessoryRectangular`. Uses `bolt.heart.fill` icon + `.widgetURL(URL(string: "n4x4watch://open"))` for tap-to-launch.

### Gotchas

- Set `.minimumScaleFactor(0.7)` on all text — the 40mm/41mm display is narrower than expected.
- Use plain `VStack` as root, not `NavigationView` — the back button would pollute the minimal timer UI.
- `WKInterfaceDevice.current().play()` must be called on the main thread.
- `.play(.notification)` = crown haptic (distinct click). `.play(.success)` = workout complete. Both available since watchOS 2.

---

## Phase 5 — State Sync Edge Cases

**Complexity: Medium**

| Scenario | How it's handled |
|---|---|
| Watch launches mid-workout | `activationDidCompleteWith` fires → phone calls `sendStateUpdate()` → Watch receives via `applicationContext` |
| Phone goes to background | `workout-processing` background mode keeps the phone's timer alive; Watch commands arrive via background WCSession delivery |
| Bluetooth drops mid-workout | Watch computes `timeRemaining` locally from `intervalEndTime` (stays accurate). Controls don't work until reconnection. No reconciliation loop needed. |
| Watch app comes to foreground | `scenePhase == .active` → `requestStateFromPhone()` → phone replies immediately |
| Interval crosses zero on Watch | Watch shows 00:00 briefly (~1s). Phone broadcasts new state in `moveToNextInterval()` before returning. |

---

## Phase 6 — Phone-Side Changes

**Complexity: Simple**

### `TimerView.swift` — HR display during workout

```swift
// Add below heartRateZoneText, inside the main VStack:
if let hr = viewModel.currentHeartRate, viewModel.isRunning {
    HStack(spacing: 6) {
        Image(systemName: "applewatch.watchface")
            .font(.system(size: 14))
            .foregroundColor(.secondary)
        Image(systemName: "heart.fill")
            .font(.system(size: 14))
            .foregroundColor(hrZoneColor(hr))
        Text("\(Int(hr)) BPM")
            .font(.system(size: 20, weight: .semibold, design: .monospaced))
            .foregroundColor(hrZoneColor(hr))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(Color(UIColor.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 10))
}

// Helper:
private func hrZoneColor(_ bpm: Double) -> Color {
    guard viewModel.intervals.indices.contains(viewModel.currentIntervalIndex) else { return .secondary }
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

### `TimerViewModel.swift` — clear HR on workout end

```swift
// In reset() and finishWorkout():
currentHeartRate = nil
```

### `SettingsView.swift` — Watch section

```swift
Section("Apple Watch") {
    Toggle("Stream heart rate from Watch", isOn: $viewModel.watchHeartRateEnabled)
    if WCSession.isSupported() {
        Label(
            WCSession.default.isWatchAppInstalled ? "Watch app installed" : "Watch app not installed",
            systemImage: WCSession.default.isWatchAppInstalled ? "applewatch.watchface" : "applewatch.slash"
        )
        .foregroundColor(.secondary)
        .font(.caption)
    }
}
```

---

## Phase 7 — Testing

**Complexity: Simple | Requires real hardware**

| # | Scenario | Expected result |
|---|---|---|
| 1 | Cold-start Watch with workout in progress | Timer state immediately correct, arc at right position |
| 2 | Start workout from Watch | Phone starts, voice cues fire |
| 3 | Interval transition on phone | Watch shows new interval + haptic fires within ~1s |
| 4 | Skip from Watch | Phone advances, new state broadcast back to Watch |
| 5 | HR after 30s of running | BPM appears on Watch and phone in correct zone color |
| 6 | Phone in airplane mode 10s → reconnect | Watch timer accurate during gap, controls resume |
| 7 | Workout complete | Watch shows completion state + `.success` haptic |

---

## Files Summary

### New files to create

| File | Target | Purpose |
|---|---|---|
| `Shared/WatchMessage.swift` | iOS + watchOS | Message key constants |
| `N4x4/PhoneSessionManager.swift` | iOS | WCSession phone side |
| `N4x4Watch/N4x4WatchApp.swift` | watchOS | `@main` entry point |
| `N4x4Watch/WatchSessionManager.swift` | watchOS | WCSession watch side + state model |
| `N4x4Watch/WatchTimerView.swift` | watchOS | Main Watch UI |
| `N4x4Watch/WorkoutManager.swift` | watchOS | HKWorkoutSession + HR streaming |
| `N4x4Watch/N4x4Complication.swift` | watchOS Widget Ext | Watch face complication |

### Existing files to modify

| File | Change |
|---|---|
| `N4x4/TimerViewModel.swift` | Add `PhoneSessionManager`, `currentHeartRate`, `broadcastStateToWatch()` call sites |
| `N4x4/TimerView.swift` | Add HR display block + `hrZoneColor()` helper |
| `N4x4/N4x4LiveActivityAttributes.swift` | Wrap `ActivityKit` in `#if canImport(ActivityKit)`, add Watch target membership |
| `N4x4/Interval.swift` | Add Watch target membership (no code changes) |
| `N4x4/Info.plist` | Add `workout-processing` to `UIBackgroundModes` |
| `N4x4/SettingsView.swift` | Add Watch section with HR toggle + install status |

---

## Key Non-Obvious Decisions

1. **Never make the Watch the source of truth.** If both sides run independent timers, they will drift within seconds. Phone drives, Watch renders.

2. **`intervalEndTime` is the sync anchor.** Passing an absolute `Date` means the Watch computes `timeRemaining` locally — no per-second messages needed. The same technique powers the Dynamic Island.

3. **`WorkoutPhase` is the cross-target type bridge.** It's already `Codable`, `Hashable`, and carries `.color` and `.shortLabel`. Use it in all messages. Never put `IntervalType` in messages — it has no `rawValue` and can't be serialised.

4. **`sessionDidDeactivate` must reactivate on iOS.** Required when the user pairs a new Watch. Omitting it causes a silent permanent session drop.

5. **HR sampling is ~5s.** Don't show a stale or zero value in the UI. Only display HR when `heartRate > 0`.

6. **Separate HealthKit permissions per device.** The phone's existing VO2 max auth is separate from the Watch's HKWorkoutSession auth. Both must be requested independently.

7. **`@main` conflict with complication.** The Watch app and the Watch Widget Extension are separate targets precisely because both need `@main`. Xcode handles this automatically when you add the Widget Extension target.

8. **`applicationContext` replaces, not queues.** If state updates arrive faster than the Watch can process, only the latest matters. This is correct behaviour for a timer.

---

## Implementation Order

```
Phase 1 (Xcode setup)
    │
    ▼
Phase 2 (WatchConnectivity — phone + watch session managers)
    │
    ├──────────────┐
    ▼              ▼
Phase 3           Phase 4
(HKWorkoutSession  (Watch UI)
  + HR streaming)
    │
    ▼
Phase 5 (Edge cases — connectivity drops, cold launch, etc.)
    │
    ▼
Phase 6 (Phone-side HR display + settings)
    │
    ▼
Phase 7 (Testing on physical hardware)
```

Phases 3 and 4 can be built in parallel once Phase 2 is working on the bench.

**Estimated total effort: 3–4 focused days.**
