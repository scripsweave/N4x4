import Foundation
import HealthKit
import UIKit

/// Persisted with History so a crash cannot lose the intent to export a workout.
struct HealthWorkoutExport: Codable, Equatable {
    enum State: String, Codable { case pending, saved, notRequested }
    // Numeric timestamps retain precision with the History encoder's ISO date strategy.
    let startTimestamp: Double
    let endTimestamp: Double
    var state: State
    var attempts = 0
    var lastAttempt: Date?
    var lastError: String?
    var healthID: UUID?
    var savedAt: Date?
    var start: Date { Date(timeIntervalSince1970: startTimestamp) }
    var end: Date { Date(timeIntervalSince1970: endTimestamp) }
    var isValid: Bool { startTimestamp.isFinite && endTimestamp.isFinite && endTimestamp > startTimestamp }

    init(start: Date, end: Date, requested: Bool) {
        startTimestamp = start.timeIntervalSince1970
        endTimestamp = end.timeIntervalSince1970
        state = requested ? .pending : .notRequested
    }
    static func syncIdentifier(_ id: UUID) -> String { "N4x4.workout.\(id.uuidString)" }
}

struct HealthWorkoutMatch: Identifiable, Equatable {
    let id: UUID
    let start: Date
    let end: Date
    let syncIdentifier: String?

    func exactlyMatches(_ export: HealthWorkoutExport) -> Bool {
        abs(start.timeIntervalSince(export.start)) <= 1 && abs(end.timeIntervalSince(export.end)) <= 1
    }
}

protocol HealthWorkoutExportClient {
    var authorization: HKAuthorizationStatus { get }
    var isAvailable: Bool { get }
    func save(_ export: HealthWorkoutExport, id: UUID) async throws -> UUID
    func matches(_ export: HealthWorkoutExport, id: UUID) async throws -> [HealthWorkoutMatch]
}

enum HealthExportError: LocalizedError {
    case unavailable, permission, unconfirmed, invalidTiming
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Apple Health is unavailable on this device."
        case .permission: return "Allow N4x4 to write workouts in Apple Health, then retry."
        case .unconfirmed: return "Apple Health did not confirm the save. It will be retried."
        case .invalidTiming: return "This session does not have usable workout timing."
        }
    }
}

final class SystemHealthWorkoutExportClient: HealthWorkoutExportClient {
    private let store = HKHealthStore()
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var authorization: HKAuthorizationStatus { store.authorizationStatus(for: .workoutType()) }

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
                                       syncIdentifier: $0.metadata?[HKMetadataKeySyncIdentifier] as? String)
                })
            }
            store.execute(query)
        }
    }

    func save(_ export: HealthWorkoutExport, id: UUID) async throws -> UUID {
        guard isAvailable else { throw HealthExportError.unavailable }
        guard authorization == .sharingAuthorized else { throw HealthExportError.permission }
        guard export.isValid else { throw HealthExportError.invalidTiming }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .highIntensityIntervalTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.addMetadata([
                HKMetadataKeySyncIdentifier: HealthWorkoutExport.syncIdentifier(id),
                HKMetadataKeySyncVersion: NSNumber(value: 1)
            ])
            try await builder.beginCollection(at: export.start)
            try await builder.endCollection(at: export.end)
            if let workout = try await builder.finishWorkout() { return workout.uuid }
            // A repeated sync identifier/version can be ignored by HealthKit.
            // Only acknowledge a nil result if the original object can be found.
            if let existing = try await matches(export, id: id).first(where: {
                $0.syncIdentifier == HealthWorkoutExport.syncIdentifier(id)
            }) { return existing.id }
            throw HealthExportError.unconfirmed
        } catch {
            builder.discardWorkout()
            // Some HealthKit versions report a duplicate sync version as an error.
            // A readable original is also a confirmed success; otherwise retain pending.
            if let records = try? await matches(export, id: id),
               let existing = records.first(where: { $0.syncIdentifier == HealthWorkoutExport.syncIdentifier(id) }) {
                return existing.id
            }
            throw error
        }
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

    func newHealthExport(start: Date, end: Date) -> HealthWorkoutExport {
        HealthWorkoutExport(start: start, end: end, requested: healthSavingEnabled)
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
                    guard self.healthExportClient.isAvailable else { throw HealthExportError.unavailable }
                    guard self.healthExportClient.authorization == .sharingAuthorized else { throw HealthExportError.permission }
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
                    export.healthID = try await self.healthExportClient.save(export, id: entry.id)
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
            let export = HealthWorkoutExport(start: series.startedAt, end: entry.completedAt, requested: true)
            if export.isValid { return (export, false) }
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
            export.savedAt = Date()
        } else {
            guard healthSavingEnabled, healthExportClient.authorization == .sharingAuthorized else { return }
            export.state = .pending
        }
        if updateHealthExport(export, for: review.id), existing == nil { retryHealthExports() }
    }
}
