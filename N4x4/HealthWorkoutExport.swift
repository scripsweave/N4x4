import Foundation
import HealthKit
import UIKit

/// Persisted with History so a crash cannot lose the intent to export a workout.
struct HealthWorkoutExport: Codable, Equatable {
    enum State: String, Codable { case pending, saved, notRequested }
    enum HeartRateContent: String, Codable { case included, noSamples, permissionNotGranted }
    enum EnergyContent: String, Codable { case awaitingWatch, included, noSamples, permissionNotGranted, skipped, invalid }
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
    var energyContent: EnergyContent?
    var activeEnergyKilocalories: Double?
    var workoutTypeRaw: String?
    var workoutTitle: String?
    // Immutable alongside start/end so retries cannot change a remote workout.
    var activityTiming: WorkoutActivityTiming? = nil
    var expectedActiveDuration: Double? = nil
    var start: Date { Date(timeIntervalSince1970: startTimestamp) }
    var end: Date { Date(timeIntervalSince1970: endTimestamp) }
    var activeDuration: Double { activityTiming?.activeDuration ?? endTimestamp - startTimestamp }
    var isValid: Bool {
        guard startTimestamp.isFinite, endTimestamp.isFinite, endTimestamp > startTimestamp else { return false }
        if let workoutTypeRaw, WorkoutType(rawValue: workoutTypeRaw) == nil { return false }
        if let workoutTitle, workoutTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
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

    private enum CodingKeys: String, CodingKey {
        case startTimestamp, endTimestamp, state, attempts, lastAttempt, lastError, healthID, savedAt
        case heartRateContent, energyContent, activeEnergyKilocalories, activityTiming, expectedActiveDuration
        case workoutTypeRaw, workoutTitle
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        startTimestamp = try values.decode(Double.self, forKey: .startTimestamp)
        endTimestamp = try values.decode(Double.self, forKey: .endTimestamp)
        state = try values.decode(State.self, forKey: .state)
        attempts = try values.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
        lastAttempt = try values.decodeIfPresent(Date.self, forKey: .lastAttempt)
        lastError = try values.decodeIfPresent(String.self, forKey: .lastError)
        healthID = try values.decodeIfPresent(UUID.self, forKey: .healthID)
        savedAt = try values.decodeIfPresent(Date.self, forKey: .savedAt)
        heartRateContent = try values.decodeIfPresent(HeartRateContent.self, forKey: .heartRateContent)
        activityTiming = try values.decodeIfPresent(WorkoutActivityTiming.self, forKey: .activityTiming)
        expectedActiveDuration = try values.decodeIfPresent(Double.self, forKey: .expectedActiveDuration)
        // A malformed new optional field must not erase an older export's
        // identity, confirmed save, timing or HR intent during History repair.
        energyContent = try? values.decodeIfPresent(EnergyContent.self, forKey: .energyContent)
        activeEnergyKilocalories = try? values.decodeIfPresent(Double.self, forKey: .activeEnergyKilocalories)
        workoutTypeRaw = try? values.decodeIfPresent(String.self, forKey: .workoutTypeRaw)
        workoutTitle = try? values.decodeIfPresent(String.self, forKey: .workoutTitle)
        if values.contains(.workoutTypeRaw), (try? values.decodeNil(forKey: .workoutTypeRaw)) == false, workoutTypeRaw == nil { workoutTypeRaw = "" }
        if values.contains(.workoutTitle), (try? values.decodeNil(forKey: .workoutTitle)) == false, workoutTitle == nil { workoutTitle = "" }
        if (values.contains(.energyContent) && (try? values.decodeNil(forKey: .energyContent)) == false && energyContent == nil)
            || (values.contains(.activeEnergyKilocalories) && (try? values.decodeNil(forKey: .activeEnergyKilocalories)) == false
                && activeEnergyKilocalories.map({ $0.isFinite && $0 >= 0 }) != true) {
            energyContent = .invalid
        }
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

enum HealthWorkoutEnergySamples {
    /// Return the exact queried objects. This must never construct replacements:
    /// the same Watch calories already contribute to the user's Move ring.
    static func verified(_ samples: [HKQuantitySample], against manifest: [WorkoutEnergySample]) throws -> [HKQuantitySample] {
        let ids = Set(manifest.map(\.id))
        guard samples.count == ids.count, Set(samples.map(\.uuid)) == ids else { throw HealthExportError.waitingForHealthEnergy }
        let originals = Dictionary(uniqueKeysWithValues: samples.map { ($0.uuid, $0) })
        for item in manifest {
            guard let sample = originals[item.id], sample.quantityType == HKQuantityType(.activeEnergyBurned),
                  abs(sample.startDate.timeIntervalSince1970 - item.start) < 0.001,
                  abs(sample.endDate.timeIntervalSince1970 - item.end) < 0.001,
                  abs(sample.quantity.doubleValue(for: .kilocalorie()) - item.kilocalories) < 0.0001 else {
                throw HealthExportError.missingEnergy
            }
        }
        return samples
    }
}

struct HealthWorkoutSaveResult {
    let id: UUID
    let heartRateContent: HealthWorkoutExport.HeartRateContent?
    var energyContent: HealthWorkoutExport.EnergyContent? = nil
    var activeEnergyKilocalories: Double? = nil
}

struct HealthWorkoutMatch: Identifiable, Equatable {
    let id: UUID
    let start: Date
    let end: Date
    let syncIdentifier: String?
    var heartRateContent: HealthWorkoutExport.HeartRateContent? = nil
    var energyContent: HealthWorkoutExport.EnergyContent? = nil
    var activeEnergyKilocalories: Double? = nil

    func exactlyMatches(_ export: HealthWorkoutExport) -> Bool {
        abs(start.timeIntervalSince(export.start)) <= 1 && abs(end.timeIntervalSince(export.end)) <= 1
    }
}

protocol HealthWorkoutExportClient {
    var authorization: HKAuthorizationStatus { get }
    var heartRateAuthorization: HKAuthorizationStatus { get }
    var energyAuthorization: HKAuthorizationStatus { get }
    var isAvailable: Bool { get }
    func prepareEnergy(_ export: HealthWorkoutExport, id: UUID) async throws
    func save(_ export: HealthWorkoutExport, id: UUID,
              heartRateSamples: [HealthWorkoutHeartRateSample]) async throws -> HealthWorkoutSaveResult
    func matches(_ export: HealthWorkoutExport, id: UUID) async throws -> [HealthWorkoutMatch]
}

enum HealthExportError: LocalizedError {
    case unavailable, permission, unconfirmed, invalidTiming, heartRatePermission, missingHeartRate
    case waitingForWatchEnergy, waitingForHealthEnergy, missingEnergy, energyPermission
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Apple Health is unavailable on this device."
        case .permission: return "Allow N4x4 to write workouts in Apple Health, then retry."
        case .unconfirmed: return "Apple Health did not confirm the save. It will be retried."
        case .invalidTiming: return "This workout’s active time could not be verified. It remains in History, but Apple Health saving is on hold."
        case .heartRatePermission: return "Allow N4x4 to write Heart Rate in Apple Health, then retry this save."
        case .missingHeartRate: return "The recorded heart-rate data could not be loaded. This workout will retry saving later."
        case .waitingForWatchEnergy: return "Waiting for Watch calories. Open N4x4 on your Watch and reconnect it to your iPhone, then retry. You can also save this workout without calories."
        case .waitingForHealthEnergy: return "Waiting for Active Energy samples to sync from your Watch. Allow N4x4 to read Active Energy in Health, then retry, or save this workout without calories."
        case .missingEnergy: return "The recorded calorie data could not be verified. This workout will retry saving later."
        case .energyPermission: return "Allow N4x4 to write Active Energy in Apple Health, then retry this save."
        }
    }
}

final class SystemHealthWorkoutExportClient: HealthWorkoutExportClient {
    private static let heartRateContentKey = "N4x4.heartRateContent"
    private let store = HKHealthStore()
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var authorization: HKAuthorizationStatus { store.authorizationStatus(for: .workoutType()) }
    var heartRateAuthorization: HKAuthorizationStatus { store.authorizationStatus(for: HKQuantityType(.heartRate)) }
    var energyAuthorization: HKAuthorizationStatus { store.authorizationStatus(for: HKQuantityType(.activeEnergyBurned)) }

    func prepareEnergy(_ export: HealthWorkoutExport, id: UUID) async throws {
        _ = try await energySamples(export, id: id)
    }

    /// Resolve the original Health objects, preserving their UUIDs and source.
    /// Recreating the Watch's estimate would count those calories a second time.
    private func energySamples(_ export: HealthWorkoutExport, id: UUID) async throws -> [HKQuantitySample] {
        guard export.energyContent == .included else { return [] }
        guard energyAuthorization == .sharingAuthorized else { throw HealthExportError.energyPermission }
        guard let timing = export.activityTiming,
              let manifest = try WorkoutEnergyStore.shared.samples(for: id, timing: timing), !manifest.isEmpty,
              let expected = export.activeEnergyKilocalories,
              abs(manifest.reduce(0) { $0 + $1.kilocalories } - expected) < 0.0001 else {
            throw HealthExportError.missingEnergy
        }
        let ids = Set(manifest.map(\.id))
        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKQuantityType(.activeEnergyBurned),
                                      predicate: HKQuery.predicateForObjects(with: ids),
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples as? [HKQuantitySample] ?? []) }
            }
            store.execute(query)
        }
        return try HealthWorkoutEnergySamples.verified(samples, against: manifest)
    }

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
                                        .flatMap(HealthWorkoutExport.HeartRateContent.init(rawValue:)),
                                       energyContent: ($0.metadata?["N4x4.energyContent"] as? String)
                                        .flatMap(HealthWorkoutExport.EnergyContent.init(rawValue:)),
                                       activeEnergyKilocalories: $0.statistics(for: HKQuantityType(.activeEnergyBurned))?
                                        .sumQuantity()?.doubleValue(for: .kilocalorie()))
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
        let energy = try await energySamples(export, id: id)
        let configuration = HKWorkoutConfiguration()
        let type = export.workoutTypeRaw.flatMap(WorkoutType.init(rawValue:))
        configuration.activityType = type?.healthActivityType ?? .highIntensityIntervalTraining
        configuration.locationType = type?.healthLocationType ?? .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            var metadata: [String: Any] = [
                HKMetadataKeySyncIdentifier: HealthWorkoutExport.syncIdentifier(id),
                HKMetadataKeySyncVersion: NSNumber(value: 1)
            ]
            if let content = export.heartRateContent { metadata[Self.heartRateContentKey] = content.rawValue }
            if let content = export.energyContent { metadata["N4x4.energyContent"] = content.rawValue }
            if let title = export.workoutTitle { metadata[HKMetadataKeyWorkoutBrandName] = title }
            try await builder.addMetadata(metadata)
            try await builder.beginCollection(at: export.start)
            if !export.workoutEvents.isEmpty { try await builder.addWorkoutEvents(export.workoutEvents) }
            if export.heartRateContent == .included {
                try await builder.addSamples(heartRateSamples.map(\.quantitySample))
            }
            if !energy.isEmpty { try await builder.addSamples(energy) }
            try await builder.endCollection(at: export.end)
            guard abs(builder.elapsedTime(at: export.end) - export.activeDuration) < 1 else {
                throw HealthExportError.invalidTiming
            }
            if let workout = try await builder.finishWorkout() {
                return HealthWorkoutSaveResult(id: workout.uuid, heartRateContent: export.heartRateContent,
                                               energyContent: export.energyContent,
                                               activeEnergyKilocalories: export.activeEnergyKilocalories)
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
        return HealthWorkoutSaveResult(id: match.id, heartRateContent: match.heartRateContent,
                                       energyContent: match.energyContent, activeEnergyKilocalories: match.activeEnergyKilocalories)
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
                         activeDuration: Double? = nil, id: UUID? = nil,
                         expectsWatchEnergy: Bool = false, workoutType: WorkoutType? = nil,
                         title: String? = nil) -> HealthWorkoutExport {
        var export = HealthWorkoutExport(start: start, end: end, requested: healthSavingEnabled,
                                         timing: timing, activeDuration: activeDuration)
        let hasReports = id.map { (try? energyStore.reports(for: $0).isEmpty) != true } ?? false
        if expectsWatchEnergy || hasReports {
            export.energyContent = .awaitingWatch
        } else { export.energyContent = .noSamples }
        export.workoutTypeRaw = workoutType?.rawValue
        export.workoutTitle = title
        return export
    }

    /// Accept the durable manifest before acknowledging it. Finalized or saved
    /// exports keep their original payload even if an old transfer arrives late.
    @discardableResult
    func receiveWatchEnergy(_ report: WorkoutEnergyReport) -> Bool {
        guard report.isValid else { return false }
        if isDiscardedPhoneWorkout(report.workoutID) || isDiscardedWatchWorkout(report.workoutID) { return true }
        let previous = workoutLogEntries.first(where: { $0.id == report.workoutID })?.healthExport
        if let export = previous,
           export.state == .saved || (export.energyContent != .awaitingWatch && !(export.energyContent == .noSamples && export.heartRateContent == nil)) { return true }
        do { try energyStore.save(report) }
        catch { return false }
        if var export = previous, export.energyContent == .noSamples, export.heartRateContent == nil {
            export.energyContent = .awaitingWatch
            guard updateHealthExport(export, for: report.workoutID) else { return false }
        }
        retryHealthExports()
        return true
    }

    /// Explicit escape hatch for missing permissions or a Watch that was lost.
    /// Once samples were prepared, preserve the immutable remote-write payload.
    func saveHealthWorkoutWithoutCalories(_ id: UUID) {
        guard var export = workoutLogEntries.first(where: { $0.id == id })?.healthExport,
              export.state != .saved, export.energyContent == .awaitingWatch else { return }
        export.energyContent = .skipped
        export.activeEnergyKilocalories = nil
        export.lastError = nil
        if updateHealthExport(export, for: id) {
            if healthExportTask != nil { energySyncNeedsRetry = true }
            else { retryHealthExports() }
        }
    }

    func healthEnergyStatus(for id: UUID) -> String? {
        guard let export = workoutLogEntries.first(where: { $0.id == id })?.healthExport else { return nil }
        switch export.energyContent {
        case .included:
            guard let calories = export.activeEnergyKilocalories, calories.isFinite, calories >= 0 else { return nil }
            return "\(calories.formatted(.number.precision(.fractionLength(0)))) kcal active energy from Apple Watch\(export.state == .saved ? " included." : " · waiting to save.")"
        case .awaitingWatch: return "Waiting for Apple Watch calories."
        case .permissionNotGranted: return "Calories weren’t included. Allow Active Energy access in Health & Devices for future workouts."
        case .noSamples: return "No Apple Watch calorie samples included."
        case .skipped: return "Saved without calories at your request."
        case .invalid: return "Calorie metadata could not be read. The original Health save status is preserved."
        case nil: return nil
        }
    }

    func setHealthIntegrationEnabled(_ enabled: Bool) {
        healthKitUserOptedOut = !enabled
        healthKitEnabled = enabled
        observeEnergySyncIfNeeded()
        if enabled { requestHealthKitAuthorizationIfNeeded() }
        objectWillChange.send()
    }

    func setHealthWorkoutLogging(_ enabled: Bool) {
        logWorkoutsToHealthKit = enabled
        observeEnergySyncIfNeeded()
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
        observeEnergySyncIfNeeded()
        healthExportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.healthExportTask = nil
                self.observeEnergySyncIfNeeded()
                if self.energySyncNeedsRetry {
                    self.energySyncNeedsRetry = false
                    self.retryHealthExports()
                }
            }
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
                    guard export.energyContent != .invalid else { throw HealthExportError.missingEnergy }
                    if export.energyContent == .awaitingWatch {
                        guard let timing = export.activityTiming, timing.isValid else { throw HealthExportError.invalidTiming }
                        guard let energy = try self.energyStore.samples(for: entry.id, timing: timing) else {
                            throw HealthExportError.waitingForWatchEnergy
                        }
                        export.energyContent = energy.isEmpty ? .noSamples
                            : (self.healthExportClient.energyAuthorization == .sharingAuthorized ? .included : .permissionNotGranted)
                        if export.energyContent == .included { export.activeEnergyKilocalories = energy.reduce(0) { $0 + $1.kilocalories } }
                        // Resolve every original Health UUID before freezing the
                        // payload. Until then the user may save without calories.
                        try await self.healthExportClient.prepareEnergy(export, id: entry.id)
                        guard !self.isDiscardedPhoneWorkout(entry.id),
                              self.workoutLogEntries.first(where: { $0.id == entry.id })?.healthExport?.energyContent == .awaitingWatch else { continue }
                        guard try self.energyStore.samples(for: entry.id, timing: timing) == energy else {
                            self.energySyncNeedsRetry = true
                            continue
                        }
                        guard self.updateHealthExport(export, for: entry.id) else { break }
                        self.observeEnergySyncIfNeeded()
                    }
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
                    export.energyContent = result.energyContent
                    export.activeEnergyKilocalories = result.activeEnergyKilocalories
                    export.state = .saved
                    export.savedAt = Date()
                } catch {
                    if self.workoutLogEntries.first(where: { $0.id == entry.id })?.healthExport?.state == .saved { continue }
                    // A preflight query may have yielded while the user chose
                    // Save Without Calories. Never overwrite that newer choice.
                    if let current = self.workoutLogEntries.first(where: { $0.id == entry.id })?.healthExport,
                       current.energyContent == .awaitingWatch {
                        export.energyContent = .awaitingWatch
                        export.activeEnergyKilocalories = nil
                    } else if self.workoutLogEntries.first(where: { $0.id == entry.id })?.healthExport?.energyContent == .skipped,
                              export.energyContent != .skipped { continue }
                    export.lastError = error.localizedDescription
                }
                // Deletion may have happened while HealthKit was saving.
                guard !self.isDiscardedPhoneWorkout(entry.id) else { continue }
                guard self.updateHealthExport(export, for: entry.id) else { break }
            }
        }
    }

    private func observeEnergySyncIfNeeded() {
        let needed = healthSavingEnabled && workoutLogEntries.contains(where: {
            $0.healthExport?.state == .pending
                && ($0.healthExport?.energyContent == .included || $0.healthExport?.energyContent == .awaitingWatch)
        })
        guard needed else {
            if let energyObserver { healthStore.stop(energyObserver) }
            energyObserver = nil
            return
        }
        guard energyObserver == nil, HKHealthStore.isHealthDataAvailable() else { return }
        let query = HKObserverQuery(sampleType: HKQuantityType(.activeEnergyBurned), predicate: nil) { [weak self] _, completion, error in
            DispatchQueue.main.async {
                if error == nil, let self {
                    if self.healthExportTask != nil { self.energySyncNeedsRetry = true }
                    else { self.retryHealthExports() }
                } else if let self, let observer = self.energyObserver {
                    self.healthStore.stop(observer)
                    self.energyObserver = nil
                }
                completion()
            }
        }
        energyObserver = query
        healthStore.execute(query)
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
            export.energyContent = match.energyContent
            export.activeEnergyKilocalories = match.activeEnergyKilocalories
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
            export.energyContent = existing.energyContent
            export.activeEnergyKilocalories = existing.activeEnergyKilocalories
            export.savedAt = Date()
        } else {
            guard healthSavingEnabled, healthExportClient.authorization == .sharingAuthorized else { return }
            export.state = .pending
        }
        if updateHealthExport(export, for: review.id), existing == nil { retryHealthExports() }
    }
}

extension WorkoutType {
    var healthLocationType: HKWorkoutSessionLocationType {
        switch self {
        case .run, .hillSprints: return .outdoor
        case .treadmill, .rowing, .elliptical, .stairs: return .indoor
        default: return .unknown
        }
    }
    var healthActivityType: HKWorkoutActivityType {
        switch self {
        case .run, .treadmill, .hillSprints: return .running
        case .cycle: return .cycling
        case .rowing: return .rowing
        case .elliptical: return .elliptical
        case .stairs: return .stairClimbing
        case .jumpRope: return .jumpRope
        case .kettlebell: return .functionalStrengthTraining
        default: return .highIntensityIntervalTraining
        }
    }
}

extension TimerViewModel {
    func updateWorkoutTitle(_ title: String, for id: UUID) {
        guard let index = workoutLogEntries.firstIndex(where: { $0.id == id }) else { return }
        if completedWorkoutEntryID == id { workoutTitleDraft = title; return }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        workoutLogEntries[index].customTitle = title.isEmpty ? nil : title
        persistWorkoutLogEntries()
    }
}
