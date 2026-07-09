// WatchTimerView.swift
// Main Watch UI: two-line phase header, progress ring with a big heart-rate
// readout, a Speed Up / Slow Down coaching cue with the live target range, and
// start/pause/skip controls. This mirrors the layout advertised on the website
// so the real app and the marketing look identical. Out-of-zone haptics are
// driven from here as each reading arrives.

import SwiftUI
import WatchKit

struct WatchTimerView: View {

    @EnvironmentObject var sessionManager: WatchSessionManager
    @EnvironmentObject var workoutManager: WorkoutManager

    @State private var lastIntervalIndex = 0
    @Environment(\.scenePhase) private var scenePhase

    private var state: WatchTimerState { sessionManager.timerState }

    /// The ring scales to the watch's actual screen width so it never clips on
    /// small models (e.g. 40 mm Series 4), while staying capped on large ones.
    private var ringSize: CGFloat {
        min(WKInterfaceDevice.current().screenBounds.width * 0.60, 132)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {

                // TimelineView drives a smooth 1 s countdown (a plain
                // Timer.publish is throttled to ~5 s on watchOS).
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = state.timeRemaining(asOf: context.date)
                    VStack(spacing: 8) {

                        // ── Header: phase + interval / countdown ──
                        VStack(spacing: 1) {
                            Text(phaseName)
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundColor(state.phase.color)
                                .tracking(0.5)
                            Text(detailLine(remaining))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.55))
                                .monospacedDigit()
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                        // ── Progress ring with big BPM readout ──
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
                        .frame(width: ringSize, height: ringSize)

                        // ── Coaching cue + target range ──
                        VStack(spacing: 1) {
                            if let cue = zoneCue {
                                Text(cue.text)
                                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                                    .foregroundColor(cue.color)
                            }
                            if hasTarget {
                                Text("TARGET \(state.hrLow)–\(state.hrHigh)")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.4))
                                    .monospacedDigit()
                                    .tracking(0.5)
                            }
                        }
                        .frame(minHeight: 32)
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
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
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

    /// Ring centre: big live heart rate with a small BPM label (matches the
    /// advertised layout). Falls back to the countdown until HR is streaming.
    @ViewBuilder
    private func centerContent(remaining: TimeInterval) -> some View {
        if workoutManager.heartRate > 0 {
            VStack(spacing: 0) {
                Text("\(Int(workoutManager.heartRate))")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                Text("BPM")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .tracking(2)
            }
        } else {
            Text(timeString(remaining))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
        }
    }

    /// Line 1 of the header — full phase name, colour-coded to the phase.
    private var phaseName: String {
        switch state.phase {
        case .highIntensity: return "HIGH INTENSITY"
        case .rest:          return "RECOVERY"
        case .warmup:        return "WARM UP"
        case .cooldown:      return "COOL DOWN"
        }
    }

    /// Line 2 of the header — interval count (high-intensity only) plus the
    /// live countdown, so time-remaining stays visible during a workout.
    private func detailLine(_ remaining: TimeInterval) -> String {
        let t = timeString(remaining)
        if state.phase == .highIntensity {
            return "INTERVAL \(state.highIntensityCount) / \(state.totalIntervals)  ·  \(t)"
        }
        return t
    }

    private var hasTarget: Bool { state.hrLow > 0 && state.hrHigh > 0 }

    /// Coaching cue from live HR vs the target zone (matches the phone/website).
    private var zoneCue: (text: String, color: Color)? {
        switch sessionManager.zoneStatus(bpm: workoutManager.heartRate) {
        case .below:    return ("▲ SPEED UP", .orange)
        case .above:    return ("▼ SLOW DOWN", .cyan)
        case .inZone:   return ("✓ IN ZONE", .green)
        case .noTarget: return nil
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60 % 60, Int(t) % 60)
    }
}
