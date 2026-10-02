import XCTest
import HealthKit
@testable import N4x4

private final class FakeHealthExportClient: HealthWorkoutExportClient {
    var authorization: HKAuthorizationStatus = .sharingAuthorized
    var heartRateAuthorization: HKAuthorizationStatus = .sharingAuthorized
    var isAvailable = true
    var failSave = false
    var failQuery = false
    var calls: [UUID] = []
    var objects: [UUID: UUID] = [:]
    var heartRates: [UUID: [HealthWorkoutHeartRateSample]] = [:]
    var contents: [UUID: HealthWorkoutExport.HeartRateContent] = [:]
    var exports: [HealthWorkoutExport] = []
    var candidates: [HealthWorkoutMatch] = []
    var onSave: (() -> Void)?
    var hold = false
    var continuation: CheckedContinuation<Void, Never>?
    func save(_ export: HealthWorkoutExport, id: UUID,
              heartRateSamples: [HealthWorkoutHeartRateSample] = []) async throws -> HealthWorkoutSaveResult {
        calls.append(id)
        exports.append(export)
        if hold {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                onSave?()
            }
        }
        if failSave { throw HealthExportError.unconfirmed }
        if let result = objects[id] { return HealthWorkoutSaveResult(id: result, heartRateContent: contents[id]) }
        if export.heartRateContent == .included && heartRateAuthorization != .sharingAuthorized {
            throw HealthExportError.heartRatePermission
        }
        let result = UUID()
        objects[id] = result
        heartRates[id] = heartRateSamples
        contents[id] = export.heartRateContent
        return HealthWorkoutSaveResult(id: result, heartRateContent: export.heartRateContent)
    }
    func matches(_ export: HealthWorkoutExport, id: UUID) async throws -> [HealthWorkoutMatch] {
        if failQuery { throw HealthExportError.unavailable }
        return candidates
    }
}

final class HealthWorkoutExportTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ["workoutLogEntriesData", "discardedPhoneWorkoutIDs", "importedWatchWorkoutIDs", "discardedWatchWorkoutIDs",
         "healthKitEnabled", "healthKitUserOptedOut", "logWorkoutsToHealthKit", "appleSensorHREnabled"]
            .forEach { UserDefaults.standard.removeObject(forKey: $0) }
        UserDefaults.standard.set(true, forKey: "healthKitUserOptedOut")
        UserDefaults.standard.set(false, forKey: "workoutRemindersEnabled")
    }

    @MainActor
    private func model(_ client: FakeHealthExportClient, checkpoint: URL? = nil,
                       seriesSaver: @escaping (HeartRateSeries, UUID) -> Bool = { HeartRateSeriesStore.save($0, for: $1) }) -> TimerViewModel {
        let vm = TimerViewModel(checkpointURL: checkpoint ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("current.json"),
                                healthExportClient: client, seriesSaver: seriesSaver)
        vm.healthKitEnabled = true
        vm.logWorkoutsToHealthKit = true
        vm.audioMode = .silent
        vm.hapticsEnabled = false
        vm.liveActivitiesEnabled = false
        vm.notificationsEnabled = false
        return vm
    }

    private func entry(requested: Bool = true) -> WorkoutLogEntry {
        let end = Date(timeIntervalSince1970: 1_790_000_000)
        return WorkoutLogEntry(completedAt: end, workoutType: .treadmill,
                               notes: "private note", healthExport: HealthWorkoutExport(start: end - 600, end: end, requested: requested))
    }

    @MainActor
    func testFailedSaveSurvivesRelaunchThenSavesOnce() async throws {
        let client = FakeHealthExportClient()
        client.failSave = true
        let vm = model(client)
        let row = entry()
        vm.workoutLogEntries = [row]
        XCTAssertTrue(vm.persistWorkoutLogEntries())
        vm.retryHealthExports()
        await vm.healthExportTask?.value
        XCTAssertEqual(vm.pendingHealthExports, 1)
        XCTAssertNotNil(vm.latestHealthExportError)
        client.failSave = false
        let restored = model(client)
        restored.retryHealthExports()
        await restored.healthExportTask?.value
        XCTAssertEqual(restored.workoutLogEntries.first?.healthExport?.state, .saved)
        XCTAssertEqual(client.objects.count, 1)
        restored.retryHealthExports()
        await restored.healthExportTask?.value
        XCTAssertEqual(client.calls.count, 2)
    }

    @MainActor
    func testCrashAfterHealthSuccessRetriesSameIdentity() async throws {
        let client = FakeHealthExportClient()
        let vm = model(client)
        let row = entry()
        vm.workoutLogEntries = [row]
        XCTAssertTrue(vm.persistWorkoutLogEntries())
        let remoteID = try await client.save(XCTUnwrap(row.healthExport), id: row.id)
        // Persisted local state is still pending, simulating termination before acknowledgement.
        let restored = model(client)
        restored.retryHealthExports()
        await restored.healthExportTask?.value
        XCTAssertEqual(client.objects.count, 1)
        XCTAssertEqual(restored.workoutLogEntries.first?.healthExport?.healthID, remoteID.id)
    }

    @MainActor
    func testRepeatedTriggersCoalesceAndDeletionIgnoresLateResult() async {
        let client = FakeHealthExportClient()
        let vm = model(client)
        let row = entry()
        vm.workoutLogEntries = [row]
        client.hold = true
        let started = expectation(description: "save started")
        client.onSave = { started.fulfill() }
        vm.retryHealthExports()
        await fulfillment(of: [started], timeout: 3)
        vm.retryHealthExports()
        vm.deleteWorkoutLogEntry(id: row.id)
        client.continuation?.resume()
        await vm.healthExportTask?.value
        XCTAssertEqual(client.calls, [row.id])
        XCTAssertTrue(vm.workoutLogEntries.isEmpty)
        XCTAssertTrue(vm.isDiscardedPhoneWorkout(row.id))
    }

    @MainActor
    func testDisabledSwitchesAndPermissionRevocationKeepPending() async {
        let client = FakeHealthExportClient()
        let vm = model(client)
        vm.workoutLogEntries = [entry()]
        vm.healthKitEnabled = false
        vm.retryHealthExports()
        XCTAssertNil(vm.healthExportTask)
        vm.healthKitEnabled = true
        vm.logWorkoutsToHealthKit = false
        vm.retryHealthExports()
        XCTAssertNil(vm.healthExportTask)
        vm.logWorkoutsToHealthKit = true
        client.authorization = .sharingDenied
        vm.retryHealthExports()
        await vm.healthExportTask?.value
        XCTAssertTrue(client.calls.isEmpty)
        XCTAssertEqual(vm.pendingHealthExports, 1)
        vm.refreshHealthKitAuthorizationState()
        XCTAssertTrue(vm.healthKitEnabled, "Permission is independent of the user's preference")
        XCTAssertFalse(vm.healthAuthorizationGranted)
        client.authorization = .sharingAuthorized
        vm.refreshHealthKitAuthorizationState()
        vm.retryHealthExports()
        await vm.healthExportTask?.value
        XCTAssertEqual(client.calls.count, 1)
    }

    @MainActor
    func testNotRequestedAndLegacyRowsNeverAutomaticallyExport() async {
        let client = FakeHealthExportClient()
        let vm = model(client)
        vm.workoutLogEntries = [entry(requested: false), WorkoutLogEntry(workoutType: .treadmill, notes: "old")]
        vm.retryHealthExports()
        await vm.healthExportTask?.value
        XCTAssertTrue(client.calls.isEmpty)
        XCTAssertNil(vm.recoveryExport(for: vm.workoutLogEntries[1].id))
        XCTAssertEqual(vm.healthExportStatus(for: vm.workoutLogEntries[1].id), "Health save status unknown")
    }

    @MainActor
    func testNewCompletionAndReviewEditsKeepSavedExport() async throws {
        let client = FakeHealthExportClient()
        let vm = model(client)
        vm.warmupDuration = 0
        vm.numberOfIntervals = 1
        vm.startTimer()
        vm.finishAndSaveWorkout(now: Date().addingTimeInterval(15))
        await vm.healthExportTask?.value
        let id = try XCTUnwrap(vm.completedWorkoutEntryID)
        XCTAssertEqual(vm.workoutLogEntries.first?.healthExport?.state, .saved)
        vm.workoutNotesDraft = "Edited later"
        await vm.healthExportTask?.value
        XCTAssertEqual(client.calls, [id])
        XCTAssertEqual(vm.workoutLogEntries.first?.healthExport?.state, .saved)
        XCTAssertEqual(vm.workoutLogEntries.first?.notes, "Edited later")
    }

    @MainActor
    func testWatchImportPersistsIntentBeforeAcknowledgementAndDuplicateDelivery() async {
        let client = FakeHealthExportClient()
        client.failSave = true
        let vm = model(client)
        let plan = WatchWorkoutPlan.fallback
        var engine = WatchWorkoutEngine.start(plan: plan, now: Date().addingTimeInterval(-10_000))!
        engine.reconcile(now: Date())
        let record = engine.completedRecord()!
        XCTAssertTrue(vm.importWatchWorkout(record))
        XCTAssertTrue(vm.canAcknowledgeWatchWorkout(record.id))
        XCTAssertEqual(vm.workoutLogEntries.first?.healthExport?.state, .pending)
        await vm.healthExportTask?.value
        XCTAssertFalse(vm.importWatchWorkout(record))
        XCTAssertEqual(client.calls, [record.id])
        XCTAssertEqual(vm.pendingHealthExports, 1)
    }

    @MainActor
    func testLegacyExactMatchMarksSavedWithoutWriting() async throws {
        let client = FakeHealthExportClient()
        let vm = model(client)
        let row = entry(requested: false)
        vm.workoutLogEntries = [row]
        let export = try XCTUnwrap(row.healthExport)
        let match = HealthWorkoutMatch(id: UUID(), start: export.start, end: export.end, syncIdentifier: nil)
        client.candidates = [match]
        let review = await vm.reviewHealthRecovery(for: row.id)
        XCTAssertNil(review)
        XCTAssertEqual(vm.workoutLogEntries.first?.healthExport?.healthID, match.id)
        XCTAssertTrue(client.calls.isEmpty)
    }

    @MainActor
    func testFailedLegacyQueryRequiresExplicitConfirmation() async throws {
        let client = FakeHealthExportClient()
        client.failQuery = true
        let vm = model(client)
        let row = entry(requested: false)
        vm.workoutLogEntries = [row]
        let result = await vm.reviewHealthRecovery(for: row.id)
        let review = try XCTUnwrap(result)
        XCTAssertTrue(review.queryFailed)
        XCTAssertTrue(client.calls.isEmpty)
        vm.confirmHealthRecovery(review)
        await vm.healthExportTask?.value
        XCTAssertEqual(client.calls, [row.id])
        vm.confirmHealthRecovery(review)
        XCTAssertEqual(client.calls, [row.id])
    }

    @MainActor
    func testApproximateLegacyTimingAndAmbiguousMatchesNeedReview() async throws {
        let client = FakeHealthExportClient()
        let vm = model(client)
        let end = Date()
        let row = WorkoutLogEntry(completedAt: end, workoutType: .treadmill, notes: "", sessionBreakdown:
            WorkoutSessionBreakdown(totalDuration: 60, warmupDuration: 0, highIntensityDuration: 60,
                                    recoveryDuration: 0, cooldownDuration: 0, cooldownSkipped: true))
        vm.workoutLogEntries = [row]
        client.candidates = [HealthWorkoutMatch(id: UUID(), start: end - 60, end: end, syncIdentifier: nil)]
        let result = await vm.reviewHealthRecovery(for: row.id)
        let review = try XCTUnwrap(result)
        XCTAssertTrue(review.approximate)
        XCTAssertEqual(review.matches.count, 1)
        XCTAssertNil(vm.workoutLogEntries.first?.healthExport)
        vm.confirmHealthRecovery(review, existing: review.matches[0])
        XCTAssertEqual(vm.workoutLogEntries.first?.healthExport?.state, .saved)
        XCTAssertTrue(client.calls.isEmpty)
    }

    @MainActor
    func testBadPersistencePreventsRemoteSave() async {
        let client = FakeHealthExportClient()
        let vm = model(client)
        var row = entry()
        row.healthExport = HealthWorkoutExport(start: Date(timeIntervalSince1970: .infinity), end: Date(), requested: true)
        vm.workoutLogEntries = [row]
        vm.retryHealthExports()
        await vm.healthExportTask?.value
        XCTAssertTrue(client.calls.isEmpty)
        XCTAssertNotNil(vm.workoutSaveError)
    }

    @MainActor
    func testDiagnosticsExcludePrivateWorkoutDetails() {
        let vm = model(FakeHealthExportClient())
        vm.workoutLogEntries = [entry()]
        vm.vo2DataPoints = [VO2DataPoint(date: Date(), value: 48.1)]
        let text = vm.healthDiagnosticsSummary()
        XCTAssertFalse(text.contains("48.1"))
        XCTAssertTrue(text.contains("Pending Health saves: 1"))
        XCTAssertTrue(text.contains("Save workouts enabled: yes"))
        XCTAssertFalse(text.contains("private note"))
    }
}

extension HealthWorkoutExportTests {
    func testHeartRateExportPreservesTimingGapsAndFiltersInvalidSamples() throws {
        let start = Date(timeIntervalSince1970: 1_790_000_000.25)
        let export = HealthWorkoutExport(start: start, end: start + 120, requested: true)
        let id = UUID()
        let series = HeartRateSeries(samples: [
            .init(t: 0, bpm: 110), .init(t: 2, bpm: 120),
            .init(t: 90, bpm: 150), .init(t: 120, bpm: 145),
            .init(t: 90, bpm: 151), .init(t: 122, bpm: 140),
            .init(t: -1, bpm: 100), .init(t: .nan, bpm: 120),
            .init(t: 5, bpm: .infinity), .init(t: 6, bpm: 0)
        ], spans: [], startedAt: Date(timeIntervalSince1970: 1_790_000_000))
        let result = HealthWorkoutHeartRateSample.samples(from: series, export: export, id: id)
        XCTAssertEqual(result.map(\.bpm), [110, 120, 150, 145])
        XCTAssertEqual(result.map { $0.date.timeIntervalSince(start) }, [0, 2, 90, 120])
        XCTAssertEqual(result, HealthWorkoutHeartRateSample.samples(from: series, export: export, id: id))
        XCTAssertEqual(Set(result.map(\.syncIdentifier)).count, 4)
        let sample = try XCTUnwrap(result.first).quantitySample
        XCTAssertEqual(sample.quantityType, HKQuantityType(.heartRate))
        XCTAssertEqual(sample.quantity.doubleValue(for: .count().unitDivided(by: .minute())), 110)
        XCTAssertEqual(sample.startDate, start)
        XCTAssertEqual(sample.endDate, start, "No invented readings across pauses or signal gaps")
        XCTAssertEqual(sample.metadata?[HKMetadataKeySyncIdentifier] as? String, result.first?.syncIdentifier)
        XCTAssertEqual(sample.metadata?[HKMetadataKeySyncVersion] as? Int, 1)
    }

    @MainActor
    func testBluetoothCompletionExportsItsPersistedHeartRateSeries() async throws {
        let client = FakeHealthExportClient()
        let vm = model(client)
        vm.warmupDuration = 0
        vm.startTimer()
        vm.ingestHeartRate(153, from: .bluetooth)
        vm.finishAndSaveWorkout(now: Date().addingTimeInterval(10))
        await vm.healthExportTask?.value
        let id = try XCTUnwrap(vm.completedWorkoutEntryID)
        defer { HeartRateSeriesStore.delete(for: id) }
        XCTAssertEqual(client.heartRates[id]?.map(\.bpm), [153])
        XCTAssertEqual(vm.workoutLogEntries.first?.healthExport?.heartRateContent, .included)
        XCTAssertEqual(vm.healthHeartRateStatus(for: id), "Recorded heart rate included.")
    }

    @MainActor
    func testHeartRatePermissionIsSeparateAndDoesNotBlockWorkoutSave() async throws {
        for permission in [HKAuthorizationStatus.sharingDenied, .notDetermined] {
            let client = FakeHealthExportClient()
            client.heartRateAuthorization = permission
            let vm = model(client)
            let row = entry()
            defer { HeartRateSeriesStore.delete(for: row.id) }
            XCTAssertTrue(HeartRateSeriesStore.save(HeartRateSeries(
                samples: [.init(t: 5, bpm: 145)], spans: [], startedAt: row.healthExport!.start), for: row.id))
            vm.workoutLogEntries = [row]
            vm.refreshHealthKitAuthorizationState()
            XCTAssertTrue(vm.healthAuthorizationGranted)
            XCTAssertEqual(vm.heartRateWritePermissionState, permission == .sharingDenied ? .denied : .notDetermined)
            vm.retryHealthExports()
            await vm.healthExportTask?.value
            XCTAssertEqual(vm.workoutLogEntries.first?.healthExport?.state, .saved)
            XCTAssertEqual(vm.workoutLogEntries.first?.healthExport?.heartRateContent, .permissionNotGranted)
            XCTAssertEqual(client.heartRates[row.id], [])
            client.heartRateAuthorization = .sharingAuthorized
            vm.retryHealthExports()
            await vm.healthExportTask?.value
            XCTAssertEqual(client.calls, [row.id], "Already saved workouts are never rewritten")
        }
    }

    @MainActor
    func testInterruptedHeartRateSaveRetriesIdenticalSamplesAfterRelaunch() async throws {
        let client = FakeHealthExportClient()
        let vm = model(client)
        var row = entry()
        row.healthExport?.heartRateContent = .included
        let export = try XCTUnwrap(row.healthExport)
        let series = HeartRateSeries(samples: [.init(t: 1, bpm: 120), .init(t: 50, bpm: 155)],
                                     spans: [], startedAt: export.start)
        defer { HeartRateSeriesStore.delete(for: row.id) }
        XCTAssertTrue(HeartRateSeriesStore.save(series, for: row.id))
        vm.workoutLogEntries = [row]
        XCTAssertTrue(vm.persistWorkoutLogEntries())
        let samples = HealthWorkoutHeartRateSample.samples(from: series, export: export, id: row.id)
        let remote = try await client.save(export, id: row.id, heartRateSamples: samples)
        // Crash before the local acknowledgement; permission also changes.
        client.heartRateAuthorization = .sharingDenied
        let restored = model(client)
        restored.retryHealthExports()
        await restored.healthExportTask?.value
        XCTAssertEqual(client.objects.count, 1)
        XCTAssertEqual(client.heartRates[row.id], samples)
        XCTAssertEqual(restored.workoutLogEntries.first?.healthExport?.healthID, remote.id)
        XCTAssertEqual(restored.workoutLogEntries.first?.healthExport?.heartRateContent, .included)
    }

    @MainActor
    func testPreparedHeartRateExportNeverSilentlyDowngradesOnRetry() async throws {
        let client = FakeHealthExportClient()
        client.failSave = true
        let vm = model(client)
        let row = entry()
        defer { HeartRateSeriesStore.delete(for: row.id) }
        XCTAssertTrue(HeartRateSeriesStore.save(HeartRateSeries(
            samples: [.init(t: 5, bpm: 145)], spans: [], startedAt: row.healthExport!.start), for: row.id))
        vm.workoutLogEntries = [row]
        vm.retryHealthExports()
        await vm.healthExportTask?.value
        XCTAssertEqual(vm.workoutLogEntries.first?.healthExport?.heartRateContent, .included)
        client.failSave = false
        client.heartRateAuthorization = .sharingDenied
        vm.retryHealthExports()
        await vm.healthExportTask?.value
        XCTAssertEqual(vm.pendingHealthExports, 1)
        XCTAssertTrue(client.objects.isEmpty)
        client.heartRateAuthorization = .sharingAuthorized
        vm.retryHealthExports()
        await vm.healthExportTask?.value
        XCTAssertEqual(client.heartRates[row.id]?.map(\.bpm), [145])
        XCTAssertEqual(vm.workoutLogEntries.first?.healthExport?.state, .saved)
    }

    @MainActor
    func testMissingPreparedSeriesKeepsExportPending() async {
        let client = FakeHealthExportClient()
        let vm = model(client)
        var row = entry()
        row.healthExport?.heartRateContent = .included
        vm.workoutLogEntries = [row]
        vm.retryHealthExports()
        await vm.healthExportTask?.value
        XCTAssertTrue(client.calls.isEmpty)
        XCTAssertEqual(vm.pendingHealthExports, 1)
        XCTAssertEqual(vm.latestHealthExportError, HealthExportError.missingHeartRate.errorDescription)
    }

    @MainActor
    func testWatchImportExportsHeartRateFromOriginalWatchTimeline() async throws {
        let client = FakeHealthExportClient()
        let vm = model(client)
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        var engine = WatchWorkoutEngine.start(plan: .fallback, now: start)!
        engine.record(bpm: 122, now: start + 5)
        engine.record(bpm: 148, now: start + 15)
        engine.reconcile(now: start + 10_000)
        let record = try XCTUnwrap(engine.completedRecord())
        defer { HeartRateSeriesStore.delete(for: record.id) }
        XCTAssertTrue(vm.importWatchWorkout(record))
        XCTAssertTrue(vm.canAcknowledgeWatchWorkout(record.id))
        await vm.healthExportTask?.value
        XCTAssertEqual(client.heartRates[record.id]?.map(\.bpm), [122, 148])
        XCTAssertEqual(client.heartRates[record.id]?.map(\.date), [start + 5, start + 15])
    }

    @MainActor
    func testLegacyExportsDecodeWithoutClaimingHeartRateWasIncluded() throws {
        let row = entry()
        let data = try JSONEncoder().encode(row.healthExport)
        let decoded = try JSONDecoder().decode(HealthWorkoutExport.self, from: data)
        XCTAssertNil(decoded.heartRateContent)
        let vm = model(FakeHealthExportClient())
        var saved = row
        saved.healthExport?.state = .saved
        vm.workoutLogEntries = [saved]
        XCTAssertNil(vm.healthHeartRateStatus(for: row.id))
    }

    @MainActor
    func testFailedSeriesSaveRetainsExportInCheckpointUntilRecovery() async throws {
        let client = FakeHealthExportClient()
        let checkpoint = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("current.json")
        let vm = model(client, checkpoint: checkpoint, seriesSaver: { _, _ in false })
        vm.warmupDuration = 0
        vm.startTimer()
        vm.finishAndSaveWorkout(now: Date().addingTimeInterval(15))
        XCTAssertTrue(vm.hasPendingWorkoutSave)
        let id = try XCTUnwrap(vm.completedWorkoutEntryID)
        vm.retryHealthExports()
        await vm.healthExportTask?.value
        XCTAssertTrue(client.calls.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkpoint.path))
        let restored = model(client, checkpoint: checkpoint)
        restored.retryHealthExports()
        await restored.healthExportTask?.value
        XCTAssertEqual(client.calls, [id])
        XCTAssertEqual(restored.workoutLogEntries.first?.healthExport?.state, .saved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkpoint.path))
    }

    @MainActor
    func testNewCompletionDuringDrainIsIncludedWithoutRepeatingFailure() async {
        let client = FakeHealthExportClient()
        client.hold = true
        client.failSave = true
        let vm = model(client)
        let first = entry(), second = entry()
        vm.workoutLogEntries = [first]
        let started = expectation(description: "first export")
        client.onSave = { started.fulfill() }
        vm.retryHealthExports()
        await fulfillment(of: [started], timeout: 3)
        vm.workoutLogEntries.append(second)
        vm.persistWorkoutLogEntries()
        vm.retryHealthExports()
        client.hold = false
        client.continuation?.resume()
        await vm.healthExportTask?.value
        XCTAssertEqual(client.calls, [first.id, second.id])
        XCTAssertEqual(vm.pendingHealthExports, 2)
    }

    @MainActor
    func testDamagedOptionalFieldPreservesHealthExportAndOriginalBytes() throws {
        let client = FakeHealthExportClient()
        let vm = model(client)
        var row = entry(requested: false)
        row.healthExport?.state = .saved
        row.healthExport?.healthID = UUID()
        vm.workoutLogEntries = [row]
        XCTAssertTrue(vm.persistWorkoutLogEntries())
        let raw = UserDefaults.standard.string(forKey: "workoutLogEntriesData")!
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]])
        rows[0]["hrSummary"] = "damaged optional field"
        let broken = String(decoding: try JSONSerialization.data(withJSONObject: rows), as: UTF8.self)
        UserDefaults.standard.set(broken, forKey: "workoutLogEntriesData")
        let restored = model(client)
        XCTAssertEqual(restored.workoutLogEntries.first?.healthExport, row.healthExport)
        XCTAssertNil(restored.workoutLogEntries.first?.hrSummary)
        XCTAssertNotNil(restored.historyRecoveryNotice)
    }

    @MainActor
    func testBluetoothReadingNeverClaimsWatchIsStreaming() {
        let vm = model(FakeHealthExportClient())
        vm.ingestHeartRate(150, from: .bluetooth)
        XCTAssertFalse(vm.hasFreshWatchHeartRate)
        vm.ingestHeartRate(145, from: .watch)
        XCTAssertTrue(vm.hasFreshWatchHeartRate)
        XCTAssertEqual(vm.heartRateSourceLabel, vm.bleHeartRateManager.rememberedName ?? "Heart Rate Monitor")
    }

    @MainActor
    func testWatchReceiptAcknowledgesDuplicatesWithoutRecordingThemTwice() {
        let vm = model(FakeHealthExportClient())
        // Whole seconds make the exact ten-second expiry boundary independent
        // of sub-microsecond rounding in the WCSession timestamp conversion.
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let message = WatchHeartRateSample(bpm: 145, measuredAt: now).message
        XCTAssertTrue(vm.ingestWatchHeartRate(message, now: now))
        XCTAssertTrue(vm.ingestWatchHeartRate(message, now: now + 1))
        XCTAssertEqual(vm.watchHeartRateAcceptedCount, 1)
        XCTAssertEqual(vm.watchHeartRateRejectedCount, 0)
        XCTAssertEqual(vm.lastWatchHeartRateMeasuredAt?.timeIntervalSince1970 ?? 0,
                       now.timeIntervalSince1970, accuracy: 0.000001)
        XCTAssertFalse(vm.ingestWatchHeartRate(message, now: now + 10))
        XCTAssertEqual(vm.watchHeartRateRejectedCount, 1)
        XCTAssertEqual(vm.lastWatchHeartRateRejection, "Invalid or expired reading")
        XCTAssertFalse(vm.ingestWatchHeartRate(message, now: now + 20, isCachedContext: true))
        XCTAssertEqual(vm.lastWatchHeartRateReceivedAt, now + 10, "Rereading local context is not a new packet")
        XCTAssertEqual(vm.watchHeartRateRejectedCount, 1)
    }

    @MainActor
    func testLateHeartRateFromPreviousWorkoutCannotEnterANewWorkout() throws {
        let vm = model(FakeHealthExportClient())
        vm.startTimer()
        defer { vm.reset() }
        let id = try XCTUnwrap(vm.activeWorkoutID)
        let now = Date()
        let old = WatchHeartRateSample(bpm: 145, measuredAt: now, workoutID: UUID().uuidString)
        XCTAssertFalse(vm.ingestWatchHeartRate(old.message, now: now))
        XCTAssertNil(vm.currentHeartRate)
        XCTAssertEqual(vm.lastWatchHeartRateRejection, "Reading belongs to another workout")
        let current = WatchHeartRateSample(bpm: 145, measuredAt: now, workoutID: id.uuidString)
        XCTAssertTrue(vm.ingestWatchHeartRate(current.message, now: now))
        XCTAssertEqual(vm.currentHeartRate, 145)
    }

    @MainActor
    func testEmptyContextIsNotReportedAsAHeartRatePacketAndDiagnosticsExcludeBPM() {
        let vm = model(FakeHealthExportClient())
        XCTAssertFalse(vm.ingestWatchHeartRate([:]))
        XCTAssertNil(vm.lastWatchHeartRateReceivedAt)
        XCTAssertEqual(vm.watchHeartRateRejectedCount, 0)
        let now = Date()
        XCTAssertTrue(vm.ingestWatchHeartRate(WatchHeartRateSample(bpm: 153, measuredAt: now).message, now: now))
        let diagnostics = vm.healthDiagnosticsSummary()
        XCTAssertTrue(diagnostics.contains("Watch HR received this launch: 1"))
        XCTAssertFalse(diagnostics.contains("153"))
        XCTAssertFalse(diagnostics.contains("BPM"))
    }

    @MainActor
    func testDelayedWatchReadingRecordsMeasurementTimeInsteadOfArrivalTime() throws {
        let vm = model(FakeHealthExportClient())
        let start = Date().addingTimeInterval(-10)
        vm.startTimer(now: start)
        let id = try XCTUnwrap(vm.activeWorkoutID)
        defer { HeartRateSeriesStore.delete(for: id) }
        let sample = WatchHeartRateSample(bpm: 145, measuredAt: start + 2, workoutID: id.uuidString)
        XCTAssertTrue(vm.ingestWatchHeartRate(sample.message, now: start + 9))
        vm.finishAndSaveWorkout(now: start + 11)
        XCTAssertEqual(vm.completedSeries?.samples.first?.t ?? -1, 2, accuracy: 0.000001)
    }
}

extension HealthWorkoutExportTests {
    @MainActor
    func testFinishingWithLoggingOffNeverBackfillsWhenEnabledLater() async {
        let client = FakeHealthExportClient()
        let vm = model(client)
        vm.logWorkoutsToHealthKit = false
        vm.warmupDuration = 0
        vm.startTimer()
        vm.finishAndSaveWorkout(now: Date().addingTimeInterval(10))
        XCTAssertEqual(vm.workoutLogEntries.first?.healthExport?.state, .notRequested)
        vm.setHealthWorkoutLogging(true)
        await vm.healthExportTask?.value
        XCTAssertTrue(client.calls.isEmpty)
    }
}

// MARK: - Active workout time and recovery (Louise's multi-day export regression)
extension HealthWorkoutExportTests {
    @MainActor
    private func timingModel(_ client: FakeHealthExportClient, checkpoint: URL? = nil) -> TimerViewModel {
        let vm = model(client, checkpoint: checkpoint)
        vm.warmupDuration = 0
        vm.numberOfIntervals = 1
        vm.highIntensityDuration = 600
        vm.cooldownEnabled = false
        return vm
    }

    private func assertHealthDuration(_ export: HealthWorkoutExport, equals seconds: Double,
                                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(export.isValid, file: file, line: line)
        // Uses HealthKit's own event-based duration calculation, without writing to Health.
        let workout = HKWorkout(activityType: .highIntensityIntervalTraining,
                                start: export.start, end: export.end,
                                workoutEvents: export.workoutEvents, totalEnergyBurned: nil,
                                totalDistance: nil, metadata: nil)
        XCTAssertEqual(workout.duration, seconds, accuracy: 0.001, file: file, line: line)
    }

    @MainActor
    func testRecoveredTwoDaySessionExportsOnlyActiveExercise() async throws {
        let client = FakeHealthExportClient()
        let checkpoint = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("current.json")
        let vm = timingModel(client, checkpoint: checkpoint)
        let start = Date(timeIntervalSince1970: 1_790_780_000.25)
        let end = start + 172_305.85
        vm.startTimer(now: start)
        vm.reconcileTimerState(now: start + 10, playAlarm: false)
        vm.timer?.cancel()
        let restored = model(client, checkpoint: checkpoint)
        XCTAssertTrue(restored.showWorkoutRecovery)
        restored.startTimer(now: end - 590)
        restored.reconcileTimerState(now: end, playAlarm: false)
        await restored.healthExportTask?.value
        let row = try XCTUnwrap(restored.workoutLogEntries.first)
        let export = try XCTUnwrap(client.exports.last)
        XCTAssertEqual(row.sessionBreakdown?.totalDuration ?? 0, 600, accuracy: 0.001)
        XCTAssertEqual(export.end.timeIntervalSince(export.start), 172_305.85, accuracy: 0.001)
        assertHealthDuration(export, equals: 600)
        XCTAssertEqual(export.workoutEvents.map(\.type), [.pause, .resume])
        XCTAssertEqual(HeartRateSeriesStore.load(for: row.id)?.activityTiming, export.activityTiming)
        restored.reset()
    }

    @MainActor
    func testWatchResumeEntryPointKeepsCountdownFrozenAndExcludesPause() async throws {
        let client = FakeHealthExportClient()
        let vm = timingModel(client)
        let start = Date()
        vm.startTimer(now: start)
        vm.pause(now: start + 10)
        vm.startTimer(now: start + 3_610) // Same entry point as the Watch command.
        XCTAssertTrue(vm.isRunning)
        XCTAssertNil(vm.workoutCompletionDate)
        XCTAssertEqual(vm.timeRemaining, 590, accuracy: 0.001)
        vm.reconcileTimerState(now: start + 4_200, playAlarm: false)
        await vm.healthExportTask?.value
        assertHealthDuration(try XCTUnwrap(client.exports.last), equals: 600)
        vm.reset()
    }

    @MainActor
    func testRepeatedRecoveryAndPhoneResumeKeepEveryGap() async throws {
        let client = FakeHealthExportClient()
        let checkpoint = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("current.json")
        let start = Date()
        let vm = timingModel(client, checkpoint: checkpoint)
        vm.startTimer(now: start)
        vm.pause(now: start + 10)
        vm.pause(now: start + 100)
        vm.reconcileTimerState(now: start + 120, playAlarm: false)
        vm.timer?.cancel()
        let restored = model(client, checkpoint: checkpoint)
        restored.startTimer(now: start + 1_000)
        restored.pause(now: start + 1_030)
        let again = model(client, checkpoint: checkpoint)
        again.startTimer(now: start + 10_000)
        again.finishAndSaveWorkout(now: start + 10_040)
        await again.healthExportTask?.value
        let export = try XCTUnwrap(client.exports.last)
        assertHealthDuration(export, equals: 100)
        XCTAssertEqual(export.workoutEvents.map(\.type), [.pause, .resume, .pause, .resume, .pause, .resume])
        again.reset()
    }

    @MainActor
    func testFinishWhilePausedAndFreshWorkoutDoNotCountTimeAway() async throws {
        let client = FakeHealthExportClient()
        let vm = timingModel(client)
        let start = Date()
        vm.startTimer(now: start)
        vm.pause(now: start + 10)
        vm.finishAndSaveWorkout(now: start + 172_800)
        await vm.healthExportTask?.value
        assertHealthDuration(try XCTUnwrap(client.exports.last), equals: 10)
        vm.reset()
        vm.startTimer(now: start + 172_800)
        vm.reconcileTimerState(now: start + 173_400, playAlarm: false)
        await vm.healthExportTask?.value
        let export = try XCTUnwrap(client.exports.last)
        XCTAssertEqual(export.start.timeIntervalSince(start + 172_800), 0, accuracy: 0.001)
        assertHealthDuration(export, equals: 600)
        XCTAssertTrue(export.workoutEvents.isEmpty)
        vm.reset()
    }

    @MainActor
    func testOldPendingInflatedExportIsHeldWithoutChangingPayload() async throws {
        let client = FakeHealthExportClient()
        let vm = model(client)
        let row = WorkoutLogEntry(workoutType: .treadmill, notes: "",
            sessionBreakdown: .init(totalDuration: 10, warmupDuration: 0, highIntensityDuration: 10,
                                   recoveryDuration: 0, cooldownDuration: 0, cooldownSkipped: true),
            healthExport: entry().healthExport)
        let original = try XCTUnwrap(row.healthExport)
        vm.workoutLogEntries = [row]
        XCTAssertTrue(vm.persistWorkoutLogEntries())
        vm.retryHealthExports()
        await vm.healthExportTask?.value
        XCTAssertTrue(client.calls.isEmpty)
        let pending = try XCTUnwrap(vm.workoutLogEntries.first?.healthExport)
        XCTAssertEqual(pending.state, .pending)
        XCTAssertNotNil(pending.lastError)
        XCTAssertEqual(pending.startTimestamp, original.startTimestamp)
        XCTAssertEqual(pending.endTimestamp, original.endTimestamp)
    }

    @MainActor
    func testLegacyCheckpointGapIsNotGuessedOnUpgrade() async throws {
        let client = FakeHealthExportClient()
        let checkpoint = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("current.json")
        let vm = timingModel(client, checkpoint: checkpoint)
        let start = Date()
        vm.startTimer(now: start)
        vm.pause(now: start + 10)
        vm.startTimer(now: start + 100)
        vm.pause(now: start + 110)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: checkpoint)) as? [String: Any])
        json.removeValue(forKey: "activityTiming")
        try JSONSerialization.data(withJSONObject: json).write(to: checkpoint)
        let restored = model(client, checkpoint: checkpoint)
        restored.startTimer(now: start + 172_800)
        restored.finishAndSaveWorkout(now: start + 172_810)
        await restored.healthExportTask?.value
        XCTAssertEqual(restored.workoutLogEntries.first?.sessionBreakdown?.totalDuration ?? 0, 30, accuracy: 0.001)
        XCTAssertTrue(client.calls.isEmpty)
        XCTAssertNotNil(restored.latestHealthExportError)
        restored.reset()
    }

    @MainActor
    func testContinuousLegacyCheckpointCanRecoverWithoutInventingExercise() async throws {
        let client = FakeHealthExportClient()
        let checkpoint = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("current.json")
        let vm = timingModel(client, checkpoint: checkpoint)
        let start = Date()
        vm.startTimer(now: start)
        vm.pause(now: start + 10)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: checkpoint)) as? [String: Any])
        json.removeValue(forKey: "activityTiming")
        try JSONSerialization.data(withJSONObject: json).write(to: checkpoint)
        let restored = model(client, checkpoint: checkpoint)
        restored.startTimer(now: start + 172_800)
        restored.finishAndSaveWorkout(now: start + 172_810)
        await restored.healthExportTask?.value
        assertHealthDuration(try XCTUnwrap(client.exports.last), equals: 20)
        restored.reset()
    }

    @MainActor
    func testPausedExportRetryRetainsEventsAndHeartRateDates() async throws {
        let client = FakeHealthExportClient()
        client.failSave = true
        let vm = timingModel(client)
        let start = Date()
        vm.startTimer(now: start)
        vm.ingestHeartRate(150, from: .bluetooth, sampledAt: start + 5, now: start + 5)
        vm.pause(now: start + 10)
        vm.startTimer(now: start + 100)
        vm.ingestHeartRate(155, from: .bluetooth, sampledAt: start + 105, now: start + 105)
        vm.finishAndSaveWorkout(now: start + 110)
        await vm.healthExportTask?.value
        let first = try XCTUnwrap(client.exports.last)
        vm.reset()
        client.failSave = false
        let restored = model(client)
        restored.retryHealthExports()
        await restored.healthExportTask?.value
        let retried = try XCTUnwrap(client.exports.last)
        XCTAssertEqual(first.activityTiming, retried.activityTiming)
        XCTAssertEqual(first.startTimestamp, retried.startTimestamp)
        XCTAssertEqual(first.endTimestamp, retried.endTimestamp)
        assertHealthDuration(retried, equals: 20)
        let id = try XCTUnwrap(client.calls.last)
        let dates = try XCTUnwrap(client.heartRates[id]).map { $0.date.timeIntervalSince(start) }
        XCTAssertEqual(dates.count, 2)
        XCTAssertEqual(dates[0], 5, accuracy: 0.001)
        XCTAssertEqual(dates[1], 105, accuracy: 0.001)
    }

    @MainActor
    func testStandaloneWatchPauseSurvivesEncodingAndImportsExactTiming() async throws {
        let client = FakeHealthExportClient()
        let vm = model(client)
        let start = Date(timeIntervalSince1970: 1_790_780_000.75)
        var engine = try XCTUnwrap(WatchWorkoutEngine.start(plan: .fallback, now: start))
        engine.pause(now: start + 10.25)
        engine = try JSONDecoder().decode(WatchWorkoutEngine.self, from: JSONEncoder().encode(engine))
        engine.resume(now: start + 172_800.5)
        engine.finish(now: start + 172_820.75)
        let record = try XCTUnwrap(engine.completedRecord())
        let wire = try XCTUnwrap(CompletedWatchWorkout.decode(XCTUnwrap(record.encoded())))
        XCTAssertTrue(vm.importWatchWorkout(wire))
        await vm.healthExportTask?.value
        let export = try XCTUnwrap(client.exports.last)
        XCTAssertEqual(export.start.timeIntervalSince(start), 0, accuracy: 0.001)
        XCTAssertEqual(export.end.timeIntervalSince(start), 172_820.75, accuracy: 0.001)
        assertHealthDuration(export, equals: 30.5)
        XCTAssertTrue(vm.canAcknowledgeWatchWorkout(record.id))
    }

    @MainActor
    func testStandaloneWatchFinishWhilePausedExcludesTrailingGap() async throws {
        let client = FakeHealthExportClient()
        let vm = model(client)
        let start = Date()
        var engine = try XCTUnwrap(WatchWorkoutEngine.start(plan: .fallback, now: start))
        engine.pause(now: start + 10)
        engine.finish(now: start + 172_800)
        let record = try XCTUnwrap(engine.completedRecord())
        XCTAssertTrue(vm.importWatchWorkout(record))
        await vm.healthExportTask?.value
        let export = try XCTUnwrap(client.exports.last)
        assertHealthDuration(export, equals: 10)
        XCTAssertEqual(export.workoutEvents.map(\.type), [.pause])
    }

    @MainActor
    func testLegacyWatchGapStillImportsButDoesNotExportInflatedDuration() async throws {
        let client = FakeHealthExportClient()
        let vm = model(client)
        let start = Date()
        var engine = try XCTUnwrap(WatchWorkoutEngine.start(plan: .fallback, now: start))
        engine.pause(now: start + 10)
        engine.resume(now: start + 172_800)
        engine.finish(now: start + 172_810)
        var record = try XCTUnwrap(engine.completedRecord())
        record.activityTiming = nil
        XCTAssertTrue(vm.importWatchWorkout(record))
        await vm.healthExportTask?.value
        XCTAssertTrue(client.calls.isEmpty)
        XCTAssertNotNil(vm.latestHealthExportError)
        XCTAssertTrue(vm.canAcknowledgeWatchWorkout(record.id))
    }

    func testTimingValidationRejectsOverlapAndDisagreement() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        var timing = WorkoutActivityTiming(startedAt: start)
        timing.pause(at: start + 10)
        timing.resume(at: start + 5) // Backward wall-clock adjustment creates overlap.
        timing.finish(at: start + 20)
        XCTAssertFalse(timing.isValid)
        XCTAssertFalse(HealthWorkoutExport(start: start, end: start + 20, requested: true,
                                          timing: timing, activeDuration: 25).isValid)
        var valid = WorkoutActivityTiming(startedAt: start)
        valid.finish(at: start + 20)
        XCTAssertFalse(HealthWorkoutExport(start: start, end: start + 20, requested: true,
                                          timing: valid, activeDuration: 10).isValid)
    }
}
