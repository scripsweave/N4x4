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
        case .warmup:
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
                            viewModel.skip()
                        }) {
                            Image(systemName: "forward.end.alt")
                                .font(.system(size: 50, weight: .regular, design: .default))
                                .foregroundColor(.primary)
                        }
                    }

                    vo2Section
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
                    if viewModel.healthKitEnabled {
                        viewModel.fetchVO2MaxSamples()
                    }
                }
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    @ViewBuilder
    var vo2Section: some View {
        if viewModel.healthKitEnabled && viewModel.vo2DataPoints.count >= 2 {
#if canImport(Charts)
            VStack(alignment: .leading, spacing: 8) {
                Text("VO₂ Max Trend")
                    .font(.headline)
                Chart(viewModel.vo2DataPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("VO₂", point.value)
                    )
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("VO₂", point.value)
                    )
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
                Section(header: Text("Workout complete")) {
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.saveWorkoutLogEntryAndResetSession()
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var sessionDateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: viewModel.workoutStartDate ?? Date())
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
