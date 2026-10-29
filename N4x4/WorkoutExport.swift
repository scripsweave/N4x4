import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// A snapshot of one workout. Encoding happens only when the share destination
/// requests it; no export files or extra copies of Health data are persisted.
struct WorkoutExportFile: Transferable {
    let entry: WorkoutLogEntry
    let series: HeartRateSeries?
    var energyReports: [WorkoutEnergyReport]? = nil

    var filename: String { "N4x4-Workout-\(entry.id.uuidString).json" }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { file in
            try WorkoutExport(entry: file.entry, series: file.series, energyReports: file.energyReports).jsonData()
        }
        .suggestedFileName { $0.filename }
    }
}

extension UTType {
    static let workoutFIT = UTType(exportedAs: "app.n4x4.fit", conformingTo: .data)
}

struct WorkoutFITExportFile: Transferable {
    let snapshot: WorkoutExportFile
    var filename: String { "N4x4-Workout-\(snapshot.entry.id.uuidString).fit" }
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .workoutFIT) { file in
            try WorkoutFITExport(entry: file.snapshot.entry, series: file.snapshot.series,
                                 energyReports: file.snapshot.energyReports).data()
        }.suggestedFileName { $0.filename }
    }
}

extension WorkoutExportFile {
    var fitFile: WorkoutFITExportFile? {
        WorkoutFITExport(entry: entry, series: series, energyReports: energyReports).isAvailable
            ? WorkoutFITExportFile(snapshot: self) : nil
    }
}

/// Versioned, self-describing export. Keep the original saved models alongside
/// derived stage statistics so no samples, optional fields or timing gaps are lost.
struct WorkoutExport: Encodable {
    let format = "app.n4x4.workout"
    let schemaVersion = 1
    let exportedAt: Date
    let appVersion: String
    let appBuild: String
    let definitions: [String: String]
    let performanceMetric: PerformanceMetric
    let recordingStatus: String
    let workout: WorkoutLogEntry
    let recording: HeartRateSeries?
    let energyReports: [WorkoutEnergyReport]?
    let stages: [Stage]?

    struct PerformanceMetric: Encodable {
        let modality: String
        let primaryLabel: String
        let primaryUnit: String
    }

    struct Stage: Encodable {
        let sequence: Int
        let kind: String
        let workNumber: Int
        let startedAt: Date
        let endedAt: Date
        let elapsedDurationSeconds: Double
        let activeDurationSeconds: Double?
        let sampleCount: Int
        let averageBPM: Int?
        let peakBPM: Int?
        let inZonePercent: Int?
        let timeToZoneSeconds: Double?
    }

    init(entry: WorkoutLogEntry, series: HeartRateSeries?, exportedAt: Date = Date(),
         energyReports: [WorkoutEnergyReport]? = nil) {
        self.exportedAt = exportedAt
        appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        workout = entry
        recording = series
        self.energyReports = energyReports
        recordingStatus = series.map { $0.samples.isEmpty ? "timelineOnly" : "heartRateAvailable" } ?? "unavailable"
        let modality = entry.modality ?? entry.workoutType.trainingModality
        performanceMetric = PerformanceMetric(modality: modality.rawValue,
                                              primaryLabel: modality.performanceMetric.label,
                                              primaryUnit: modality.performanceMetric.unit)
        definitions = [
            "scope": "One saved N4x4 workout, including all locally stored workout fields and recorded samples. No additional Apple Health queries are performed.",
            "missingData": "Omitted optional fields are unknown or unavailable, never zero. An unavailable recording does not mean no heart rate was measured. Historical stages are not reconstructed from current settings.",
            "dates": "Date strings are ISO 8601 UTC. Numeric activityTiming start/end, segment start/end and healthExport startTimestamp/endTimestamp are Unix seconds, with fractional precision.",
            "durations": "All durations and offsets are seconds. workout.sessionBreakdown durations are active exercise time, aggregated by phase. Stage elapsedDurationSeconds includes pauses; activeDurationSeconds excludes pauses and recovery gaps and is omitted when valid activity timing is unavailable.",
            "recording": "recording.startedAt is the wall-clock origin for sample t and span start/end offsets. Every stored sample is exported without further downsampling. The recorder retains at most one reading per two-second bucket; gaps remain gaps.",
            "targets": "recording.spans targetLo/targetHi are inclusive heart-rate bounds in BPM. Zero means no target. kind is warmup, work, recovery or cooldown; workNumber is one-based for work stages and zero otherwise.",
            "performance": "workout.intervalPerformances contains manually logged values and notes, including values without a matching recorded stage. intervalNumber matches a work stage's workNumber. primary uses performanceMetric.primaryUnit, always km/h for speed regardless of display preferences. secondary is reserved and has no defined metric or unit.",
            "stageStatistics": "Statistics match the interval cards: samples include both span boundaries; averageBPM and peakBPM round to whole BPM. inZonePercent uses leading-sample zone status with inter-sample gaps capped at ten seconds and requires a target and at least two samples. It describes sampled coverage, not unobserved time.",
            "timeToZoneSeconds": "For work stages with a target, seconds from stage start to the first recorded sample at or above targetLo (including above-zone readings). Includes wall-clock pauses; omitted if never reached or unavailable.",
            "summary": "workout.hrSummary is the stored summary, including its sparkline. It can be absent with fewer than five samples even when recording contains data. workInZonePct is the mean of eligible work-stage in-zone percentages. Heart rate is BPM; percentages range from 0 to 100.",
            "healthExport": "workout.healthExport, when present, is saved Apple Health export intent/status and timing. activeEnergyKilocalories is Apple's recorded active-energy estimate selected for Health export, in kcal; it excludes resting energy, pauses and samples crossing active-time boundaries. It can cover only part of the workout. Missing calories are unknown, never zero. Export state does not affect whether this file contains recorded heart-rate samples.",
            "energyReports": "Optional Apple Watch sensor-session manifests. Sample id is the original Health UUID; start/end are numeric Unix seconds and kilocalories is active energy in kcal. Raw manifests may include pauses; only whole samples inside active workout segments are selected for Health export. Uncovered time is not estimated. finalized=false means the Watch is still collecting or the manifest is waiting for recovery."
        ]
        stages = series.map { series in
            // Never turn a legacy wall-clock span into continuous exercise.
            let timing = [series.activityTiming, entry.healthExport?.activityTiming]
                .compactMap { $0 }.first { $0.isValid }
            return series.spans.enumerated().map { index, span in
                let start = series.startedAt.addingTimeInterval(span.start)
                let end = series.startedAt.addingTimeInterval(span.end)
                let bpms = series.samples(in: span).map(\.bpm)
                let active = timing.map { timing in
                    timing.segments.reduce(0.0) { total, segment in
                        total + max(0, min(segment.end, end.timeIntervalSince1970)
                                    - max(segment.start, start.timeIntervalSince1970))
                    }
                }
                return Stage(sequence: index + 1, kind: span.kind, workNumber: span.workNumber,
                             startedAt: start, endedAt: end,
                             elapsedDurationSeconds: span.duration, activeDurationSeconds: active,
                             sampleCount: bpms.count,
                             averageBPM: bpms.isEmpty ? nil : Int((bpms.reduce(0, +) / Double(bpms.count)).rounded()),
                             peakBPM: bpms.max().map { Int($0.rounded()) },
                             inZonePercent: HeartRateSeriesAnalytics.inZonePct(series, span: span),
                             timeToZoneSeconds: span.kind == HeartRateSeries.IntervalSpan.kindWork
                                ? HeartRateSeriesAnalytics.timeToZone(series, span: span) : nil)
            }
        }
    }

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        // Preserve fractional dates as well as numeric offsets. Storage uses
        // ISO dates, but this also supports the just-completed in-memory series.
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: date))
        }
        return try encoder.encode(self)
    }
}

extension TimerViewModel {
    /// Resolve the latest autosaved review edits by ID instead of exporting a
    /// stale row captured when a sheet opened. A deleted workout cannot export.
    func workoutExport(for id: UUID, series: HeartRateSeries?) -> WorkoutExportFile? {
        guard let entry = workoutLogEntries.first(where: { $0.id == id }) else { return nil }
        let recording = id == completedWorkoutEntryID ? (completedSeries ?? series) : series
        let energy = try? energyStore.reports(for: id)
        return WorkoutExportFile(entry: entry, series: recording,
                                 energyReports: energy.flatMap { $0.isEmpty ? nil : $0 })
    }
}
