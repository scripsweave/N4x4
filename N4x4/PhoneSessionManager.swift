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
            WatchMessageKey.zoneHapticEnabled:      vm.zoneHapticAlertsEnabled,
            WatchMessageKey.intervalHapticsEnabled: vm.hapticsEnabled,
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
                vm.ingestHeartRate(bpm, from: .watch)
            }
        default:
            break
        }
    }
}
