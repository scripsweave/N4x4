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
                        Image(systemName: signalBars(rssi: monitor.rssi))
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
