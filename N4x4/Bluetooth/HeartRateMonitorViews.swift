// HeartRateMonitorViews.swift
// iOS UI for pairing and managing a Bluetooth heart rate monitor:
//   • HeartRateMonitorSheet — stock-styled sheet used from Settings and the
//     in-workout heart-rate troubleshooting flow.
//   • HeartRateMonitorSettingsRow — the live status row inside Settings.
//   • MonitorPairingCompact — dark-styled inline pairing block embedded in the
//     first-run onboarding card.
// All three render the same BluetoothHeartRateManager state machine; none of
// them owns any Bluetooth logic.

import SwiftUI

// MARK: - Shared presentation helpers

private extension BluetoothHeartRateManager.MonitorState {
    var statusIcon: String {
        switch self {
        case .idle:                 return "heart.slash"
        case .unavailable(.denied): return "exclamationmark.triangle.fill"
        case .unavailable:          return "antenna.radiowaves.left.and.right.slash"
        case .scanning:             return "antenna.radiowaves.left.and.right"
        case .connecting:           return "antenna.radiowaves.left.and.right"
        case .searching:            return "magnifyingglass"
        case .connected:            return "heart.fill"
        }
    }

    var statusTint: Color {
        switch self {
        case .idle:        return .secondary
        case .unavailable: return .orange
        case .scanning, .connecting, .searching: return .blue
        case .connected:   return .green
        }
    }

    var statusTitle: String {
        switch self {
        case .idle:                      return "No monitor connected"
        case .unavailable(.poweredOff):  return "Bluetooth is off"
        case .unavailable(.denied):      return "Bluetooth access needed"
        case .unavailable(.unsupported): return "Bluetooth unavailable"
        case .scanning:                  return "Looking for monitors…"
        case .connecting(let name):      return "Connecting to \(name)…"
        case .searching(let name):       return "Searching for \(name)…"
        case .connected(let name):       return name
        }
    }

    var statusDetail: String {
        switch self {
        case .idle:
            return "Connect a chest strap or armband to see live heart rate."
        case .unavailable(.poweredOff):
            return "Turn on Bluetooth in Control Center to connect your monitor."
        case .unavailable(.denied):
            return "Allow Bluetooth for N4x4 in Settings to connect your monitor."
        case .unavailable(.unsupported):
            return "This device doesn't support Bluetooth LE."
        case .scanning:
            return "Wear your monitor — most only wake up on skin contact."
        case .connecting:
            return "One moment…"
        case .searching:
            return "It will connect automatically the moment it's worn and in range."
        case .connected:
            return "Connected"
        }
    }
}

private func signalBars(rssi: Int) -> String {
    // 127 is CoreBluetooth's "RSSI unavailable" sentinel, not a great signal.
    switch rssi {
    case 127:      return "wifi.slash"
    case (-60)...: return "wifi"
    case (-75)...: return "wifi.exclamationmark"
    default:       return "wifi.slash"
    }
}

private func batteryIcon(percent: Int) -> String {
    switch percent {
    case 88...: return "battery.100"
    case 63...: return "battery.75"
    case 38...: return "battery.50"
    case 13...: return "battery.25"
    default:    return "battery.0"
    }
}

private func openSystemSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString),
          UIApplication.shared.canOpenURL(url) else { return }
    UIApplication.shared.open(url)
}

// MARK: - Settings row

/// The one-line status row shown in Settings. Observes the manager directly so
/// it stays live while the Settings screen is open.
struct HeartRateMonitorSettingsRow: View {
    @ObservedObject var manager: BluetoothHeartRateManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: manager.state.statusIcon)
                .foregroundColor(manager.state.statusTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(rowTitle)
                    .font(.body)
                    .foregroundColor(.primary)
                Text(rowSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if case .connected = manager.state, let battery = manager.batteryPercent {
                HStack(spacing: 3) {
                    Image(systemName: batteryIcon(percent: battery))
                    Text("\(battery)%")
                }
                .font(.caption)
                .foregroundColor(battery <= 15 ? .orange : .secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var rowTitle: String {
        if manager.hasRememberedMonitor || manager.state != .idle {
            return manager.state.statusTitle
        }
        return "Connect a monitor…"
    }

    private var rowSubtitle: String {
        if case .connected = manager.state,
           let bpm = manager.latestReading?.bpm, manager.latestReading?.isPlausible == true {
            return "\(bpm) BPM streaming"
        }
        return "Tap to set up & manage"
    }
}

// MARK: - Management / pairing sheet

/// Full pairing and management UI, presented as a sheet from Settings and from
/// the in-workout troubleshooting flow. Scans automatically when nothing is
/// remembered (the user's tap to open this sheet is the explicit opt-in that
/// justifies the permission prompt).
struct HeartRateMonitorSheet: View {
    @ObservedObject var manager: BluetoothHeartRateManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                statusSection
                contentSections
                helpSection
            }
            .navigationTitle("Heart Rate Monitor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            if manager.hasRememberedMonitor {
                manager.reconnectIfNeeded()
            } else {
                manager.beginPairing()
            }
        }
        .onDisappear {
            manager.endPairing()
        }
    }

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: manager.state.statusIcon)
                    .font(.system(size: 28))
                    .foregroundStyle(manager.state.statusTint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.state.statusTitle).font(.headline)
                    Text(manager.state.statusDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            if case .connected = manager.state {
                liveReadingRow
            }
        }
    }

    @ViewBuilder
    private var liveReadingRow: some View {
        HStack(spacing: 10) {
            if let reading = manager.latestReading, reading.isPlausible {
                PulsingHeart(bpm: Double(reading.bpm), size: 18)
                    .id(reading.bpm / 4)
                Text("\(reading.bpm)")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("BPM")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            } else if manager.latestReading?.sensorContact == .notDetected {
                Image(systemName: "hand.raised.slash")
                    .foregroundStyle(.orange)
                Text("No skin contact — adjust the strap until it reads.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                Text("Acquiring signal — this can take a few seconds.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let battery = manager.batteryPercent {
                HStack(spacing: 3) {
                    Image(systemName: batteryIcon(percent: battery))
                    Text("\(battery)%")
                }
                .font(.caption)
                .foregroundStyle(battery <= 15 ? .orange : .secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var contentSections: some View {
        switch manager.state {
        case .unavailable(.denied):
            Section {
                Button("Open Settings") { openSystemSettings() }
            }

        case .unavailable:
            EmptyView()

        case .scanning:
            discoveredSection
            companionHintSection

        case .connected, .searching, .connecting:
            Section {
                Button("Switch to a Different Monitor") {
                    manager.beginPairing()
                }
                Button("Forget This Monitor", role: .destructive) {
                    manager.forgetMonitor()
                }
            }

        case .idle:
            Section(
                footer: Text("Works with any Bluetooth heart rate monitor — chest straps like Polar, Garmin, and Wahoo, or armbands.")
            ) {
                Button("Scan for Monitors") {
                    manager.beginPairing()
                }
            }
        }
    }

    private var discoveredSection: some View {
        Section(
            header: HStack {
                Text("Available Monitors")
                Spacer()
                ProgressView()
            },
            footer: Text("Don't see yours? Most monitors only wake up and advertise while they're being worn.")
        ) {
            if manager.discovered.isEmpty {
                Text("Searching nearby…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(manager.discovered) { monitor in
                    Button {
                        manager.connect(to: monitor)
                    } label: {
                        HStack {
                            Text(monitor.name)
                                .foregroundColor(.primary)
                            Spacer()
                            if monitor.isSystemConnected {
                                Text("Paired to iPhone")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: signalBars(rssi: monitor.rssi))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Wearables paired to this phone via a companion app (Garmin Connect,
    /// WHOOP) that can never appear in the scan until their broadcast setting
    /// is on. Named hints beat an empty list that looks broken.
    @ViewBuilder
    private var companionHintSection: some View {
        if !manager.companionDevices.isEmpty {
            Section {
                ForEach(manager.companionDevices) { device in
                    NavigationLink {
                        HeartRateDeviceGuideView(manager: manager,
                                                 highlightBrand: device.brand.guideID)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.arrow.circlepath")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(device.brand.scanHint)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var helpSection: some View {
        Section {
            NavigationLink {
                HeartRateDeviceGuideView(manager: manager)
            } label: {
                Label("Don't see your device?", systemImage: "questionmark.circle")
            }
        }
    }
}

// MARK: - Onboarding embed

/// Inline pairing block for the first-run onboarding card. Dark-styled to sit
/// on the onboarding gradient. Scanning (and therefore the system Bluetooth
/// permission prompt) starts only on the explicit Connect tap.
struct MonitorPairingCompact: View {
    @ObservedObject var manager: BluetoothHeartRateManager

    var body: some View {
        VStack(spacing: 10) {
            switch manager.state {
            case .connected(let name):
                connectedRow(name: name)

            case .scanning:
                scanningBlock

            case .connecting(let name), .searching(let name):
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Connecting to \(name)…")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(rowBackground)

            case .unavailable(.denied):
                VStack(spacing: 8) {
                    Text("N4x4 needs Bluetooth access to connect your monitor.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                    Button("Open Settings") { openSystemSettings() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(rowBackground)

            case .unavailable(.poweredOff):
                Text("Bluetooth is off — turn it on in Control Center, then try again.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(rowBackground)

            case .unavailable(.unsupported):
                EmptyView()

            case .idle:
                Button {
                    manager.beginPairing()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "sensor.tag.radiowaves.forward")
                            .font(.title3)
                            .frame(width: 28)
                            .foregroundStyle(.white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bluetooth monitor")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("Chest strap or armband — connect it now.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        Spacer()
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.white)
                    }
                    .padding(14)
                    .background(rowBackground)
                }
            }
        }
        .onDisappear {
            manager.endPairing()
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.08))
    }

    private func connectedRow(name: String) -> some View {
        HStack(spacing: 14) {
            if let reading = manager.latestReading, reading.isPlausible {
                PulsingHeart(bpm: Double(reading.bpm), size: 20)
                    .id(reading.bpm / 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(reading.bpm) BPM")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
            } else {
                ProgressView().tint(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Connected — waiting for a reading…")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.22))
        )
    }

    private var scanningBlock: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("Looking for monitors — wear yours so it wakes up.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            // Capped so the onboarding card stays compact in a crowded gym;
            // strongest signal (usually the wearer's own strap) sorts first.
            ForEach(manager.discovered.prefix(4)) { monitor in
                Button {
                    manager.connect(to: monitor)
                } label: {
                    HStack {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                        Text(monitor.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: monitor.isSystemConnected
                              ? "checkmark.circle" : signalBars(rssi: monitor.rssi))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(12)
                    .background(rowBackground)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(rowBackground)
    }
}

// MARK: - Device guide

extension BluetoothHeartRateManager.CompanionDevice.Brand {
    /// Key into `DeviceGuide.all` for the matching how-to section.
    var guideID: String {
        switch self {
        case .garmin: return "garmin"
        case .whoop:  return "whoop"
        }
    }

    /// One-liner shown in the scan list when a paired-but-not-broadcasting
    /// wearable is detected.
    var scanHint: String {
        switch self {
        case .garmin:
            return "Paired to this iPhone, but Garmin watches only appear here while Broadcast Heart Rate is on. Tap for the steps."
        case .whoop:
            return "Paired to this iPhone, but WHOOP only appears here while HR Broadcast is on in the WHOOP app. Tap for the steps."
        }
    }
}

/// One brand's troubleshooting entry. All copy states only what's verified;
/// menu paths vary by model year, and the copy says so where it matters.
private struct DeviceGuide: Identifiable {
    let id: String
    let title: String
    let icon: String
    let summary: String
    let steps: [String]
    let caveat: String?

    static let all: [DeviceGuide] = [
        DeviceGuide(
            id: "garmin",
            title: "Garmin watches",
            icon: "applewatch",
            summary: "Pairing with Garmin Connect is not enough — a Garmin only appears here while its Broadcast Heart Rate mode is on.",
            steps: [
                "On the watch, open Settings → Sensors & Accessories → Wrist Heart Rate → Broadcast Heart Rate. (Menu names vary slightly by model.)",
                "Confirm to start broadcasting. Many models can also broadcast from the controls menu or during an activity.",
                "Come back here and scan — the watch is visible only while it's broadcasting.",
            ],
            caveat: "Older Garmins (vívosmart 4, vívoactive 3/4, the first Venu, and earlier) broadcast over ANT+ only, which iPhones can't receive. Roughly Forerunner 245 / fēnix 6 and newer also broadcast over Bluetooth."
        ),
        DeviceGuide(
            id: "whoop",
            title: "WHOOP",
            icon: "waveform.path.ecg",
            summary: "WHOOP 4.0 streams live heart rate once HR Broadcast is on in its app.",
            steps: [
                "In the WHOOP app, open the menu and go to Device Settings.",
                "Turn on HR Broadcast.",
                "Scan here again — the band appears within a few seconds.",
            ],
            caveat: "App and firmware updates can quietly switch HR Broadcast back off — recheck it after updating. WHOOP streams to one receiver at a time, so disconnect it from Peloton, Zwift, etc. first."
        ),
        DeviceGuide(
            id: "polar",
            title: "Polar watches & straps",
            icon: "heart.circle",
            summary: "Polar chest straps (H9/H10) work out of the box. Polar watches need heart-rate sharing turned on.",
            steps: [
                "On the watch, open Settings → General settings and turn on 'Heart rate visible to other devices' (called HR sensor mode on some models).",
                "Start a training session on the watch — most Polar watches only share heart rate while recording.",
                "Scan here again.",
            ],
            caveat: "A Polar H10 can hold two Bluetooth connections at once; most other straps hold only one, so close any other app using it."
        ),
        DeviceGuide(
            id: "fitbit",
            title: "Fitbit",
            icon: "heart.text.square",
            summary: "Only recent Fitbits can broadcast heart rate.",
            steps: [
                "On a Charge 6 or newer: swipe down and choose 'HR on Equipment'.",
                "Scan here while that screen is active.",
            ],
            caveat: "Fitbit's broadcast asks the receiver to pair first, which many apps and devices don't support — if it never appears, that's why. Older Fitbits can't broadcast heart rate at all."
        ),
        DeviceGuide(
            id: "applewatch",
            title: "Apple Watch",
            icon: "applewatch.radiowaves.left.and.right",
            summary: "Don't connect it here — an Apple Watch can't act as a Bluetooth heart rate strap for iPhone apps.",
            steps: [
                "Use the built-in integration instead: install N4x4 on the watch via the Watch app on this iPhone.",
                "Open N4x4 on your wrist and allow Health access.",
                "Heart rate then streams automatically during workouts.",
            ],
            caveat: nil
        ),
        DeviceGuide(
            id: "straps",
            title: "Chest straps & armbands",
            icon: "sensor.tag.radiowaves.forward",
            summary: "Polar, Garmin HRM, Wahoo TICKR, COROS, Scosche and similar all use the standard heart-rate service and just work — when they're awake.",
            steps: [
                "Wear it: straps only wake up on skin contact. Moisten the electrodes for a reliable signal.",
                "Close other apps or devices that may already be using it — most straps accept only one connection at a time.",
                "Still nothing? Replace the battery; a dying coin cell fails silently.",
            ],
            caveat: nil
        ),
    ]
}

/// Comprehensive per-brand troubleshooting, pushed from the pairing sheet.
/// Named companion devices (a paired Garmin / WHOOP that isn't broadcasting)
/// surface at the top with their brand's section pre-expanded.
struct HeartRateDeviceGuideView: View {
    @ObservedObject var manager: BluetoothHeartRateManager
    var highlightBrand: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: Set<String> = []

    var body: some View {
        List {
            if !manager.companionDevices.isEmpty {
                companionSection
            }
            generalSection
            brandSection
            Section {
                Button {
                    manager.beginPairing()
                    dismiss()
                } label: {
                    Label("Scan Again", systemImage: "arrow.clockwise")
                }
            }
        }
        .navigationTitle("Device Guide")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            var open = Set(manager.companionDevices.map(\.brand.guideID))
            if let highlightBrand { open.insert(highlightBrand) }
            expanded = open
        }
    }

    private var companionSection: some View {
        Section(
            header: Text("Paired to this iPhone"),
            footer: Text("These are paired through their own app, which doesn't share heart rate. Their broadcast setting fixes that — steps below.")
        ) {
            ForEach(manager.companionDevices) { device in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.arrow.circlepath")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .font(.subheadline.weight(.semibold))
                        Text("Not broadcasting heart rate yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var generalSection: some View {
        Section(header: Text("First, the basics")) {
            checkRow("Bluetooth is on, and N4x4 is allowed to use it (iPhone Settings → N4x4).")
            checkRow("The device is awake and worn — most only announce themselves on skin contact.")
            checkRow("Nothing else is holding its connection. Fully close Zwift, Peloton and similar apps; most monitors stream to one receiver at a time.")
            checkRow("Ready-to-use devices already paired to this iPhone appear in the scan list automatically, marked 'Paired to iPhone'.")
        }
    }

    private func checkRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private var brandSection: some View {
        Section(header: Text("By device")) {
            ForEach(DeviceGuide.all) { guide in
                DisclosureGroup(isExpanded: expansionBinding(for: guide.id)) {
                    Text(guide.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                    ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.accentColor, in: Circle())
                            Text(step)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                    }
                    if let caveat = guide.caveat {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Text(caveat)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                    }
                } label: {
                    Label(guide.title, systemImage: guide.icon)
                }
            }
        }
    }

    private func expansionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isOpen in
                if isOpen { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }
}
