// BluetoothHeartRateManager.swift
// Connects to standard BLE heart rate monitors (chest straps, armbands) via
// Core Bluetooth and forwards readings into the app's heart-rate funnel.
// Owned by TimerViewModel, mirroring PhoneSessionManager.
//
// Design rules (see docs/Bluetooth HR Monitor Plan.md):
//   • The CBCentralManager is created lazily — instantiating it is what
//     triggers the system Bluetooth permission prompt, so it must never
//     happen at launch unless a monitor is already remembered (which implies
//     permission was granted before).
//   • The connection is independent of the workout lifecycle. A pending
//     connect has no timeout and negligible battery cost; the strap completes
//     it the moment it's worn.
//   • Scans are always filtered to the Heart Rate Service (0x180D), stop on
//     connect / UI dismissal, and time out after 30 s.

import CoreBluetooth
import Foundation

final class BluetoothHeartRateManager: NSObject, ObservableObject {

    // MARK: - Public state

    enum UnavailableReason: Equatable {
        case poweredOff     // Bluetooth switched off in Control Center / Settings
        case denied         // user declined the permission prompt
        case unsupported    // no BLE hardware (unlikely on any modern iPhone)
    }

    enum MonitorState: Equatable {
        case idle                       // nothing remembered, not scanning
        case unavailable(UnavailableReason)
        case scanning
        case connecting(name: String)
        case searching(name: String)    // remembered monitor, waiting for it to appear
        case connected(name: String)
    }

    struct DiscoveredMonitor: Identifiable, Equatable {
        let id: UUID
        let name: String
        let rssi: Int
        /// The system already holds a connection to this device (it was paired
        /// through another app). Shown as ready-to-use instead of a signal bar.
        var isSystemConnected: Bool = false
    }

    /// A wearable paired to this iPhone through its companion app (detected by
    /// its proprietary GATT service) that is NOT currently exposing the
    /// standard Heart Rate Service. These can never appear in a 0x180D scan
    /// until the user flips their broadcast setting — the troubleshooting UI
    /// uses this to say so by name instead of showing an empty list.
    struct CompanionDevice: Identifiable, Equatable {
        enum Brand { case garmin, whoop }
        let id: UUID
        let brand: Brand
        let name: String
    }

    @Published private(set) var state: MonitorState = .idle
    @Published private(set) var discovered: [DiscoveredMonitor] = []
    @Published private(set) var companionDevices: [CompanionDevice] = []
    @Published private(set) var batteryPercent: Int?
    /// Latest raw reading while connected (plausible or not) — drives the live
    /// preview in pairing/settings UI. Cleared on disconnect so the preview
    /// can never freeze on a stale number.
    @Published private(set) var latestReading: HeartRateReading?

    /// Called on the main queue for every usable reading (plausible bpm,
    /// sensor contact not lost). Wire to TimerViewModel.ingestHeartRate.
    var onReading: ((HeartRateReading) -> Void)?

    var hasRememberedMonitor: Bool { rememberedID != nil }
    var rememberedName: String? {
        UserDefaults.standard.string(forKey: Self.nameDefaultsKey)
    }

    // MARK: - Private state

    private static let idDefaultsKey = "bleMonitorPeripheralID"
    private static let nameDefaultsKey = "bleMonitorName"

    private static let heartRateService = CBUUID(string: "180D")
    private static let heartRateMeasurement = CBUUID(string: "2A37")
    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")

    /// Proprietary companion-app services, used ONLY to detect that a wearable
    /// is paired to this phone (never to talk to it). Best-effort: a miss just
    /// means no named hint in the troubleshooting UI.
    /// Garmin Multi-Link + legacy GFDI, per Gadgetbridge's protocol docs.
    private static let garminProprietaryServices = [
        CBUUID(string: "6A4E2800-667B-11E3-949A-0800200C9A66"),
        CBUUID(string: "6A4E2401-667B-11E3-949A-0800200C9A66"),
    ]
    /// WHOOP 4.0 custom service, per the open-source whoomp/whoop-reader work.
    private static let whoopProprietaryService = CBUUID(string: "61080000-8D6D-82B8-614A-1C8CB0F8DCC6")

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    /// What to do once the central reaches .poweredOn (its state callback is
    /// asynchronous, so intent set before then is parked here).
    private enum PendingIntent { case none, scan, reconnect }
    private var pendingIntent: PendingIntent = .none

    /// Peripherals whose next disconnect callback is user-initiated (forget /
    /// switch) and must not trigger auto-reconnect. Keyed by identifier
    /// because the callback for an old peripheral can arrive after
    /// `self.peripheral` already points at its replacement.
    private var userInitiatedDisconnects: Set<UUID> = []
    private var consecutiveConnectFailures = 0
    /// One retry when a strap rejects the heart-rate notify subscribe.
    private var didRetryNotifySubscribe = false
    /// A 30 s backoff retry is already queued after the fast-retry cap.
    private var slowRetryScheduled = false

    /// After the fast-retry cap, keep trying on a slow cycle so "Searching…"
    /// stays true. 30 s spacing makes even a permanent failure storm cost
    /// nothing meaningful in battery.
    private func scheduleSlowRetry() {
        guard !slowRetryScheduled else { return }
        slowRetryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self else { return }
            self.slowRetryScheduled = false
            guard self.hasRememberedMonitor,
                  self.central?.state == .poweredOn,
                  self.peripheral?.state != .connected,
                  self.peripheral?.state != .connecting else { return }
            self.consecutiveConnectFailures = 0
            self.reconnectToRemembered()
        }
    }
    private static let maxConnectRetries = 5
    private var scanTimeoutWork: DispatchWorkItem?
    private static let scanTimeout: TimeInterval = 30

    private var rememberedID: UUID? {
        UserDefaults.standard.string(forKey: Self.idDefaultsKey).flatMap(UUID.init)
    }

    // MARK: - Public API

    /// Call once at launch. Only acts when a monitor was previously paired —
    /// never triggers a permission prompt for users who haven't opted in.
    func startIfRemembered() {
        guard rememberedID != nil else { return }
        switch CBManager.authorization {
        case .allowedAlways:
            if central?.state == .poweredOn {
                pendingIntent = .none
                reconnectToRemembered()
            } else {
                pendingIntent = .reconnect
                ensureCentral()
            }
        case .denied, .restricted:
            // Permission was revoked since pairing (or the app moved to a new
            // phone via backup, which copies defaults but not permissions and
            // reports .notDetermined — handled below by doing nothing).
            state = .unavailable(.denied)
        case .notDetermined:
            break // wait for an explicit user tap so the prompt has context
        @unknown default:
            break
        }
    }

    /// User tapped "Connect a monitor". Creates the central (permission prompt
    /// on first use) and scans.
    func beginPairing() {
        discovered = []
        ensureCentral()
        if central?.state == .poweredOn {
            // Act now and leave no pending intent behind — a stale intent
            // would replay this scan on the next Bluetooth power cycle.
            pendingIntent = .none
            startScan()
        } else {
            pendingIntent = .scan
        }
    }

    /// Pairing UI dismissed — stop scanning (never disconnects).
    func endPairing() {
        stopScan()
        if case .scanning = state {
            state = fallbackStateForNoScan()
        }
    }

    func connect(to monitor: DiscoveredMonitor) {
        guard let central, central.state == .poweredOn else { return }
        stopScan()
        // Retrieve a fresh CBPeripheral for the identifier; the discovery
        // callback's instance is already retained in discoveredPeripherals.
        guard let target = discoveredPeripherals[monitor.id]
            ?? central.retrievePeripherals(withIdentifiers: [monitor.id]).first else {
            // The tapped device vanished from the system cache between
            // discovery and tap (rare). Settle on the truthful state — .idle
            // here would contradict a still-remembered previous monitor.
            state = fallbackStateForNoScan()
            return
        }
        // Switching monitors implicitly forgets the old one.
        if let old = peripheral, old.identifier != target.identifier {
            userInitiatedDisconnects.insert(old.identifier)
            central.cancelPeripheralConnection(old)
        }
        remember(id: target.identifier, name: monitor.name)
        consecutiveConnectFailures = 0
        connectPeripheral(target, name: monitor.name)
    }

    func forgetMonitor() {
        UserDefaults.standard.removeObject(forKey: Self.idDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.nameDefaultsKey)
        if let peripheral, let central {
            userInitiatedDisconnects.insert(peripheral.identifier)
            central.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        latestReading = nil
        batteryPercent = nil
        stopScan()
        state = .idle
    }

    /// Safe to call on foreground/appear: re-issues the pending connect if the
    /// remembered monitor isn't connected (e.g. after a failure cap was hit).
    func reconnectIfNeeded() {
        guard hasRememberedMonitor else { return }
        guard let central else {
            startIfRemembered()
            return
        }
        if central.state == .poweredOn, peripheral?.state != .connected,
           peripheral?.state != .connecting {
            consecutiveConnectFailures = 0
            reconnectToRemembered()
        }
    }

    // MARK: - Central lifecycle

    private func ensureCentral() {
        guard central == nil else { return }
        // Main queue so every delegate callback can touch @Published directly.
        central = CBCentralManager(delegate: self, queue: .main)
    }

    private func startScan() {
        guard let central, central.state == .poweredOn else { return }
        state = .scanning
        // A peripheral the system already holds a connection to (paired in
        // another app, e.g. a Garmin watch with a companion app) does NOT
        // advertise, so the scan below can never discover it. Surface those
        // explicitly or they're invisible in the pairing list.
        for connected in central.retrieveConnectedPeripherals(withServices: [Self.heartRateService])
        where connected.identifier != peripheral?.identifier {
            discoveredPeripherals[connected.identifier] = connected
            let monitor = DiscoveredMonitor(id: connected.identifier,
                                            name: connected.name ?? "Heart Rate Monitor",
                                            rssi: 0, // connected ⇒ in range; no RSSI without a live read
                                            isSystemConnected: true)
            if !discovered.contains(where: { $0.id == monitor.id }) {
                discovered.append(monitor)
            }
        }
        refreshCompanionDevices()
        // Filtering on 0x180D is not just hygiene: it's what makes every
        // discovery a heart rate monitor, so the UI needs no further filtering.
        central.scanForPeripherals(withServices: [Self.heartRateService], options: nil)

        scanTimeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, case .scanning = self.state else { return }
            self.stopScan()
            self.state = self.fallbackStateForNoScan()
        }
        scanTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scanTimeout, execute: work)
    }

    private func stopScan() {
        scanTimeoutWork?.cancel()
        scanTimeoutWork = nil
        if central?.state == .poweredOn {
            central?.stopScan()
        }
    }

    /// Repopulates `companionDevices`: wearables paired to this phone via
    /// their companion app but not exposing the Heart Rate Service, i.e.
    /// devices the scan can never find until their broadcast setting is on.
    private func refreshCompanionDevices() {
        guard let central, central.state == .poweredOn else { return }
        // Anything already exposing 0x180D needs no hint — it's usable as-is.
        let usable = Set(central.retrieveConnectedPeripherals(withServices: [Self.heartRateService])
            .map(\.identifier))
        var found: [CompanionDevice] = []
        for p in central.retrieveConnectedPeripherals(withServices: Self.garminProprietaryServices)
        where !usable.contains(p.identifier) {
            found.append(CompanionDevice(id: p.identifier, brand: .garmin,
                                         name: p.name ?? "Garmin watch"))
        }
        for p in central.retrieveConnectedPeripherals(withServices: [Self.whoopProprietaryService])
        where !usable.contains(p.identifier) {
            found.append(CompanionDevice(id: p.identifier, brand: .whoop,
                                         name: p.name ?? "WHOOP"))
        }
        if found != companionDevices { companionDevices = found }
    }

    /// Where the state machine settles when no scan is running. Derived from
    /// the peripheral's actual state, not the current enum — a "switch
    /// monitor" scan overwrites `state` while the old device stays connected,
    /// and dismissing that scan must land back on .connected.
    private func fallbackStateForNoScan() -> MonitorState {
        if let peripheral, peripheral.state == .connected {
            return .connected(name: peripheral.name ?? rememberedName ?? "Heart Rate Monitor")
        }
        if let name = rememberedName, hasRememberedMonitor {
            return .searching(name: name)
        }
        return .idle
    }

    private func reconnectToRemembered() {
        guard let central, central.state == .poweredOn, let id = rememberedID else { return }
        let name = rememberedName ?? "Heart Rate Monitor"

        // Another app (or the system) may already hold the connection — iOS
        // shares BLE connections between apps, and connecting to an
        // already-connected peripheral completes instantly.
        if let connected = central.retrieveConnectedPeripherals(withServices: [Self.heartRateService])
            .first(where: { $0.identifier == id }) {
            connectPeripheral(connected, name: connected.name ?? name)
            return
        }

        if let known = central.retrievePeripherals(withIdentifiers: [id]).first {
            state = .searching(name: known.name ?? name)
            connectPeripheral(known, name: known.name ?? name, announceConnecting: false)
            return
        }

        // The system no longer knows this identifier (rare: BT cache cleared).
        // Fall back to a filtered scan; didDiscover auto-connects on ID match.
        state = .searching(name: name)
        central.scanForPeripherals(withServices: [Self.heartRateService], options: nil)
        scanTimeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.stopScan() }
        scanTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scanTimeout, execute: work)
    }

    private func connectPeripheral(_ target: CBPeripheral, name: String,
                                   announceConnecting: Bool = true) {
        // An intent to connect invalidates any earlier "user wanted this
        // disconnected" marker. Cancelling a *pending* (never-established)
        // connection produces no didDisconnect callback, so a marker set then
        // would otherwise leak and eat a future genuine disconnect.
        userInitiatedDisconnects.remove(target.identifier)
        // Never show the previous monitor's numbers as this one's.
        latestReading = nil
        batteryPercent = nil
        didRetryNotifySubscribe = false
        peripheral = target
        target.delegate = self
        if announceConnecting {
            state = .connecting(name: name)
        }
        central?.connect(target, options: nil)
    }

    private func remember(id: UUID, name: String) {
        UserDefaults.standard.set(id.uuidString, forKey: Self.idDefaultsKey)
        UserDefaults.standard.set(name, forKey: Self.nameDefaultsKey)
    }

    // MARK: - Discovery bookkeeping

    /// CoreBluetooth requires holding a strong reference to any peripheral you
    /// intend to connect to; discovery-callback instances are otherwise freed.
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]

    private func displayName(for peripheral: CBPeripheral,
                             advertisement: [String: Any]) -> String {
        peripheral.name
            ?? advertisement[CBAdvertisementDataLocalNameKey] as? String
            ?? "Heart Rate Monitor"
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothHeartRateManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if case .unavailable = state { state = fallbackStateForNoScan() }
            switch pendingIntent {
            case .scan:      startScan()
            case .reconnect: reconnectToRemembered()
            case .none:
                // e.g. Bluetooth toggled back on mid-session.
                if hasRememberedMonitor, peripheral?.state != .connected {
                    reconnectToRemembered()
                }
            }
            pendingIntent = .none

        case .poweredOff:
            handleUnavailable(.poweredOff)
        case .unauthorized:
            handleUnavailable(.denied)
        case .unsupported:
            handleUnavailable(.unsupported)
        case .resetting, .unknown:
            break // transient; wait for the next state callback
        @unknown default:
            break
        }
    }

    private func handleUnavailable(_ reason: UnavailableReason) {
        // Peripheral references don't survive the stack going down.
        peripheral = nil
        userInitiatedDisconnects.removeAll()
        discoveredPeripherals.removeAll()
        discovered = []
        companionDevices = []
        latestReading = nil
        batteryPercent = nil
        scanTimeoutWork?.cancel()
        scanTimeoutWork = nil
        state = .unavailable(reason)
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        discoveredPeripherals[peripheral.identifier] = peripheral
        let name = displayName(for: peripheral, advertisement: advertisementData)

        // Auto-reconnect path: scanning because the remembered ID wasn't
        // retrievable — connect the moment it shows up.
        if case .searching = state, peripheral.identifier == rememberedID {
            stopScan()
            connectPeripheral(peripheral, name: name)
            return
        }

        var monitor = DiscoveredMonitor(id: peripheral.identifier,
                                        name: name,
                                        rssi: RSSI.intValue)
        if let idx = discovered.firstIndex(where: { $0.id == monitor.id }) {
            // A system-connected seed stays badged even if it also advertises.
            monitor.isSystemConnected = discovered[idx].isSystemConnected
            discovered[idx] = monitor
        } else {
            discovered.append(monitor)
            discovered.sort { $0.rssi > $1.rssi }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        // A pending reconnect can complete while a switch-monitor scan is
        // running; without this the scan (and its now-defused timeout) would
        // keep burning battery until the pairing UI disappears.
        stopScan()
        consecutiveConnectFailures = 0
        // Prefer the real GATT name now that we're connected.
        let name = peripheral.name ?? rememberedName ?? "Heart Rate Monitor"
        remember(id: peripheral.identifier, name: name)
        state = .connected(name: name)
        peripheral.discoverServices([Self.heartRateService, Self.batteryService])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        consecutiveConnectFailures += 1
        guard consecutiveConnectFailures < Self.maxConnectRetries else {
            // Stop the fast churn, but keep the .searching promise honest:
            // back off to a slow 30 s retry cycle instead of going silent
            // until the next app foreground.
            state = fallbackStateForNoScan()
            scheduleSlowRetry()
            return
        }
        let name = rememberedName ?? "Heart Rate Monitor"
        state = .searching(name: name)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, let central = self.central, central.state == .poweredOn,
                  let target = self.peripheral,
                  target.identifier == peripheral.identifier,
                  target.state != .connected, target.state != .connecting else { return }
            central.connect(target, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        // Consume the user-initiated marker BEFORE the identifier guard: the
        // callback for a forgotten/replaced peripheral often arrives after
        // self.peripheral has already changed (or been nilled), and a stale
        // marker would eat a later genuine disconnect's auto-reconnect.
        if userInitiatedDisconnects.remove(peripheral.identifier) != nil {
            return
        }
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        latestReading = nil
        batteryPercent = nil
        // Strap taken off / out of range / battery died. Re-issue the connect:
        // it stays pending at no cost and completes when the strap wakes.
        state = .searching(name: peripheral.name ?? rememberedName ?? "Heart Rate Monitor")
        central.connect(peripheral, options: nil)
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothHeartRateManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }
        for service in services {
            switch service.uuid {
            case Self.heartRateService:
                peripheral.discoverCharacteristics([Self.heartRateMeasurement], for: service)
            case Self.batteryService:
                peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard error == nil, let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            switch characteristic.uuid {
            case Self.heartRateMeasurement:
                peripheral.setNotifyValue(true, for: characteristic)
            case Self.batteryLevel:
                peripheral.readValue(for: characteristic)
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        // Some straps (encryption-required, flaky firmware) reject the first
        // subscribe. Retry once; after that, log — the UI stays in its
        // "acquiring signal" state, and the aggregator never shows stale data.
        guard characteristic.uuid == Self.heartRateMeasurement, error != nil else { return }
        if !didRetryNotifySubscribe {
            didRetryNotifySubscribe = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, peripheral.identifier == self.peripheral?.identifier,
                      peripheral.state == .connected else { return }
                peripheral.setNotifyValue(true, for: characteristic)
            }
        } else {
            print("HR monitor refused heart-rate notifications: \(error!.localizedDescription)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        switch characteristic.uuid {
        case Self.heartRateMeasurement:
            guard let reading = HeartRateMeasurementParser.parse(data) else { return }
            latestReading = reading
            if reading.isUsable {
                onReading?(reading)
            }
        case Self.batteryLevel:
            if let level = data.first, level <= 100 {
                batteryPercent = Int(level)
            }
        default:
            break
        }
    }
}
