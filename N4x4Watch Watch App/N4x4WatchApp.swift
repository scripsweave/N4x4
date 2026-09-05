// N4x4WatchApp.swift
// watchOS app entry point and root routing.
//
// The root owns everything that must outlive a single screen: the
// HKWorkoutSession lifecycle, interval/countdown haptics and the foreground
// re-sync. The screens (Home / Workout / Complete) are pure rendering and are
// swapped by the phone's state, so a state change that swaps screens can never
// drop a lifecycle event — the previous design hung these on the workout view,
// which is unmounted exactly when the final "complete" state arrives.

import SwiftUI
import WatchKit

@main
struct N4x4WatchApp: App {

    @StateObject private var sessionManager = WatchSessionManager()
    @StateObject private var workoutManager = WorkoutManager()
    /// DEBUG-only layout/screenshot mode
    /// (`-demoState home|offline|workout|paused|controls|complete|local|localComplete`).
    private let demo = WatchDemoState.fromLaunchArguments()

    var body: some Scene {
        WindowGroup {
            WatchRootView(demo: demo)
                .environmentObject(sessionManager)
                .environmentObject(workoutManager)
                .onAppear {
                    if let demo {
                        demo.apply(to: sessionManager, workoutManager)
                        return
                    }
                    sessionManager.activate()
                    workoutManager.requestAuthorization { _ in }
                    workoutManager.discardAbandonedSession()
                }
        }
    }
}

// MARK: - Root

private struct WatchRootView: View {
    var demo: WatchDemoState? = nil
    private var demoMode: Bool { demo != nil }

    @EnvironmentObject var sessionManager: WatchSessionManager
    @EnvironmentObject var workoutManager: WorkoutManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var lastIntervalIndex = 0
    /// Pending countdown-tap haptics for the current interval; cancelled and
    /// rebuilt whenever fresh state arrives from the phone.
    @State private var countdownTaps: [DispatchWorkItem] = []

    private var state: WatchTimerState { sessionManager.timerState }

    var body: some View {
        Group {
            if state.workoutComplete {
                WatchCompleteView()
            } else if state.sessionStarted {
                WatchTimerView(initialPage: demo?.screen == .controls ? 1 : 0)
            } else {
                WatchHomeView()
            }
        }
        .onAppear { syncWorkoutSession(for: state) }

        // Drive the zone-feedback engine off each fresh HR reading, and keep
        // the Watch-led series (local mode records; mirror mode ignores).
        .onChange(of: workoutManager.heartRate) { _, bpm in
            sessionManager.evaluateZoneHaptic(bpm: bpm)
            sessionManager.recordHeartRate(bpm)
        }

        .onChange(of: sessionManager.timerState) { _, s in
            syncWorkoutSession(for: s)
            scheduleCountdownTaps(for: s)
        }

        // Long buzz as the new interval starts — closes the two-short-taps
        // countdown. Only while actively running, so the reset-to-idle index
        // change doesn't fire a spurious buzz.
        .onChange(of: state.currentIntervalIndex) { _, newIndex in
            let advanced = newIndex != lastIntervalIndex
            lastIntervalIndex = newIndex
            if advanced, state.isRunning, state.intervalHapticsEnabled {
                WKInterfaceDevice.current().play(.notification)
            }
        }

        // The workout's end is signalled by the two countdown taps alone —
        // no closing buzz, since no new interval starts.
        .onChange(of: state.workoutComplete) { _, complete in
            if complete {
                countdownTaps.forEach { $0.cancel() }
                countdownTaps = []
            }
        }

        // Foreground return: catch the engine up, re-sync, retry pending uploads.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !demoMode { sessionManager.appDidBecomeActive() }
        }
    }

    // MARK: HKWorkoutSession lifecycle

    /// The session must be active while running OR paused mid-workout, and
    /// ended on completion, reset, or abandon. Keying only off `isRunning`
    /// leaked the session on every non-completed exit. Evaluated on appear as
    /// well as on change, so a state that arrives before the view mounts still
    /// starts HR streaming.
    private func syncWorkoutSession(for s: WatchTimerState) {
        guard !demoMode else { return }
        let shouldRun = s.isRunning || (!s.workoutComplete && s.intervalDuration > 0)
        if shouldRun, !workoutManager.isSessionActive {
            workoutManager.startWorkout()
        } else if !shouldRun, workoutManager.isSessionActive {
            workoutManager.stopWorkout()
        }
    }

    // MARK: Countdown haptics

    /// Two short wrist taps at ~3 s and ~2 s before the interval boundary,
    /// mirroring the phone. The boundary itself gets the long buzz (interval
    /// change handler above); after the final interval nothing follows, so
    /// the taps stand alone. Scheduled off the absolute end time because
    /// watchOS timers tied to view updates are throttled.
    private func scheduleCountdownTaps(for s: WatchTimerState) {
        countdownTaps.forEach { $0.cancel() }
        countdownTaps = []
        guard s.isRunning, s.intervalHapticsEnabled, !s.workoutComplete else { return }

        for lead in [3.0, 2.0] {
            let delay = s.intervalEndTime.timeIntervalSinceNow - lead
            guard delay > 0 else { continue }
            let tap = DispatchWorkItem { WKInterfaceDevice.current().play(.click) }
            countdownTaps.append(tap)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: tap)
        }
    }
}

// MARK: - Demo state (DEBUG screenshots / layout checks)

/// Injects a representative state so every screen can be viewed in the
/// Simulator without a paired phone or a live HKWorkoutSession. Launch with
/// `-demoState home|offline|workout|paused|controls|complete|local|localComplete`.
/// Inert in Release builds.
struct WatchDemoState {
    enum Screen: String { case home, offline, workout, paused, controls, complete, local, localComplete }
    let screen: Screen

    static func fromLaunchArguments() -> WatchDemoState? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoState"), i + 1 < args.count,
              let screen = Screen(rawValue: args[i + 1]) else { return nil }
        return WatchDemoState(screen: screen)
        #else
        return nil
        #endif
    }

    func apply(to session: WatchSessionManager, _ workout: WorkoutManager) {
        #if DEBUG
        var s = WatchTimerState.idle
        s.streak = 7
        s.totalIntervals = 4
        s.planPhases = [.warmup, .highIntensity, .rest, .highIntensity, .rest,
                        .highIntensity, .rest, .highIntensity, .cooldown]
        s.planDurations = [600, 240, 180, 240, 180, 240, 180, 240, 300]
        s.intervalDuration = 600
        s.workLow = 158; s.workHigh = 172
        s.recoveryLow = 112; s.recoveryHigh = 130

        switch screen {
        case .home, .offline:
            break
        case .local, .localComplete:
            // Cache the plan via a phone state, then start on the Watch with
            // the phone "out of range", back-dated so the engine has progress.
            session.injectDemo(phoneState: s, reachable: false)
            let lead: TimeInterval = (screen == .local) ? 700 : 3000
            session.startLocalWorkout(now: Date().addingTimeInterval(-lead))
            workout.heartRate = (screen == .local) ? 163 : 0
            return
        case .workout, .paused, .controls:
            s.sessionStarted = true
            s.isRunning = (screen != .paused)
            s.currentIntervalIndex = 3
            s.intervalDuration = 240
            s.phase = .highIntensity
            s.highIntensityCount = 2
            s.hrLow = 158
            s.hrHigh = 172
            s.intervalEndTime = Date().addingTimeInterval(151)
            s.reportedTimeRemaining = 151
            workout.heartRate = 148
        case .complete:
            s.sessionStarted = true
            s.workoutComplete = true
        }

        session.injectDemo(phoneState: s, reachable: screen != .offline)
        #endif
    }
}
