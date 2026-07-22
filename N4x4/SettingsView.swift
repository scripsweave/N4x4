// SettingsView
// Top level of the restructured Settings (v4.6): grouped, icon-tiled rows with
// current-value previews, iOS Settings style. Detail pages live in
// SettingsSubpages.swift; most-used settings (default workout, training days)
// are pinned at the top. Searchable.

import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: TimerViewModel
    /// When true, the view is hosted inside a tab (not a sheet), so the
    /// dismiss-style "Done" button is omitted.
    var embedded: Bool = false
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.openURL) private var openURL

    // Local mirrors of the keys behind the value previews. @AppStorage on the
    // view observes UserDefaults directly, so rows refresh when a subpage (or
    // onboarding, or the watch) writes the underlying key — @AppStorage on the
    // ObservableObject alone doesn't publish to SwiftUI.
    @AppStorage("defaultWorkoutTypeRaw") private var defaultWorkoutTypeRaw: String = ""
    @AppStorage("workoutRemindersEnabled") private var remindersEnabledMirror = false
    @AppStorage("workoutReminderWeekdays") private var reminderWeekdaysMirror = ""
    @AppStorage("numberOfIntervals") private var numberOfIntervalsMirror = 4
    @AppStorage("highIntensityDuration") private var highIntensityDurationMirror: Double = 4 * 60
    @AppStorage("audioModeRaw") private var audioModeMirror = AudioMode.voice.rawValue
    @AppStorage("hapticsEnabled") private var hapticsEnabledMirror = true
    @AppStorage("userAge") private var userAgeMirror = 40
    @AppStorage("useCustomMaxHR") private var useCustomMaxHRMirror = false
    @AppStorage("customMaxHR") private var customMaxHRMirror = 0
    @AppStorage("vo2TargetTierRaw") private var vo2TierMirror = ""
    @AppStorage("healthKitEnabled") private var healthKitEnabledMirror = false
    @AppStorage("appleSensorHREnabled") private var appleSensorEnabledMirror = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var showResetAlert = false
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Form {
                if trimmedSearch.isEmpty {
                    pinnedSection
                    workoutSection
                    coachingSection
                    devicesSection
                    progressSection
                    generalSection
                    resetSection
                } else {
                    searchResultsSection
                }
            }
            .navigationTitle("Settings")
            .searchable(text: $searchText, prompt: "Search settings")
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { presentationMode.wrappedValue.dismiss() }
                    }
                }
            }
            .alert(isPresented: $showResetAlert) {
                Alert(
                    title: Text("Reset to Defaults"),
                    message: Text("Are you sure you want to reset all settings to their default values?"),
                    primaryButton: .destructive(Text("Reset")) {
                        viewModel.resetSettingsToDefaults()
                    },
                    secondaryButton: .cancel()
                )
            }
            .onAppear {
                viewModel.refreshNotificationPermissionState()
                viewModel.refreshHealthKitAuthorizationState()
                if viewModel.healthKitEnabled {
                    viewModel.fetchVO2MaxSamples()
                }
            }
        }
    }

    // MARK: - Sections

    /// Most-used settings, unlabeled and first — like iOS pins Wi-Fi.
    private var pinnedSection: some View {
        Section(
            footer: Text("The default workout is pre-selected when you save a completed session; exercise tips follow it.")
        ) {
            defaultWorkoutRow
            trainingDaysRow
        }
    }

    private var workoutSection: some View {
        Section(header: Text("Workout")) {
            intervalsRow
        }
    }

    private var coachingSection: some View {
        Section(header: Text("Coaching")) {
            audioRow
            hapticsRow
            zonesRow
        }
    }

    private var devicesSection: some View {
        Section(header: Text("Devices & Health")) {
            watchRow
            monitorRow
            hrSourcesRow
            healthRow
        }
    }

    private var progressSection: some View {
        Section(header: Text("Progress")) {
            vo2Row
            unitsRow
        }
    }

    private var generalSection: some View {
        Section(header: Text("General")) {
            displayRow
            replayOnboardingRow
            feedbackRow
        }
    }

    private var resetSection: some View {
        Section {
            resetRow
        }
    }

    private var resetRow: some View {
        Button(action: { showResetAlert = true }) {
            Text("Reset All Settings")
                .frame(maxWidth: .infinity)
                .foregroundColor(.red)
        }
    }

    // MARK: - Rows

    /// Reads through to the resolved default; writes route through the view
    /// model so the exercise-guidance modality follows the chosen type.
    private var defaultWorkoutBinding: Binding<WorkoutType> {
        Binding(
            get: { WorkoutType(rawValue: defaultWorkoutTypeRaw) ?? viewModel.resolvedDefaultWorkoutType },
            set: { viewModel.setDefaultWorkoutType($0) }
        )
    }

    private var defaultWorkoutRow: some View {
        HStack(spacing: 12) {
            SettingsIconTile(systemName: "figure.run", tint: .orange)
            Picker("Default Workout", selection: defaultWorkoutBinding) {
                ForEach(WorkoutType.selectableCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
        }
    }

    private var trainingDaysRow: some View {
        SettingsRow(icon: "calendar", tint: .red, title: "Training Days & Reminders",
                    value: viewModel.reminderDaysSummary) {
            TrainingDaysSettingsView(viewModel: viewModel)
        }
    }

    private var intervalsRow: some View {
        SettingsRow(icon: "timer", tint: .green, title: "Intervals & Durations",
                    value: viewModel.intervalPlanSummary) {
            IntervalSettingsView(viewModel: viewModel)
        }
    }

    private var audioRow: some View {
        SettingsRow(icon: "speaker.wave.2.fill", tint: .blue, title: "Audio",
                    value: audioValue) {
            AudioSettingsView(viewModel: viewModel)
        }
    }

    private var hapticsRow: some View {
        SettingsRow(icon: "iphone.radiowaves.left.and.right", tint: .purple, title: "Haptics",
                    value: hapticsEnabledMirror ? "On" : "Off") {
            HapticsSettingsView(viewModel: viewModel)
        }
    }

    private var zonesRow: some View {
        SettingsRow(icon: "heart.fill", tint: .pink, title: "Heart-Rate Zones & Alerts",
                    value: "Max \(viewModel.maximumHeartRate)") {
            ZoneSettingsView(viewModel: viewModel)
        }
    }

    private var watchRow: some View {
        SettingsRow(icon: "applewatch", tint: Color(uiColor: .darkGray), title: "Apple Watch",
                    value: watchValue) {
            AppleWatchSettingsView(viewModel: viewModel)
        }
    }

    private var monitorRow: some View {
        MonitorSettingsRowLink(viewModel: viewModel, manager: viewModel.bleHeartRateManager)
    }

    private var hrSourcesRow: some View {
        SettingsRow(icon: "waveform.path.ecg", tint: .orange, title: "Heart Rate Sources",
                    value: appleSensorEnabledMirror ? "AirPods On" : "") {
            HeartRateSourcesSettingsView(viewModel: viewModel)
        }
    }

    private var healthRow: some View {
        SettingsRow(icon: "heart.text.square.fill", tint: .red, title: "Apple Health",
                    value: healthKitEnabledMirror ? "On" : "Off") {
            AppleHealthSettingsView(viewModel: viewModel)
        }
    }

    private var vo2Row: some View {
        SettingsRow(icon: "chart.line.uptrend.xyaxis", tint: .blue, title: "VO₂ Max Goal",
                    value: VO2TargetTier(rawValue: vo2TierMirror)?.rawValue ?? "None") {
            VO2GoalSettingsView(viewModel: viewModel)
        }
    }

    private var unitsRow: some View {
        HStack(spacing: 12) {
            SettingsIconTile(systemName: "ruler", tint: .gray)
            Picker("Units", selection: $viewModel.unitPreference) {
                ForEach(UnitPreference.allCases) { pref in
                    Text(pref.label).tag(pref)
                }
            }
        }
    }

    private var displayRow: some View {
        SettingsRow(icon: "iphone", tint: .indigo, title: "Display") {
            DisplaySettingsView(viewModel: viewModel)
        }
    }

    private var replayOnboardingRow: some View {
        Button {
            hasCompletedOnboarding = false
            presentationMode.wrappedValue.dismiss()
        } label: {
            HStack(spacing: 12) {
                SettingsIconTile(systemName: "arrow.counterclockwise", tint: .gray)
                Text("Replay Onboarding")
                    .foregroundStyle(.primary)
            }
        }
    }

    private var feedbackRow: some View {
        Button {
            if let url = feedbackMailURL {
                openURL(url)
            }
        } label: {
            HStack(spacing: 12) {
                SettingsIconTile(systemName: "envelope.fill", tint: .blue)
                Text("Send Feedback")
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Value previews

    private var audioValue: String {
        switch AudioMode(rawValue: audioModeMirror) ?? .voice {
        case .voice:  return "Voice"
        case .alarm:  return "Beep"
        case .silent: return "Silent"
        }
    }

    private var watchValue: String {
        switch viewModel.watchConnectionStatus {
        case .noWatchPaired:   return "Not paired"
        case .appNotInstalled: return "App missing"
        case .notReachable:    return "Installed"
        case .connected:       return "Connected"
        }
    }

    // MARK: - Search

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    /// One entry per destination; keywords cover the controls that live there
    /// so "cooldown" finds Intervals and "strap" finds the monitor.
    private var searchEntries: [(title: String, keywords: String, row: AnyView)] {
        [
            ("Default Workout", "default workout type kettlebells cycle run exercise",
             AnyView(defaultWorkoutRow)),
            ("Training Days & Reminders", "training days reminders schedule week notifications night morning comeback nudge interval change",
             AnyView(trainingDaysRow)),
            ("Intervals & Durations", "intervals durations warmup warm-up high intensity recovery rest cooldown cool-down skip confirm structure minutes",
             AnyView(intervalsRow)),
            ("Audio", "audio voice prompts beep alarm silent halfway ten second sound cues music",
             AnyView(audioRow)),
            ("Haptics", "haptics vibration vibrate taps buzz countdown",
             AnyView(hapticsRow)),
            ("Heart-Rate Zones & Alerts", "heart rate zones alerts max age custom bpm target haptic voice visual tanaka",
             AnyView(zonesRow)),
            ("Apple Watch", "apple watch wrist pairing troubleshooting",
             AnyView(watchRow)),
            ("Heart Rate Monitor", "heart rate monitor bluetooth chest strap armband garmin polar whoop pairing",
             AnyView(monitorRow)),
            ("Heart Rate Sources", "heart rate sources airpods powerbeats priority order arbitration apple sensors earbuds",
             AnyView(hrSourcesRow)),
            ("Apple Health", "apple health healthkit sync log workouts vo2 refresh",
             AnyView(healthRow)),
            ("VO₂ Max Goal", "vo2 max goal target tier good amazing elite biological sex",
             AnyView(vo2Row)),
            ("Units", "units metric imperial system measurement km miles",
             AnyView(unitsRow)),
            ("Display", "display screen awake sleep live activity dynamic island lock",
             AnyView(displayRow)),
            ("Replay Onboarding", "replay onboarding first run guide intro tutorial",
             AnyView(replayOnboardingRow)),
            ("Send Feedback", "send feedback email bug idea feature support",
             AnyView(feedbackRow)),
            ("Reset All Settings", "reset defaults clear",
             AnyView(resetRow)),
        ]
    }

    @ViewBuilder
    private var searchResultsSection: some View {
        let needle = trimmedSearch.lowercased()
        let matches = searchEntries.filter {
            $0.title.lowercased().contains(needle) || $0.keywords.contains(needle)
        }
        if matches.isEmpty {
            Section {
                Text("No settings match “\(trimmedSearch)”.")
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                ForEach(matches, id: \.title) { match in
                    match.row
                }
            }
        }
    }

    /// mailto: link for Send Feedback, with app/OS/device details prefilled
    /// below a divider so triage never needs a follow-up email. The body opens
    /// with blank lines for the user's own text.
    private var feedbackMailURL: URL? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        var systemInfo = utsname()
        uname(&systemInfo)
        let model = withUnsafeBytes(of: &systemInfo.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let body = """


        —
        N4x4 \(version) (\(build))
        iOS \(UIDevice.current.systemVersion) · \(model)
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "feedback@n4x4.app"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "N4x4 Feedback"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}

/// Observes the Bluetooth manager so the "Paired"/"Not paired" preview stays
/// live while the settings screen is visible.
private struct MonitorSettingsRowLink: View {
    @ObservedObject var viewModel: TimerViewModel
    @ObservedObject var manager: BluetoothHeartRateManager

    var body: some View {
        SettingsRow(icon: "dot.radiowaves.left.and.right", tint: .teal, title: "Heart Rate Monitor",
                    value: manager.hasRememberedMonitor ? "Paired" : "Not paired") {
            HeartRateMonitorSettingsView(viewModel: viewModel)
        }
    }
}
