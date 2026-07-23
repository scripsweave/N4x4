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

            RedesignHistoryView(viewModel: viewModel, embedded: true)
                .tabItem { Label("History", systemImage: "clock") }
                .tag(1)

            TipsView(embedded: true)
                .tabItem { Label("Guide", systemImage: "book.fill") }
                .tag(2)

            SettingsView(viewModel: viewModel, embedded: true)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(3)
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
        .sheet(isPresented: $viewModel.showHRSourcesAnnouncement, onDismiss: {
            viewModel.hasSeenHRSourcesAnnouncement = true
        }) {
            HeartRateSourcesAnnouncementView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.evaluateHRSourcesAnnouncement()
        }
        .sheet(isPresented: $viewModel.showPostWorkoutSummary) {
            PostWorkoutSummaryRedesignView(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $viewModel.showMilestoneCelebration) {
            MilestoneCelebrationView(count: viewModel.pendingMilestoneCount) {
                viewModel.dismissMilestoneCelebration()
            }
        }
        .sheet(isPresented: $viewModel.showWeeklyStreaks) {
            RedesignHistoryView(viewModel: viewModel)
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

    // 2 August easter egg (see BirthdayEasterEgg.swift). The preview flag is
    // @AppStorage so flipping the DEBUG Settings toggle re-renders Home live.
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(BirthdayEasterEgg.previewDefaultsKey) private var birthdayPreview = false
    @StateObject private var birthday = BirthdayShowController()
    /// Bumped by `significantTimeChangeNotification` (fires at local midnight,
    /// and on time-zone/clock changes) so the date check flips live even if
    /// the app sits open or suspended across midnight.
    @State private var dayFlipTick = 0

    private var isBirthday: Bool {
        // The preview read is compiled out of Release: the UserDefaults key
        // survives app updates, so a device that ever ran a debug build with
        // the toggle on must not stay in birthday mode on the App Store build.
        #if DEBUG
        if birthdayPreview { return true }
        #endif
        return BirthdayEasterEgg.isTheDay()
    }

    var body: some View {
        ZStack {
            if isBirthday {
                BirthdaySkyView(controller: birthday)
            }
            homeContent
            if isBirthday {
                BirthdayMessageView(controller: birthday)
            }
        }
        .coordinateSpace(name: "birthdayHome")
        .onPreferenceChange(BirthdayBallFrameKey.self) { birthday.ballFrame = $0 }
        // Any tap sparks a firework (simultaneous, so controls still work);
        // the opening show replays on every arrival at Home that day.
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .named("birthdayHome"))
                .onEnded { value in
                    guard isBirthday else { return }
                    birthday.engine.launch(at: value.location)
                }
        )
        .onAppear { if isBirthday { birthday.beginShow() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, isBirthday { birthday.beginShow() }
        }
        .onChange(of: birthdayPreview) { _, enabled in
            if enabled { birthday.beginShow() }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.significantTimeChangeNotification)) { _ in
            dayFlipTick += 1   // invalidates Home so isBirthday re-evaluates
            if BirthdayEasterEgg.isTheDay() { birthday.beginShow() }
        }
    }

    private var homeContent: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 8)

            // Suppressed for users already covered by a Bluetooth monitor —
            // nagging them about the Watch app would be noise.
            if viewModel.watchAppMissingOnPairedWatch, !watchBannerDismissed,
               !viewModel.bleHeartRateManager.hasRememberedMonitor {
                watchConnectBanner
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Top flex expands only when the tall VO₂ card is present (to balance
            // it); with no card it stays small so content sits higher.
            Spacer(minLength: 8)
                .frame(maxHeight: hasVO2Data ? .infinity : 28)

            if isBirthday {
                DiscoBallStartButton(side: 340, controller: birthday) { viewModel.startTimer() }
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: BirthdayBallFrameKey.self,
                                               value: geo.frame(in: .named("birthdayHome")))
                    })
            } else {
                StartRingButton(title: "START", side: 340) { viewModel.startTimer() }
            }

            // Interval plan + VO₂ trend, always sitting clearly below the ring.
            // The bottom-anchored layout means this block's height pushes the ring
            // upward, so a positive gap here keeps the timeline off the ring.
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
            .padding(.top, 14)

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
        guard let first = allPoints.first?.date, let last = allPoints.last?.date else { return nil }
        // Guard against a degenerate (zero-width) domain when every sample shares
        // one timestamp — Swift Charts renders a collapsed spike otherwise.
        guard first < last else { return first...first.addingTimeInterval(86_400) }
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

            HRZoneBar(viewModel: viewModel,
                      onMissingHeartRateTap: { showWatchHelp = true })
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
        case .above:    return ("SLOW DOWN", "arrow.down.circle.fill", Palette.danger)
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
                        // Zone-coded: orange = too low, red = too high (shared tint).
                        .foregroundStyle(
                            viewModel.currentZoneStatus(for: hr).tint ?? Palette.textPrimary)
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
    /// Invoked when the user taps the missing-heart-rate warning — the
    /// highest-intent moment for the troubleshooting / connect-a-strap flow.
    var onMissingHeartRateTap: (() -> Void)? = nil

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
        Zone(name: "Z3", lo: 70, hi: 85,  color: Palette.recovery),
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
                            // Zone-coded: orange = too low, red = too high (shared tint).
                            .foregroundStyle(
                                viewModel.currentZoneStatus(for: hr).tint ?? Palette.textPrimary)
                            .monospacedDigit()
                        Text("BPM")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.textSecondary)
                        if let symbol = viewModel.heartRateSourceSymbol {
                            Image(systemName: symbol)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Palette.textTertiary)
                        }
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
                Text("\(viewModel.heartRateSourceLabel ?? "Heart Rate") Connected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
            } else if viewModel.shouldWarnMissingHeartRate {
                Button {
                    onMissingHeartRateTap?()
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Palette.amber).frame(width: 7, height: 7)
                        Text("\(viewModel.missingHeartRateHint) — tap for help")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.amber)
                    }
                }
                .buttonStyle(.plain)
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

// MARK: - History / streaks screen

/// Premium redesign of the streaks/history screen: a glowing streak hero with a
/// last-8-weeks strip, stat tiles, an aligned month calendar, and a styled
/// performance-trend chart — all in the app's dark design language.
struct RedesignHistoryView: View {
    @ObservedObject var viewModel: TimerViewModel
    var embedded: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var selectedWorkout: WorkoutLogEntry?
    /// Entry opened in the full-session detail sheet (charts + intervals).
    @State private var detailedWorkout: WorkoutLogEntry?
    @State private var selectedPerfModality: TrainingModality?
    @State private var selectedChartDate: Date?

    private let cal = Calendar.current
    private let daySymbols = ["S", "M", "T", "W", "T", "F", "S"]
    private struct WeekKey: Hashable { let year: Int; let week: Int }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                streakHero
                statTiles
                calendarCard
                performanceCard
                if let workout = selectedWorkout {
                    workoutDetailCard(workout)
                }
            }
            .padding(20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(item: $detailedWorkout) { workout in
            SessionDetailSheet(entry: workout, viewModel: viewModel)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("History")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            if !embedded {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Palette.surfaceRaised))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Streak hero

    private var streakHero: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Palette.amber)
                        .frame(width: 54, height: 54)
                        .blur(radius: 18)
                        .opacity(viewModel.currentStreak > 0 ? 0.7 : 0)
                    Image(systemName: viewModel.currentStreak > 0 ? "flame.fill" : "flame")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(
                            viewModel.currentStreak > 0
                            ? LinearGradient(colors: [Palette.amber, Color(red: 1, green: 0.82, blue: 0.3)],
                                             startPoint: .bottom, endPoint: .top)
                            : LinearGradient(colors: [Palette.textTertiary], startPoint: .top, endPoint: .bottom)
                        )
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(viewModel.currentStreak)")
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                    Text("WEEK STREAK")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.textSecondary)
                        .tracking(1)
                }
                Spacer()
                VStack(spacing: 3) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Palette.amber)
                    Text("\(viewModel.longestStreak)")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                    Text("BEST")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.textTertiary)
                        .tracking(0.5)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surfaceRaised))
            }

            // Last 8 weeks strip.
            HStack(spacing: 6) {
                ForEach(Array(last8Weeks.enumerated()), id: \.offset) { _, done in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(done ? Palette.amber : Palette.surfaceRaised)
                        .frame(height: 8)
                        .overlay {
                            if done {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Palette.amber).blur(radius: 4).opacity(0.6)
                            }
                        }
                }
            }
            HStack {
                Text("8 WEEKS AGO").font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.textTertiary)
                Spacer()
                Text("THIS WEEK").font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Palette.hairline, lineWidth: 1))
    }

    private var last8Weeks: [Bool] {
        let now = Date()
        let entryWeeks = Set(viewModel.workoutLogEntries.map { WeekKey(year: $0.year, week: $0.weekOfYear) })
        return (0..<8).reversed().map { i in
            guard let d = cal.date(byAdding: .weekOfYear, value: -i, to: now) else { return false }
            let key = WeekKey(year: cal.component(.yearForWeekOfYear, from: d),
                              week: cal.component(.weekOfYear, from: d))
            return entryWeeks.contains(key)
        }
    }

    // MARK: Stat tiles

    private var statTiles: some View {
        HStack(spacing: 10) {
            statTile(value: "\(viewModel.workoutLogEntries.count)", label: "TOTAL", icon: "checkmark.seal.fill", tint: Palette.recovery)
            statTile(value: "\(thisMonthCount)", label: "THIS MONTH", icon: "calendar", tint: Palette.electricBlue)
            statTile(value: "\(viewModel.longestStreak)", label: "BEST STREAK", icon: "flame.fill", tint: Palette.amber)
        }
    }

    private func statTile(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
            Text(value).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(Palette.textPrimary)
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.textTertiary).tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.hairline, lineWidth: 1))
    }

    private var thisMonthCount: Int {
        guard let interval = cal.dateInterval(of: .month, for: Date()) else { return 0 }
        return viewModel.workoutLogEntries.filter { interval.contains($0.completedAt) }.count
    }

    // MARK: Calendar

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(monthTitle)
                .font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.textSecondary).tracking(0.5)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(daySymbols.enumerated()), id: \.offset) { _, d in
                    Text(d).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.textTertiary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(maxWidth: .infinity, minHeight: 34)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Palette.hairline, lineWidth: 1))
    }

    private func dayCell(_ day: Int) -> some View {
        let workout = workoutOnDay(day)
        let today = isToday(day)
        let future = isFutureDay(day)
        return Button {
            if let w = workout { selectedWorkout = w }
        } label: {
            ZStack {
                if workout != nil {
                    Circle().fill(Palette.amber)
                    Circle().fill(Palette.amber).blur(radius: 6).opacity(0.5)
                } else if today {
                    Circle().stroke(Palette.electricBlue, lineWidth: 2)
                }
                if workout != nil {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.black)
                } else {
                    Text("\(day)")
                        .font(.system(size: 13, weight: today ? .heavy : .medium))
                        .foregroundStyle(future ? Palette.textTertiary : (today ? Palette.electricBlue : Palette.textSecondary))
                }
            }
            .frame(height: 34)
        }
        .buttonStyle(.plain)
        .disabled(workout == nil)
    }

    // MARK: Performance trend

    private var performanceCard: some View {
        Group {
            if let modality = activePerfModality {
                let points = performancePoints(for: modality)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("PERFORMANCE TREND")
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.textSecondary).tracking(0.5)
                        Spacer()
                        if loggedModalities.count > 1 {
                            Picker("", selection: Binding(
                                get: { activePerfModality ?? modality },
                                set: { selectedPerfModality = $0 })) {
                                ForEach(loggedModalities, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .tint(Palette.electricBlue)
                        }
                    }
                    perfChart(points: points, modality: modality)
                    Text("\(modality.rawValue) • \(modality.performanceMetric.label) (\(unitLabel(for: modality)))")
                        .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Palette.hairline, lineWidth: 1))
            }
        }
    }

    @ViewBuilder
    private func perfChart(points: [(date: Date, value: Double)], modality: TrainingModality) -> some View {
#if canImport(Charts)
        if points.count >= 2 {
            Chart {
                ForEach(points, id: \.date) { p in
                    AreaMark(x: .value("Date", p.date), y: .value("v", p.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(LinearGradient(colors: [Palette.electricBlue.opacity(0.35), .clear],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", p.date), y: .value("v", p.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Palette.electricBlue)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
            }
            .chartXSelection(value: $selectedChartDate)
            .chartYAxis { AxisMarks(position: .leading) { _ in
                AxisValueLabel().foregroundStyle(Palette.textTertiary)
                AxisGridLine().foregroundStyle(Palette.hairline)
            } }
            .chartXAxis { AxisMarks { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated)).foregroundStyle(Palette.textTertiary)
            } }
            .frame(height: 150)
            .onChange(of: selectedChartDate) { _, date in
                guard let date else { return }
                let candidates = viewModel.workoutLogEntries.filter {
                    $0.modality == modality && !($0.intervalPerformances ?? []).isEmpty
                }
                if let nearest = candidates.min(by: {
                    abs($0.completedAt.timeIntervalSince(date)) < abs($1.completedAt.timeIntervalSince(date))
                }) { selectedWorkout = nearest }
            }
        } else {
            Text("Log at least two \(modality.rawValue) sessions to see your trend.")
                .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
        }
#else
        Text("Trend chart requires iOS Charts support.")
            .font(.footnote).foregroundStyle(Palette.textSecondary)
#endif
    }

    // MARK: Workout detail

    private func workoutDetailCard(_ workout: WorkoutLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.recovery)
                Text(workout.workoutType.rawValue).font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                Text(workout.completedAt, style: .date).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                Button { selectedWorkout = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.textTertiary)
                }.buttonStyle(.plain)
            }
            if let b = workout.sessionBreakdown {
                Divider().overlay(Palette.hairline)
                VStack(alignment: .leading, spacing: 4) {
                    detailRow("Total", formatMinutes(b.totalDuration))
                    detailRow("High intensity", formatMinutes(b.highIntensityDuration))
                    detailRow("Recovery", formatMinutes(b.recoveryDuration))
                    detailRow("Cooldown", b.cooldownSkipped ? "Skipped" : formatMinutes(b.cooldownDuration))
                }
            }
            if let summary = workout.hrSummary, !summary.sparkline.isEmpty {
                Divider().overlay(Palette.hairline)
                HStack(spacing: 12) {
                    HRSparklineView(points: summary.sparkline)
                        .frame(height: 34)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(summary.avgBPM) avg · \(summary.maxBPM) peak")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                        if let z = summary.workInZonePct {
                            Text("\(z)% in zone")
                                .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
            }
            if let perfs = workout.intervalPerformances, !perfs.isEmpty, let modality = workout.modality {
                Divider().overlay(Palette.hairline)
                Text("\(modality.performanceMetric.label) per interval")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.textTertiary)
                ForEach(perfs) { perf in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Interval \(perf.intervalNumber)").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                            Spacer()
                            if let v = perf.primary {
                                Text("\(formatPerf(viewModel.displayValue(v, for: modality), for: modality)) \(unitLabel(for: modality))")
                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                            } else {
                                Text("—").font(.system(size: 13)).foregroundStyle(Palette.textTertiary)
                            }
                        }
                        if let note = perf.note, !note.isEmpty {
                            Text(note).font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                        }
                    }
                }
            }
            if !workout.notes.isEmpty {
                Divider().overlay(Palette.hairline)
                Text(workout.notes).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            }
            if workout.hrSummary != nil {
                Button {
                    detailedWorkout = workout
                } label: {
                    HStack {
                        Image(systemName: "chart.xyaxis.line")
                        Text("View full session")
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Palette.electricBlue)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Palette.electricBlue.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Palette.hairline, lineWidth: 1))
        .transition(.opacity)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            Spacer()
            Text(value).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textPrimary)
        }
    }

    // MARK: Data helpers

    private var monthTitle: String {
        let f = DateFormatter(); f.dateFormat = "MMMM"
        return f.string(from: Date()).uppercased()
    }
    private var currentMonthDays: Int { cal.range(of: .day, in: .month, for: Date())?.count ?? 30 }
    private var leadingBlanks: Int {
        let comps = cal.dateComponents([.year, .month], from: Date())
        guard let first = cal.date(from: comps) else { return 0 }
        return cal.component(.weekday, from: first) - 1
    }
    /// Calendar cells: leading nils to align day 1 to its weekday, then day numbers.
    private var monthCells: [Int?] {
        Array(repeating: Int?.none, count: leadingBlanks) + (1...currentMonthDays).map { Int?($0) }
    }
    private func isToday(_ day: Int) -> Bool { cal.component(.day, from: Date()) == day }
    private func isFutureDay(_ day: Int) -> Bool { day > cal.component(.day, from: Date()) }
    private func workoutOnDay(_ day: Int) -> WorkoutLogEntry? {
        guard let interval = cal.dateInterval(of: .month, for: Date()) else { return nil }
        return viewModel.workoutLogEntries
            .filter { interval.contains($0.completedAt) && cal.component(.day, from: $0.completedAt) == day }
            .max(by: { $0.completedAt < $1.completedAt })
    }
    private func formatMinutes(_ s: TimeInterval) -> String { "\(max(0, Int(s) / 60)) min" }

    private var loggedModalities: [TrainingModality] {
        var seen: [TrainingModality] = []
        for e in viewModel.workoutLogEntries where e.modality != nil && !(e.intervalPerformances ?? []).isEmpty {
            if let m = e.modality, !seen.contains(m) { seen.append(m) }
        }
        return seen
    }
    private var activePerfModality: TrainingModality? { selectedPerfModality ?? loggedModalities.first }
    private func performancePoints(for modality: TrainingModality) -> [(date: Date, value: Double)] {
        viewModel.workoutLogEntries
            .filter { $0.modality == modality }
            .compactMap { e in e.averagePrimaryPerformance.map { (e.completedAt, viewModel.displayValue($0, for: modality)) } }
            .sorted { $0.date < $1.date }
    }
    private func unitLabel(for modality: TrainingModality) -> String {
        let m = modality.performanceMetric
        if m.localeConverted, viewModel.usesImperialUnits, let imp = m.imperialUnit { return imp }
        return m.unit
    }
    private func formatPerf(_ v: Double, for modality: TrainingModality) -> String {
        String(format: "%.\(modality.performanceMetric.step < 1 ? 1 : 0)f", v)
    }
}
