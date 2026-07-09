// WatchTimerView.swift
// Main Watch UI: phase label, progress ring, countdown, heart rate, and
// start/pause/skip controls. Heart rate is shown prominently and colour-coded
// to the live target zone; out-of-zone haptics are driven from here as each
// reading arrives.

import SwiftUI
import WatchKit

struct WatchTimerView: View {

    @EnvironmentObject var sessionManager: WatchSessionManager
    @EnvironmentObject var workoutManager: WorkoutManager

    @State private var lastIntervalIndex = 0
    @Environment(\.scenePhase) private var scenePhase

    private var state: WatchTimerState { sessionManager.timerState }

    var body: some View {
        VStack(spacing: 6) {

            // ── Phase label + countdown + progress ring ─────
            // TimelineView drives a smooth 1 s countdown (a plain Timer.publish
            // is throttled to ~5 s on watchOS). The centre shows the live heart
            // rate with a Speed Up / Slow Down coaching cue, matching the phone.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = state.timeRemaining(asOf: context.date)
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Text(intervalLabel)
                            .foregroundColor(state.phase.color)
                        Text(timeString(remaining))
                            .foregroundColor(.white.opacity(0.6))
                            .monospacedDigit()
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 8)

                        Circle()
                            .trim(from: 0, to: state.progressValue(asOf: context.date))
                            .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .foregroundColor(state.phase.color)
                            .rotationEffect(.degrees(-90))
                            .shadow(color: state.phase.color.opacity(0.6), radius: 4)

                        centerContent(remaining: remaining)
                    }
                    .frame(width: 128, height: 128)
                }
            }

            // ── Controls ────────────────────────────────────
            HStack(spacing: 14) {
                Button {
                    sessionManager.sendStartPause()
                } label: {
                    Image(systemName: state.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 54, height: 42)
                        .background(Color.white.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button {
                    sessionManager.sendSkip()
                } label: {
                    Image(systemName: "forward.end.alt.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 54, height: 42)
                        .background(Color.white.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        // Drive the zone-feedback engine off each fresh HR reading.
        .onChange(of: workoutManager.heartRate) { _, bpm in
            sessionManager.evaluateZoneHaptic(bpm: bpm)
        }

        // Start/stop the HKWorkoutSession alongside the timer.
        .onChange(of: state.isRunning) { _, isRunning in
            if isRunning, !workoutManager.isSessionActive {
                workoutManager.startWorkout()
            } else if !isRunning, workoutManager.isSessionActive, state.workoutComplete {
                workoutManager.stopWorkout()
            }
        }

        // Crown-click haptic on interval change.
        .onChange(of: state.currentIntervalIndex) { _, newIndex in
            guard newIndex != lastIntervalIndex else { return }
            lastIntervalIndex = newIndex
            WKInterfaceDevice.current().play(.notification)
        }

        // Success haptic on completion.
        .onChange(of: state.workoutComplete) { _, complete in
            if complete { WKInterfaceDevice.current().play(.success) }
        }

        // Re-sync when the Watch app returns to the foreground.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { sessionManager.requestStateFromPhone() }
        }
    }

    // MARK: - Helpers

    /// Ring centre: live heart rate with a Speed Up / Slow Down cue. Falls back
    /// to the countdown until a heart rate is streaming.
    @ViewBuilder
    private func centerContent(remaining: TimeInterval) -> some View {
        if workoutManager.heartRate > 0 {
            VStack(spacing: 1) {
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                    Text("\(Int(workoutManager.heartRate))")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                }
                if let cue = zoneCue {
                    Text(cue.text)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(cue.color)
                }
            }
        } else {
            Text(timeString(remaining))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
        }
    }

    private var intervalLabel: String {
        switch state.phase {
        case .highIntensity: return "HIGH \(state.highIntensityCount)/\(state.totalIntervals)"
        case .rest:          return "RECOVERY"
        case .warmup:        return "WARM UP"
        case .cooldown:      return "COOL DOWN"
        }
    }

    /// Coaching cue from live HR vs the target zone (matches the phone).
    private var zoneCue: (text: String, color: Color)? {
        switch sessionManager.zoneStatus(bpm: workoutManager.heartRate) {
        case .below:    return ("SPEED UP", .orange)
        case .above:    return ("SLOW DOWN", .cyan)
        case .inZone:   return ("IN ZONE", .green)
        case .noTarget: return nil
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60 % 60, Int(t) % 60)
    }
}
