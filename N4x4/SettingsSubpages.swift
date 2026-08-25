// SettingsSubpages.swift
// Detail pages for the restructured Settings (v4.6): the top level in
// SettingsView.swift shows grouped rows with value previews; every page here
// is a plain Form pushed via NavigationLink. All bindings stay on
// TimerViewModel — this file moves UI, not logic.

import SwiftUI
import WatchConnectivity
import HealthKit
import UIKit

// MARK: - Shared row components

/// iOS Settings-style icon tile: white SF Symbol on a small colored
/// rounded square.
struct SettingsIconTile: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 6.5, style: .continuous).fill(tint))
    }
}

/// Top-level row: icon tile · title · current value · chevron (from the
/// NavigationLink). The value preview is what saves the tap.
struct SettingsRow<Destination: View>: View {
    let icon: String
    let tint: Color
    let title: String
    var value: String = ""
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                SettingsIconTile(systemName: icon, tint: tint)
                Text(title)
                Spacer()
                if !value.isEmpty {
                    Text(value)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// Inline "permission denied" note with a jump to the system Settings app.
struct PermissionDeniedNote: View {
    let message: String
    @ObservedObject var viewModel: TimerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.footnote)
                .foregroundColor(.secondary)
            Button("Open Settings") {
                viewModel.openAppSettings()
            }
            .font(.footnote)
        }
        .padding(.vertical, 4)
    }
}

/// Mon–Sun selection grid shared by the Training Days page (same look as the
/// one that lived in the flat Settings form).
struct WeekdaySelectionGrid: View {
    @ObservedObject var viewModel: TimerViewModel

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
            ForEach(TimerViewModel.reminderWeekdayOptions, id: \.value) { option in
                Button(action: {
                    viewModel.toggleWeekday(option.value)
                }) {
                    Text(String(option.title.prefix(3)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(viewModel.isWeekdaySelected(option.value) ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(viewModel.isWeekdaySelected(option.value) ? Color.accentColor : Color.gray.opacity(0.2))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

func settingsHasConsecutiveDays(_ days: [Int]) -> Bool {
    guard days.count >= 2 else { return false }
    let sorted = days.sorted()
    for i in 0..<(sorted.count - 1) {
        if sorted[i + 1] - sorted[i] == 1 { return true }
    }
    return sorted.contains(7) && sorted.contains(1)
}

// MARK: - Training Days & Reminders

struct TrainingDaysSettingsView: View {
    @ObservedObject var viewModel: TimerViewModel

    var body: some View {
        Form {
            Section(
                header: Text("Weekly Schedule"),
                footer: Text(scheduleFooter)
            ) {
                WeekdaySelectionGrid(viewModel: viewModel)
                if settingsHasConsecutiveDays(viewModel.selectedWeekdays) {
                    Label(
                        "Consecutive days aren't recommended — allow 48–72 hours of recovery between sessions.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundColor(.orange)
                }
            }

            Section(
                header: Text("Reminders"),
                footer: Text("Night-before arrives at 8pm, morning-of at 8am. Comeback nudges follow up daily at 10am after a missed training day, until you train.")
            ) {
                Toggle("Night-Before Reminder", isOn: $viewModel.nightBeforeReminderEnabled)
                Toggle("Morning-Of Reminder", isOn: $viewModel.morningOfReminderEnabled)
                Toggle("Comeback Nudges", isOn: $viewModel.comebackNudgesEnabled)
            }

            Section(
                header: Text("During Workouts"),
                footer: Text("Notifies you at each interval change when the screen is locked.")
            ) {
                Toggle("Interval Change Notifications", isOn: $viewModel.notificationsEnabled)
                if viewModel.notificationPermissionState == .denied {
                    PermissionDeniedNote(
                        message: "Notifications are denied for N4x4. Enable them in Settings to receive interval and reminder alerts.",
                        viewModel: viewModel
                    )
                }
            }
        }
        .navigationTitle("Training Days")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.refreshNotificationPermissionState() }
    }

    private var scheduleFooter: String {
        let count = viewModel.selectedWeekdays.count
        guard count > 0 else { return "Pick the days you plan to train." }
        return "\(count) day\(count == 1 ? "" : "s") per week. Leave 48–72 hours between sessions."
    }
}

// MARK: - Intervals & Durations

struct IntervalSettingsView: View {
    @ObservedObject var viewModel: TimerViewModel

    var body: some View {
        Form {
            Section(
                header: Text("Structure"),
                footer: Text("The classic protocol is 4 × 4 minutes. Start with 2 and build up.")
            ) {
                Stepper(value: $viewModel.numberOfIntervals, in: 1...10) {
                    Text("Intervals: \(viewModel.numberOfIntervals)")
                }
            }

            Section(header: Text("Durations (Minutes)")) {
                Stepper(value: $viewModel.warmupDuration, in: 0...600, step: 60) {
                    Text("Warm-Up: \(Int(viewModel.warmupDuration / 60)) min")
                }
                Stepper(value: $viewModel.highIntensityDuration, in: 60...600, step: 60) {
                    Text("High Intensity: \(Int(viewModel.highIntensityDuration / 60)) min")
                }
                Stepper(value: $viewModel.restDuration, in: 60...600, step: 60) {
                    Text("Recovery: \(Int(viewModel.restDuration / 60)) min")
                }
                Toggle("Cool-Down", isOn: $viewModel.cooldownEnabled)
                if viewModel.cooldownEnabled {
                    Stepper(value: $viewModel.cooldownDuration, in: 60...600, step: 60) {
                        Text("Cool-Down: \(Int(viewModel.cooldownDuration / 60)) min")
                    }
                }
            }

            Section(
                header: Text("Skipping"),
                footer: Text("Ask before a tap on Skip ends an interval early.")
            ) {
                Toggle("Confirm Cool-Down Skip", isOn: $viewModel.confirmSkipCooldown)
                Toggle("Confirm Other Skips", isOn: $viewModel.confirmSkipOtherIntervals)
            }
        }
        .navigationTitle("Intervals")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Audio

struct AudioSettingsView: View {
    @ObservedObject var viewModel: TimerViewModel

    var body: some View {
        Form {
            Section(footer: Text(modeDescription)) {
                Picker("Audio Cues", selection: $viewModel.audioMode) {
                    ForEach(AudioMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            if viewModel.audioMode == .voice {
                Section(header: Text("Voice Prompts")) {
                    Toggle("Halfway Prompts", isOn: $viewModel.halfwayVoicePromptsEnabled)
                    Toggle("10-Second Warnings", isOn: $viewModel.tenSecondVoicePromptsEnabled)
                }
            }
        }
        .navigationTitle("Audio")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var modeDescription: String {
        switch viewModel.audioMode {
        case .alarm:
            return "A beep plays at each interval change (foreground only)."
        case .voice:
            return "Voice cues at start, halfway, and 10 seconds to go. Music softens while speaking."
        case .silent:
            return "No audio alerts. Watch the screen for interval changes."
        }
    }
}

// MARK: - Haptics

struct HapticsSettingsView: View {
    @ObservedObject var viewModel: TimerViewModel

    var body: some View {
        Form {
            Section(
                footer: Text("Vibrates on both iPhone and Apple Watch, regardless of the audio mode. Countdown into every interval change: two short taps at 3 and 2 seconds out, then one long buzz as the new interval starts. The end of the final interval gets just the two short taps.")
            ) {
                Toggle("Interval Haptics", isOn: $viewModel.hapticsEnabled)
            }
        }
        .navigationTitle("Haptics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Heart-Rate Zones & Alerts

struct ZoneSettingsView: View {
    @ObservedObject var viewModel: TimerViewModel

    var body: some View {
        Form {
            Section(
                header: Text("Max Heart Rate"),
                footer: Text(viewModel.useCustomMaxHR
                             ? "Using your custom maximum."
                             : (viewModel.userAge >= 40
                                ? "Estimated with the Tanaka formula (208 − 0.7 × age)."
                                : "Estimated with 220 − age."))
            ) {
                Picker("Method", selection: $viewModel.useCustomMaxHR) {
                    Text("Based on Age").tag(false)
                    Text("Custom").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.useCustomMaxHR) { _, isCustom in
                    if isCustom && viewModel.customMaxHR == 0 {
                        viewModel.customMaxHR = viewModel.maximumHeartRate
                    }
                }

                if viewModel.useCustomMaxHR {
                    Picker("Max Heart Rate", selection: $viewModel.customMaxHR) {
                        ForEach(100...220, id: \.self) { bpm in
                            Text("\(bpm) BPM").tag(bpm)
                        }
                    }
                } else {
                    Picker("Age", selection: $viewModel.userAge) {
                        ForEach(TimerViewModel.minimumSupportedAge...TimerViewModel.maximumSupportedAge, id: \.self) { age in
                            Text("\(age)").tag(age)
                        }
                    }
                }

                LabeledContent("Your Max Heart Rate") {
                    Text("\(viewModel.maximumHeartRate) BPM")
                }
            }

            Section(header: Text("Target Zones")) {
                HeartRateGuidanceCard(viewModel: viewModel, showInstructions: false)
                    .listRowInsets(EdgeInsets())
            }

            Section(
                header: Text("Zone Alerts"),
                footer: Text("When your heart rate drifts outside the target zone for the current interval, N4x4 nudges you back. Alerts wait for your heart rate to settle after each interval and never fire more than once a minute. Requires live heart rate from an Apple Watch or a Bluetooth monitor.")
            ) {
                Toggle("Haptic (Apple Watch)", isOn: $viewModel.zoneHapticAlertsEnabled)
                Toggle("Voice (iPhone)", isOn: $viewModel.zoneVoiceAlertsEnabled)
                Toggle("Visual (colour the heart rate)", isOn: $viewModel.zoneVisualAlertsEnabled)
            }
        }
        .navigationTitle("Heart-Rate Zones")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Apple Watch

struct AppleWatchSettingsView: View {
    @ObservedObject var viewModel: TimerViewModel
    @State private var showWatchHelp = false

    var body: some View {
        Form {
            Section(
                footer: Text("Wear your Apple Watch and start the workout from either device to stream live heart rate.")
            ) {
                if WCSession.isSupported() {
                    Button {
                        showWatchHelp = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: statusIcon)
                                .foregroundColor(statusTint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(statusTitle)
                                    .foregroundColor(.primary)
                                Text("Tap for setup & troubleshooting")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Apple Watch")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showWatchHelp) {
            WatchTroubleshootingView(viewModel: viewModel)
        }
    }

    private var statusIcon: String {
        switch viewModel.watchConnectionStatus {
        case .noWatchPaired, .appNotInstalled: return "applewatch.slash"
        case .notReachable:                    return "applewatch"
        case .connected:
            return viewModel.currentHeartRate == nil ? "applewatch" : "applewatch.radiowaves.left.and.right"
        }
    }

    private var statusTint: Color {
        switch viewModel.watchConnectionStatus {
        case .noWatchPaired:   return .secondary
        case .appNotInstalled: return .orange
        case .notReachable:    return .secondary
        case .connected:       return viewModel.currentHeartRate == nil ? .secondary : .green
        }
    }

    private var statusTitle: String {
        switch viewModel.watchConnectionStatus {
        case .noWatchPaired:   return "No Apple Watch paired"
        case .appNotInstalled: return "Watch app not installed"
        case .notReachable:    return "Watch app installed"
        case .connected:
            return viewModel.currentHeartRate == nil ? "Connected" : "Connected · HR streaming"
        }
    }
}

// MARK: - Heart Rate Monitor (Bluetooth)

struct HeartRateMonitorSettingsView: View {
    @ObservedObject var viewModel: TimerViewModel
    @State private var showMonitorSheet = false

    var body: some View {
        Form {
            Section(
                footer: Text("Connect a Bluetooth chest strap or armband for accurate live heart rate — with or without an Apple Watch. When both are connected, N4x4 uses the monitor.")
            ) {
                Button {
                    showMonitorSheet = true
                } label: {
                    HeartRateMonitorSettingsRow(manager: viewModel.bleHeartRateManager)
                }
            }
        }
        .navigationTitle("Heart Rate Monitor")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showMonitorSheet) {
            HeartRateMonitorSheet(manager: viewModel.bleHeartRateManager)
        }
    }
}

// MARK: - Heart Rate Sources

/// AirPods opt-in plus the arbitration order between simultaneous sources.
struct HeartRateSourcesSettingsView: View {
    @ObservedObject var viewModel: TimerViewModel
    /// Mirror of the view model's storage so the reordered list re-renders —
    /// writes still go through the view model (its didSet re-arbitrates).
    @AppStorage("hrSourcePriorityRaw") private var hrSourcePriorityRawMirror = ""

    var body: some View {
        Form {
            Section(
                header: Text("AirPods Pro 3"),
                footer: Text(airPodsFooter)
            ) {
                if #available(iOS 26.0, *) {
                    Toggle("AirPods Heart Rate", isOn: $viewModel.appleSensorHREnabled)
                } else {
                    LabeledContent("AirPods Heart Rate") {
                        Text("Requires iOS 26")
                    }
                }
            }

            Section(
                header: Text("Source Priority"),
                footer: Text("When several sources send heart rate at once, the highest in this list wins. Lower sources take over automatically when a higher one goes quiet. Drag to reorder.")
            ) {
                ForEach(viewModel.heartRateSourcePriority, id: \.rawValue) { source in
                    HStack(spacing: 12) {
                        SettingsIconTile(systemName: icon(for: source), tint: tint(for: source))
                        Text(source.displayName)
                    }
                }
                .onMove { from, to in
                    var order = viewModel.heartRateSourcePriority
                    order.move(fromOffsets: from, toOffset: to)
                    viewModel.heartRateSourcePriority = order
                }
            }
            .environment(\.editMode, .constant(.active))
        }
        .navigationTitle("Heart Rate Sources")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var airPodsFooter: String {
        if #available(iOS 26.0, *) {
            return "Streams live heart rate from AirPods Pro 3 during workouts through an Apple Health workout session (AirPods don't broadcast standard Bluetooth heart rate). Powerbeats Pro 2 connect as a regular Bluetooth monitor instead. Enabling this asks for Health access to your heart rate."
        }
        return "AirPods Pro 3 heart rate needs an iPhone on iOS 26 or later. Powerbeats Pro 2 work today — pair them as a Bluetooth monitor."
    }

    private func icon(for source: HeartRateAggregator.Source) -> String {
        switch source {
        case .bluetooth:   return "dot.radiowaves.left.and.right"
        case .watch:       return "applewatch"
        case .appleSensor: return "airpods"
        }
    }

    private func tint(for source: HeartRateAggregator.Source) -> Color {
        switch source {
        case .bluetooth:   return .teal
        case .watch:       return Color(uiColor: .darkGray)
        case .appleSensor: return .orange
        }
    }
}

// MARK: - Apple Health

struct AppleHealthSettingsView: View {
    @ObservedObject var viewModel: TimerViewModel

    var body: some View {
        Form {
            Section(
                footer: Text(viewModel.healthAuthorizationGranted ? "Connected" : "Not connected")
            ) {
                Toggle("Enable Apple Health", isOn: $viewModel.healthKitEnabled)
                    .onChange(of: viewModel.healthKitEnabled) { _, enabled in
                        // Remember that this was the user's own choice, so the
                        // authorization refresh doesn't switch it back on.
                        viewModel.healthKitUserOptedOut = !enabled
                        if enabled {
                            viewModel.requestHealthKitAuthorizationIfNeeded()
                        }
                    }

                if viewModel.healthKitEnabled {
                    Toggle("Log Workouts to Apple Health", isOn: $viewModel.logWorkoutsToHealthKit)
                }

                if viewModel.healthKitPermissionState == .denied {
                    PermissionDeniedNote(
                        message: "Apple Health access is denied. Enable workout and VO₂ permissions in Settings to sync completed sessions.",
                        viewModel: viewModel
                    )
                }

                Button("Refresh VO₂ max Data") {
                    viewModel.fetchVO2MaxSamples()
                }
                .disabled(!viewModel.healthKitEnabled)
            }

            // Deliberately outside the toggle's `if`: someone whose connection
            // looks off is exactly who needs the checklist most.
            Section {
                NavigationLink {
                    AppleHealthTroubleshootView(viewModel: viewModel)
                } label: {
                    Label("Troubleshoot Apple Health", systemImage: "stethoscope")
                        .font(.footnote)
                }
            } footer: {
                Text("No VO₂ max chart on the home screen? Check what N4x4 can actually see.")
            }
        }
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.refreshHealthKitAuthorizationState() }
    }
}

// MARK: - Apple Health troubleshooting

/// Answers "why is there no VO₂ max graph?" without the user having to write in.
/// Every row is a live check rather than static advice, because the usual causes
/// look identical from the home screen: permission revoked, never granted,
/// granted but Apple Health simply holds no Cardio Fitness readings.
struct AppleHealthTroubleshootView: View {
    @ObservedObject var viewModel: TimerViewModel
    @State private var copied = false

    private var points: [VO2DataPoint] {
        viewModel.vo2DataPoints.sorted { $0.date < $1.date }
    }

    private var healthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        Form {
            checksSection
            actionsSection
            whereItComesFromSection
            manualStepsSection
            diagnosticsSection
        }
        .navigationTitle("Troubleshoot")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.refreshHealthKitAuthorizationState()
            if viewModel.healthKitEnabled { viewModel.fetchVO2MaxSamples() }
        }
    }

    // MARK: Checks

    private var checksSection: some View {
        Section(header: Text("Checks"), footer: Text(verdict)) {
            HealthCheckRow(
                state: healthDataAvailable ? .pass : .fail,
                title: "Health data on this device",
                detail: healthDataAvailable ? "Available" : "This device has no Health database"
            )
            HealthCheckRow(
                state: viewModel.healthKitEnabled ? .pass : .fail,
                title: "Apple Health enabled in N4x4",
                detail: viewModel.healthKitEnabled
                    ? "On"
                    : (viewModel.healthKitUserOptedOut
                       ? "Switched off on the previous screen"
                       : "Off — use Reconnect below")
            )
            HealthCheckRow(
                state: permissionCheckState,
                title: "Permission",
                detail: "Workout access \(viewModel.healthKitPermissionState.diagnosticLabel)"
            )
            HealthCheckRow(
                state: points.isEmpty ? .fail : .pass,
                title: "VO₂ max readings found",
                detail: readingsDetail
            )
            HealthCheckRow(
                state: points.count >= 2 ? .pass : .warn,
                title: "Enough for a trend line",
                detail: points.count >= 2
                    ? "Yes — the chart should appear on the home screen"
                    : "Needs at least 2 readings"
            )
        }
    }

    private var permissionCheckState: HealthCheckRow.State {
        switch viewModel.healthKitPermissionState {
        case .granted:       return .pass
        case .denied, .unavailable: return .fail
        case .notDetermined, .unknown: return .warn
        }
    }

    private var readingsDetail: String {
        guard let latest = points.last else { return "None in Apple Health" }
        return "\(points.count) · latest \(String(format: "%.1f", latest.value)) mL/kg·min on \(Self.day.string(from: latest.date))"
    }

    /// The single sentence the user came here for.
    private var verdict: String {
        if !healthDataAvailable {
            return "This device can't store Health data, so the VO₂ max chart is unavailable."
        }
        if !viewModel.healthKitEnabled || viewModel.healthKitPermissionState == .denied {
            return "N4x4 can't read Apple Health right now. Reconnect below, then check the permission in the Settings app."
        }
        if points.isEmpty {
            return "N4x4 can read Apple Health, but Apple Health holds no VO₂ max readings. That is what's missing — see below for where the number comes from."
        }
        if points.count < 2 {
            return "One reading so far. The chart needs two before it can draw a trend."
        }
        return "Everything checks out. The VO₂ max chart should be on the home screen."
    }

    // MARK: Actions

    private var actionsSection: some View {
        Section(header: Text("Try this")) {
            Button {
                viewModel.reconnectAppleHealth()
            } label: {
                Label("Reconnect Apple Health", systemImage: "arrow.triangle.2.circlepath")
            }

            Button {
                viewModel.fetchVO2MaxSamples()
            } label: {
                Label("Re-check for readings", systemImage: "arrow.clockwise")
            }
            .disabled(!viewModel.healthKitEnabled)

            if TimerViewModel.canOpenHealthApp {
                Button {
                    viewModel.openHealthApp()
                } label: {
                    Label("Open the Health app", systemImage: "heart.text.square")
                }
            }

            Button {
                viewModel.openAppSettings()
            } label: {
                Label("Open N4x4 in the Settings app", systemImage: "gear")
            }
        }
    }

    // MARK: Explanations

    private var whereItComesFromSection: some View {
        Section(header: Text("Where the number comes from")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("N4x4 reads your VO₂ max — it doesn't measure it.")
                    .font(.footnote.weight(.semibold))
                Text("Apple records VO₂ max as \"Cardio Fitness\", and only Apple Watch produces it, during outdoor walks, runs and hikes. A chest strap or other heart rate monitor gives N4x4 live heart rate during a session, but it can't generate a Cardio Fitness reading.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("If another app writes VO₂ max into Apple Health, N4x4 will read that too.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var manualStepsSection: some View {
        Section(header: Text("Check it yourself")) {
            TroubleshootStep(
                number: 1,
                text: "In the Health app, go to Browse → Heart → Cardio Fitness. If that is empty, there is no VO₂ max data for N4x4 to show."
            )
            TroubleshootStep(
                number: 2,
                text: "In the Settings app, go to Privacy & Security → Health → N4x4 and make sure Cardio Fitness is switched on under \"Allow N4x4 to read\"."
            )
            TroubleshootStep(
                number: 3,
                text: "If you changed anything there, come back and tap Reconnect Apple Health above."
            )
        }
    }

    // MARK: Diagnostics

    private var diagnosticsSection: some View {
        Section(
            header: Text("Diagnostics"),
            footer: Text("Still stuck? Copy this and include it when you send feedback.")
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.healthDiagnosticsSummary())
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let fetched = viewModel.lastVO2FetchDate {
                    Text("Checked \(Self.stamp.string(from: fetched))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 2)

            Button {
                UIPasteboard.general.string = viewModel.healthDiagnosticsSummary()
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy Diagnostics",
                      systemImage: copied ? "checkmark" : "doc.on.doc")
            }
        }
    }
}

/// Pass / warn / fail row used by the checklist above.
struct HealthCheckRow: View {
    enum State { case pass, warn, fail }

    let state: State
    let title: String
    let detail: String

    private var symbol: (String, Color) {
        switch state {
        case .pass: return ("checkmark.circle.fill", .green)
        case .warn: return ("exclamationmark.circle.fill", .orange)
        case .fail: return ("xmark.circle.fill", .red)
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol.0)
                .foregroundStyle(symbol.1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct TroubleshootStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - VO₂ Max Goal

struct VO2GoalSettingsView: View {
    @ObservedObject var viewModel: TimerViewModel

    var body: some View {
        Form {
            Section(
                footer: Text(footerText)
            ) {
                Picker("Biological Sex", selection: $viewModel.userBiologicalSexRaw) {
                    ForEach(BiologicalSex.allCases, id: \.rawValue) { sex in
                        Text(sex.rawValue).tag(sex.rawValue)
                    }
                }

                Picker("Goal", selection: $viewModel.vo2TargetTierRaw) {
                    Text("None").tag("")
                    ForEach(VO2TargetTier.allCases, id: \.rawValue) { tier in
                        let value = TimerViewModel.vo2TargetValue(
                            age: viewModel.userAge,
                            sex: viewModel.userBiologicalSex,
                            tier: tier
                        )
                        Text("\(tier.rawValue) — \(Int(value)) mL/kg/min").tag(tier.rawValue)
                    }
                }
            }
        }
        .navigationTitle("VO₂ Max Goal")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var footerText: String {
        if let target = viewModel.vo2MaxTarget, let tier = viewModel.vo2TargetTier {
            return "Target: \(Int(target)) mL/kg/min (\(tier.description)) — drawn as a line on your progress chart."
        }
        return "Sets a target line on your VO₂ max progress chart."
    }
}

// MARK: - Display

struct DisplaySettingsView: View {
    @ObservedObject var viewModel: TimerViewModel

    var body: some View {
        Form {
            Section(
                footer: Text("Live Activity shows the interval countdown on the Lock Screen and Dynamic Island during a workout.")
            ) {
                Toggle("Keep Screen Awake During Workouts", isOn: $viewModel.preventSleep)
                Toggle("Live Activity / Dynamic Island", isOn: $viewModel.liveActivitiesEnabled)
            }
        }
        .navigationTitle("Display")
        .navigationBarTitleDisplayMode(.inline)
    }
}
