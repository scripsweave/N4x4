import XCTest
@testable import N4x4

/// Standalone Watch workouts: the shared interval engine, phone-timeline
/// projection, and the phone-side import of a completed Watch record.
final class WatchStandaloneTests: XCTestCase {

    /// Fixed instant for deterministic engine maths.
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    /// Import tests need a real "earlier today" so ordering and the week
    /// streak behave as they would for a workout just finished.
    private let recent = Date().addingTimeInterval(-3600 - 420)

    /// 60 s warm-up, 2 × (120 s work / 60 s recovery), 60 s cool-down = 420 s.
    private var plan: WatchWorkoutPlan {
        WatchWorkoutPlan(
            steps: [.init(phase: .warmup, duration: 60),
                    .init(phase: .highIntensity, duration: 120),
                    .init(phase: .rest, duration: 60),
                    .init(phase: .highIntensity, duration: 120),
                    .init(phase: .cooldown, duration: 60)],
            totalIntervals: 2,
            workLow: 150, workHigh: 170, recoveryLow: 110, recoveryHigh: 130,
            zoneHapticEnabled: true, intervalHapticsEnabled: true,
            workoutTypeRaw: WorkoutType.treadmill.rawValue)
    }

    override func setUp() {
        super.setUp()
        ["workoutLogEntriesData", "importedWatchWorkoutIDs", "discardedWatchWorkoutIDs",
         "currentStreak", "longestStreak", "healthKitEnabled"]
            .forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    // MARK: Engine

    func testStartIsWarmupWithFullCountdown() {
        let e = WatchWorkoutEngine.start(plan: plan, now: t0)!
        XCTAssertEqual(e.phase, .warmup)
        XCTAssertTrue(e.isRunning)
        XCTAssertEqual(e.timeRemaining(asOf: t0), 60)
        XCTAssertEqual(e.highIntensityCount, 0)
        XCTAssertEqual(e.targetRange.low, 0)
    }

    func testReconcileAdvancesOneBoundary() {
        var e = WatchWorkoutEngine.start(plan: plan, now: t0)!
        XCTAssertEqual(e.reconcile(now: t0 + 59), 0)
        XCTAssertEqual(e.reconcile(now: t0 + 60), 1)
        XCTAssertEqual(e.phase, .highIntensity)
        XCTAssertEqual(e.highIntensityCount, 1)
        XCTAssertEqual(e.targetRange.low, 150)
        XCTAssertEqual(e.timeRemaining(asOf: t0 + 60), 120, accuracy: 0.001)
    }

    func testReconcileCatchesUpAfterSuspension() {
        // App suspended/killed for 5 minutes: 60 + 120 + 60 + (60 into work 2).
        var e = WatchWorkoutEngine.start(plan: plan, now: t0)!
        XCTAssertEqual(e.reconcile(now: t0 + 300), 3)
        XCTAssertEqual(e.currentIndex, 3)
        XCTAssertEqual(e.highIntensityCount, 2)
        XCTAssertEqual(e.timeRemaining(asOf: t0 + 300), 60, accuracy: 0.001)
        XCTAssertFalse(e.isComplete)
    }

    func testCompletesExactlyAtPlanEndAndBreakdownMatchesPlan() {
        var e = WatchWorkoutEngine.start(plan: plan, now: t0)!
        e.reconcile(now: t0 + 10_000)
        XCTAssertTrue(e.isComplete)
        XCTAssertFalse(e.isRunning)
        XCTAssertEqual(e.completionDate, t0 + 420)
        let r = e.completedRecord()!
        XCTAssertEqual(r.warmupSeconds, 60, accuracy: 0.001)
        XCTAssertEqual(r.highIntensitySeconds, 240, accuracy: 0.001)
        XCTAssertEqual(r.recoverySeconds, 60, accuracy: 0.001)
        XCTAssertEqual(r.cooldownSeconds, 60, accuracy: 0.001)
        XCTAssertEqual(r.totalSeconds, 420, accuracy: 0.001)
        XCTAssertFalse(r.cooldownSkipped)
        XCTAssertEqual(r.spans.count, 5)
        XCTAssertEqual(r.spans[1].kind, "work")
        XCTAssertEqual(r.spans[1].workNumber, 1)
        XCTAssertEqual(r.spans[1].targetLo, 150)
        XCTAssertEqual(r.spans[3].workNumber, 2)
        XCTAssertEqual(r.spans[2].kind, "recovery")
    }

    func testPauseFreezesCountdownAndResumeShiftsEndTime() {
        var e = WatchWorkoutEngine.start(plan: plan, now: t0)!
        e.pause(now: t0 + 20)
        XCTAssertFalse(e.isRunning)
        XCTAssertEqual(e.timeRemaining(asOf: t0 + 500), 40, accuracy: 0.001)
        XCTAssertEqual(e.reconcile(now: t0 + 500), 0, "paused engines never advance")
        e.resume(now: t0 + 500)
        XCTAssertTrue(e.isRunning)
        XCTAssertEqual(e.timeRemaining(asOf: t0 + 500), 40, accuracy: 0.001)
        e.reconcile(now: t0 + 540)
        XCTAssertEqual(e.phase, .highIntensity)
        // Paused time is excluded from the phase total.
        e.reconcile(now: t0 + 10_000)
        XCTAssertEqual(e.completedRecord()!.warmupSeconds, 60, accuracy: 0.001)
    }

    func testSkipShortensPhaseAndSkippingCooldownCompletes() {
        var e = WatchWorkoutEngine.start(plan: plan, now: t0)!
        e.skip(now: t0 + 15)                       // leave warm-up early
        XCTAssertEqual(e.phase, .highIntensity)
        XCTAssertEqual(e.timeRemaining(asOf: t0 + 15), 120, accuracy: 0.001)
        e.reconcile(now: t0 + 15 + 120 + 60 + 120) // into cool-down
        XCTAssertEqual(e.phase, .cooldown)
        e.skip(now: t0 + 15 + 300 + 5)
        XCTAssertTrue(e.isComplete)
        let r = e.completedRecord()!
        XCTAssertTrue(r.cooldownSkipped)
        XCTAssertEqual(r.warmupSeconds, 15, accuracy: 0.001)
        XCTAssertEqual(r.cooldownSeconds, 5, accuracy: 0.001)
    }

    func testSkipWhilePausedMovesOnAndStaysPaused() {
        var e = WatchWorkoutEngine.start(plan: plan, now: t0)!
        e.pause(now: t0 + 10)
        e.skip(now: t0 + 30)
        XCTAssertFalse(e.isRunning)
        XCTAssertEqual(e.phase, .highIntensity)
        XCTAssertEqual(e.timeRemaining(asOf: t0 + 30), 120, accuracy: 0.001)
    }

    func testHeartRateSamplesAreBucketedAndNotRecordedWhilePaused() {
        var e = WatchWorkoutEngine.start(plan: plan, now: t0)!
        e.record(bpm: 120, now: t0 + 1)
        e.record(bpm: 121, now: t0 + 2)     // < 2 s after last: dropped
        e.record(bpm: 122, now: t0 + 3.5)
        e.pause(now: t0 + 4)
        e.record(bpm: 150, now: t0 + 6)     // paused: dropped
        e.resume(now: t0 + 10)
        e.record(bpm: 0, now: t0 + 12)      // garbage: dropped
        e.record(bpm: 130, now: t0 + 12)
        XCTAssertEqual(e.samples.map(\.bpm), [120, 122, 130])
        XCTAssertEqual(e.samples.map(\.t), [1, 3.5, 12])
    }

    func testEngineSurvivesCodableRoundTrip() throws {
        var e = WatchWorkoutEngine.start(plan: plan, now: t0)!
        e.reconcile(now: t0 + 100)
        e.record(bpm: 140, now: t0 + 100)
        e.pause(now: t0 + 110)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let restored = try dec.decode(WatchWorkoutEngine.self, from: try enc.encode(e))
        XCTAssertEqual(restored, e)
        var r = restored
        r.resume(now: t0 + 200)
        r.reconcile(now: t0 + 10_000)
        XCTAssertTrue(r.isComplete)
    }

    func testRecordWireFormatRoundTrips() {
        var e = WatchWorkoutEngine.start(plan: plan, now: t0)!
        e.record(bpm: 150, now: t0 + 5)
        e.reconcile(now: t0 + 10_000)
        let record = e.completedRecord()!
        let data = record.encoded()!
        XCTAssertEqual(CompletedWatchWorkout.decode(data), record)
    }

    func testFallbackPlanIsTheShippedProtocol() {
        let p = WatchWorkoutPlan.fallback
        XCTAssertEqual(p.steps.count, 9)
        XCTAssertEqual(p.totalIntervals, 4)
        let expected: TimeInterval = 300 + 960 + 540 + 300   // warm-up + 4 work + 3 recovery + cool-down
        XCTAssertEqual(p.totalDuration, expected)
        XCTAssertEqual(p.steps.first?.phase, .warmup)
        XCTAssertEqual(p.steps.last?.phase, .cooldown)
        XCTAssertEqual(p.targetRange(for: .highIntensity).low, 0, "no max-HR without the phone")
    }

    // MARK: Projection (phone-led timeline extrapolated on the Watch)

    func testPositionWalksForwardAndReportsCompletion() {
        let end0 = t0 + 60
        XCTAssertEqual(plan.position(index: 0, endTime: end0, at: t0 + 30)?.crossed, 0)
        let p = plan.position(index: 0, endTime: end0, at: t0 + 250)!   // 60+120+60 = 240
        XCTAssertEqual(p.index, 3)
        XCTAssertEqual(p.crossed, 3)
        XCTAssertEqual(p.endTime, t0 + 360)
        XCTAssertNil(plan.position(index: 0, endTime: end0, at: t0 + 420), "past the last step")
        XCTAssertNil(plan.position(index: 9, endTime: end0, at: t0), "bad index")
        XCTAssertEqual(plan.highIntensityCount(through: 3), 2)
    }

    // MARK: Phone import

    private func makeRecord(id: UUID = UUID(), samples: Int = 40) -> CompletedWatchWorkout {
        var e = WatchWorkoutEngine.start(plan: plan, now: recent, id: id)!
        for i in 0..<samples { e.record(bpm: 150 + Double(i % 5), now: recent + Double(i) * 2) }
        e.reconcile(now: recent + 10_000)
        return e.completedRecord()!
    }

    func testImportCreatesEntryWithBreakdownTypeAndHRSummary() {
        let vm = TimerViewModel()
        let before = vm.workoutLogEntries.count
        let record = makeRecord()
        XCTAssertTrue(vm.importWatchWorkout(record))
        XCTAssertEqual(vm.workoutLogEntries.count, before + 1)
        let entry = vm.workoutLogEntries.first { $0.id == record.id }!
        XCTAssertEqual(entry.completedAt.timeIntervalSince1970, (recent + 420).timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(entry.workoutType, .treadmill)
        XCTAssertEqual(entry.sessionBreakdown?.totalDuration ?? 0, 420, accuracy: 0.001)
        XCTAssertEqual(entry.sessionBreakdown?.highIntensityDuration ?? 0, 240, accuracy: 0.001)
        XCTAssertNotNil(entry.hrSummary)
        XCTAssertEqual(entry.hrSummary?.maxBPM, 154)
        XCTAssertNotNil(HeartRateSeriesStore.load(for: record.id))
        HeartRateSeriesStore.delete(for: record.id)
    }

    func testImportIsIdempotent() {
        let vm = TimerViewModel()
        let record = makeRecord()
        XCTAssertTrue(vm.importWatchWorkout(record))
        XCTAssertFalse(vm.importWatchWorkout(record), "re-delivered record must not double-log")
        XCTAssertEqual(vm.workoutLogEntries.filter { $0.id == record.id }.count, 1)
        HeartRateSeriesStore.delete(for: record.id)
    }

    func testImportKeepsLogNewestFirstAndUpdatesStreak() {
        let vm = TimerViewModel()
        let old = makeRecord()                                   // completed ~an hour ago
        // A newer phone-style entry already present.
        let newer = WorkoutLogEntry(completedAt: Date(), workoutType: .run, notes: "")
        vm.workoutLogEntries = [newer]
        vm.importWatchWorkout(old)
        XCTAssertEqual(vm.workoutLogEntries.first?.id, newer.id)
        XCTAssertEqual(vm.workoutLogEntries.last?.id, old.id)
        XCTAssertGreaterThanOrEqual(vm.currentStreak, 1)
        HeartRateSeriesStore.delete(for: old.id)
    }

    func testDiscardRemovesEntryAndBlocksLateCopy() {
        let vm = TimerViewModel()
        let record = makeRecord()
        vm.importWatchWorkout(record)
        vm.discardWatchWorkout(id: record.id)
        XCTAssertFalse(vm.workoutLogEntries.contains { $0.id == record.id })
        XCTAssertFalse(vm.importWatchWorkout(record), "a queued copy arriving after the discard is dropped")
        XCTAssertNil(HeartRateSeriesStore.load(for: record.id))
    }

    func testImportWithFewSamplesHasNoHRSummary() {
        let vm = TimerViewModel()
        let record = makeRecord(samples: 2)
        vm.importWatchWorkout(record)
        defer { HeartRateSeriesStore.delete(for: record.id) }
        XCTAssertNil(vm.workoutLogEntries.first { $0.id == record.id }?.hrSummary)
        XCTAssertEqual(HeartRateSeriesStore.load(for: record.id)?.spans.count, record.spans.count)
        XCTAssertEqual(HeartRateSeriesStore.load(for: record.id)?.samples.count, 2)
    }

    func testImportWithoutHeartRateKeepsTimelineAndCanBeDeletedFromHistory() {
        let vm = TimerViewModel()
        let record = makeRecord(samples: 0)
        vm.importWatchWorkout(record)
        XCTAssertEqual(HeartRateSeriesStore.load(for: record.id)?.spans.count, record.spans.count)
        vm.deleteWorkoutLogEntry(id: record.id)
        XCTAssertNil(HeartRateSeriesStore.load(for: record.id))
        XCTAssertFalse(vm.importWatchWorkout(record), "A deleted import must not return on redelivery")
        XCTAssertTrue(TimerViewModel().workoutLogEntries.isEmpty)
    }
}
