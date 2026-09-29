import SwiftUI

struct HealthDevicesView: View {
    enum SectionID: String { case health, devices, sources, readings, help }
    @ObservedObject var viewModel: TimerViewModel
    var initialSection: SectionID = .health
    @Environment(\.scenePhase) private var scenePhase
    @State private var watchHelp = false
    @State private var copied = false
    @AppStorage("hrSourcePriorityRaw") private var priorityMirror = ""
    @AppStorage("appleSensorHREnabled") private var sensorMirror = false

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                healthSection.id(SectionID.health)
                devicesSection.id(SectionID.devices)
                sourcesSection.id(SectionID.sources)
                readingsSection.id(SectionID.readings)
                helpSection.id(SectionID.help)
            }
            .environment(\.editMode, .constant(.active))
            .onAppear {
                refresh()
                if initialSection != .health {
                    DispatchQueue.main.async { proxy.scrollTo(initialSection, anchor: .top) }
                }
            }
        }
        .navigationTitle("Health & Devices")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
        .sheet(isPresented: $watchHelp) { WatchTroubleshootingView(viewModel: viewModel) }
    }

    private func refresh() {
        viewModel.refreshHealthKitAuthorizationState()
        if viewModel.healthKitEnabled {
            viewModel.fetchVO2MaxSamples()
            viewModel.refreshCachedUserBirthday()
        }
    }

    private var healthSection: some View {
        Section {
            Toggle("Enable Apple Health", isOn: Binding(
                get: { viewModel.healthKitEnabled }, set: viewModel.setHealthIntegrationEnabled))
                .accessibilityIdentifier("healthEnabled")
            Toggle("Save Workouts to Apple Health", isOn: Binding(
                get: { viewModel.logWorkoutsToHealthKit }, set: viewModel.setHealthWorkoutLogging))
                .disabled(!viewModel.healthKitEnabled)
                .accessibilityIdentifier("healthWorkoutLogging")
            if !viewModel.healthKitEnabled {
                Text("Enable Apple Health above to save workouts. Your workout-saving preference is kept.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            statusRow("Workout write permission", value: permissionText)
            if let saved = viewModel.latestHealthSave {
                statusRow("Last confirmed save", value: saved.formatted(date: .abbreviated, time: .shortened))
            } else {
                statusRow("Last confirmed save", value: "None recorded yet")
            }
            if viewModel.pendingHealthExports > 0 {
                statusRow("Pending workouts", value: "\(viewModel.pendingHealthExports)")
                if !viewModel.healthSavingEnabled {
                    Text("Pending saves will resume when both switches are on.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error = viewModel.latestHealthExportError {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
                Button("Retry Pending Saves") { viewModel.retryHealthExports() }
                    .disabled(!viewModel.healthSavingEnabled || !viewModel.healthAuthorizationGranted)
            }
            Button("Review Health Access") { viewModel.requestHealthKitAuthorizationIfNeeded() }
            Text("To change an existing permission, open Settings → Privacy & Security → Health → N4x4. Allow Workouts under write access. Read permissions are separate.")
                .font(.footnote).foregroundStyle(.secondary)
        } header: {
            Label("Apple Health", systemImage: "heart.text.square")
        } footer: {
            Text("Workouts save on your iPhone without internet access. Older sessions may have an unknown save status; open a session in History to check or recover it.")
        }
    }

    private var devicesSection: some View {
        Section {
            statusRow("Current heart-rate source", value: viewModel.currentHeartRate == nil ? "No live reading" : (viewModel.heartRateSourceLabel ?? "No live reading"))
            Button { watchHelp = true } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Apple Watch", systemImage: "applewatch").foregroundStyle(.primary)
                    Text(watchStatus).font(.subheadline).foregroundStyle(.secondary)
                    Text("Setup & troubleshooting").font(.footnote).foregroundStyle(.tint)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            HealthMonitorConnectionRow(manager: viewModel.bleHeartRateManager)
            if #available(iOS 26.0, *) {
                Toggle("AirPods Heart Rate", isOn: $viewModel.appleSensorHREnabled)
            } else {
                statusRow("AirPods Heart Rate", value: "Requires iOS 26")
            }
            Text("AirPods Pro 3 heart rate uses Apple Health during workouts. Powerbeats Pro 2 use the Bluetooth monitor connection.")
                .font(.footnote).foregroundStyle(.secondary)
        } header: {
            Label("Heart Rate & Devices", systemImage: "waveform.path.ecg")
        } footer: {
            Text("Health read access cannot be confirmed by the app. No live reading can also mean the device is idle. Check Watch Health permissions on your Watch if readings are missing.")
        }
    }

    private var sourcesSection: some View {
        Section {
            ForEach(viewModel.heartRateSourcePriority, id: \.rawValue) { source in
                Text(source.displayName)
            }
            .onMove { from, to in
                var order = viewModel.heartRateSourcePriority
                order.move(fromOffsets: from, toOffset: to)
                viewModel.heartRateSourcePriority = order
            }
        } header: {
            Text("Source Priority")
        } footer: {
            Text("Drag to reorder. The first source with a fresh reading is used; other sources take over when it stops sending.")
        }
    }

    private var readingsSection: some View {
        Section {
            if !viewModel.healthKitEnabled {
                Text("Enable Apple Health to check readings.").foregroundStyle(.secondary)
            } else {
                if let point = viewModel.vo2DataPoints.max(by: { $0.date < $1.date }) {
                    statusRow("Cardio Fitness", value: String(format: "%.1f mL/kg/min", point.value))
                    statusRow("Latest reading", value: point.date.formatted(date: .abbreviated, time: .omitted))
                } else {
                    statusRow("Cardio Fitness", value: "No readings available")
                }
                if let error = viewModel.lastVO2FetchError {
                    Text("Couldn’t check Cardio Fitness: \(error)").font(.footnote).foregroundStyle(.secondary)
                }
                statusRow("Birthday data", value: viewModel.birthdayReadingAvailable ? "Available" : "Not available to N4x4")
                Button("Refresh Health Readings") { refresh() }
            }
        } header: {
            Label("Health Readings", systemImage: "chart.line.uptrend.xyaxis")
        } footer: {
            Text("No readings may mean no data is recorded or read access is off. Check Cardio Fitness in Health, then N4x4’s read permissions in Settings. Birthday data is optional.")
        }
    }

    private var helpSection: some View {
        Section {
            Text("A workout in N4x4 History and a workout in Apple Health are separate saves. Permission to write doesn’t confirm that a workout saved.")
            Text("Watch workouts completed away from your iPhone transfer when the devices reconnect. N4x4 on the iPhone then saves them to Health.")
            Button(copied ? "Diagnostics Copied" : "Copy Diagnostics", systemImage: copied ? "checkmark" : "doc.on.doc") {
                UIPasteboard.general.string = viewModel.healthDiagnosticsSummary()
                copied = true
            }
        } header: { Text("Help & Diagnostics") }
    }

    private var permissionText: String {
        switch viewModel.healthKitPermissionState {
        case .granted: return "Allowed"
        case .denied: return "Not allowed"
        case .notDetermined: return "Not requested"
        case .unavailable: return "Unavailable"
        case .unknown: return "Not checked"
        }
    }

    private var watchStatus: String {
        switch viewModel.watchConnectionStatus {
        case .noWatchPaired: return "No Watch paired"
        case .appNotInstalled: return "N4x4 is not installed on your Watch"
        case .notReachable: return "App installed · not currently reachable"
        case .connected: return viewModel.hasFreshWatchHeartRate ? "Connected · heart rate streaming" : "Connected · no live Watch reading"
        }
    }

    private func statusRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(value).font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HealthMonitorConnectionRow: View {
    @ObservedObject var manager: BluetoothHeartRateManager
    @State private var showPairing = false
    var body: some View {
        Button { showPairing = true } label: {
            VStack(alignment: .leading, spacing: 5) {
                HeartRateMonitorSettingsRow(manager: manager)
                Text(manager.diagnosticStatus).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPairing) { HeartRateMonitorSheet(manager: manager) }
    }
}

/// Used in History and completion review; always reads the current persisted row.
struct WorkoutHealthSaveView: View {
    @ObservedObject var viewModel: TimerViewModel
    let id: UUID
    @State private var checking = false
    @State private var review: HealthRecoveryReview?

    private var state: HealthWorkoutExport.State? {
        viewModel.workoutLogEntries.first { $0.id == id }?.healthExport?.state
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Apple Health", systemImage: "heart.text.square")
                .font(.headline)
            Text(viewModel.healthExportStatus(for: id)).font(.subheadline)
            if let error = viewModel.workoutLogEntries.first(where: { $0.id == id })?.healthExport?.lastError {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
            if let error = viewModel.workoutSaveError {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
            if state != .saved {
                if !viewModel.healthSavingEnabled || !viewModel.healthAuthorizationGranted {
                    NavigationLink("Review Health & Devices") { HealthDevicesView(viewModel: viewModel) }
                }
                if state == .pending {
                    Button("Retry Health Save") { viewModel.retryHealthExports() }
                        .disabled(!viewModel.healthSavingEnabled || !viewModel.healthAuthorizationGranted)
                } else {
                    Button(checking ? "Checking Apple Health…" : "Save to Apple Health") {
                        checking = true
                        Task { @MainActor in
                            review = await viewModel.reviewHealthRecovery(for: id)
                            checking = false
                        }
                    }
                    .disabled(checking || viewModel.recoveryExport(for: id) == nil)
                    if viewModel.recoveryExport(for: id) == nil {
                        Text("This older session has no usable timing to export.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
        .sheet(item: $review) { item in HealthRecoverySheet(viewModel: viewModel, review: item) }
    }
}

private struct HealthRecoverySheet: View {
    @ObservedObject var viewModel: TimerViewModel
    let review: HealthRecoveryReview
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Session to save") {
                    LabeledContent(review.approximate ? "Estimated start" : "Start", value: review.export.start.formatted())
                    LabeledContent("End", value: review.export.end.formatted())
                    if review.approximate {
                        Text("The original start time is unavailable. This estimate uses the recorded duration and may exclude pauses.")
                    }
                }
                if !review.matches.isEmpty {
                    Section("Possible existing workouts") {
                        ForEach(review.matches.sorted { $0.start < $1.start }) { match in
                            Button {
                                viewModel.confirmHealthRecovery(review, existing: match)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading) {
                                    Text("Use this existing workout")
                                    Text("\(match.start.formatted()) – \(match.end.formatted(date: .omitted, time: .shortened))")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section {
                    Text(review.queryFailed
                         ? "Apple Health couldn’t be checked. This session may already exist there. Saving a new copy could create a duplicate."
                         : "Only workouts visible to N4x4 can be checked. Before saving, confirm this session is missing in Apple Health; otherwise you may create a duplicate.")
                    if !viewModel.healthSavingEnabled || !viewModel.healthAuthorizationGranted {
                        NavigationLink("Enable Health saving and review access") { HealthDevicesView(viewModel: viewModel) }
                    }
                    Button("Confirm & Save New Workout") {
                        viewModel.confirmHealthRecovery(review)
                        dismiss()
                    }
                    .disabled(!viewModel.healthSavingEnabled || !viewModel.healthAuthorizationGranted)
                }
            }
            .navigationTitle("Save to Apple Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
