// WatchWorkoutImport.swift
// Phone side of standalone Watch workouts: turns a `CompletedWatchWorkout`
// (run entirely on the wrist while the phone was out of reach) into a normal
// `WorkoutLogEntry` — same breakdown, HR series, streak update and HealthKit
// save as a phone-led session.
//
// Delivery is queued and may repeat (the Watch re-sends anything un-acked
// after a reconnect), so the import is idempotent by record id. A record the
// user discarded on the Watch is remembered so a late-arriving copy is dropped.

import Foundation

extension TimerViewModel {

    private static let importedIDsKey  = "importedWatchWorkoutIDs"
    private static let discardedIDsKey = "discardedWatchWorkoutIDs"
    /// Keep the dedup sets bounded; anything older than this many records has
    /// long since been acked.
    private static let idHistoryLimit = 200

    /// Logs a workout completed on the Watch. Returns true when a new entry
    /// was added; false when it was already logged or had been discarded.
    @discardableResult
    func importWatchWorkout(_ record: CompletedWatchWorkout) -> Bool {
        let key = record.id.uuidString
        var imported = Self.ids(forKey: Self.importedIDsKey)
        let discarded = Self.ids(forKey: Self.discardedIDsKey)
        guard !imported.contains(key), !discarded.contains(key), !isDiscardedPhoneWorkout(record.id) else { return false }
        guard record.totalSeconds.isFinite, record.totalSeconds >= 0 else { return false }
        // The bounded ID cache can forget an old transfer; the committed log
        // still proves it was imported and must prevent another Health save.
        let alreadyLogged = isWorkoutPersistedInLog(record.id)

        let type = record.workoutTypeRaw.flatMap(WorkoutType.init(rawValue:)) ?? resolvedDefaultWorkoutType

        // Full series to its own file (charts), small summary inline — the
        // same split the phone's automatic completion save uses. Keep the
        // timeline even when there are too few samples for HR statistics.
        let series = HeartRateSeries(
            samples: record.samples.map { .init(t: $0.t, bpm: $0.bpm) },
            spans: record.spans.map {
                .init(kind: $0.kind, workNumber: $0.workNumber, start: $0.start, end: $0.end,
                      targetLo: $0.targetLo, targetHi: $0.targetHi)
            },
            startedAt: record.startedAt
        )
        pendingWatchImports[record.id] = record
        guard seriesSaver(series, record.id) else {
            reportWorkoutSaveFailure("Your Watch workout couldn’t be saved yet. It remains on your Watch and will retry syncing.")
            return false
        }
        let hrSummary = HeartRateSeriesAnalytics.summary(for: series)

        let entry = WorkoutLogEntry(
            id: record.id,
            completedAt: record.completedAt,
            workoutType: type,
            notes: "",
            sessionBreakdown: WorkoutSessionBreakdown(
                totalDuration: record.totalSeconds,
                warmupDuration: record.warmupSeconds,
                highIntensityDuration: record.highIntensitySeconds,
                recoveryDuration: record.recoverySeconds,
                cooldownDuration: record.cooldownSeconds,
                cooldownSkipped: record.cooldownSkipped
            ),
            modality: type.trainingModality,
            intervalPerformances: nil,
            hrSummary: hrSummary, endedEarly: record.endedEarly
        )

        // The record may arrive after newer phone sessions; keep newest-first.
        if !workoutLogEntries.contains(where: { $0.id == record.id }) { workoutLogEntries.append(entry) }
        workoutLogEntries.sort { $0.completedAt > $1.completedAt }
        guard persistWorkoutLogEntries() else { return false }

        didSaveWatchImport(record.id)
        imported.insert(key)
        Self.store(imported, forKey: Self.importedIDsKey)

        updateStreakOnWorkoutComplete()
        if entry.countsTowardStreak { cancelMissedWorkoutFollowUpIfCompletedToday() }
        if !alreadyLogged { saveWorkoutToHealthKit(start: record.startedAt, end: record.completedAt) }
        return !alreadyLogged
    }

    /// A failed write must leave the Watch's pending record intact for retry.
    func canAcknowledgeWatchWorkout(_ id: UUID) -> Bool {
        Self.ids(forKey: Self.importedIDsKey).contains(id.uuidString)
            || Self.ids(forKey: Self.discardedIDsKey).contains(id.uuidString)
            || isDiscardedPhoneWorkout(id)
    }

    /// The user discarded the workout on the Watch. Remove it if it already
    /// landed, and remember the id so a queued copy can't resurrect it.
    func discardWatchWorkout(id: UUID) {
        pendingWatchImports.removeValue(forKey: id)
        var discarded = Self.ids(forKey: Self.discardedIDsKey)
        discarded.insert(id.uuidString)
        Self.store(discarded, forKey: Self.discardedIDsKey)
        if workoutLogEntries.contains(where: { $0.id == id }) {
            deleteWorkoutLogEntry(id: id)
        }
    }

    private static func ids(forKey key: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    private static func store(_ ids: Set<String>, forKey key: String) {
        UserDefaults.standard.set(Array(ids.suffix(idHistoryLimit)), forKey: key)
    }
}
