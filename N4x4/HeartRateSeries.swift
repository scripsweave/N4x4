// HeartRateSeries.swift
// Fine-grained heart-rate recording for completed workouts:
//   • HeartRateSeries — the persisted per-workout document: bucketed BPM
//     samples plus the interval timeline as it actually unfolded.
//   • HeartRateSeriesRecorder — accumulates samples/spans during a workout.
//     Pure logic (no I/O, no UI) so it is trivially unit-testable.
//   • HeartRateSeriesStore — one JSON file per workout under Application
//     Support, keyed by the log entry's UUID. Deliberately NOT in the
//     UserDefaults log blob: ~840 samples per session would balloon it.
//   • HRSessionSummary — tiny stats stored inline on the log entry so
//     history rows render without touching the filesystem.

import Foundation

// MARK: - Persisted models

struct HeartRateSeries: Codable, Equatable {
    struct Sample: Codable, Equatable {
        /// Seconds since the workout started (wall clock — pauses appear as
        /// sample gaps, which the charts render honestly as line breaks).
        let t: Double
        let bpm: Double
    }

    /// One interval as it actually happened (skips shorten it, pauses stretch
    /// it). Target bounds are 0 when the phase has no target (warmup/cooldown).
    struct IntervalSpan: Codable, Equatable {
        let kind: String        // IntervalType raw name: warmup/work/recovery/cooldown
        let workNumber: Int     // 1-based work-interval number; 0 for non-work
        let start: Double       // seconds since workout start
        var end: Double
        let targetLo: Int
        let targetHi: Int

        var hasTarget: Bool { targetLo > 0 && targetHi > 0 }
        var duration: Double { max(0, end - start) }

        static let kindWarmup = "warmup"
        static let kindWork = "work"
        static let kindRecovery = "recovery"
        static let kindCooldown = "cooldown"
    }

    var samples: [Sample]
    var spans: [IntervalSpan]
    let startedAt: Date

    func samples(in span: IntervalSpan) -> [Sample] {
        samples.filter { $0.t >= span.start && $0.t <= span.end }
    }
}

/// Inline stats for the log entry — keeps history rows filesystem-free.
struct HRSessionSummary: Codable, Equatable {
    let avgBPM: Int
    let maxBPM: Int
    /// % of work-interval time spent inside the target zone, nil when no
    /// work interval had both a target and samples.
    let workInZonePct: Int?
    /// ~40 evenly-spaced BPM values for the history-row sparkline.
    let sparkline: [Int]
}

// MARK: - Analytics (pure, shared by summary + detail UI)

enum HeartRateSeriesAnalytics {

    /// % of a span's sampled time with BPM inside the target, or nil when the
    /// span has no target or fewer than two samples.
    static func inZonePct(_ series: HeartRateSeries,
                          span: HeartRateSeries.IntervalSpan) -> Int? {
        guard span.hasTarget else { return nil }
        let s = series.samples(in: span)
        guard s.count >= 2 else { return nil }
        // Credit each inter-sample gap to the zone state of its leading sample.
        var inZone = 0.0, total = 0.0
        for (a, b) in zip(s, s.dropFirst()) {
            let dt = min(b.t - a.t, 10) // a pause gap shouldn't count as coverage
            total += dt
            if Int(a.bpm) >= span.targetLo && Int(a.bpm) <= span.targetHi {
                inZone += dt
            }
        }
        guard total > 0 else { return nil }
        return Int((inZone / total * 100).rounded())
    }

    /// Seconds from span start until the heart rate first reaches the target's
    /// lower bound. nil when it never got there or the span has no target.
    static func timeToZone(_ series: HeartRateSeries,
                           span: HeartRateSeries.IntervalSpan) -> Double? {
        guard span.hasTarget else { return nil }
        guard let hit = series.samples(in: span).first(where: { Int($0.bpm) >= span.targetLo })
        else { return nil }
        return hit.t - span.start
    }

    /// Summary stats for the log entry. nil when there's nothing worth keeping
    /// (fewer than 5 samples — a workout with no meaningful HR stream).
    static func summary(for series: HeartRateSeries) -> HRSessionSummary? {
        let bpms = series.samples.map(\.bpm)
        guard bpms.count >= 5 else { return nil }
        let workSpans = series.spans.filter { $0.kind == HeartRateSeries.IntervalSpan.kindWork }
        let pcts = workSpans.compactMap { inZonePct(series, span: $0) }
        return HRSessionSummary(
            avgBPM: Int((bpms.reduce(0, +) / Double(bpms.count)).rounded()),
            maxBPM: Int(bpms.max()!.rounded()),
            workInZonePct: pcts.isEmpty ? nil : pcts.reduce(0, +) / pcts.count,
            sparkline: sparkline(from: bpms, points: 40)
        )
    }

    /// Downsample to `points` evenly-spaced values (bucket means).
    static func sparkline(from bpms: [Double], points: Int) -> [Int] {
        guard !bpms.isEmpty else { return [] }
        guard bpms.count > points else { return bpms.map { Int($0.rounded()) } }
        return (0..<points).map { i in
            let lo = i * bpms.count / points
            let hi = max(lo + 1, (i + 1) * bpms.count / points)
            let bucket = bpms[lo..<hi]
            return Int((bucket.reduce(0, +) / Double(bucket.count)).rounded())
        }
    }
}

// MARK: - Recorder

/// Accumulates one workout's heart-rate stream and interval timeline.
/// Owned by TimerViewModel; created on workout start, finished on completion.
final class HeartRateSeriesRecorder {
    private(set) var samples: [HeartRateSeries.Sample] = []
    private(set) var closedSpans: [HeartRateSeries.IntervalSpan] = []
    private var openSpan: HeartRateSeries.IntervalSpan?
    let startedAt: Date

    /// Bucket width: one kept sample per 2 s keeps a 28-minute session under
    /// ~850 points (a few KB on disk) with no visible loss at chart scale.
    private let bucketSeconds: Double

    init(startedAt: Date = Date(), bucketSeconds: Double = 2) {
        self.startedAt = startedAt
        self.bucketSeconds = bucketSeconds
    }

    func record(bpm: Double, at offset: Double) {
        guard bpm > 0, offset >= 0 else { return }
        if let last = samples.last, offset - last.t < bucketSeconds { return }
        samples.append(.init(t: offset, bpm: bpm))
    }

    /// Close the current span (if any) and open the next. Call at workout
    /// start and on every interval advance.
    func beginInterval(kind: String, workNumber: Int,
                       targetLo: Int, targetHi: Int, at offset: Double) {
        closeOpenSpan(at: offset)
        openSpan = .init(kind: kind, workNumber: workNumber,
                         start: max(0, offset), end: max(0, offset),
                         targetLo: targetLo, targetHi: targetHi)
    }

    func finish(at offset: Double) -> HeartRateSeries {
        closeOpenSpan(at: offset)
        return HeartRateSeries(samples: samples, spans: closedSpans, startedAt: startedAt)
    }

    private func closeOpenSpan(at offset: Double) {
        guard var span = openSpan else { return }
        span.end = max(span.start, offset)
        // Zero-length spans (double advance in the same instant) add noise, drop them.
        if span.duration > 0.5 { closedSpans.append(span) }
        openSpan = nil
    }
}

// MARK: - Store

/// One JSON document per workout under Application Support/HeartRateSeries/.
enum HeartRateSeriesStore {

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("HeartRateSeries", isDirectory: true)
    }

    static func url(for entryID: UUID) -> URL {
        directory.appendingPathComponent("\(entryID.uuidString).json")
    }

    static func save(_ series: HeartRateSeries, for entryID: UUID) {
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(series).write(to: url(for: entryID), options: .atomic)
        } catch {
            // Losing one chart is not worth crashing a just-finished workout.
            print("HeartRateSeriesStore save failed: \(error.localizedDescription)")
        }
    }

    static func load(for entryID: UUID) -> HeartRateSeries? {
        guard let data = try? Data(contentsOf: url(for: entryID)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HeartRateSeries.self, from: data)
    }

    static func delete(for entryID: UUID) {
        try? FileManager.default.removeItem(at: url(for: entryID))
    }
}
