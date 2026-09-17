// PhoneSessionManager.swift
// iOS side of WatchConnectivity.
// Owned by TimerViewModel. Sends timer state to the Watch; receives control
// commands and streamed heart rate back from the Watch.

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

    var isWatchAppInstalled: Bool {
        WCSession.isSupported()
            && WCSession.default.activationState == .activated
            && WCSession.default.isWatchAppInstalled
    }

    // MARK: - Send state to Watch

    func sendStateUpdate(to vm: TimerViewModel) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isWatchAppInstalled else { return }

        // intervalEndTime (an absolute Date) is the sync anchor: the Watch
        // derives timeRemaining from it locally, so no per-second messages are
        // needed. Same technique the Dynamic Island uses.
        let endTime = vm.intervalEndTime?.timeIntervalSince1970
            ?? Date().addingTimeInterval(vm.timeRemaining).timeIntervalSince1970

        let interval = vm.intervals.indices.contains(vm.currentIntervalIndex)
            ? vm.intervals[vm.currentIntervalIndex] : nil

        // Send the CURRENT phase's target range (not always the work range) so
        // the Watch can colour-code and run zone-haptic feedback for recovery too.
        let range = vm.currentPhaseHRRange
        let hrLow = range?.lowerBound ?? 0
        let hrHigh = range?.upperBound ?? 0

        let payload: [String: Any] = [
            WatchMessageKey.messageType:            WatchMessageKey.stateSync,
            WatchMessageKey.isRunning:              vm.isRunning,
            WatchMessageKey.currentIntervalIndex:   vm.currentIntervalIndex,
            WatchMessageKey.intervalEndTime:        endTime,
            WatchMessageKey.timeRemaining:          vm.timeRemaining,
            WatchMessageKey.intervalName:           interval?.name ?? "",
            WatchMessageKey.intervalDuration:       interval?.duration ?? 0.0,
            WatchMessageKey.phase:                  vm.currentWorkoutPhase.rawValue,
            WatchMessageKey.highIntensityCount:     vm.highIntensityCount,
            WatchMessageKey.totalIntervals:         vm.numberOfIntervals,
            WatchMessageKey.hrLow:                  hrLow,
            WatchMessageKey.hrHigh:                 hrHigh,
            WatchMessageKey.workoutComplete:        vm.showPostWorkoutSummary,
            WatchMessageKey.sessionStarted:         vm.workoutStartDate != nil,
            WatchMessageKey.zoneHapticEnabled:      vm.zoneHapticAlertsEnabled,
            WatchMessageKey.intervalHapticsEnabled: vm.hapticsEnabled,
            // Home-screen extras so the Watch can mirror the phone: streak
            // header and the full interval plan (timeline bar + "N min left").
            WatchMessageKey.streak:                 vm.currentStreak,
            WatchMessageKey.planPhases:             vm.intervals.map { workoutPhase(for: $0.type).rawValue },
            WatchMessageKey.planDurations:          vm.intervals.map { $0.duration },
            // Per-phase targets + default type so the Watch can run (and log)
            // a workout on its own when the phone is out of reach.
            WatchMessageKey.workHRLow:              vm.highIntensityTargetRange.lowerBound,
            WatchMessageKey.workHRHigh:             vm.highIntensityTargetRange.upperBound,
            WatchMessageKey.recoveryHRLow:          vm.recoveryTargetRange.lowerBound,
            WatchMessageKey.recoveryHRHigh:         vm.recoveryTargetRange.upperBound,
            WatchMessageKey.workoutTypeRaw:         vm.resolvedDefaultWorkoutType.rawValue,
        ]

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil) { _ in
                // Fallback: stash in applicationContext so the Watch gets the
                // latest state on its next connection.
                try? WCSession.default.updateApplicationContext(payload)
            }
        } else {
            try? WCSession.default.updateApplicationContext(payload)
        }
    }

    /// Mirrors `TimerViewModel.currentWorkoutPhase` for any interval so the
    /// Watch can draw the whole plan, not just the current phase.
    private func workoutPhase(for type: IntervalType) -> WorkoutPhase {
        switch type {
        case .warmup:        return .warmup
        case .highIntensity: return .highIntensity
        case .rest:          return .rest
        case .cooldown:      return .cooldown
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        guard activationState == .activated else { return }
        refreshWatchState()
        DispatchQueue.main.async { [weak self] in
            guard let vm = self?.timerViewModel else { return }
            self?.sendStateUpdate(to: vm)
        }
    }

    /// Fired when the Watch is paired/unpaired or the Watch app is installed/removed.
    func sessionWatchStateDidChange(_ session: WCSession) {
        refreshWatchState()
    }

    /// Fired when live reachability changes (Watch app foregrounded/backgrounded).
    func sessionReachabilityDidChange(_ session: WCSession) {
        refreshWatchState()
    }

    /// Read the current WCSession flags and push them to the view model so the UI
    /// can show connection status and drive troubleshooting.
    private func refreshWatchState() {
        let activated = WCSession.isSupported()
            && WCSession.default.activationState == .activated
        let paired = activated && WCSession.default.isPaired
        let installed = activated && WCSession.default.isWatchAppInstalled
        let reachable = activated && WCSession.default.isReachable
        DispatchQueue.main.async { [weak self] in
            self?.timerViewModel?.updateWatchConnectionState(
                paired: paired, installed: installed, reachable: reachable
            )
        }
    }

    // Required on iOS so the session survives the user switching Watches.
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

    /// Queued delivery (transferUserInfo) — how the Watch hands over workouts
    /// it ran on its own. Guaranteed and ordered, delivered whenever the phone
    /// is next reachable, even if that is hours later.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        DispatchQueue.main.async { [weak self] in self?.handle(userInfo) }
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
        case WatchMessageKey.cmdReset:
            vm.deleteCurrentWorkoutAndResetSession()
        case WatchMessageKey.cmdRequestState:
            sendStateUpdate(to: vm)
        case WatchMessageKey.heartRate:
            if let bpm = message[WatchMessageKey.hrBPM] as? Double {
                vm.ingestHeartRate(bpm, from: .watch)
            }
        case WatchMessageKey.workoutCompleted:
            handleCompletedWatchWorkout(message, vm: vm)
        case WatchMessageKey.workoutDiscard:
            if let idString = message[WatchMessageKey.workoutID] as? String,
               let id = UUID(uuidString: idString) {
                vm.discardWatchWorkout(id: id)
            }
        default:
            break
        }
    }

    // MARK: - Standalone Watch workouts

    /// Import (idempotent) and always ack by id — an already-imported or
    /// discarded record still needs acking so the Watch can clear its queue.
    /// A record that fails to decode is not acked; the Watch keeps it and the
    /// next app build can try again.
    private func handleCompletedWatchWorkout(_ message: [String: Any], vm: TimerViewModel) {
        guard let idString = message[WatchMessageKey.workoutID] as? String,
              let data = message[WatchMessageKey.workoutRecord] as? Data,
              let record = CompletedWatchWorkout.decode(data),
              record.id.uuidString == idString else { return }
        vm.importWatchWorkout(record)
        ackWatchWorkout(id: idString)
    }

    private func ackWatchWorkout(id: String) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo([
            WatchMessageKey.messageType: WatchMessageKey.workoutAck,
            WatchMessageKey.workoutID:   id,
        ])
    }
}
