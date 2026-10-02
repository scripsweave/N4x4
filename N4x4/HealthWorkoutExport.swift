import Foundation
import HealthKit
import UIKit

/// Persisted with History so a crash cannot lose the intent to export a workout.
struct HealthWorkoutExport: Codable, Equatable {
    enum State: String, Codable { case pending, saved, notRequested }
    enum HeartRateContent: String, Codable { case included, noSamples, permissionNotGranted }
    // Numeric timestamps retain precision with the History encoder's ISO date strategy.
    let startTimestamp: Double
    let endTimestamp: Double
    var state: State
    var attempts = 0
    var lastAttempt: Date?
    var lastError: String?
    var healthID: UUID?
    var savedAt: Date?
    // Frozen before the first Health write. Retries must not change the payload
    // when permissions change. Nil on older exports means inclusion is unknown.
    var heartRateContent: HeartRateContent?
    // Immutable alongside start/end so retries cannot change a remote workout.
    var activityTiming: WorkoutActivityTiming? = nil
    var expectedActiveDuration: Double? = nil
    var start: Date { Date(timeIntervalSince1970: startTimestamp) }
    var end: Date { Date(timeIntervalSince1970: endTimestamp) }
    var activeDuration: Double { activityTiming?.activeDuration ?? endTimestamp - startTimestamp }
    var isValid: Bool {
        guard startTimestamp.isFinite, endTimestamp.isFinite, endTimestamp > startTimestamp else { return false }
        if let timing = activityTiming {
            guard timing.isValid, timing.start == startTimestamp, timing.end == endTimestamp else { return false }
        }
        if let expected = expectedActiveDuration {
            guard expected.isFinite, expected > 0, abs(activeDuration - expected) < 1 else { return false }
        }
        return true
    }

    /// Also checks old pending exports against History, without rewriting their identity/payload.
    func matchesActiveDuration(_ recorded: Double?) -> Bool {
        guard isValid else { return false }
        guard let recorded else { return true }
        return recorded.isFinite && recorded > 0 && abs(activeDuration - recorded) < 1
    }

    var workoutEvents: [HKWorkoutEvent] {
        guard let timing = activityTiming, isValid else { return [] }
        var events: [HKWorkoutEvent] = []
        var cursor = startTimestamp
        func event(_ type: HKWorkoutEventType, at timestamp: Double) -> HKWorkoutEvent {
            HKWorkoutEvent(type: type, dateInterval: DateInterval(start: Date(timeIntervalSince1970: timestamp), duration: 0), metadata: nil)
        }
        for segment in timing.segments {
            if segment.start > cursor {
                events.append(event(.pause, at: cursor))
                events.append(event(.resume, at: segment.start))
            }
            cursor = segment.end
        }
        if cursor < endTimestamp { events.append(event(.pause, at: cursor)) }
        return events
    }

    init(start: Date, end: Date, requested: Bool,
         timing: WorkoutActivityTiming? = nil, activeDuration: Double? = nil) {
        startTimestamp = timing?.start ?? start.timeIntervalSince1970
        endTimestamp = timing?.end ?? end.timeIntervalSince1970
        state = requested ? .pending : .notRequested
        activityTiming = timing
        expectedActiveDuration = activeDuration
    }
    static func syncIdentifier(_ id: UUID) -> String { "N4x4.workout.\(id.uuidString)" }
}

/// The recorded wall-clock timeline, not an average stretched across the session.
/// Stable sample identities also prevent duplicate readings after an interrupted save.
struct HealthWorkoutHeartRateSample: Equatable {
    let date: Date
    let bpm: Double
    let syncIdentifier: String

    static func samples(from series: HeartRateSeries?, export: HealthWorkoutExport,
                        id: UUID) -> [Self] {
        guard let series, export.isValid, series.startedAt.timeIntervalSince1970.isFinite else { return [] }
        // Older series files round startedAt to whole seconds; the export keeps
        // the original precision. Restore that anchor without shifting legacy
        // sessions whose start was only estimated from their duration.
        let start = abs(series.startedAt.timeIntervalSince(export.start)) < 1 ? export.start : series.startedAt
        var seen: Set<Double> = []
        return series.samples.enumerated().compactMap { index, sample in
            guard sample.t.isFinite, sample.t >= 0, sample.bpm.isFinite, sample.bpm > 0 else { return nil }
            let date = start.addingTimeInterval(sample.t)
            guard date >= export.start, date <= export.end, seen.insert(sample.t).inserted else { return nil }
            return Self(date: date, bpm: sample.bpm,
                        syncIdentifier: "\(HealthWorkoutExport.syncIdentifier(id)).heartRate.\(index)")
        }.sorted { $0.date < $1.date }
    }

    var quantitySample: HKQuantitySample {
        HKQuantitySample(type: HKQuantityType(.heartRate),
                         quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: bpm),
                         start: date, end: date,
                         metadata: [HKMetadataKeySyncIdentifier: syncIdentifier,
                                    HKMetadataKeySyncVersion: NSNumber(value: 1)])
    }
}

struct HealthWorkoutSaveResult {
    let id: UUID
    let heartRateContent: HealthWorkoutExport.HeartRateContent?
}

struct HealthWorkoutMatch: Identifiable, Equatable {
    let id: UUID
    let start: Date
    let end: Date
    let syncIdentifier: String?
    var heartRateContent: HealthWorkoutExport.HeartRateContent? = nil

    func exactlyMatches(_ export: HealthWorkoutExport) -> Bool {
        abs(start.timeIntervalSince(export.start)) <= 1 && abs(end.timeIntervalSince(export.end)) <= 1
    }
}

protocol HealthWorkoutExportClient {
    var authorization: HKAuthorizationStatus { get }
    var heartRateAuthorization: HKAuthorizationStatus { get }
    var isAvailable: Bool { get }
    func save(_ export: HealthWorkoutExport, id: UUID,
              heartRateSamples: [HealthWorkoutHeartRateSample]) async throws -> HealthWorkoutSaveResult
    func matches(_ export: HealthWorkoutExport, id: UUID) async throws -> [HealthWorkoutMatch]
}

enum HealthExportError: LocalizedError {
    case unavailable, permission, unconfirmed, invalidTiming, heartRatePermission, missingHeartRate
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Apple Health is unavailable on this device."
        case .permission: return "Allow N4x4 to write workouts in Apple Health, then retry."
        case .unconfirmed: return "Apple Health did not confirm the save. It will be retried."
        case .invalidTiming: return "This workout’s active time could not be verified. It remains in History, but Apple Health saving is on hold."
        case .heartRatePermission: return "Allow N4x4 to write Heart Rate in Apple Health, then retry this save."
        case .missingHeartRate: return "The recorded heart-rate data could not be loaded. This workout will retry saving later."
        }
    }
}

final class SystemHealthWorkoutExportClient: HealthWorkoutExportClient {
    private static let heartRateContentKey = "N4x4.heartRateContent"
    private let store = HKHealthStore()
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var authorization: HKAuthorizationStatus { store.authorizationStatus(for: .workoutType()) }
    var heartRateAuthorization: HKAuthorizationStatus { store.authorizationStatus(for: HKQuantityType(.heartRate)) }

    func matches(_ export: HealthWorkoutExport, id: UUID) async throws -> [HealthWorkoutMatch] {
        guard isAvailable, let bundleID = Bundle.main.bundleIdentifier else { throw HealthExportError.unavailable }
        guard export.isValid else { throw HealthExportError.invalidTiming }
        let identity = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier,
                                                 allowedValues: [HealthWorkoutExport.syncIdentifier(id)])
        let overlap = HKQuery.predicateForSamples(withStart: export.start.addingTimeInterval(-1),
                                                  end: export.end.addingTimeInterval(1))
        // Filter sources on returned samples: HKSource.default() throws an
        // Objective-C exception in unsigned/unentitled environments. A query
        // instead reports unavailable access through its normal error callback.
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [identity, overlap])
        // Include historical Watch-authored records from before the single-saver fix.
        let sourceIDs = [bundleID, bundleID + ".watchkitapp"]
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: (samples as? [HKWorkout] ?? []).filter {
                    sourceIDs.contains($0.sourceRevision.source.bundleIdentifier)
                }.map {
                    HealthWorkoutMatch(id: $0.uuid, start: $0.startDate, end: $0.endDate,
                                       syncIdentifier: $0.metadata?[HKMetadataKeySyncIdentifier] as? String,
                                       heartRateContent: ($0.metadata?[Self.heartRateContentKey] as? String)
                                        .flatMap(HealthWorkoutExport.HeartRateContent.init(rawValue:)))
                })
            }
            store.execute(query)
        }
    }

    func save(_ export: HealthWorkoutExport, id: UUID,
              heartRateSamples: [HealthWorkoutHeartRateSample]) async throws -> HealthWorkoutSaveResult {
        guard isAvailable else { throw HealthExportError.unavailable }
        guard authorization == .sharingAuthorized else { throw HealthExportError.permission }
        guard export.isValid else { throw HealthExportError.invalidTiming }
        // A previous attempt can have succeeded before the local acknowledgement.
        // A missing read result is not proof of absence; sync IDs remain the guard.
        if let existing = try? await existingResult(export, id: id) { return existing }
        if export.heartRateContent == .included {
            guard heartRateAuthorization == .sharingAuthorized else { throw HealthExportError.heartRatePermission }
            guard !heartRateSamples.isEmpty else { throw HealthExportError.missingHeartRate }
        }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .highIntensityIntervalTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            var metadata: [String: Any] = [
                HKMetadataKeySyncIdentifier: HealthWorkoutExport.syncIdentifier(id),
                HKMetadataKeySyncVersion: NSNumber(value: 1)
            ]
            if let content = export.heartRateContent { metadata[Self.heartRateContentKey] = content.rawValue }
            try await builder.addMetadata(metadata)
            try await builder.beginCollection(at: export.start)
            if !export.workoutEvents.isEmpty { try await builder.addWorkoutEvents(export.workoutEvents) }
            if export.heartRateContent == .included {
                try await builder.addSamples(heartRateSamples.map(\.quantitySample))
            }
            try await builder.endCollection(at: export.end)
            guard abs(builder.elapsedTime(at: export.end) - export.activeDuration) < 1 else {
                throw HealthExportError.invalidTiming
            }
            if let workout = try await builder.finishWorkout() {
                return HealthWorkoutSaveResult(id: workout.uuid, heartRateContent: export.heartRateContent)
            }
            // A repeated sync identifier/version can be ignored by HealthKit.
            // Only acknowledge a nil result if the original object can be found.
            if let existing = try await existingResult(export, id: id) { return existing }
            throw HealthExportError.unconfirmed
        } catch {
            builder.discardWorkout()
            // Some HealthKit versions report a duplicate sync version as an error.
            // A readable original is also a confirmed success; otherwise retain pending.
            if let existing = try? await existingResult(export, id: id) { return existing }
            throw error
        }
    }

    private func existingResult(_ export: HealthWorkoutExport, id: UUID) async throws -> HealthWorkoutSaveResult? {
        guard let match = try await matches(export, id: id).first(where: {
            $0.syncIdentifier == HealthWorkoutExport.syncIdentifier(id)
        }) else { return nil }
        return HealthWorkoutSaveResult(id: match.id, heartRateContent: match.heartRateContent)
    }
}

struct HealthRecoveryReview: Identifiable {
    let id: UUID
    let export: HealthWorkoutExport
    let approximate: Bool
    let matches: [HealthWorkoutMatch]
    let queryFailed: Bool
}

extension TimerViewModel {
    func healthHeartRateStatus(for id: UUID) -> String? {
        guard let export = workoutLogEntries.first(where: { $0.id == id })?.healthExport,
              export.state == .saved else { return nil }
        switch export.heartRateContent {
        case .included: return "Recorded heart rate included."
        case .noSamples: return "No recorded heart-rate samples were available to include."
        case .permissionNotGranted: return "Heart rate wasn’t included. Allow Heart Rate write access in Health & Devices for future workouts."
        case nil: return nil
        }
    }
    var pendingHealthExports: Int { workoutLogEntries.filter { $0.healthExport?.state == .pending }.count }
    var latestHealthSave: Date? {
        workoutLogEntries.compactMap(\.healthExport).filter { $0.state == .saved }.compactMap(\.savedAt).max()
    }
    var latestHealthExportError: String? {
        workoutLogEntries.compactMap(\.healthExport)
            .filter { $0.state == .pending && $0.lastError != nil }
            .sorted { ($0.lastAttempt ?? .distantPast) > ($1.lastAttempt ?? .distantPast) }.first?.lastError
    }
    var healthSavingEnabled: Bool { healthKitEnabled && logWorkoutsToHealthKit }

    func newHealthExport(start: Date, end: Date, timing: WorkoutActivityTiming? = nil,
                         activeDuration: Double? = nil) -> HealthWorkoutExport {
        HealthWorkoutExport(start: start, end: end, requested: healthSavingEnabled,
                            timing: timing, activeDuration: activeDuration)
    }

    func setHealthIntegrationEnabled(_ enabled: Bool) {
        healthKitUserOptedOut = !enabled
        healthKitEnabled = enabled
        if enabled { requestHealthKitAuthorizationIfNeeded() }
        objectWillChange.send()
    }

    func setHealthWorkoutLogging(_ enabled: Bool) {
        logWorkoutsToHealthKit = enabled
        objectWillChange.send()
        if enabled { retryHealthExports() }
    }

    func healthExportStatus(for id: UUID) -> String {
        guard let record = workoutLogEntries.first(where: { $0.id == id })?.healthExport else {
            return "Health save status unknown"
        }
        switch record.state {
        case .saved: return "Saved to Apple Health"
        case .notRequested: return "Not sent to Apple Health"
        case .pending:
            if !healthSavingEnabled { return "Waiting · Health saving is off" }
            if healthExportClient.authorization != .sharingAuthorized { return "Waiting for workout permission" }
            return record.lastError == nil ? "Waiting to save to Apple Health" : "Health save needs retrying"
        }
    }

    /// One serial drain per trigger. Repeated foreground/UI events coalesce;
    /// new completions arriving during the drain are included, failed IDs aren't spun.
    func retryHealthExports() {
        guard healthExportTask == nil, healthSavingEnabled else { return }
        healthExportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.healthExportTask = nil }
            var attempted: Set<UUID> = []
            while self.healthSavingEnabled,
                  let entry = self.workoutLogEntries.first(where: {
                      $0.healthExport?.state == .pending && !attempted.contains($0.id)
                          && !($0.id == self.completedWorkoutEntryID && self.hasPendingWorkoutSave)
                          && self.pendingWatchImports[$0.id] == nil
                  }), var export = entry.healthExport {
                attempted.insert(entry.id)
                guard !self.isDiscardedPhoneWorkout(entry.id) else { continue }
                export.attempts += 1
                export.lastAttempt = Date()
                export.lastError = nil
                guard self.updateHealthExport(export, for: entry.id) else { break }
                do {
                    guard export.matchesActiveDuration(entry.sessionBreakdown?.totalDuration) else {
                        throw HealthExportError.invalidTiming
                    }
                    guard self.healthExportClient.isAvailable else { throw HealthExportError.unavailable }
                    guard self.healthExportClient.authorization == .sharingAuthorized else { throw HealthExportError.permission }
                    let samples = HealthWorkoutHeartRateSample.samples(
                        from: HeartRateSeriesStore.load(for: entry.id), export: export, id: entry.id)
                    if export.heartRateContent == nil {
                        export.heartRateContent = samples.isEmpty ? .noSamples
                            : (self.healthExportClient.heartRateAuthorization == .sharingAuthorized
                               ? .included : .permissionNotGranted)
                        guard self.updateHealthExport(export, for: entry.id) else { break }
                    }
                    // Never silently downgrade a previously prepared export on retry.
                    if export.heartRateContent == .included && samples.isEmpty { throw HealthExportError.missingHeartRate }
                    // A bounded UIKit background task gives a just-completed session
                    // time to save after workout audio stops. Expiration never loses intent.
                    var backgroundID = UIBackgroundTaskIdentifier.invalid
                    backgroundID = UIApplication.shared.beginBackgroundTask(withName: "Save workout to Health") {
                        if backgroundID != .invalid {
                            UIApplication.shared.endBackgroundTask(backgroundID)
                            backgroundID = .invalid
                        }
                    }
                    defer {
                        if backgroundID != .invalid { UIApplication.shared.endBackgroundTask(backgroundID) }
                    }
                    let result = try await self.healthExportClient.save(
                        export, id: entry.id, heartRateSamples: export.heartRateContent == .included ? samples : [])
                    export.healthID = result.id
                    export.heartRateContent = result.heartRateContent
                    export.state = .saved
                    export.savedAt = Date()
                } catch {
                    export.lastError = error.localizedDescription
                }
                // Deletion may have happened while HealthKit was saving.
                guard !self.isDiscardedPhoneWorkout(entry.id) else { continue }
                guard self.updateHealthExport(export, for: entry.id) else { break }
            }
        }
    }

    @discardableResult
    func updateHealthExport(_ export: HealthWorkoutExport, for id: UUID) -> Bool {
        guard !isDiscardedPhoneWorkout(id), let index = workoutLogEntries.firstIndex(where: { $0.id == id }) else { return false }
        let old = workoutLogEntries[index].healthExport
        workoutLogEntries[index].healthExport = export
        guard persistWorkoutLogEntries() else {
            workoutLogEntries[index].healthExport = old
            return false
        }
        return true
    }

    func recoveryExport(for id: UUID) -> (export: HealthWorkoutExport, approximate: Bool)? {
        guard let entry = workoutLogEntries.first(where: { $0.id == id }) else { return nil }
        if let export = entry.healthExport { return export.isValid ? (export, false) : nil }
        if let series = HeartRateSeriesStore.load(for: id) {
            let export = HealthWorkoutExport(start: series.startedAt, end: entry.completedAt, requested: true,
                                            timing: series.activityTiming,
                                            activeDuration: entry.sessionBreakdown?.totalDuration)
            if export.isValid { return (export, false) }
            // A known start with an unexplained gap must not be silently replaced
            // by an invented continuous timeline (which also shifts recorded HR).
            return nil
        }
        guard let duration = entry.sessionBreakdown?.totalDuration, duration.isFinite, duration > 0 else { return nil }
        let export = HealthWorkoutExport(start: entry.completedAt.addingTimeInterval(-duration), end: entry.completedAt, requested: true)
        return export.isValid ? (export, true) : nil
    }

    @MainActor
    func reviewHealthRecovery(for id: UUID) async -> HealthRecoveryReview? {
        guard let candidate = recoveryExport(for: id) else { return nil }
        var matches: [HealthWorkoutMatch] = []
        var queryFailed = false
        do { matches = try await healthExportClient.matches(candidate.export, id: id) }
        catch { queryFailed = true }
        guard let current = workoutLogEntries.first(where: { $0.id == id }), !isDiscardedPhoneWorkout(id) else { return nil }
        if current.healthExport?.state == .saved { return nil }
        let identified = matches.filter { $0.syncIdentifier == HealthWorkoutExport.syncIdentifier(id) }
        let exact = matches.filter { $0.exactlyMatches(candidate.export) }
        if let match = identified.first ?? (!candidate.approximate && exact.count == 1 ? exact.first : nil) {
            var export = candidate.export
            export.state = .saved
            export.healthID = match.id
            export.heartRateContent = match.heartRateContent
            export.savedAt = Date()
            export.lastError = nil
            if updateHealthExport(export, for: id) { return nil }
        }
        return HealthRecoveryReview(id: id, export: candidate.export, approximate: candidate.approximate,
                                    matches: matches, queryFailed: queryFailed)
    }

    func confirmHealthRecovery(_ review: HealthRecoveryReview, existing: HealthWorkoutMatch? = nil) {
        guard let entry = workoutLogEntries.first(where: { $0.id == review.id }),
              entry.healthExport?.state != .saved, !isDiscardedPhoneWorkout(review.id) else { return }
        var export = review.export
        export.lastError = nil
        if let existing {
            guard review.matches.contains(existing) else { return }
            export.state = .saved
            export.healthID = existing.id
            export.heartRateContent = existing.heartRateContent
            export.savedAt = Date()
        } else {
            guard healthSavingEnabled, healthExportClient.authorization == .sharingAuthorized else { return }
            export.state = .pending
        }
        if updateHealthExport(export, for: review.id), existing == nil { retryHealthExports() }
    }
}
