// WatchTheme.swift
// Design tokens and shared chrome for the Watch app, mirroring the phone's
// redesign in HomeWorkoutRedesign.swift (`Palette`, `MetalRing`,
// `IntervalTimelineBar`, `PulsingHeart`). Those types live in the iOS target,
// so the values are repeated here — when either side changes, change both.

import SwiftUI

// MARK: - Palette (== iOS `Palette`)

enum WatchPalette {
    static let background    = Color(red: 0.04, green: 0.04, blue: 0.05)
    static let surface       = Color(red: 0.09, green: 0.10, blue: 0.12)
    static let surfaceRaised = Color(red: 0.13, green: 0.14, blue: 0.16)
    static let hairline      = Color.white.opacity(0.08)

    static let textPrimary   = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary  = Color.white.opacity(0.4)

    static let electricBlue  = Color(red: 0.18, green: 0.52, blue: 1.0)
    static let amber         = Color(red: 1.0,  green: 0.58, blue: 0.0)
    static let lime          = Color(red: 0.55, green: 0.85, blue: 0.25)
    static let danger        = Color(red: 1.0,  green: 0.27, blue: 0.27)
    static let recovery      = Color(red: 0.20, green: 0.78, blue: 0.55)

    /// Brand glow for the idle Home ring — electric blue on the right, amber on
    /// the left, seamless. Same construction as the phone: +90° start angle
    /// cancels the arc's −90° rotation so blue lands on the right.
    static let brandGlow = AngularGradient(
        gradient: Gradient(colors: [electricBlue, amber, electricBlue]),
        center: .center,
        startAngle: .degrees(90),
        endAngle: .degrees(450)
    )
}

/// mm:ss, clamped at zero.
func watchTimeString(_ t: TimeInterval) -> String {
    let clamped = max(0, t)
    return String(format: "%02d:%02d", Int(clamped) / 60, Int(clamped) % 60)
}

// MARK: - Neon ring

/// The phone's chrome ring, redrawn for the wrist: a programmatic brushed
/// bezel (no image asset on the Watch), a neon glow arc on its outer edge, an
/// optional tip dot, and a centre slot. Home passes the brand gradient at full
/// progress; the workout passes the phase colour and remaining fraction.
struct NeonRing<Center: View>: View {
    var side: CGFloat
    /// Fraction of the ring drawn as glow (1 = full).
    var progress: CGFloat = 1
    var glow: AnyShapeStyle
    var glowColor: Color
    var showDot: Bool = false
    var animates: Bool = false
    /// Paused look — the glow drops back so the ring reads as "held".
    var dimmed: Bool = false
    @ViewBuilder var center: () -> Center

    /// Bezel radius as a fraction of `side`. The glow sits just outside it and
    /// its halo spills into the black, so the interior stays clean and dark.
    private let rimRatio: CGFloat = 0.425

    private var bezelGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [
                Color(white: 0.62), Color(white: 0.28), Color(white: 0.70),
                Color(white: 0.24), Color(white: 0.58), Color(white: 0.32),
                Color(white: 0.62),
            ]),
            center: .center
        )
    }

    var body: some View {
        let rim = side * rimRatio
        let bezel = side * 0.055
        let glowRadius = rim + bezel * 0.5
        let dot = side * 0.055

        ZStack {
            // Brushed-metal bezel with a dark inner lip and a faint outer highlight.
            Circle()
                .stroke(bezelGradient, lineWidth: bezel)
                .frame(width: rim * 2, height: rim * 2)
            Circle()
                .stroke(Color.black.opacity(0.6), lineWidth: 1)
                .frame(width: rim * 2 - bezel, height: rim * 2 - bezel)
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                .frame(width: rim * 2 + bezel, height: rim * 2 + bezel)

            // Neon: wide soft halo + crisp core, both on the bezel's outer edge.
            Group {
                arc(radius: glowRadius, lineWidth: side * 0.065)
                    .blur(radius: side * 0.035)
                    .opacity(0.75)
                arc(radius: glowRadius, lineWidth: side * 0.018)
            }
            .opacity(dimmed ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.3), value: dimmed)

            if showDot {
                Circle()
                    .fill(.white)
                    .frame(width: dot, height: dot)
                    .shadow(color: glowColor, radius: side * 0.03)
                    .offset(y: -glowRadius)
                    .rotationEffect(.degrees(Double(progress) * 360))
                    .animation(animates ? .linear(duration: 1) : nil, value: progress)
            }

            center()
        }
        .frame(width: side, height: side)
    }

    private func arc(radius: CGFloat, lineWidth: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(glow, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: radius * 2, height: radius * 2)
            .rotationEffect(.degrees(-90))
            .animation(animates ? .linear(duration: 1) : nil, value: progress)
    }
}

// MARK: - Pulsing heart (== iOS `PulsingHeart`)

/// Beats once per actual heartbeat. Re-create it with `.id(...)` keyed off the
/// rounded BPM so the beat rate tracks the live reading.
struct WatchPulsingHeart: View {
    var bpm: Double
    var size: CGFloat
    @State private var big = false

    private var beatPeriod: Double { 60.0 / min(210, max(40, bpm)) }

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: size))
            .foregroundStyle(WatchPalette.danger)
            .scaleEffect(big ? 1.0 : 0.72)
            .shadow(color: WatchPalette.danger.opacity(0.7), radius: big ? size * 0.4 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: beatPeriod / 2).repeatForever(autoreverses: true)) {
                    big = true
                }
            }
    }
}

// MARK: - Interval timeline (== iOS `IntervalTimelineBar`)

/// Every interval as a capsule sized by duration and coloured by phase. With a
/// `currentIndex` it also draws the live progress marker; without one it is
/// the plan preview shown on Home.
struct WatchTimelineBar: View {
    var phases: [WorkoutPhase]
    var durations: [Double]
    var currentIndex: Int? = nil
    var timeRemaining: TimeInterval = 0
    var barHeight: CGFloat = 6

    private var count: Int { min(phases.count, durations.count) }
    private var total: Double { max(1, durations.prefix(count).reduce(0, +)) }
    private let spacing: CGFloat = 2

    private func elapsed() -> Double {
        guard let idx = currentIndex, idx < count else { return 0 }
        let before = durations.prefix(idx).reduce(0, +)
        return min(total, before + max(0, durations[idx] - timeRemaining))
    }

    private func markerX(usable: CGFloat) -> CGFloat {
        var x: CGFloat = 0
        var remaining = elapsed()
        for i in 0..<count {
            let segW = usable * CGFloat(durations[i] / total)
            if remaining <= durations[i] {
                return x + segW * CGFloat(remaining / max(1, durations[i]))
            }
            remaining -= durations[i]
            x += segW + spacing
        }
        return usable + CGFloat(max(0, count - 1)) * spacing
    }

    private func opacity(_ idx: Int) -> Double {
        guard let current = currentIndex else { return 0.9 }
        if idx == current { return 1 }
        return idx < current ? 0.85 : 0.3
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let gaps = CGFloat(max(0, count - 1)) * spacing
            let usable = max(0, w - gaps)

            ZStack(alignment: .leading) {
                HStack(spacing: spacing) {
                    ForEach(0..<count, id: \.self) { i in
                        Capsule()
                            .fill(phases[i].color)
                            .frame(width: usable * CGFloat(durations[i] / total), height: barHeight)
                            .opacity(opacity(i))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)

                if currentIndex != nil {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: barHeight + 6)
                        .offset(x: min(w, markerX(usable: usable)) - 1)
                        .shadow(color: .black.opacity(0.6), radius: 1)
                        .animation(.linear(duration: 1), value: timeRemaining)
                }
            }
            .frame(width: w, height: barHeight + 6)
        }
        .frame(height: barHeight + 6)
    }
}

// MARK: - Controls (== iOS `WorkoutScreen.controlLabel` / END pill)

/// Full-width control matching the phone's workout buttons: charcoal card with
/// a hairline, heavy tracked caps. `outlined` gives the phone's END treatment —
/// no fill, tinted stroke and text.
struct WatchControlButtonStyle: ButtonStyle {
    var tint: Color = WatchPalette.textPrimary
    var outlined: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .heavy))
            .tracking(1)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(outlined ? Color.clear : WatchPalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(outlined ? tint.opacity(0.6) : WatchPalette.hairline,
                            lineWidth: outlined ? 1.5 : 1)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Phase copy (== iOS `WorkoutRing.phaseLabel`)

extension WorkoutPhase {
    /// Full phase name in the phone's caps style.
    var watchLabel: String {
        switch self {
        case .warmup:        return "WARM UP"
        case .highIntensity: return "HIGH INTENSITY"
        case .rest:          return "RECOVERY"
        case .cooldown:      return "COOL DOWN"
        }
    }
}
