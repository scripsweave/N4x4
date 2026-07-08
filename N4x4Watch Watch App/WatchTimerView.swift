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

            // ── Phase label ─────────────────────────────────
            Text(intervalLabel)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(state.phase.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // ── Progress ring + countdown + HR ──────────────
            // TimelineView drives a smooth 1 s countdown. A plain Timer.publish
            // is throttled to ~5 s on watchOS; TimelineView is refreshed by the
            // system every second, so the ring and clock stay live.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = state.timeRemaining(asOf: context.date)
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.25), lineWidth: 6)

                    Circle()
                        .trim(from: 0, to: state.progressValue(asOf: context.date))
                        .stroke(style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .foregroundColor(state.phase.color)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 2) {
                        Text(timeString(remaining))
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)

                        if workoutManager.heartRate > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.red)
                                Text("\(Int(workoutManager.heartRate))")
                                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                                    .foregroundColor(hrColor)
                            }
                        }
                    }
                }
                .frame(width: 130, height: 130)
            }

            // ── Out-of-zone hint ────────────────────────────
            if let hint = zoneHint {
                Text(hint)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(hrColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            // ── Controls ────────────────────────────────────
            HStack(spacing: 16) {
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

    private var intervalLabel: String {
        switch state.phase {
        case .highIntensity: return "Work \(state.highIntensityCount)/\(state.totalIntervals)"
        case .rest:          return "Recovery"
        case .warmup:        return "Warm Up"
        case .cooldown:      return "Cool Down"
        }
    }

    /// Heart-rate colour: green = in target, yellow = below, red = above.
    private var hrColor: Color {
        sessionManager.zoneStatus(bpm: workoutManager.heartRate).tint ?? .white
    }

    /// Short coaching hint shown under the ring when out of zone.
    private var zoneHint: String? {
        ZoneFeedbackCopy.hint(phase: state.phase,
                              status: sessionManager.zoneStatus(bpm: workoutManager.heartRate))
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60 % 60, Int(t) % 60)
    }
}
