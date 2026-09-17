// WatchTimerView.swift
// Active-workout UI, mirroring the phone's WorkoutScreen: a "ROUND 2 OF 4"
// header, the neon countdown ring (time, phase, live zone-coloured HR) with
// the Speed Up / Slow Down cue beneath, then a second vertical page with the
// plan timeline and PAUSE / SKIP / END controls (END and skip-out-of-cooldown
// confirm, like the phone). Works identically for phone-led and Watch-led
// workouts; the header badge says which, and controls go quiet when a
// phone-led workout is being shown with the phone out of range. Lifecycle —
// HK session, haptics, re-sync — lives in the root view.

import SwiftUI

struct WatchTimerView: View {

    @EnvironmentObject var sessionManager: WatchSessionManager
    @EnvironmentObject var workoutManager: WorkoutManager

    @State private var page: Int
    @State private var showEndAlert = false
    @State private var finishingWorkoutID: UUID?
    @State private var showSkipAlert = false

    /// `initialPage` 1 opens on the controls page (used by the DEBUG demo mode).
    init(initialPage: Int = 0) {
        _page = State(initialValue: initialPage)
    }

    private var state: WatchTimerState { sessionManager.timerState }
    private var phaseColor: Color { state.phase.color }
    private var hasTarget: Bool { state.hrLow > 0 && state.hrHigh > 0 }
    private var hasPlan: Bool { state.hasPlan }
    private var canControl: Bool { sessionManager.canControl }
    private var offline: Bool { sessionManager.isProjectingOffline }

    var body: some View {
        TabView(selection: $page) {
            ringPage.tag(0)
            controlsPage.tag(1)
        }
        .tabViewStyle(.verticalPage)
        .alert(offline ? "Stop showing this workout?" : "Finish workout?", isPresented: $showEndAlert) {
            Button(offline ? "Stop Showing" : "Finish & Save") { sessionManager.endWorkout(for: finishingWorkoutID) }
            if !offline {
                Button("Discard Workout", role: .destructive) { sessionManager.discardActiveWorkout(for: finishingWorkoutID) }
            }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text(offline
                 ? "Check your iPhone to finish and save. This only hides the workout on your Watch."
                 : "Save your progress, or discard this workout.")
        }
        .alert("End workout now?", isPresented: $showSkipAlert) {
            Button("End Now", role: .destructive) { sessionManager.skip() }
            Button("Continue Cooldown", role: .cancel) {}
        }
    }

    // MARK: - Page 1: ring

    private var ringPage: some View {
        GeometryReader { geo in
            let side = min(geo.size.width * 0.76, geo.size.height * 0.72)
            // TimelineView drives a smooth 1 s countdown (a plain
            // Timer.publish is throttled to ~5 s on watchOS).
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = state.timeRemaining(asOf: context.date)
                let progress = state.progressValue(asOf: context.date)
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        Text(headerText)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(WatchPalette.electricBlue)
                            .tracking(0.8)
                        modeBadge
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                    Spacer(minLength: 2)

                    NeonRing(side: side,
                             progress: progress,
                             glow: AnyShapeStyle(phaseColor),
                             glowColor: phaseColor,
                             showDot: true,
                             animates: true,
                             dimmed: !state.isRunning) {
                        ringCenter(remaining: remaining, side: side)
                    }

                    Spacer(minLength: 2)

                    cueRow
                        .frame(height: 16)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .padding(.horizontal, 6)
    }

    /// Ring centre, same stack as the phone: countdown, phase (or PAUSED),
    /// then the live heart rate with a beating heart, tinted by zone status
    /// (shared mapping: orange = too low, red = too high, green = in zone).
    /// Before the first reading the slot shows an outline heart and "--" so
    /// the layout doesn't jump when HR arrives, and it's clear HR is expected.
    private func ringCenter(remaining: TimeInterval, side: CGFloat) -> some View {
        let hr = workoutManager.heartRate
        return VStack(spacing: side * 0.005) {
            Text(watchTimeString(remaining))
                .font(.system(size: side * 0.21, weight: .heavy, design: .rounded))
                .foregroundStyle(WatchPalette.textPrimary)
                .monospacedDigit()

            Text(state.isRunning ? state.phase.watchLabel : "PAUSED")
                .font(.system(size: side * 0.085, weight: .heavy))
                .foregroundStyle(state.isRunning ? phaseColor : WatchPalette.amber)
                .tracking(0.8)

            HStack(spacing: side * 0.03) {
                if hr > 0 {
                    WatchPulsingHeart(bpm: hr, size: side * 0.075)
                        .id(Int((hr / 4).rounded()))
                    Text("\(Int(hr))")
                        .foregroundStyle(
                            sessionManager.zoneStatus(bpm: hr).tint ?? WatchPalette.textPrimary)
                } else {
                    Image(systemName: "heart")
                        .font(.system(size: side * 0.075, weight: .semibold))
                        .foregroundStyle(WatchPalette.textTertiary)
                    Text("--")
                        .foregroundStyle(WatchPalette.textTertiary)
                }
            }
            .font(.system(size: side * 0.15, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .padding(.top, side * 0.015)
        }
        .frame(maxWidth: side * 0.74)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    /// Where the workout is running: Watch-led, or phone-led with the phone
    /// currently out of range (controls unavailable). Nothing when the phone
    /// leads and is in reach — the normal case needs no badge.
    @ViewBuilder private var modeBadge: some View {
        if sessionManager.mode == .local {
            Image(systemName: "applewatch")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WatchPalette.textTertiary)
        } else if offline {
            Image(systemName: "iphone.slash")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WatchPalette.amber)
        }
    }

    /// Phone's header line: round / recovery count in electric blue. Warm-up
    /// and cool-down show the protocol name instead of repeating the phase
    /// label that already sits inside the ring.
    private var headerText: String {
        switch state.phase {
        case .highIntensity:      return "ROUND \(state.highIntensityCount) OF \(state.totalIntervals)"
        case .rest:               return "RECOVERY \(state.highIntensityCount) OF \(state.totalIntervals)"
        case .warmup, .cooldown:  return "NORWEGIAN 4×4"
        }
    }

    /// Live coaching cue (same copy, icons and colours as the phone). Without
    /// a reading the target range takes the slot so it's still visible.
    @ViewBuilder private var cueRow: some View {
        let hr = workoutManager.heartRate
        let status = sessionManager.zoneStatus(bpm: hr)
        if hr > 0, status != .noTarget {
            let cue = cueStyle(status)
            HStack(spacing: 4) {
                Image(systemName: cue.icon)
                    .font(.system(size: 12, weight: .heavy))
                Text(cue.text)
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(1)
            }
            .foregroundStyle(cue.color)
            .animation(.easeInOut(duration: 0.3), value: status)
        } else if hasTarget {
            Text("TARGET \(state.hrLow)–\(state.hrHigh) BPM")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WatchPalette.textTertiary)
                .tracking(0.5)
                .monospacedDigit()
        }
    }

    private func cueStyle(_ status: HRZoneStatus) -> (text: String, icon: String, color: Color) {
        switch status {
        case .below:    return ("SPEED UP",  "arrow.up.circle.fill",   WatchPalette.amber)
        case .above:    return ("SLOW DOWN", "arrow.down.circle.fill", WatchPalette.danger)
        case .inZone:   return ("IN ZONE",   "checkmark.circle.fill",  WatchPalette.recovery)
        case .noTarget: return ("", "", .clear)
        }
    }

    // MARK: - Page 2: controls

    private var controlsPage: some View {
        ScrollView {
            VStack(spacing: 6) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = state.timeRemaining(asOf: context.date)
                    VStack(spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(state.phase.watchLabel)
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(phaseColor)
                                .tracking(0.8)
                            Spacer(minLength: 4)
                            Text(watchTimeString(remaining))
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(WatchPalette.textPrimary)
                                .monospacedDigit()
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 2)

                        if hasPlan {
                            WatchTimelineBar(phases: state.planPhases,
                                             durations: state.planDurations,
                                             currentIndex: state.currentIntervalIndex,
                                             timeRemaining: remaining)
                            Text("\(minutesLeft(asOf: context.date)) min left")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(WatchPalette.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }

                if offline {
                    HStack(spacing: 4) {
                        Image(systemName: "iphone.slash")
                        Text("Controls need your iPhone")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WatchPalette.amber)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }

                Button { sessionManager.togglePause() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: state.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(state.isRunning ? "PAUSE" : "RESUME")
                    }
                }
                .buttonStyle(WatchControlButtonStyle())
                .disabled(!canControl)
                .opacity(canControl ? 1 : 0.45)

                Button { skipTapped() } label: {
                    HStack(spacing: 6) {
                        Text("SKIP")
                        Image(systemName: "chevron.right.2")
                            .font(.system(size: 12, weight: .bold))
                    }
                }
                .buttonStyle(WatchControlButtonStyle())
                .disabled(!state.isRunning || !canControl)
                .opacity(state.isRunning && canControl ? 1 : 0.45)

                Button {
                    finishingWorkoutID = sessionManager.currentWorkoutID
                    showEndAlert = true
                } label: {
                    Text("FINISH")
                }
                .buttonStyle(WatchControlButtonStyle(tint: WatchPalette.electricBlue, outlined: true))
            }
            .padding(.leading, 6)
            // Clear the vertical page indicator / scroll bar on the right.
            .padding(.trailing, 12)
            .padding(.bottom, 4)
        }
    }

    /// Skipping the cool-down ends the workout, so it confirms like the phone.
    /// Other intervals skip immediately (the phone's per-interval confirmation
    /// setting isn't mirrored to the Watch).
    private func skipTapped() {
        if state.phase == .cooldown {
            showSkipAlert = true
        } else {
            sessionManager.skip()
        }
    }

    private func minutesLeft(asOf now: Date) -> Int {
        max(0, Int(((state.planTotal - state.planElapsed(asOf: now)) / 60).rounded()))
    }
}
