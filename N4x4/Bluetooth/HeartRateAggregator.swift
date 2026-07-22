// HeartRateAggregator.swift
// Pure arbitration between live heart-rate sources. No CoreBluetooth or
// WatchConnectivity imports — fully unit-testable off-device.
//
// Policy:
//   • A source is live if its last sample arrived within `freshnessWindow`.
//     Straps notify at ~1 Hz and the Watch streams every few seconds, so 10 s
//     covers both with margin.
//   • When several sources are live, the first live one in `priority` wins.
//     The default order — monitor, Watch, AirPods — reflects sensor quality:
//     a dedicated strap beats wrist optical beats ear optical. The user can
//     reorder it in Settings (stored via the Source raw values).
//   • When the preferred source goes stale, fall back down the list seamlessly.
//   • When every source is stale, the value is nil — the UI shows "—" instead
//     of a frozen number.

import Foundation

struct HeartRateAggregator {

    enum Source: String, CaseIterable {
        case bluetooth   = "monitor"   // Bluetooth strap / armband (standard GATT HR)
        case watch       = "watch"     // Apple Watch app stream over WCSession
        case appleSensor = "airpods"   // AirPods Pro 3 etc. via iOS 26 workout session

        /// User-facing name for the Settings priority list.
        var displayName: String {
            switch self {
            case .bluetooth:   return "Bluetooth Monitor"
            case .watch:       return "Apple Watch"
            case .appleSensor: return "AirPods"
            }
        }
    }

    /// Sensor-quality order: strap, then wrist, then ear.
    static let defaultPriority: [Source] = [.bluetooth, .watch, .appleSensor]

    /// How old a sample may be and still count as live.
    let freshnessWindow: TimeInterval

    /// Arbitration order — first live source in this list supplies the value.
    /// Always contains every Source exactly once (see `priority(fromRaw:)`).
    var priority: [Source]

    private var samples: [Source: (bpm: Double, at: Date)] = [:]

    init(freshnessWindow: TimeInterval = 10, priority: [Source] = HeartRateAggregator.defaultPriority) {
        self.freshnessWindow = freshnessWindow
        self.priority = priority
    }

    // MARK: - Priority persistence

    /// Parse a stored comma-separated raw list ("watch,monitor,airpods") into
    /// a full priority order. Unknown tokens are dropped, duplicates keep
    /// their first position, and any source missing from the string is
    /// appended in default order — so adding a source in a future version
    /// can never make it unreachable for users with an old stored value.
    static func priority(fromRaw raw: String) -> [Source] {
        var result: [Source] = []
        for token in raw.split(separator: ",") {
            guard let source = Source(rawValue: token.trimmingCharacters(in: .whitespaces)) else { continue }
            if !result.contains(source) { result.append(source) }
        }
        for source in defaultPriority where !result.contains(source) {
            result.append(source)
        }
        return result
    }

    static func rawValue(for priority: [Source]) -> String {
        priority.map(\.rawValue).joined(separator: ",")
    }

    // MARK: - Ingestion

    /// Record a sample and return the value to display right now.
    mutating func ingest(bpm: Double, from source: Source, at now: Date) -> Double? {
        samples[source] = (bpm, now)
        return currentValue(now: now)
    }

    /// The value to display: the highest-priority live source, or nil when all
    /// sources are stale. Call on every timer tick so a dead source clears
    /// from the display within a second.
    mutating func currentValue(now: Date) -> Double? {
        prune(now: now)
        for source in priority {
            if let sample = samples[source] { return sample.bpm }
        }
        return nil
    }

    /// Which source is currently supplying the displayed value (drives the
    /// small source glyph next to the BPM readout). Non-mutating so views can
    /// call it freely.
    func liveSource(now: Date) -> Source? {
        priority.first { isLive($0, now: now) }
    }

    mutating func reset() {
        samples.removeAll()
    }

    // MARK: - Internals

    private func isLive(_ source: Source, now: Date) -> Bool {
        guard let sample = samples[source] else { return false }
        // A timestamp in the future means the wall clock was adjusted
        // backwards mid-session; such a sample would otherwise stay "fresh"
        // indefinitely. Treat it as live for now — prune() rewrites it.
        let age = now.timeIntervalSince(sample.at)
        return age < freshnessWindow
    }

    private mutating func prune(now: Date) {
        for (source, sample) in samples {
            let age = now.timeIntervalSince(sample.at)
            if age >= freshnessWindow {
                samples[source] = nil
            } else if age < 0 {
                // Wall clock moved backwards (NTP correction, timezone fix).
                // Re-anchor the sample to now so it ages out normally instead
                // of surviving forever.
                samples[source] = (sample.bpm, now)
            }
        }
    }
}
