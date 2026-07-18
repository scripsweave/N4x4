// HeartRateAggregator.swift
// Pure arbitration between live heart-rate sources. No CoreBluetooth or
// WatchConnectivity imports — fully unit-testable off-device.
//
// Policy (zero-config, by design — there is no "source picker" setting):
//   • A source is live if its last sample arrived within `freshnessWindow`.
//     Straps notify at ~1 Hz and the Watch streams every few seconds, so 10 s
//     covers both with margin.
//   • When both are live, Bluetooth wins: a dedicated strap is the more
//     accurate sensor, and wearing one is an explicit user choice.
//   • When the preferred source goes stale, fall back to the other seamlessly.
//   • When every source is stale, the value is nil — the UI shows "—" instead
//     of a frozen number.

import Foundation

struct HeartRateAggregator {

    enum Source: CaseIterable {
        case bluetooth
        case watch
    }

    /// How old a sample may be and still count as live.
    let freshnessWindow: TimeInterval

    private var samples: [Source: (bpm: Double, at: Date)] = [:]

    init(freshnessWindow: TimeInterval = 10) {
        self.freshnessWindow = freshnessWindow
    }

    /// Record a sample and return the value to display right now.
    mutating func ingest(bpm: Double, from source: Source, at now: Date) -> Double? {
        samples[source] = (bpm, now)
        return currentValue(now: now)
    }

    /// The value to display: the freshest-policy winner, or nil when all
    /// sources are stale. Call on every timer tick so a dead source clears
    /// from the display within a second.
    mutating func currentValue(now: Date) -> Double? {
        prune(now: now)
        return samples[.bluetooth]?.bpm ?? samples[.watch]?.bpm
    }

    /// Which source is currently supplying the displayed value (drives the
    /// small source glyph next to the BPM readout). Non-mutating so views can
    /// call it freely.
    func liveSource(now: Date) -> Source? {
        if isLive(.bluetooth, now: now) { return .bluetooth }
        if isLive(.watch, now: now) { return .watch }
        return nil
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
