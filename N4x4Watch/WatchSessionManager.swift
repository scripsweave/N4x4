// WatchSessionManager.swift
// watchOS side of WatchConnectivity.
// Receives timer state from the phone, sends control commands back, and runs
// the zone-feedback engine for wrist haptics.

import WatchConnectivity
import Foundation
import WatchKit

// MARK: - WatchTimerState

struct WatchTimerState: Equatable {
    var isRunning: Bool
    var intervalEndTime: Date
    var reportedTimeRemaining: Double
    var intervalName: String
    var intervalDuration: Double
    var phase: WorkoutPhase
    var highIntensityCount: Int
    var totalIntervals: Int
    var hrLow: Int
    var hrHigh: Int
    var workoutComplete: Bool
    var currentIntervalIndex: Int
    var zoneHapticEnabled: Bool

    /// While running, derive the countdown live from the absolute end-time so no
    /// per-second messages are needed. While paused, the end-time is a stale
    /// future date, so use the phone's last reported value — otherwise the Watch
    /// would keep counting down past a pause.
    var timeRemaining: TimeInterval {
        guard isRunning else { return max(0, reportedTimeRemaining) }
        return max(0, intervalEndTime.timeIntervalSinceNow)
    }

    var progressValue: CGFloat {
        guard intervalDuration > 0 else { return 0 }
        return CGFloat(min(1, max(0, timeRemaining / intervalDuration)))
    }

    /// Elapsed time within the current interval — feeds the zone-feedback grace window.
    var secondsSinceIntervalStart: TimeInterval {
        max(0, intervalDuration - timeRemaining)
    }

    static let idle = WatchTimerState(
        isRunning: false,
        intervalEndTime: Date(),
        reportedTimeRemaining: 0,
        intervalName: "Ready",
        intervalDuration: 0,
        phase: .warmup,
        highIntensityCount: 0,
        totalIntervals: 4,
        hrLow: 0,
        hrHigh: 0,
        workoutComplete: false,
        currentIntervalIndex: 0,
        zoneHapticEnabled: true
    )
}

// MARK: - WatchSessionManager

final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {

    @Published var timerState: WatchTimerState = .idle

    /// Drives haptic nudges when the wearer drifts out of zone.
    private let zoneEngine = ZoneFeedbackEngine()

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

    // MARK: - Zone feedback (haptics)

    /// Called with each fresh HR reading. Fires a distinct wrist haptic when the
    /// wearer has been sustainedly out of zone, subject to the grace window and
    /// the one-per-minute rate limit enforced by the shared engine.
    func evaluateZoneHaptic(bpm: Double) {
        let s = timerState
        guard s.isRunning, s.zoneHapticEnabled, bpm > 0 else { return }

        let alert = zoneEngine.evaluate(
            intervalKey: s.currentIntervalIndex,
            phase: s.phase,
            bpm: bpm,
            low: s.hrLow,
            high: s.hrHigh,
            secondsSinceIntervalStart: s.secondsSinceIntervalStart,
            now: Date()
        )

        guard let alert else { return }
        // .directionUp = "push" (HR too low); .directionDown = "ease off" (HR too high).
        let haptic: WKHapticType = (alert == .pushHarder) ? .directionUp : .directionDown
        WKInterfaceDevice.current().play(haptic)
    }

    /// Current zone classification for colour-coding the HR display.
    func zoneStatus(bpm: Double) -> HRZoneStatus {
        zoneEngine.status(phase: timerState.phase, bpm: bpm,
                          low: timerState.hrLow, high: timerState.hrHigh)
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}

    /// Real-time message (phone reachable).
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.applyStatePayload(message) }
    }

    /// Stored context — delivered when the Watch wasn't reachable at send time.
    func session(_ session: WCSession,
                 didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.applyStatePayload(applicationContext) }
    }

    /// Background user-info delivery.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.applyStatePayload(userInfo) }
    }

    // MARK: - State parsing

    private func applyStatePayload(_ p: [String: Any]) {
        guard (p[WatchMessageKey.messageType] as? String) == WatchMessageKey.stateSync else { return }

        let wasRunning = timerState.isRunning

        timerState = WatchTimerState(
            isRunning:            p[WatchMessageKey.isRunning]            as? Bool   ?? false,
            intervalEndTime:      Date(timeIntervalSince1970:
                                    p[WatchMessageKey.intervalEndTime]    as? Double ?? 0),
            reportedTimeRemaining: p[WatchMessageKey.timeRemaining]       as? Double ?? 0,
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
            currentIntervalIndex: p[WatchMessageKey.currentIntervalIndex] as? Int    ?? 0,
            zoneHapticEnabled:    p[WatchMessageKey.zoneHapticEnabled]    as? Bool   ?? true
        )

        // Clear any lingering zone-alert state when the workout stops/resets.
        if wasRunning && !timerState.isRunning { zoneEngine.reset() }
    }
}
