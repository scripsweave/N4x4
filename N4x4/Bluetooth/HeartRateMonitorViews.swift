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
        if case .connected = manager.state {
            if let bpm = manager.latestReading?.bpm, manager.latestReading?.isPlausible == true {
                return "\(bpm) BPM streaming"
            }
            return "No heart rate arriving — tap for help"
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
    /// Set once a connected device has produced nothing for the grace period.
    @State private var acquireTimedOut = false

    /// "Connected" is a lie the user cares about: a Garmin with Broadcast
    /// Heart Rate off happily accepts the GATT connection and then sends
    /// nothing, forever. Once the grace period passes (or the device refuses
    /// the notify subscribe outright), reframe as available-but-not-connected
    /// and lead with help.
    private var connectedButSilent: Bool {
        guard case .connected = manager.state, manager.latestReading == nil else { return false }
        return manager.notifySubscribeFailed || acquireTimedOut
    }

    private var connectedName: String? {
        if case .connected(let name) = manager.state { return name }
        return nil
    }

    /// Restarts whenever the connection or the reading-presence changes.
    private var acquireKey: String {
        "\(connectedName ?? "-")|\(manager.latestReading == nil)"
    }

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
            .task(id: acquireKey) {
                acquireTimedOut = false
                guard connectedName != nil, manager.latestReading == nil else { return }
                // Grace period: straps legitimately take a few seconds after
                // skin contact. Only after this do we call the state what it is.
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                if !Task.isCancelled, connectedName != nil, manager.latestReading == nil {
                    acquireTimedOut = true
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
                Image(systemName: connectedButSilent ? "heart.slash" : manager.state.statusIcon)
                    .font(.system(size: 28))
                    .foregroundStyle(connectedButSilent ? .orange : manager.state.statusTint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(connectedButSilent ? "Available, not connected" : manager.state.statusTitle)
                        .font(.headline)
                    Text(connectedButSilent
                         ? "\(connectedName ?? "The device") accepted the Bluetooth connection but isn't sending heart rate — usually its broadcast setting is off."
                         : manager.state.statusDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            if connectedButSilent {
                helpMeConnectButton
            } else if case .connected = manager.state {
                liveReadingRow
            }
        }
    }

    private var helpMeConnectButton: some View {
        NavigationLink {
            HeartRateDeviceGuideView(
                manager: manager,
                highlightBrand: connectedName.flatMap(DeviceGuide.brandID(forDeviceNamed:))
            )
        } label: {
            HStack {
                Spacer()
                Image(systemName: "questionmark.circle.fill")
                Text("Help Me Connect")
                    .font(.headline)
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.vertical, 6)
        }
        .listRowBackground(Color.accentColor)
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

/// One brand's troubleshooting entry. All copy states only what's verified
/// (menu paths sourced from official owner's manuals — see the research notes
/// in the git history); where paths vary by model year the copy says so.
private struct DeviceGuide: Identifiable {
    let id: String
    let title: String
    let icon: String
    let summary: String
    var steps: [String] = []
    var caveat: String? = nil
    /// Model-family subsections (e.g. Garmin's button vs touchscreen lines).
    var subGuides: [DeviceGuide] = []

    /// Best-effort brand (or Garmin model-family) match from a peripheral's
    /// advertised name, so the "Help Me Connect" flow can open the right
    /// section directly. Family IDs use "brand.family" form; the guide view
    /// expands both the family and its parent brand.
    static func brandID(forDeviceNamed name: String) -> String? {
        let n = name.lowercased()
        let garmin = ["garmin", "forerunner", "fenix", "fēnix", "epix", "venu",
                      "instinct", "vivoactive", "vívoactive", "enduro", "marq",
                      "tactix", "descent"]
        if garmin.contains(where: n.contains) {
            if n.contains("245") || n.contains("945")
                || n.contains("fenix 6") || n.contains("fēnix 6") { return "garmin.fenix6" }
            if n.contains("forerunner") { return "garmin.forerunner" }
            if ["fenix", "fēnix", "epix", "enduro", "marq", "tactix", "instinct", "descent"]
                .contains(where: n.contains) { return "garmin.fenix" }
            if n.contains("venu") || n.contains("vivoactive") || n.contains("vívoactive") {
                return "garmin.venu"
            }
            return "garmin"
        }
        if n.contains("whoop") { return "whoop" }
        if n.contains("polar") || n.contains("h10") || n.contains("h9") { return "polar" }
        if n.contains("fitbit") || n.contains("charge") { return "fitbit" }
        if n.contains("wahoo") || n.contains("tickr") || n.contains("hrm") { return "straps" }
        return nil
    }

    static let all: [DeviceGuide] = [
        DeviceGuide(
            id: "garmin",
            title: "Garmin watches",
            icon: "applewatch",
            summary: "Pairing with Garmin Connect is not enough — the watch only appears here while Broadcast Heart Rate is on. Pick your model family for the exact steps (from Garmin's own manuals).",
            caveat: "Battery drains faster while broadcasting, and during an activity there's usually no on-screen broadcast indicator — trust the scan here instead.",
            subGuides: [
                DeviceGuide(
                    id: "garmin.forerunner",
                    title: "Forerunner 165 / 255 / 265 / 955 / 965",
                    icon: "",
                    summary: "",
                    steps: [
                        "From the watch face, hold UP (MENU on 955/965).",
                        "Select Health & Wellness → Wrist Heart Rate → Broadcast Heart Rate. On some software versions the menu is just Wrist Heart Rate.",
                        "Press START. The watch broadcasts until you press STOP.",
                        "Shortcut: hold LIGHT and pick the broadcast icon from the controls menu.",
                    ],
                    caveat: "To broadcast automatically in workouts: press START → pick the activity → hold UP → the activity's settings → Broadcast Heart Rate."
                ),
                DeviceGuide(
                    id: "garmin.fenix",
                    title: "fēnix 7/8 · epix · Enduro · MARQ · Instinct 2/3",
                    icon: "",
                    summary: "",
                    steps: [
                        "Hold MENU.",
                        "Select Sensors & Accessories → Wrist Heart Rate → Broadcast Heart Rate.",
                        "Press START. STOP ends it. Shortcut: hold LIGHT → broadcast icon.",
                    ],
                    caveat: "fēnix 8 and Enduro 3 moved it: hold LIGHT → Watch Settings → Health & Wellness → Wrist Heart Rate → Broadcast Heart Rate."
                ),
                DeviceGuide(
                    id: "garmin.venu",
                    title: "Venu · vívoactive (touchscreen)",
                    icon: "",
                    summary: "",
                    steps: [
                        "Venu 2 / Venu Sq 2: hold the button → Settings → Wrist Heart Rate → Broadcast (start now) or Broadcast In Activity (auto in workouts).",
                        "Venu 3 / vívoactive 5: press the lower button → Settings → Watch Sensors → Wrist Heart Rate → Broadcast Heart Rate → press the top button.",
                        "vívoactive 6: Settings → Health & Wellness → Wrist Heart Rate → Broadcast Heart Rate, or hold the top button for the controls menu.",
                    ],
                    caveat: "First-generation Venu and vívoactive 3/4 broadcast ANT+ only — no iPhone app can see them."
                ),
                DeviceGuide(
                    id: "garmin.fenix6",
                    title: "fēnix 6 · Forerunner 245 / 945",
                    icon: "",
                    summary: "",
                    steps: [
                        "fēnix 6: from the heart rate widget, hold MENU → Heart Rate Options → Broadcast Heart Rate → press START. Bluetooth broadcast needs its mid-2020-or-later firmware.",
                        "Forerunner 245 / 945: the Broadcast Heart Rate menu is ANT+ only, which iPhones can't receive. Instead start a Virtual Run activity — that one broadcasts over Bluetooth.",
                    ]
                ),
                DeviceGuide(
                    id: "garmin.older",
                    title: "Older models — can't reach iPhone apps",
                    icon: "",
                    summary: "Forerunner 55/235/230/735XT, fēnix 3/5/5 Plus, Instinct 1, first-generation Venu, vívoactive 3/4 and vívosmart broadcast over ANT+ only — iPhones have no ANT+ radio, so no app can ever see them. Lily can't broadcast at all. The practical fix is a Bluetooth strap (Polar H9/H10, Garmin HRM-Dual, Wahoo TICKR)."
                ),
            ]
        ),
        DeviceGuide(
            id: "whoop",
            title: "WHOOP",
            icon: "waveform.path.ecg",
            summary: "Every WHOOP since 3.0 streams live heart rate over Bluetooth once broadcast is on in its app.",
            steps: [
                "In the WHOOP app, open the Menu tab (☰, bottom right) and go to Device Settings. On older app versions: More → Device Settings.",
                "Turn on Broadcast Heart Rate (also called HR Broadcast). On WHOOP 5.0 / MG it can sit under the Advanced tab.",
                "Scan here again — the band appears within a few seconds.",
            ],
            caveat: "The toggle can switch itself off after app or firmware updates — recheck it before every session. WHOOP streams to one receiver at a time, so disconnect it from Peloton, Zwift, etc. first. If the toggle won't respond (a known app bug can cover it with a coach button), force-quit the WHOOP app and reopen it."
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
            if let highlightBrand {
                open.insert(highlightBrand)
                // A family ID ("garmin.forerunner") needs its parent brand
                // group open too, or the family stays hidden inside it.
                if let dot = highlightBrand.firstIndex(of: ".") {
                    open.insert(String(highlightBrand[..<dot]))
                }
            }
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
                    if !guide.summary.isEmpty {
                        Text(guide.summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 2)
                    }
                    if guide.subGuides.isEmpty {
                        stepAndCaveatRows(for: guide)
                    } else {
                        // Model families (e.g. Garmin button vs touchscreen
                        // lines) nest one level deeper.
                        ForEach(guide.subGuides) { family in
                            DisclosureGroup(isExpanded: expansionBinding(for: family.id)) {
                                if !family.summary.isEmpty {
                                    Text(family.summary)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 2)
                                }
                                stepAndCaveatRows(for: family)
                            } label: {
                                Text(family.title)
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        // The brand-wide caveat reads after the families.
                        stepAndCaveatRows(for: DeviceGuide(
                            id: guide.id + ".caveat", title: "", icon: "",
                            summary: "", caveat: guide.caveat))
                    }
                } label: {
                    Label(guide.title, systemImage: guide.icon)
                }
            }
        }
    }

    @ViewBuilder
    private func stepAndCaveatRows(for guide: DeviceGuide) -> some View {
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

// MARK: - Post-update announcement

/// One-time sheet for upgraders: live heart rate now works with Apple Watch,
/// Garmin, and WHOOP. "Show me how" opens the device guide (which covers all
/// three); "Dismiss" just closes. The caller burns the seen-flag on dismiss.
struct HeartRateSourcesAnnouncementView: View {
    @ObservedObject var viewModel: TimerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showGuide = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "heart.circle.fill")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(.red)

            VStack(spacing: 10) {
                Text("Real-time heart rate coaching")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("N4x4 now supports Apple Watch, Garmin watches, and WHOOP for live heart rate tracking and in-workout coaching — spoken cues, zone colours, and a nudge whenever you drift out of your target zone.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 14) {
                sourceRow(icon: "applewatch",
                          text: "Apple Watch — install N4x4 on your wrist and go.")
                sourceRow(icon: "antenna.radiowaves.left.and.right",
                          text: "Garmin — turn on Broadcast Heart Rate.")
                sourceRow(icon: "waveform.path.ecg",
                          text: "WHOOP — switch on HR Broadcast in its app.")
            }
            .padding(.horizontal, 4)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    showGuide = true
                } label: {
                    Text("Show me how")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                Button("Dismiss") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .sheet(isPresented: $showGuide, onDismiss: { dismiss() }) {
            NavigationView {
                HeartRateDeviceGuideView(manager: viewModel.bleHeartRateManager)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showGuide = false }
                        }
                    }
            }
        }
    }

    private func sourceRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: 26)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
