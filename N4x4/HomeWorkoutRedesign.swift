// HomeWorkoutRedesign.swift
//
// Redesigned Home + Workout experience (dark, premium, performance-oriented).
// The ENTIRE redesign lives in this one file so it is trivial to roll back:
//   • delete this file, and
//   • flip `useRedesignedUI` back to false in ContentView.
// The legacy `TimerView` is left fully intact and continues to work when the
// flag is off. Reused screens (History, Settings, post-workout summary,
// milestone celebration) come from their existing definitions — nothing is
// duplicated or rewritten here.

import SwiftUI
#if canImport(Charts)
import Charts
#endif

// MARK: - Design tokens

/// Dark, disciplined palette. Charcoal/black surfaces with electric-blue, amber
/// and lime accents reserved for actions, active states and performance feedback.
enum Palette {
    static let background   = Color(red: 0.04, green: 0.04, blue: 0.05)   // near-black charcoal
    static let surface      = Color(red: 0.09, green: 0.10, blue: 0.12)   // cards
    static let surfaceRaised = Color(red: 0.13, green: 0.14, blue: 0.16)  // controls
    static let hairline     = Color.white.opacity(0.08)

    static let textPrimary   = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary  = Color.white.opacity(0.4)

    static let electricBlue = Color(red: 0.18, green: 0.52, blue: 1.0)
    static let amber        = Color(red: 1.0,  green: 0.58, blue: 0.0)
    static let lime         = Color(red: 0.55, green: 0.85, blue: 0.25)
    static let danger       = Color(red: 1.0,  green: 0.27, blue: 0.27)
    static let recovery     = Color(red: 0.20, green: 0.78, blue: 0.55)

    /// Brand glow for the idle Home ring: electric-blue on the right, amber on the
    /// left, symmetric (seamless) — mirrors the original rendered ring artwork.
    /// startAngle is +90° to cancel the glow arc's −90° rotation so blue lands on
    /// the right (not the top).
    static let brandGlow = AngularGradient(
        gradient: Gradient(colors: [electricBlue, amber, electricBlue]),
        center: .center,
        startAngle: .degrees(90),
        endAngle: .degrees(450)
    )
}

/// mm:ss for the redesign screens (kept local to avoid touching shared helpers).
private func rdTime(_ t: TimeInterval) -> String {
    let clamped = max(0, t)
    let m = Int(clamped) / 60
    let s = Int(clamped) % 60
    return String(format: "%02d:%02d", m, s)
}

/// Single accent colour per interval phase: blue warm-up, amber high-intensity
/// (matching the background/brand orange), green recovery, teal cool-down.
private func intervalColor(_ type: IntervalType?) -> Color {
    switch type {
    case .warmup:        return Palette.electricBlue
    case .highIntensity: return Palette.amber
    case .rest:          return Palette.recovery
    case .cooldown:      return Color(red: 0.20, green: 0.75, blue: 0.85)
    case .none:          return Palette.textSecondary
    }
}

/// A heart that beats once per actual heartbeat (period = 60 / BPM). Re-create it
/// with `.id(Int(bpm.rounded()))`-style keying so the beat rate tracks live BPM.
struct PulsingHeart: View {
    var bpm: Double
    var size: CGFloat
    @State private var big = false

    /// Seconds per beat, clamped to a sane range so extreme/garbage BPM can't
    /// produce a strobing or frozen heart.
    private var beatPeriod: Double { 60.0 / min(210, max(40, bpm)) }

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: size))
            .foregroundStyle(Palette.danger)
            .scaleEffect(big ? 1.0 : 0.72)
            .shadow(color: Palette.danger.opacity(0.7), radius: big ? size * 0.4 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: beatPeriod / 2).repeatForever(autoreverses: true)) {
                    big = true
                }
            }
    }
}

/// Horizontal timeline of every interval, sized proportionally to duration and
/// coloured by phase. With `showProgress`, a live marker shows how far through
/// the whole session the user is (and how much is left).
struct IntervalTimelineBar: View {
    @ObservedObject var viewModel: TimerViewModel
    var showProgress: Bool = true

    private var total: TimeInterval {
        max(1, viewModel.intervals.reduce(0) { $0 + $1.duration })
    }

    private var elapsed: TimeInterval {
        guard viewModel.intervals.indices.contains(viewModel.currentIntervalIndex) else { return 0 }
        let before = viewModel.intervals.prefix(viewModel.currentIntervalIndex).reduce(0) { $0 + $1.duration }
        let current = viewModel.intervals[viewModel.currentIntervalIndex].duration - viewModel.timeRemaining
        return min(total, before + max(0, current))
    }

    private var minutesLeft: Int { max(0, Int(((total - elapsed) / 60).rounded())) }

    /// Precise x-position of the progress marker, walking segments so it stays
    /// aligned with boundaries despite inter-segment gaps.
    private func markerX(width: CGFloat) -> CGFloat {
        let spacing: CGFloat = 2
        let gaps = CGFloat(max(0, viewModel.intervals.count - 1)) * spacing
        let usable = max(0, width - gaps)
        var x: CGFloat = 0
        var remaining = elapsed
        for interval in viewModel.intervals {
            let segW = usable * CGFloat(interval.duration / total)
            if remaining <= interval.duration {
                x += segW * CGFloat(remaining / max(1, interval.duration))
                return min(width, x)
            }
            remaining -= interval.duration
            x += segW + spacing
        }
        return width
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let spacing: CGFloat = 2
                let gaps = CGFloat(max(0, viewModel.intervals.count - 1)) * spacing
                let usable = max(0, w - gaps)

                ZStack(alignment: .leading) {
                    HStack(spacing: spacing) {
                        ForEach(Array(viewModel.intervals.enumerated()), id: \.offset) { idx, interval in
                            Capsule()
                                .fill(intervalColor(interval.type))
                                .frame(width: usable * CGFloat(interval.duration / total), height: 8)
                                .opacity(segmentOpacity(idx))
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)

                    if showProgress {
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2, height: 16)
                            .offset(x: markerX(width: w) - 1)
                            .shadow(color: .black.opacity(0.6), radius: 1)
                            .animation(.linear(duration: 1), value: viewModel.timeRemaining)
                    }
                }
                .frame(height: 16)
            }
            .frame(height: 16)

            if showProgress {
                Text("\(minutesLeft) min left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func segmentOpacity(_ idx: Int) -> Double {
        guard showProgress else { return 0.9 }
        if idx == viewModel.currentIntervalIndex { return 1 }
        return idx < viewModel.currentIntervalIndex ? 0.85 : 0.3
    }
}

// MARK: - Root shell (glass tab bar, always visible)

/// Hosts the app in a native `TabView` so the tab bar uses the standard
/// translucent glass material and stays visible on every screen. Home/Workout
/// swap inside the Home tab; History and Settings are full screens (not sheets).
struct RedesignRootView: View {
    @ObservedObject var viewModel: TimerViewModel

    @State private var selectedTab = 0
    @State private var showWatchHelp = false

    /// A workout is "active" (show Workout screen) whenever the timer is running
    /// or a session has been started but not yet reset. `reset()` clears
    /// `workoutStartDate`, returning us to Home.
    private var isSessionActive: Bool {
        viewModel.isRunning || viewModel.workoutStartDate != nil
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Group {
                if isSessionActive {
                    WorkoutScreen(viewModel: viewModel, showWatchHelp: $showWatchHelp)
                } else {
                    HomeScreen(viewModel: viewModel, showWatchHelp: $showWatchHelp)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background.ignoresSafeArea())
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(0)

            StreakHistoryView(viewModel: viewModel, embedded: true)
                .tabItem { Label("History", systemImage: "clock") }
                .tag(1)

            SettingsView(viewModel: viewModel, embedded: true)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(2)
        }
        .tint(Palette.electricBlue)
        .preferredColorScheme(.dark)
        // Genuinely modal flows stay as sheets/covers. `StreakHistoryView`,
        // `PostWorkoutSummaryView` and `MilestoneCelebrationView` are internal
        // (see TimerView.swift).
        .sheet(isPresented: $showWatchHelp) {
            WatchTroubleshootingView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showWatchUpgradePrompt, onDismiss: {
            viewModel.hasSeenWatchUpgradePrompt = true
        }) {
            WatchUpgradeOnboardingView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showPostWorkoutSummary) {
            PostWorkoutSummaryView(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $viewModel.showMilestoneCelebration) {
            MilestoneCelebrationView(count: viewModel.pendingMilestoneCount) {
                viewModel.dismissMilestoneCelebration()
            }
        }
        .sheet(isPresented: $viewModel.showWeeklyStreaks) {
            StreakHistoryView(viewModel: viewModel)
                .onDisappear { viewModel.showWeeklyStreaks = false }
        }
    }
}

// MARK: - Home screen (idle)

struct HomeScreen: View {
    @ObservedObject var viewModel: TimerViewModel
    @Binding var showWatchHelp: Bool
    /// Dismisses the "connect your Watch" banner for this app session; it
    /// reappears next launch if the Watch app is still not installed.
    @State private var watchBannerDismissed = false

    private var hasVO2Data: Bool {
        viewModel.healthKitEnabled && viewModel.vo2DataPoints.count >= 2
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 8)

            if viewModel.watchAppMissingOnPairedWatch, !watchBannerDismissed {
                watchConnectBanner
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Top flex expands only when the tall VO₂ card is present (to balance
            // it); with no card it stays small so content sits higher.
            Spacer(minLength: 8)
                .frame(maxHeight: hasVO2Data ? .infinity : 28)

            Text("N4x4")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
                .padding(.bottom, 12)

            StartRingButton(title: "START", side: 340) { viewModel.startTimer() }

            // Interval plan + VO₂ trend. With data present it's pulled up to overlay
            // the ring's floor reflection (and dimmed so the glow shows through);
            // with no card it sits below the reflection so nothing overlaps.
            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    IntervalTimelineBar(viewModel: viewModel, showProgress: false)
                    Text(planSummary)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                }
                .padding(.horizontal, 8)

                if hasVO2Data {
                    VO2HistoryCard(viewModel: viewModel)
                }
            }
            .padding(.horizontal, 20)
            .opacity(hasVO2Data ? 0.9 : 1)
            .padding(.top, hasVO2Data ? -78 : 14)

            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            // Streak (week-based; label reflects that).
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.currentStreak > 0 ? "flame.fill" : "flame")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(viewModel.currentStreak > 0 ? Palette.amber : Palette.textTertiary)
                    Text("\(viewModel.currentStreak)")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                }
                Text("WEEK STREAK")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .tracking(0.5)
            }

            Spacer()
        }
    }

    /// Shown when a paired Watch exists but N4x4 isn't installed on it. Tapping
    /// opens the existing troubleshooting/setup flow; the × dismisses for now.
    private var watchConnectBanner: some View {
        HStack(spacing: 12) {
            Button {
                showWatchHelp = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "applewatch.slash")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.electricBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connect your Apple Watch")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                        Text("N4x4 isn't set up on your Watch — tap to connect")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { watchBannerDismissed = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.electricBlue.opacity(0.35), lineWidth: 1))
    }

    /// Short "N intervals · ~M min total" line shown under the plan.
    private var planSummary: String {
        let total = viewModel.intervals.reduce(0) { $0 + $1.duration }
        let mins = Int((total / 60).rounded())
        return "\(viewModel.numberOfIntervals) intervals · ~\(mins) min total"
    }
}

/// Shared chrome ring: the static brushed-metal bezel (`ChromeRing` asset, black
/// already transparent) with a programmatic neon glow arc, tip dot and floor
/// reflection layered on top, plus a centre slot. Used on both Home (full ring,
/// brand gradient glow) and Workout (progress arc, phase colour, dot) so the two
/// screens share one ring system.
struct MetalRing<Center: View>: View {
    var side: CGFloat
    /// Fraction of the ring drawn as glow (1 = full). Workout passes remaining time.
    var progress: CGFloat = 1
    /// Neon glow style — a solid phase colour (workout) or brand gradient (home).
    var glow: AnyShapeStyle
    /// Dominant colour for the dot and bloom.
    var glowColor: Color
    /// Floor-reflection beam colours (left / right). Default to `glowColor`
    /// (workout); Home passes amber-left / blue-right to mirror the artwork.
    var reflectLeft: Color? = nil
    var reflectRight: Color? = nil
    var showDot: Bool = false
    var animates: Bool = false
    @ViewBuilder var center: () -> Center

    /// Radius where the glow sits — the chrome bezel's *outer* edge, so the neon
    /// glows outward into the black and the centre stays clean and dark (matching
    /// the original render), rather than washing the interior.
    private let rimRatio: CGFloat = 0.385

    var body: some View {
        let rim = side * rimRatio
        let dot = side * 0.05
        ZStack {
            // Floor reflection: two soft colour beams descending from the ring's
            // base. Each beam sits under one side of the ring and its brightness
            // tracks whether the glow arc still reaches that side — so as the
            // countdown arc recedes (right stays lit longer than left), the
            // matching beam dims and disappears. `litFraction` is that side's
            // position along the trim (from the top, clockwise).
            reflectionBeam(color: reflectLeft ?? glowColor, litFraction: 0.60)
                .offset(x: -side * 0.19, y: rim + side * 0.24)
            reflectionBeam(color: reflectRight ?? glowColor, litFraction: 0.40)
                .offset(x: side * 0.19, y: rim + side * 0.24)

            // Static chrome bezel.
            Image("ChromeRing")
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)

            // Neon glow on the outer rim.
            glowStack(rim: rim)

            // Glowing tip dot at the arc's end.
            if showDot {
                Circle()
                    .fill(.white)
                    .frame(width: dot, height: dot)
                    .shadow(color: glowColor, radius: side * 0.035)
                    .offset(y: -rim)
                    .frame(width: side, height: side)
                    .rotationEffect(.degrees(Double(progress) * 360))
                    .animation(animates ? .linear(duration: 1) : nil, value: progress)
            }

            center()
        }
        .frame(width: side, height: side)
    }

    /// Layered neon: a wide soft halo (spills outward into the black) plus a bright
    /// crisp core. Kept fully saturated so the colour reads vivid, not washed.
    private func glowStack(rim: CGFloat) -> some View {
        ZStack {
            arc(rim: rim, lineWidth: side * 0.075).blur(radius: side * 0.055).opacity(0.7)
            arc(rim: rim, lineWidth: side * 0.024).blur(radius: side * 0.010).opacity(1.0)
            arc(rim: rim, lineWidth: side * 0.010)
        }
    }

    /// A soft vertical light beam for the floor reflection. Its opacity ramps up
    /// only once the glow arc has reached this side (`progress >= litFraction`),
    /// so the reflection is dynamic with the countdown.
    private func reflectionBeam(color: Color, litFraction: CGFloat) -> some View {
        let fade: CGFloat = 0.08
        let lit = Double(min(1, max(0, (progress - litFraction) / fade)))
        return Capsule()
            .fill(LinearGradient(colors: [color.opacity(0.85), color.opacity(0.0)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: side * 0.11, height: side * 0.5)
            .blur(radius: side * 0.035)
            .opacity(lit)
            .animation(animates ? .easeInOut(duration: 0.6) : nil, value: progress)
    }

    private func arc(rim: CGFloat, lineWidth: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(glow, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: rim * 2, height: rim * 2)
            .rotationEffect(.degrees(-90))
            .animation(animates ? .linear(duration: 1) : nil, value: progress)
    }
}

/// Home "Start" affordance — the shared chrome ring with the brand gradient glow.
struct StartRingButton: View {
    let title: String
    var side: CGFloat = 340
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MetalRing(side: side,
                      progress: 1,
                      glow: AnyShapeStyle(Palette.brandGlow),
                      glowColor: Palette.amber,
                      reflectLeft: Palette.amber,
                      reflectRight: Palette.electricBlue) {
                Text(title)
                    .font(.system(size: side * 0.115, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - VO2 max history card

struct VO2HistoryCard: View {
    @ObservedObject var viewModel: TimerViewModel

    /// Explicit time windows selected via buttons (rescale the chart's x-axis).
    private enum Range: String, CaseIterable, Identifiable {
        case month = "Month"
        case year  = "Year"
        case max   = "Max"
        var id: String { rawValue }
        var months: Int? {   // nil = all data
            switch self {
            case .month: return 1
            case .year:  return 12
            case .max:   return nil
            }
        }
    }
    @State private var range: Range = .year

    private var allPoints: [VO2DataPoint] {
        viewModel.vo2DataPoints.sorted { $0.date < $1.date }
    }

    private var latestValue: Double? { allPoints.last?.value }

    /// Visible x-axis window for the selected range. Clamped so short histories
    /// still render (a 2-week history under "Year" just shows those 2 weeks).
    private var xDomain: ClosedRange<Date>? {
        guard let first = allPoints.first?.date, let last = allPoints.last?.date, first < last else { return nil }
        guard let months = range.months,
              let start = Calendar.current.date(byAdding: .month, value: -months, to: last) else {
            return first...last
        }
        let clamped = Swift.max(first, start)
        return (clamped < last ? clamped : first)...last
    }

    /// Points inside the visible window, used to fit the y-axis to what's shown.
    private var visiblePoints: [VO2DataPoint] {
        guard let d = xDomain else { return allPoints }
        let inside = allPoints.filter { d.contains($0.date) }
        return inside.count >= 2 ? inside : allPoints
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if viewModel.healthKitEnabled, allPoints.count >= 2 {
                valueRow
                chart
            } else {
                emptyState
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.surface))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Palette.hairline, lineWidth: 1))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 6) {
                Text("VO₂ MAX HISTORY")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.textSecondary)
                    .tracking(0.5)
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            Text("ml/kg/min")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.textTertiary)
        }
    }

    /// Latest value + the Month / Year / Max range selector.
    private var valueRow: some View {
        HStack(alignment: .center) {
            if let latest = latestValue {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(latest.rounded()))")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.electricBlue)
                    Text("VO₂ MAX")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer()
            rangePicker
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(Range.allCases) { r in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { range = r }
                } label: {
                    Text(r.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(range == r ? Color.black : Palette.textSecondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(range == r ? Palette.electricBlue : Palette.surfaceRaised, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
#if canImport(Charts)
        let values = visiblePoints.map(\.value)
        let lo = max(0, (values.min() ?? 30) - 5)
        let hi = (values.max() ?? 60) + 5

        Chart {
            ForEach(allPoints) { p in
                AreaMark(x: .value("Date", p.date), y: .value("VO₂", p.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(colors: [Palette.electricBlue.opacity(0.35), .clear],
                                       startPoint: .top, endPoint: .bottom)
                    )
                LineMark(x: .value("Date", p.date), y: .value("VO₂", p.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Palette.electricBlue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            if let target = viewModel.vo2MaxTarget {
                RuleMark(y: .value("Goal", target))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .chartYScale(domain: lo...hi)
        .chartXScale(domain: xDomain ?? (allPoints.first?.date ?? Date())...(allPoints.last?.date ?? Date()))
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel().foregroundStyle(Palette.textTertiary)
                AxisGridLine().foregroundStyle(Palette.hairline)
            }
        }
        .chartXAxis {
            switch range {
            case .max:
                // Multi-year span: label by year (one mark per year) so it doesn't
                // repeat "Jan Jan Jan".
                AxisMarks(values: .stride(by: .year)) { _ in
                    AxisValueLabel(format: .dateTime.year())
                        .foregroundStyle(Palette.textTertiary)
                }
            case .year:
                AxisMarks(values: .stride(by: .month, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                        .foregroundStyle(Palette.textTertiary)
                }
            case .month:
                AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        }
        .frame(height: 150)
        .animation(.easeInOut(duration: 0.25), value: range)
#else
        Text("VO₂ max trend requires iOS Charts support.")
            .font(.footnote).foregroundStyle(Palette.textSecondary)
#endif
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 26))
                .foregroundStyle(Palette.textTertiary)
            Text(viewModel.healthKitEnabled
                 ? "Log more sessions to see your VO₂ max trend."
                 : "Connect Apple Health to track VO₂ max.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Workout screen (active)

struct WorkoutScreen: View {
    @ObservedObject var viewModel: TimerViewModel
    @Binding var showWatchHelp: Bool

    @State private var showEndAlert = false
    @State private var showSkipConfirmation = false
    @State private var skipIsForCooldown = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 8)

            IntervalTimelineBar(viewModel: viewModel, showProgress: true)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            Spacer(minLength: 4)

            WorkoutRing(viewModel: viewModel, side: 300)

            zoneCue
                .padding(.top, 10)
                .frame(height: 28)

            Spacer(minLength: 8)

            controls
                .padding(.horizontal, 24)

            Spacer(minLength: 12)

            HRZoneBar(viewModel: viewModel)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .alert("End workout?", isPresented: $showEndAlert) {
            Button("End", role: .destructive) { viewModel.reset() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("This ends the current session. Your progress so far won't be logged.")
        }
        .alert(skipIsForCooldown ? "End workout now?" : "Skip interval now?", isPresented: $showSkipConfirmation) {
            Button(skipIsForCooldown ? "End Now" : "Skip Now", role: .destructive) { viewModel.skip() }
            Button(skipIsForCooldown ? "Continue Cooldown" : "Continue", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Norwegian 4×4")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                Text(roundText)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.electricBlue)
                    .tracking(0.5)
            }
            Spacer()
            Button { showEndAlert = true } label: {
                Text("END")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Palette.danger)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .overlay(Capsule().stroke(Palette.danger.opacity(0.6), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
    }

    private var roundText: String {
        switch viewModel.currentIntervalType {
        case .warmup:        return "WARM UP"
        case .highIntensity: return "ROUND \(viewModel.highIntensityCount) OF \(viewModel.numberOfIntervals)"
        case .rest:          return "RECOVERY \(viewModel.restCount) OF \(viewModel.numberOfIntervals)"
        case .cooldown:      return "COOL DOWN"
        case .none:          return ""
        }
    }

    /// Live coaching cue under the ring: speed up if below the target zone, slow
    /// down if above, in-zone otherwise. Only while a target applies and HR is
    /// streaming, and honours the visual-zone-alert setting.
    @ViewBuilder private var zoneCue: some View {
        if viewModel.zoneVisualAlertsEnabled, let hr = viewModel.currentHeartRate {
            let status = viewModel.currentZoneStatus(for: hr)
            if status != .noTarget {
                let cue = zoneCueStyle(status)
                HStack(spacing: 8) {
                    Image(systemName: cue.icon)
                        .font(.system(size: 17, weight: .heavy))
                    Text(cue.text)
                        .font(.system(size: 22, weight: .heavy))
                        .tracking(1)
                }
                .foregroundStyle(cue.color)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: status)
            }
        }
    }

    private func zoneCueStyle(_ status: HRZoneStatus) -> (text: String, icon: String, color: Color) {
        switch status {
        case .below:    return ("SPEED UP",  "arrow.up.circle.fill",   Palette.amber)
        case .above:    return ("SLOW DOWN", "arrow.down.circle.fill", Palette.electricBlue)
        case .inZone:   return ("IN ZONE",   "checkmark.circle.fill",  Palette.recovery)
        case .noTarget: return ("", "", .clear)
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.pause()
            } label: {
                controlLabel(
                    icon: viewModel.isRunning ? "pause.fill" : "play.fill",
                    text: viewModel.isRunning ? "PAUSE" : "RESUME"
                )
            }
            .buttonStyle(.plain)

            Button {
                if viewModel.shouldConfirmSkipCurrentInterval() {
                    skipIsForCooldown = viewModel.currentIntervalType == .cooldown
                    showSkipConfirmation = true
                } else {
                    viewModel.skip()
                }
            } label: {
                controlLabel(icon: "forward.fill", text: "SKIP", trailingChevrons: true)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isRunning)
            .opacity(viewModel.isRunning ? 1 : 0.5)
        }
    }

    private func controlLabel(icon: String, text: String, trailingChevrons: Bool = false) -> some View {
        HStack(spacing: 8) {
            if !trailingChevrons {
                Image(systemName: icon).font(.system(size: 15, weight: .bold))
            }
            Text(text).font(.system(size: 15, weight: .heavy)).tracking(1)
            if trailingChevrons {
                Image(systemName: "chevron.right.2").font(.system(size: 13, weight: .bold))
            }
        }
        .foregroundStyle(Palette.textPrimary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.hairline, lineWidth: 1))
    }
}

/// Countdown ring for the active workout: gradient arc + glowing progress dot.
struct WorkoutRing: View {
    @ObservedObject var viewModel: TimerViewModel

    /// Fraction of the current interval remaining (1 → full, 0 → done).
    private var progress: CGFloat {
        guard viewModel.intervals.indices.contains(viewModel.currentIntervalIndex) else { return 0 }
        let duration = max(1, viewModel.intervals[viewModel.currentIntervalIndex].duration)
        return CGFloat(min(1, max(0, viewModel.timeRemaining / duration)))
    }

    private var phaseLabel: String {
        switch viewModel.currentIntervalType {
        case .warmup:        return "WARM UP"
        case .highIntensity: return "HIGH INTENSITY"
        case .rest:          return "RECOVERY"
        case .cooldown:      return "COOL DOWN"
        case .none:          return ""
        }
    }

    private var phaseColor: Color { intervalColor(viewModel.currentIntervalType) }

    private var targetText: String? {
        switch viewModel.currentIntervalType {
        case .highIntensity:
            let r = viewModel.highIntensityTargetRange
            return "TARGET \(r.lowerBound)–\(r.upperBound) BPM"
        case .rest:
            let r = viewModel.recoveryTargetRange
            return "TARGET \(r.lowerBound)–\(r.upperBound) BPM"
        default:
            return nil
        }
    }

    var side: CGFloat = 320

    var body: some View {
        MetalRing(side: side,
                  progress: progress,
                  glow: AnyShapeStyle(phaseColor),
                  glowColor: phaseColor,
                  showDot: true,
                  animates: true) {
            centerStack
        }
    }

    private var centerStack: some View {
        VStack(spacing: 3) {
            Text(rdTime(viewModel.timeRemaining))
                .font(.system(size: side * 0.155, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()

            Text(phaseLabel)
                .font(.system(size: side * 0.05, weight: .heavy))
                .foregroundStyle(phaseColor)
                .tracking(1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let target = targetText {
                Text(target)
                    .font(.system(size: side * 0.034, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .tracking(0.5)
            }

            if let hr = viewModel.currentHeartRate {
                HStack(spacing: 6) {
                    PulsingHeart(bpm: hr, size: side * 0.072)
                        .id(Int((hr / 4).rounded()))
                    Text("\(Int(hr))")
                        .font(.system(size: side * 0.095, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                        .monospacedDigit()
                }
                .padding(.top, side * 0.02)
            }
        }
        .frame(maxWidth: side * 0.58)
    }
}

// MARK: - Heart-rate zone bar

/// Five HR zones derived from the user's max HR. The zone matching the current
/// phase target pulses; a live arrow marks the current heart rate when a Watch
/// is streaming it.
struct HRZoneBar: View {
    @ObservedObject var viewModel: TimerViewModel

    @State private var pulse = false

    private struct Zone {
        let name: String
        let lo: Int   // % of max HR
        let hi: Int
        let color: Color
    }

    private let zones: [Zone] = [
        Zone(name: "Z1", lo: 50, hi: 60,  color: Color.white.opacity(0.28)),
        Zone(name: "Z2", lo: 60, hi: 70,  color: Palette.electricBlue),
        Zone(name: "Z3", lo: 70, hi: 80,  color: Palette.recovery),
        Zone(name: "Z4", lo: 85, hi: 95,  color: Palette.amber),
        Zone(name: "Z5", lo: 95, hi: 100, color: Palette.danger),
    ]

    /// Which zone the current phase is targeting (index into `zones`), if any.
    /// Only work and recovery carry a target; warm-up and cool-down have none.
    private var targetIndex: Int? {
        switch viewModel.currentIntervalType {
        case .highIntensity:   return 3   // Z4 (85–95%)
        case .rest:            return 1   // Z2 (60–70%)
        case .warmup, .cooldown, .none: return nil
        }
    }

    private func bpm(_ pct: Int) -> Int {
        Int((Double(viewModel.maximumHeartRate) * Double(pct) / 100).rounded())
    }

    /// Fraction (0…1) across the five equal segments for the current HR.
    private func arrowFraction(for hr: Double) -> CGFloat {
        for (i, z) in zones.enumerated() {
            let lo = Double(bpm(z.lo)), hi = Double(bpm(z.hi))
            if hr < lo { return CGFloat(Double(i) / Double(zones.count)) }
            if hr <= hi {
                let within = (hr - lo) / max(1, hi - lo)
                return CGFloat((Double(i) + within) / Double(zones.count))
            }
        }
        return 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("HEART RATE ZONES")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.textSecondary)
                    .tracking(0.5)
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
                Spacer()
                if let hr = viewModel.currentHeartRate {
                    HStack(spacing: 6) {
                        PulsingHeart(bpm: hr, size: 15)
                            .id(Int((hr / 4).rounded()))
                        Text("\(Int(hr))")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(Palette.textPrimary)
                            .monospacedDigit()
                        Text("BPM")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }

            zoneBar

            zoneLabels

            connectionStatus
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Palette.hairline, lineWidth: 1))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private var zoneBar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                HStack(spacing: 4) {
                    ForEach(Array(zones.enumerated()), id: \.offset) { idx, z in
                        let isTarget = idx == targetIndex
                        Capsule()
                            .fill(z.color)
                            .frame(height: 10)
                            .opacity(isTarget ? 1 : 0.4)
                            .background {
                                // Pulsing glow behind the target zone.
                                if isTarget {
                                    Capsule()
                                        .fill(z.color)
                                        .blur(radius: 10)
                                        .opacity(pulse ? 1.0 : 0.2)
                                        .scaleEffect(pulse ? 1.15 : 0.9)
                                }
                            }
                            .scaleEffect(y: isTarget && pulse ? 1.6 : 1.0, anchor: .center)
                    }
                }

                // Live HR arrow — larger and glowing so the current position is obvious.
                if let hr = viewModel.currentHeartRate {
                    let x = arrowFraction(for: hr) * w
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                        .position(x: min(max(8, x), w - 8), y: -10)
                        .animation(.easeInOut(duration: 0.5), value: hr)
                }
            }
            .frame(height: 10)
        }
        .frame(height: 22)
        .padding(.top, 12)
    }

    private var zoneLabels: some View {
        HStack(spacing: 4) {
            ForEach(Array(zones.enumerated()), id: \.offset) { idx, z in
                VStack(spacing: 2) {
                    Text(z.name)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(idx == targetIndex ? z.color : Palette.textSecondary)
                    Text("\(z.lo)-\(z.hi)%")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Palette.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var connectionStatus: some View {
        HStack(spacing: 6) {
            Spacer()
            if viewModel.currentHeartRate != nil {
                Circle().fill(Palette.recovery).frame(width: 7, height: 7)
                Text("Apple Watch Connected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
            } else if viewModel.shouldWarnMissingHeartRate {
                Circle().fill(Palette.amber).frame(width: 7, height: 7)
                Text(viewModel.watchAppInstalled ? "Waiting for heart rate…" : "Set up N4x4 on your Watch")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.amber)
            } else {
                Circle().fill(Palette.textTertiary).frame(width: 7, height: 7)
                Text("No heart rate")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer()
        }
    }
}
