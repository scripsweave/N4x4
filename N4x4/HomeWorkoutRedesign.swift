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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds per beat, clamped to a sane range so extreme/garbage BPM can't
    /// produce a strobing or frozen heart.
    private var beatPeriod: Double { 60.0 / min(210, max(40, bpm)) }

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: size))
            .foregroundStyle(Palette.danger)
            .scaleEffect(reduceMotion || big ? 1.0 : 0.72)
            .shadow(color: Palette.danger.opacity(0.7), radius: !reduceMotion && big ? size * 0.4 : 0)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
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
    @State private var workoutMinimized = false
    @Environment(\.scenePhase) private var scenePhase

    /// A workout is "active" (show Workout screen) whenever the timer is running
    /// or a session has been started but not yet reset. `reset()` clears
    /// `workoutStartDate`, returning us to Home.
    private var isSessionActive: Bool {
        viewModel.isRunning || viewModel.workoutStartDate != nil
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Group {
                if isSessionActive && !workoutMinimized {
                    WorkoutScreen(viewModel: viewModel, showWatchHelp: $showWatchHelp,
                                  onMinimize: { workoutMinimized = true })
                } else {
                    ZStack(alignment: .bottom) {
                        HomeScreen(viewModel: viewModel, showWatchHelp: $showWatchHelp)
                        if isSessionActive {
                            Button { workoutMinimized = false } label: {
                                Label("Workout in progress · Tap to return", systemImage: "stopwatch.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Palette.electricBlue)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 12)
                        }
                    }
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
        .workoutRecovery(viewModel: viewModel)
        .preferredColorScheme(.dark)
        .onChange(of: isSessionActive) { _, active in
            if !active { workoutMinimized = false }
        }
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
        .onChange(of: scenePhase) { _, phase in
            // The redesigned UI replaced TimerView, which used to own this. Without
            // it the foreground refresh (streak sync, reminder rescheduling, health
            // auth, idle-timer re-assert) and post-background timer reconciliation
            // never ran in the shipping app.
            if phase == .active {
                viewModel.refreshOnForeground()
                if viewModel.isRunning {
                    viewModel.reconcileTimerState(now: Date(), playAlarm: false)
                }
            } else if phase == .background {
                viewModel.checkpointOnBackground()
            }
        }
        .sheet(isPresented: $viewModel.showPostWorkoutSummary,
               onDismiss: viewModel.postWorkoutSummaryDidDismiss) {
            PostWorkoutSummaryRedesignView(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $viewModel.showMilestoneCelebration) {
            MilestoneCelebrationView(count: viewModel.pendingMilestoneCount) {
                viewModel.dismissMilestoneCelebration()
            }
        }
        .sheet(isPresented: $viewModel.showWeeklyStreaks) {
            RedesignHistoryView(viewModel: viewModel)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var showVO2Card: Bool { viewModel.healthKitEnabled }

    // 2 August easter egg (see BirthdayEasterEgg.swift).
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var birthday = BirthdayShowController()
    /// Bumped by `significantTimeChangeNotification` (fires at local midnight,
    /// and on time-zone/clock changes) so the date check flips live even if
    /// the app sits open or suspended across midnight.
    @State private var dayFlipTick = 0
    /// True after the Guide easter egg's one-shot flag was consumed —
    /// birthday mode for the rest of this app session only. The persisted
    /// flag is already cleared, so the next launch is normal again.
    @State private var birthdayOneShot = false

    /// 2 August for everyone, plus the user's own birthday once HealthKit has
    /// given us one (`BirthdayEasterEgg.isCelebrationDay`).
    private var isBirthday: Bool {
        birthdayOneShot || BirthdayEasterEgg.isCelebrationDay()
    }

    private func activateBirthdayIfDue() {
        // A freshly armed one-shot (Guide → Advanced → hold the last tile) is an
        // explicit "show me now", so it skips the arrival cooldown.
        let armed = BirthdayEasterEgg.consumeOneShot()
        if armed { birthdayOneShot = true }
        if isBirthday { birthday.beginShow(force: armed) }
    }

    var body: some View {
        ZStack {
            if isBirthday {
                BirthdaySkyView(controller: birthday)
            }
            homeContent
            if isBirthday {
                // room light landing on the cards, so the reflections don't
                // stop dead at the edge of the content
                BirthdayLightSpillView(controller: birthday)
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
        .onAppear { activateBirthdayIfDue() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                activateBirthdayIfDue()
            } else {
                // the spin rumble is a looping haptic player — never leave it
                // running into the background
                birthday.suspend()
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.significantTimeChangeNotification)) { _ in
            dayFlipTick += 1   // invalidates Home so isBirthday re-evaluates
            if BirthdayEasterEgg.isTheDay() { birthday.beginShow() }
        }
    }

    private var homeContent: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height && !dynamicTypeSize.isAccessibilitySize
            ScrollView {
                if wide {
                    HStack(spacing: 24) {
                        startRing(side: min(340, max(200, geometry.size.height - 24), geometry.size.width * 0.44))
                            .frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 16) {
                            header
                            connectBannerIfNeeded
                            Text("Norwegian 4×4")
                                .font(.title2.bold())
                                .foregroundStyle(Palette.textPrimary)
                            planAndFitness
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(minHeight: geometry.size.height)
                } else {
                    VStack(spacing: 16) {
                        header
                        connectBannerIfNeeded
                        startRing(side: min(340, max(220, geometry.size.height * 0.48), geometry.size.width - 40))
                        planAndFitness
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    .frame(minHeight: geometry.size.height)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder
    private func startRing(side: CGFloat) -> some View {
        if isBirthday {
            DiscoBallStartButton(side: side, controller: birthday) { viewModel.startTimer() }
                .background(GeometryReader { geo in
                    Color.clear.preference(key: BirthdayBallFrameKey.self,
                                           value: geo.frame(in: .named("birthdayHome")))
                })
        } else {
            StartRingButton(title: "START", side: side) { viewModel.startTimer() }
        }
    }

    @ViewBuilder
    private var connectBannerIfNeeded: some View {
        if viewModel.watchAppMissingOnPairedWatch, !watchBannerDismissed,
           !viewModel.bleHeartRateManager.hasRememberedMonitor {
            watchConnectBanner
        }
    }

    private var planAndFitness: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                IntervalTimelineBar(viewModel: viewModel, showProgress: false)
                Text(planSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, 8)
            if showVO2Card {
                VO2HistoryCard(viewModel: viewModel)
            }
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
        return "\(viewModel.sessionIntervalCount) intervals · ~\(mins) min total"
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
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
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

    /// Says which of the three "no chart" situations the user is actually in.
    /// The old copy ("log more sessions") was misleading for the common case:
    /// N4x4 never writes VO₂ max, it only reads what Apple Health already holds,
    /// and Cardio Fitness is produced by Apple Watch — so logging more N4x4
    /// sessions does nothing for someone training with a chest strap alone.
    private var emptyStateMessage: (String, String?) {
        guard viewModel.healthKitEnabled else {
            return ("Connect Apple Health to track your VO₂ max.", nil)
        }
        switch allPoints.count {
        case 0:
            return ("No VO₂ max readings in Apple Health yet.",
                    "Apple records Cardio Fitness from Apple Watch during outdoor walks, runs and hikes. N4x4 reads that number — it can't measure it from a heart rate monitor alone.")
        case 1:
            return ("One reading so far.",
                    "The trend line appears once Apple Health holds at least two.")
        default:
            return ("VO₂ max trend unavailable.", nil)
        }
    }

    private var emptyState: some View {
        let (title, detail) = emptyStateMessage
        return VStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 26))
                .foregroundStyle(Palette.textTertiary)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Workout screen (active)

struct WorkoutScreen: View {
    @ObservedObject var viewModel: TimerViewModel
    @Binding var showWatchHelp: Bool
    var onMinimize: () -> Void = {}

    @State private var showEndAlert = false
    @State private var finishingWorkoutID: UUID?
    @State private var showSkipConfirmation = false
    @State private var skipIsForCooldown = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height && !dynamicTypeSize.isAccessibilitySize
            ScrollView {
                if wide {
                    landscapeWorkout(size: geometry.size)
                } else {
                    portraitWorkout(size: geometry.size)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .alert("Finish workout?", isPresented: $showEndAlert) {
            Button("Finish & Save") {
                if let id = finishingWorkoutID { viewModel.finishAndSaveWorkout(for: id) }
            }
            Button("Discard Workout", role: .destructive) {
                if let id = finishingWorkoutID { viewModel.discardActiveWorkout(for: id) }
            }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("Save your progress, or discard this workout.")
        }
        .alert(skipIsForCooldown ? "End workout now?" : "Skip interval now?", isPresented: $showSkipConfirmation) {
            Button(skipIsForCooldown ? "End Now" : "Skip Now", role: .destructive) { viewModel.skip() }
            Button(skipIsForCooldown ? "Continue Cooldown" : "Continue", role: .cancel) {}
        }
    }

    private func portraitWorkout(size: CGSize) -> some View {
        let compact = size.height < 650 && !dynamicTypeSize.isAccessibilitySize
        let ringSide = min(330, max(180, size.height - (compact ? 365 : 390)) * 1.1, size.width - 40)
        return VStack(spacing: compact ? 8 : 12) {
            header
            IntervalTimelineBar(viewModel: viewModel, showProgress: !compact)
            WorkoutRing(viewModel: viewModel, side: ringSide)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HRZoneBar(viewModel: viewModel, compact: compact,
                      onMissingHeartRateTap: { showWatchHelp = true })
            controls
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(minHeight: size.height)
    }

    private func landscapeWorkout(size: CGSize) -> some View {
        HStack(spacing: 20) {
            VStack(spacing: 8) {
                WorkoutRing(viewModel: viewModel,
                            side: min(300, max(200, size.height - 64), size.width * 0.34))
                IntervalTimelineBar(viewModel: viewModel)
            }
            .frame(width: min(320, size.width * 0.34))
            VStack(spacing: 10) {
                header
                HRZoneBar(viewModel: viewModel, landscape: true,
                          onMissingHeartRateTap: { showWatchHelp = true })
                controls
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(minHeight: size.height)
    }

    private var header: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        return layout {
            VStack(alignment: .leading, spacing: 3) {
                Text("Norwegian 4×4")
                    .font(.headline)
                    .foregroundStyle(Palette.textPrimary)
                Text(roundText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.electricBlue)
                    .tracking(0.5)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(action: onMinimize) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Palette.surfaceRaised))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Minimize workout")
                Button {
                    finishingWorkoutID = viewModel.activeWorkoutID
                    showEndAlert = true
                } label: {
                    Text("FINISH")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Palette.electricBlue)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .overlay(Capsule().stroke(Palette.electricBlue.opacity(0.6), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var roundText: String {
        switch viewModel.currentIntervalType {
        case .warmup:        return "WARM UP"
        case .highIntensity: return "ROUND \(viewModel.highIntensityCount) OF \(viewModel.sessionIntervalCount)"
        case .rest:          return "RECOVERY \(viewModel.restCount) OF \(viewModel.sessionIntervalCount)"
        case .cooldown:      return "COOL DOWN"
        case .none:          return ""
        }
    }

    private var controls: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 16))
        return layout {
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
            Text(text).font(.subheadline.weight(.heavy)).tracking(1)
            if trailingChevrons {
                Image(systemName: "chevron.right.2").font(.system(size: 13, weight: .bold))
            }
        }
        .foregroundStyle(Palette.textPrimary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .frame(minHeight: 48)
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
                .font(.system(size: side * 0.19, weight: .heavy, design: .rounded))
                .accessibilityLabel("Time remaining")
                .accessibilityValue(rdTime(viewModel.timeRemaining))
                .accessibilityIdentifier("workout-countdown")
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()

            Text(phaseLabel)
                .font(.system(size: side * 0.05, weight: .heavy))
                .foregroundStyle(phaseColor)
                .tracking(1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

        }
        .frame(maxWidth: side * 0.65)
    }
}

// MARK: - Heart-rate zone bar

/// Five HR zones derived from the user's max HR. The zone matching the current
/// phase target pulses; a live arrow marks the current heart rate when a Watch
/// is streaming it.
struct HRZoneBar: View {
    @ObservedObject var viewModel: TimerViewModel
    var landscape = false
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var readingSize: CGFloat = 60

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
        VStack(alignment: .leading, spacing: 6) {
            heartRateHeader

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    heartRateReading
                    Spacer(minLength: 0)
                    guidance
                        .fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 8) {
                    heartRateReading
                    guidance
                }
            }

            zoneBar
                .accessibilityHidden(true)
            if !compact {
                zoneLabels
                    .accessibilityHidden(true)
            }

            if viewModel.currentHeartRate == nil {
                connectionStatus
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Palette.hairline, lineWidth: 1))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private var heartRateHeader: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return layout {
            HStack(alignment: .firstTextBaseline) {
                if let hr = viewModel.currentHeartRate {
                    PulsingHeart(bpm: hr, size: 12)
                        .id(Int((hr / 4).rounded()))
                } else {
                    Image(systemName: "heart")
                        .accessibilityHidden(true)
                }
                Text("CURRENT HEART RATE")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            if !compact, let source = viewModel.heartRateSourceLabel, viewModel.currentHeartRate != nil {
                Label(source, systemImage: viewModel.heartRateSourceSymbol ?? "heart.fill")
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Palette.textSecondary)
    }

    private var heartRateReading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(viewModel.currentHeartRate.map { "\(Int($0))" } ?? "—")
                .font(.system(size: readingSize * (landscape ? 1.2 : 1), weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(readingColor)
                .fixedSize()
            Text("BPM")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live heart rate")
        .accessibilityValue(viewModel.currentHeartRate.map { "\(Int($0)) beats per minute" } ?? "No reading")
        .accessibilityIdentifier("live-heart-rate")
    }

    private var readingColor: Color {
        guard let hr = viewModel.currentHeartRate else { return Palette.textSecondary }
        return viewModel.currentZoneStatus(for: hr).tint ?? Palette.textPrimary
    }

    private var targetRange: ClosedRange<Int>? {
        switch viewModel.currentIntervalType {
        case .highIntensity: return viewModel.highIntensityTargetRange
        case .rest: return viewModel.recoveryTargetRange
        default: return nil
        }
    }

    private var guidance: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let targetRange {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TARGET BPM")
                        .font(.caption2.weight(.bold))
                        .tracking(0.5)
                    Text("\(targetRange.lowerBound)–\(targetRange.upperBound)")
                        .font((landscape ? Font.largeTitle : Font.title).weight(.bold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Target heart rate")
                .accessibilityValue("\(targetRange.lowerBound) to \(targetRange.upperBound) beats per minute")
                .accessibilityIdentifier("target-heart-rate")
            }
            if viewModel.zoneVisualAlertsEnabled, let hr = viewModel.currentHeartRate,
               viewModel.currentZoneStatus(for: hr) != .noTarget {
                let status = viewModel.currentZoneStatus(for: hr)
                Label(cueText(status), systemImage: cueSymbol(status))
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(status.tint ?? Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(Palette.textSecondary)
    }

    private func cueText(_ status: HRZoneStatus) -> String {
        switch status {
        case .below: return "SPEED UP"
        case .above: return "SLOW DOWN"
        case .inZone: return "IN ZONE"
        case .noTarget: return ""
        }
    }

    private func cueSymbol(_ status: HRZoneStatus) -> String {
        switch status {
        case .below: return "arrow.up.circle.fill"
        case .above: return "arrow.down.circle.fill"
        case .inZone: return "checkmark.circle.fill"
        case .noTarget: return "heart.fill"
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
                                if isTarget && !reduceMotion {
                                    Capsule()
                                        .fill(z.color)
                                        .blur(radius: 10)
                                        .opacity(pulse ? 1.0 : 0.2)
                                        .scaleEffect(pulse ? 1.15 : 0.9)
                                }
                            }
                            .scaleEffect(y: isTarget && pulse && !reduceMotion ? 1.6 : 1.0, anchor: .center)
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
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: hr)
                }
            }
            .frame(height: 10)
        }
        .frame(height: 12)
        .padding(.top, 10)
    }

    private var zoneLabels: some View {
        HStack(spacing: 4) {
            ForEach(Array(zones.enumerated()), id: \.offset) { idx, z in
                VStack(spacing: 2) {
                    Text(z.name)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(idx == targetIndex ? z.color : Palette.textSecondary)
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
                .frame(minHeight: 44)
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
    /// Entry opened in the full-session detail sheet (charts + intervals).
    @State private var detailedWorkout: WorkoutLogEntry?
    @State private var selectedPerfModality: TrainingModality?
    @State private var selectedChartDate: Date?
    /// The month shown in the calendar grid. Defaults to today; the chevrons move
    /// it a whole month at a time and it never pages past the current month.
    @State private var monthAnchor = Date()

    private let cal = Calendar.current
    private let daySymbols = ["S", "M", "T", "W", "T", "F", "S"]
    private struct WeekKey: Hashable { let year: Int; let week: Int }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if let notice = viewModel.historyRecoveryNotice {
                    Text(notice).font(.callout).foregroundStyle(Palette.textSecondary)
                }
                streakHero
                statTiles
                calendarCard
                workoutList
                performanceCard
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

    private var workoutList: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            Text("WORKOUTS")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.textSecondary)
                .tracking(0.5)
            if viewModel.workoutLogEntries.isEmpty {
                Text("Completed workouts are saved here automatically.")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textSecondary)
            }
            ForEach(viewModel.workoutLogEntries) { workout in
                Button {
                    detailedWorkout = workout
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Palette.recovery)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.workoutType.rawValue)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Palette.textPrimary)
                            Text(workout.completedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.textSecondary)
                            if workout.endedEarly == true {
                                Text("Ended early").font(.caption).foregroundStyle(Palette.amber)
                            }
                            if let breakdown = workout.sessionBreakdown {
                                Text(formatMinutes(breakdown.totalDuration))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Palette.surface))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("View workout details and deletion options")
                .accessibilityIdentifier("workout-\(workout.id.uuidString)")
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
        let entryWeeks = Set(viewModel.workoutLogEntries.filter(\.countsTowardStreak).map { WeekKey(year: $0.year, week: $0.weekOfYear) })
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
            HStack {
                Button { shiftMonth(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Palette.surfaceRaised))
                }
                .buttonStyle(.plain)

                Spacer()
                Text(monthTitle)
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.textSecondary).tracking(0.5)
                Spacer()

                Button { shiftMonth(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isCurrentMonth ? Palette.textTertiary.opacity(0.4) : Palette.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Palette.surfaceRaised))
                }
                .buttonStyle(.plain)
                .disabled(isCurrentMonth)
            }

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
            if let w = workout { detailedWorkout = w }
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
                }) { detailedWorkout = nearest }
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

    // MARK: Data helpers

    /// First day of the month currently shown in the calendar grid.
    private var monthStart: Date {
        cal.date(from: cal.dateComponents([.year, .month], from: monthAnchor)) ?? monthAnchor
    }
    /// True when the shown month is the real current month — the forward chevron
    /// is disabled here so the user can't page into empty future months.
    private var isCurrentMonth: Bool {
        cal.isDate(monthAnchor, equalTo: Date(), toGranularity: .month)
    }
    private func shiftMonth(by delta: Int) {
        guard let d = cal.date(byAdding: .month, value: delta, to: monthStart) else { return }
        // Never navigate past the current month.
        if delta > 0 && cal.compare(d, to: Date(), toGranularity: .month) == .orderedDescending { return }
        monthAnchor = d
    }
    private var monthTitle: String {
        let f = DateFormatter()
        // Append the year only when it isn't the current one — keeps the common
        // case clean while staying unambiguous when paging back across years.
        f.dateFormat = cal.isDate(monthAnchor, equalTo: Date(), toGranularity: .year) ? "MMMM" : "MMMM yyyy"
        return f.string(from: monthStart).uppercased()
    }
    private var currentMonthDays: Int { cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30 }
    private var leadingBlanks: Int {
        cal.component(.weekday, from: monthStart) - 1
    }
    /// Calendar cells: leading nils to align day 1 to its weekday, then day numbers.
    private var monthCells: [Int?] {
        Array(repeating: Int?.none, count: leadingBlanks) + (1...currentMonthDays).map { Int?($0) }
    }
    /// The absolute date for a day number in the currently shown month.
    private func dateFor(_ day: Int) -> Date {
        cal.date(byAdding: .day, value: day - 1, to: monthStart) ?? monthStart
    }
    private func isToday(_ day: Int) -> Bool { cal.isDate(dateFor(day), inSameDayAs: Date()) }
    private func isFutureDay(_ day: Int) -> Bool { dateFor(day) > cal.startOfDay(for: Date()) }
    private func workoutOnDay(_ day: Int) -> WorkoutLogEntry? {
        guard let interval = cal.dateInterval(of: .month, for: monthStart) else { return nil }
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
}
