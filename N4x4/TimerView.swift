// TimerView.swift

import SwiftUI
#if canImport(Charts)
import Charts
#endif

struct TimerView: View {
    @ObservedObject var viewModel: TimerViewModel
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showResetAlert = false
    @State private var showSkipConfirmation = false
    @State private var skipConfirmationForCooldown = false
    @Environment(\.scenePhase) private var scenePhase

    var ringColor: Color {
        guard viewModel.intervals.indices.contains(viewModel.currentIntervalIndex) else {
            return .gray
        }

        switch viewModel.intervals[viewModel.currentIntervalIndex].type {
        case .warmup:
            return .blue
        case .highIntensity:
            return .red
        case .rest:
            return .green
        case .cooldown:
            return .teal
        }
    }

    var heartRateZoneText: String? {
        guard viewModel.intervals.indices.contains(viewModel.currentIntervalIndex) else {
            return nil
        }
        let interval = viewModel.intervals[viewModel.currentIntervalIndex]
        
        switch interval.type {
        case .highIntensity:
            let range = viewModel.highIntensityTargetRange
            return "❤️ Target Zone: \(range.lowerBound)-\(range.upperBound) BPM"
        case .rest:
            let range = viewModel.recoveryTargetRange
            return "💚 Recovery Zone: \(range.lowerBound)-\(range.upperBound) BPM"
        case .warmup, .cooldown:
            return nil
        }
    }

    var currentIntervalName: String {
        guard viewModel.intervals.indices.contains(viewModel.currentIntervalIndex) else {
            return "Ready"
        }

        let interval = viewModel.intervals[viewModel.currentIntervalIndex]
        let totalIntervals = viewModel.numberOfIntervals

        switch interval.type {
        case .warmup:
            return interval.name
        case .highIntensity:
            return "\(interval.name) (\(viewModel.highIntensityCount)/\(totalIntervals))"
        case .rest:
            return "\(interval.name) (\(viewModel.restCount)/\(totalIntervals))"
        case .cooldown:
            return interval.name
        }
    }

    var progressValue: CGFloat {
        guard viewModel.intervals.indices.contains(viewModel.currentIntervalIndex) else { return 0 }
        let duration = max(1, viewModel.intervals[viewModel.currentIntervalIndex].duration)
        let raw = viewModel.timeRemaining / duration
        return CGFloat(min(1, max(0, raw)))
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemBackground)
                    .edgesIgnoringSafeArea(.all)

                VStack(spacing: 24) {
                    Text(currentIntervalName)
                        .font(.system(size: 34, weight: .semibold, design: .default))
                        .foregroundColor(.primary)

                    ZStack {
                        Circle()
                            .stroke(lineWidth: 15)
                            .foregroundColor(Color(UIColor.systemGray5))

                        Circle()
                            .trim(from: 0, to: progressValue)
                            .stroke(style: StrokeStyle(lineWidth: 15, lineCap: .round))
                            .foregroundColor(ringColor)
                            .rotationEffect(Angle(degrees: -90))
                            .animation(.linear(duration: 1), value: viewModel.timeRemaining)

                        Text(timeString(time: viewModel.timeRemaining))
                            .font(.system(size: 50, weight: .bold, design: .default))
                            .foregroundColor(.primary)
                    }
                    .frame(width: 250, height: 250)

                    if let hrZone = heartRateZoneText {
                        Text(hrZone)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }

                    HStack(spacing: 50) {
                        Button(action: {
                            viewModel.pause()
                        }) {
                            Image(systemName: viewModel.isRunning ? "pause.circle" : "play.circle")
                                .font(.system(size: 50, weight: .regular, design: .default))
                                .foregroundColor(.primary)
                        }

                        Button(action: {
                            if viewModel.shouldConfirmSkipCurrentInterval() {
                                skipConfirmationForCooldown = viewModel.currentIntervalType == .cooldown
                                showSkipConfirmation = true
                            } else {
                                viewModel.skip()
                            }
                        }) {
                            Image(systemName: "forward.end.alt")
                                .font(.system(size: 50, weight: .regular, design: .default))
                                .foregroundColor(.primary)
                        }
                    }

                    vo2Section

                    if viewModel.cooldownCompletionNotice {
                        Text("Cooldown complete ✅")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.teal)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.teal.opacity(0.12), in: Capsule())
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding()
            }
            .navigationBarTitle("", displayMode: .inline)
            .navigationBarItems(
                leading: Button(action: {
                    showResetAlert = true
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title2)
                },
                trailing: HStack(spacing: 16) {
                    Button(action: {
                        showHistory = true
                    }) {
                        Image(systemName: "book")
                            .font(.title3)
                    }

                    Button(action: {
                        showSettings = true
                    }) {
                        Image(systemName: "gear")
                            .font(.title2)
                    }
                }
            )
            .sheet(isPresented: $showSettings) {
                SettingsView(viewModel: viewModel)
            }
            .sheet(isPresented: $showHistory) {
                StreakHistoryView(viewModel: viewModel)
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
                    .onDisappear {
                        viewModel.showWeeklyStreaks = false
                    }
            }
            .alert(isPresented: $showResetAlert) {
                Alert(
                    title: Text("Reset Session"),
                    message: Text("Are you sure you want to reset the session?"),
                    primaryButton: .destructive(Text("Reset")) {
                        viewModel.reset()
                    },
                    secondaryButton: .cancel()
                )
            }
            .alert(skipConfirmationForCooldown ? "End workout now?" : "Skip interval now?", isPresented: $showSkipConfirmation) {
                Button(skipConfirmationForCooldown ? "End Now" : "Skip Now", role: .destructive) {
                    viewModel.skip()
                }
                Button(skipConfirmationForCooldown ? "Continue Cooldown" : "Continue", role: .cancel) {}
            }
            .onChange(of: viewModel.isRunning) { _, _ in
                updateIdleTimer()
            }
            .onChange(of: viewModel.preventSleep) { _, _ in
                updateIdleTimer()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    // refreshOnForeground handles streak sync (S1), permission refresh,
                    // reminder rescheduling (N1), and health auth in one place.
                    viewModel.refreshOnForeground()
                    if viewModel.isRunning {
                        viewModel.reconcileTimerState(now: Date(), playAlarm: false)
                    }
                }
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
            .onAppear {
                updateIdleTimer()
            }
        }
    }

    @ViewBuilder
    var vo2Section: some View {
        if viewModel.healthKitEnabled && viewModel.vo2DataPoints.count >= 2 {
#if canImport(Charts)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("VO₂ Max Trend")
                        .font(.headline)
                    Spacer()
                    if let tier = viewModel.vo2TargetTier, let target = viewModel.vo2MaxTarget {
                        Text("Goal: \(tier.rawValue) \(Int(target))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Chart {
                    ForEach(viewModel.vo2DataPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("VO₂", point.value)
                        )
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("VO₂", point.value)
                        )
                    }
                    if let target = viewModel.vo2MaxTarget {
                        RuleMark(y: .value("Goal", target))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .foregroundStyle(.secondary)
                            .annotation(position: .top, alignment: .trailing) {
                                Text(viewModel.vo2TargetTier?.rawValue ?? "")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(height: 160)
            }
#else
            Text("VO₂ max data available. Trend chart requires iOS Charts support.")
                .font(.footnote)
                .foregroundColor(.secondary)
#endif
        }
    }

    // Helper functions inside TimerView
    func timeString(time: TimeInterval) -> String {
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        return String(format: "%02i:%02i", minutes, seconds)
    }

    func updateIdleTimer() {
        if viewModel.isRunning && viewModel.preventSleep {
            UIApplication.shared.isIdleTimerDisabled = true
        } else {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}

private struct PostWorkoutSummaryView: View {
    @ObservedObject var viewModel: TimerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                // Science card — rotates per session
                Section {
                    ScienceCardView(fact: currentFact)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                Section(header: Text("Session Breakdown")) {
                    LabeledContent("Total") { Text(formatDuration(viewModel.currentSessionBreakdown.totalDuration)) }
                    LabeledContent("High Intensity") { Text(formatDuration(viewModel.currentSessionBreakdown.highIntensityDuration)) }
                    LabeledContent("Recovery") { Text(formatDuration(viewModel.currentSessionBreakdown.recoveryDuration)) }
                    LabeledContent("Cooldown") {
                        if viewModel.currentSessionBreakdown.cooldownSkipped {
                            Text("Skipped")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(formatDuration(viewModel.currentSessionBreakdown.cooldownDuration))
                        }
                    }
                }

                Section(header: Text("Log this session")) {
                    Picker("Type", selection: $viewModel.selectedWorkoutType) {
                        ForEach(WorkoutType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    TextField("Notes (optional)", text: $viewModel.workoutNotesDraft, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Session on \(sessionDateText)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        viewModel.closePostWorkoutSummaryWithoutSaving()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.saveWorkoutLogEntryAndResetSession()
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(true)
    }

    private var currentFact: ScienceFact {
        ScienceFact.all[viewModel.workoutLogEntries.count % ScienceFact.all.count]
    }

    private var sessionDateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: viewModel.workoutStartDate ?? Date())
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        if minutes <= 0 { return "0 min" }
        return "\(minutes) min"
    }
}

// MARK: - Science facts

private struct ScienceFact {
    let icon: String
    let color: Color
    let title: String
    let body: String

    static let all: [ScienceFact] = [
        ScienceFact(
            icon: "bolt.heart.fill",
            color: Color(red: 1.0, green: 0.3, blue: 0.3),
            title: "Your metabolism stays elevated",
            body: "EPOC — excess post-exercise oxygen consumption — keeps your metabolic rate elevated for up to 24 hours after high-intensity intervals. You're still burning extra energy while you rest."
        ),
        ScienceFact(
            icon: "waveform.path.ecg",
            color: Color(red: 0.3, green: 0.7, blue: 1.0),
            title: "New blood vessels are forming",
            body: "High-intensity exercise triggers VEGF, a growth factor that signals your muscles to sprout new capillaries. More vessels means more oxygen delivery — which is exactly what raises VO₂ max."
        ),
        ScienceFact(
            icon: "atom",
            color: Color(red: 0.4, green: 0.9, blue: 0.5),
            title: "Your cells are building power plants",
            body: "PGC-1α, activated by hard intervals, is now triggering mitochondrial biogenesis — your muscle cells are literally building new mitochondria, the engines that convert oxygen into energy."
        ),
        ScienceFact(
            icon: "heart.fill",
            color: Color(red: 1.0, green: 0.4, blue: 0.6),
            title: "Your heart is getting stronger",
            body: "Repeated high-intensity efforts train the left ventricle to pump more blood per beat (stroke volume). Over months, this is the primary mechanism behind a rising VO₂ max."
        ),
        ScienceFact(
            icon: "brain.head.profile",
            color: Color(red: 0.7, green: 0.4, blue: 1.0),
            title: "Your brain just got a boost",
            body: "Hard exercise floods the brain with BDNF — Brain-Derived Neurotrophic Factor. It sharpens focus, improves memory consolidation, and protects against cognitive decline. You're sharper right now."
        ),
        ScienceFact(
            icon: "gauge.with.dots.needle.67percent",
            color: .orange,
            title: "Your lactate threshold just moved",
            body: "Your muscles repeatedly produced and cleared lactate during those work intervals. Each session nudges the intensity level at which lactate starts to accumulate — meaning you can go harder before hitting the wall."
        ),
        ScienceFact(
            icon: "staroflife.fill",
            color: Color(red: 0.2, green: 0.85, blue: 0.75),
            title: "Repair is already underway",
            body: "Satellite cells — your muscles' repair crew — are already mobilising to fix micro-tears from the effort. The slight soreness tomorrow is controlled inflammation: your body rebuilding slightly stronger than before."
        ),
        ScienceFact(
            icon: "chart.line.uptrend.xyaxis",
            color: Color(red: 1.0, green: 0.75, blue: 0.2),
            title: "The most effective VO₂ max stimulus",
            body: "Studies consistently show that 4×4 high-intensity intervals produce greater VO₂ max improvements than any other training format — including longer, slower cardio. You chose the right tool."
        ),
    ]
}

private struct ScienceCardView: View {
    let fact: ScienceFact
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: fact.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(fact.color)
                Text("What's happening in your body")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(fact.title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(fact.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fact.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(fact.color.opacity(0.25), lineWidth: 1)
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .animation(.easeOut(duration: 0.4).delay(0.15), value: appeared)
        .onAppear { appeared = true }
    }
}

private struct StreakHistoryView: View {
    @ObservedObject var viewModel: TimerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedWorkout: WorkoutLogEntry?
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    private let daySymbols = ["S", "M", "T", "W", "T", "F", "S"]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    streakHeader
                    calendarSection
                    if let workout = selectedWorkout {
                        workoutDetailCard(workout)
                    }
                }
                .padding()
            }
            .navigationTitle("Weekly Streaks")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private var streakHeader: some View {
        HStack(spacing: 20) {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.currentStreak > 0 ? "flame.fill" : "flame")
                        .font(.title)
                        .foregroundStyle(viewModel.currentStreak > 0 ? .orange : .gray)
                    Text("\(viewModel.currentStreak)")
                        .font(.system(size: 36, weight: .bold))
                }
                Text("Current Streak")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider().frame(height: 50)
            
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .font(.title)
                        .foregroundStyle(.orange)
                    Text("\(viewModel.longestStreak)")
                        .font(.system(size: 36, weight: .bold))
                }
                Text("Best Streak")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }
    
    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Month")
                .font(.headline)
            
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(daySymbols, id: \.self) { day in
                    Text(day).font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity)
                }
            }
            
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<currentMonthDays, id: \.self) { index in
                    let dayNumber = index + 1
                    let workout = workoutOnDay(dayNumber)
                    let isToday = isToday(dayNumber)
                    
                    Button(action: {
                        if let w = workout { selectedWorkout = w }
                    }) {
                        ZStack {
                            Circle().fill(workout != nil ? Color.green : (isToday ? Color.accentColor.opacity(0.2) : Color.clear))
                            if workout != nil {
                                Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundColor(.white)
                            }
                            Text("\(dayNumber)").font(.caption).foregroundColor(workout != nil ? .white : (isToday ? .accentColor : .primary))
                        }
                        .aspectRatio(1, contentMode: .fit)
                    }
                    .disabled(workout == nil)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }
    
    private func workoutDetailCard(_ workout: WorkoutLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Text("Workout Details").font(.headline)
                Spacer()
                Button("Close") { selectedWorkout = nil }.font(.caption)
            }
            Divider()
            HStack {
                VStack(alignment: .leading) {
                    Text("Type").font(.caption).foregroundColor(.secondary)
                    Text(workout.workoutType.rawValue).font(.body.weight(.medium))
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Date").font(.caption).foregroundColor(.secondary)
                    Text(workout.completedAt, style: .date).font(.body.weight(.medium))
                }
            }
            if let breakdown = workout.sessionBreakdown {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Protocol").font(.caption).foregroundColor(.secondary)
                    Text("Total: \(formatMinutes(breakdown.totalDuration)) • HI: \(formatMinutes(breakdown.highIntensityDuration)) • Recovery: \(formatMinutes(breakdown.recoveryDuration))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Cooldown: \(breakdown.cooldownSkipped ? "Skipped" : formatMinutes(breakdown.cooldownDuration))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if !workout.notes.isEmpty {
                VStack(alignment: .leading) {
                    Text("Notes").font(.caption).foregroundColor(.secondary)
                    Text(workout.notes).font(.body)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }
    
    private func formatMinutes(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        return "\(max(0, minutes)) min"
    }

    private var currentMonthDays: Int {
        Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
    }
    
    private func isToday(_ day: Int) -> Bool {
        Calendar.current.component(.day, from: Date()) == day
    }
    
    private func workoutOnDay(_ day: Int) -> WorkoutLogEntry? {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: Date()) else { return nil }
        // G3: return the most recent workout on this day rather than the first match,
        // so that multiple same-day entries (e.g. reset + redo) show the latest one.
        return viewModel.workoutLogEntries
            .filter { monthInterval.contains($0.completedAt) && calendar.component(.day, from: $0.completedAt) == day }
            .max(by: { $0.completedAt < $1.completedAt })
    }
}

// MARK: - Milestone celebration

private struct MilestoneCelebrationView: View {
    let count: Int
    let onContinue: () -> Void

    @State private var scaleIn = false
    @State private var fadeIn  = false

    private var milestone: (icon: String, title: String, message: String) {
        switch count {
        case 1:
            return ("flag.checkered", "First Session Done!", "Every elite athlete started exactly here. The most important rep is always the first one.")
        case 5:
            return ("flame.fill", "5 Sessions Strong!", "You've shown up 5 times. Your heart is already adapting — blood vessels are growing, mitochondria multiplying.")
        case 10:
            return ("star.fill", "10 Sessions!", "Science says habits take about 10 repetitions to start sticking. You're there. This is becoming part of who you are.")
        case 25:
            return ("bolt.circle.fill", "25 Sessions!", "A quarter-century of intervals. Your VO₂ max has almost certainly improved. The data is in your body.")
        case 50:
            return ("diamond.fill", "50 Sessions!", "This is elite consistency. Most people never make it this far. You are not most people.")
        case 100:
            return ("trophy.fill", "100 Sessions!", "You are the Norwegian 4x4 program. This level of commitment is exceptional. You've genuinely changed your cardiovascular system.")
        default:
            return ("checkmark.seal.fill", "Session \(count) Complete!", "Another session in the books. Keep building.")
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.05, blue: 0.15), Color(red: 0.1, green: 0.0, blue: 0.25)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                // Confetti
                ConfettiView(width: geo.size.width, height: geo.size.height)
                    .ignoresSafeArea()

                // Content
                VStack(spacing: 32) {
                    Spacer()

                    // Icon
                    Image(systemName: milestone.icon)
                        .font(.system(size: 80, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                        )
                        .scaleEffect(scaleIn ? 1.0 : 0.3)
                        .opacity(scaleIn ? 1.0 : 0.0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1), value: scaleIn)

                    // Count badge
                    Text("\(count)")
                        .font(.system(size: 96, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.white, .white.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                        )
                        .opacity(fadeIn ? 1.0 : 0.0)
                        .animation(.easeOut(duration: 0.5).delay(0.3), value: fadeIn)

                    Text(milestone.title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .opacity(fadeIn ? 1.0 : 0.0)
                        .animation(.easeOut(duration: 0.5).delay(0.45), value: fadeIn)

                    Text(milestone.message)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 32)
                        .opacity(fadeIn ? 1.0 : 0.0)
                        .animation(.easeOut(duration: 0.5).delay(0.6), value: fadeIn)

                    Spacer()

                    Button(action: onContinue) {
                        Text("Keep Going →")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
                    .opacity(fadeIn ? 1.0 : 0.0)
                    .animation(.easeOut(duration: 0.5).delay(0.8), value: fadeIn)
                }
            }
        }
        .onAppear {
            scaleIn = true
            fadeIn  = true
        }
    }
}

private struct ConfettiView: View {
    struct Piece: Identifiable {
        let id    = UUID()
        let color : Color
        let startX: CGFloat
        let endX  : CGFloat
        let size  : CGSize
        let duration : Double
        let delay    : Double
        let endRotation: Double
    }

    @State private var animate = false
    let pieces: [Piece]
    let height: CGFloat

    init(width: CGFloat, height: CGFloat) {
        self.height = height
        let colors: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .white]
        pieces = (0..<60).map { _ in
            Piece(
                color:      colors.randomElement()!,
                startX:     CGFloat.random(in: 0...width),
                endX:       CGFloat.random(in: 0...width),
                size:       CGSize(width: CGFloat.random(in: 6...14), height: CGFloat.random(in: 8...18)),
                duration:   Double.random(in: 2.5...4.5),
                delay:      Double.random(in: 0...1.8),
                endRotation: Double.random(in: 180...1080)
            )
        }
    }

    var body: some View {
        ZStack {
            ForEach(pieces) { p in
                Rectangle()
                    .fill(p.color.opacity(0.85))
                    .frame(width: p.size.width, height: p.size.height)
                    .rotationEffect(.degrees(animate ? p.endRotation : 0))
                    .position(x: animate ? p.endX : p.startX,
                              y: animate ? height + 60 : -20)
                    .animation(.easeIn(duration: p.duration).delay(p.delay), value: animate)
            }
        }
        .onAppear { animate = true }
    }
}
