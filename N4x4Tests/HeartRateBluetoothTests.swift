// HeartRateBluetoothTests.swift
// Unit tests for the pure BLE heart-rate logic: the 0x2A37 packet parser and
// the source aggregator. No CoreBluetooth — these run anywhere.

import XCTest
@testable import N4x4

final class WatchHeartRateStreamTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func sample(_ bpm: Double = 160, seconds: Double = 0) -> WatchHeartRateSample {
        WatchHeartRateSample(bpm: bpm, measuredAt: t0.addingTimeInterval(seconds))
    }

    private final class Transport {
        var now = Date(timeIntervalSince1970: 1_000)
        var activated = true
        var reachable = true
        var sent: [[String: Any]] = []
        var contexts: [[String: Any]] = []
        var completions: [(Bool) -> Void] = []
        var scheduled: [(Date, () -> Void)] = []
        var acknowledgements: [WatchHeartRateSample] = []
        lazy var delivery = WatchHeartRateDelivery(
            now: { [unowned self] in now },
            activated: { [unowned self] in activated },
            reachable: { [unowned self] in reachable },
            send: { [unowned self] message, completed in sent.append(message); completions.append(completed) },
            saveContext: { [unowned self] in contexts.append($0) },
            retryLater: { [unowned self] in scheduled.append((now + 2, $0)) },
            acknowledged: { [unowned self] in acknowledgements.append($0) }
        )
        func advance(_ seconds: Double) {
            let end = now + seconds
            while let first = scheduled.firstIndex(where: { $0.0 <= end }) {
                let task = scheduled.remove(at: first)
                now = task.0
                task.1()
            }
            now = end
        }
    }

    func testUnavailableLinkKeepsLatestAndRecoversWithoutReachabilityCallback() {
        let transport = Transport()
        transport.reachable = false
        transport.delivery.receive(sample())
        XCTAssertEqual(transport.contexts.count, 1)
        transport.reachable = true
        transport.advance(2)
        XCTAssertEqual(transport.sent.count, 1)
        transport.completions[0](true)
        XCTAssertEqual(transport.acknowledgements, [sample()])
    }

    func testMissingReplyTimesOutAndRetriesOnceWithOriginalTimestamp() {
        let transport = Transport()
        transport.delivery.receive(sample())
        transport.advance(4)
        XCTAssertEqual(transport.sent.count, 2)
        XCTAssertEqual(WatchHeartRateSample(message: transport.sent[1]), sample())
        transport.advance(20)
        XCTAssertEqual(transport.sent.count, 2, "A silent transport must not spin forever")
        XCTAssertTrue(transport.acknowledgements.isEmpty)
    }

    func testSuccessfulAcknowledgementCancelsTimeoutFallback() {
        let transport = Transport()
        transport.delivery.receive(sample())
        transport.completions[0](true)
        transport.advance(10)
        XCTAssertEqual(transport.sent.count, 1)
        XCTAssertTrue(transport.contexts.isEmpty)
        XCTAssertEqual(transport.acknowledgements, [sample()])
    }

    func testSlowSendCoalescesNewSamplesAndFailureFallsBackToNewest() {
        let transport = Transport()
        transport.delivery.receive(sample())
        transport.now = t0 + 1
        transport.delivery.receive(sample(162, seconds: 1))
        transport.now = t0 + 1.5
        transport.delivery.receive(sample(166, seconds: 1.5))
        XCTAssertEqual(transport.sent.count, 1)
        transport.completions[0](false)
        XCTAssertEqual(transport.sent.count, 2)
        XCTAssertEqual(WatchHeartRateSample(message: transport.sent[1]), sample(166, seconds: 1.5))
        XCTAssertEqual(WatchHeartRateSample(message: transport.contexts[0]), sample(166, seconds: 1.5))
        transport.completions[0](true) // Late callback must not acknowledge the old attempt.
        XCTAssertTrue(transport.acknowledgements.isEmpty)
        transport.completions[1](true)
        XCTAssertEqual(transport.acknowledgements, [sample(166, seconds: 1.5)])
    }

    func testResetCancelsPendingRetryTimeoutAndLateReply() {
        let transport = Transport()
        transport.delivery.receive(sample())
        transport.completions[0](false)
        transport.delivery.reset()
        transport.completions[0](true)
        transport.advance(5)
        transport.delivery.resendLatest()
        XCTAssertEqual(transport.sent.count, 1)
        XCTAssertEqual(transport.contexts.count, 1)
        XCTAssertTrue(transport.acknowledgements.isEmpty)
    }

    func testStaleSampleIsNotResentAfterReconnection() {
        let transport = Transport()
        transport.reachable = false
        transport.delivery.receive(sample())
        transport.advance(10)
        transport.reachable = true
        transport.delivery.resendLatest()
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testActivationAndUnchangedBPMStillDeliverFreshSamples() {
        let transport = Transport()
        transport.activated = false
        transport.delivery.receive(sample())
        XCTAssertTrue(transport.sent.isEmpty)
        XCTAssertTrue(transport.contexts.isEmpty)
        transport.activated = true
        transport.delivery.resendLatest()
        transport.completions[0](true)
        transport.advance(4)
        transport.delivery.receive(sample(seconds: 4))
        XCTAssertEqual(transport.sent.count, 2)
    }

    func testDelayedErrorCannotOverrideNewerContextOrAttempt() {
        let transport = Transport()
        transport.delivery.receive(sample())
        transport.advance(2) // timeout
        transport.now = t0 + 3
        transport.reachable = false
        transport.delivery.receive(sample(170, seconds: 3))
        let count = transport.contexts.count
        transport.completions[0](false)
        XCTAssertEqual(transport.contexts.count, count)
        XCTAssertEqual(WatchHeartRateSample(message: transport.contexts.last!), sample(170, seconds: 3))
    }

    func testInboxRejectsDuplicatesOlderSamplesAndExpiredContext() {
        var inbox = WatchHeartRateInbox()
        let now = t0.addingTimeInterval(5)
        XCTAssertNotNil(inbox.accept(sample(seconds: 3).message, now: now))
        XCTAssertNil(inbox.accept(sample(seconds: 3).message, now: now))
        XCTAssertNil(inbox.accept(sample(seconds: 2).message, now: now))
        XCTAssertNil(inbox.accept(sample(seconds: 4).message, now: t0.addingTimeInterval(20)))
        XCTAssertNotNil(inbox.accept(sample(seconds: 5).message, now: now))
    }

    func testInboxRejectsMissingTimestampFutureDateAndInvalidBPM() {
        var inbox = WatchHeartRateInbox()
        var missing = sample().message
        missing.removeValue(forKey: WatchMessageKey.hrTimestamp)
        XCTAssertNil(inbox.accept(missing, now: t0))
        XCTAssertNil(inbox.accept(sample(seconds: 60).message, now: t0))
        for bpm in [Double.nan, Double.infinity, 0, -10, 100_000] {
            XCTAssertNil(inbox.accept(sample(bpm).message, now: t0))
        }
    }

    func testDelayedDeliveryDoesNotExtendExpiryOrOverridePriority() {
        var inbox = WatchHeartRateInbox()
        var aggregator = HeartRateAggregator()
        let now = t0.addingTimeInterval(8)
        let received = inbox.accept(sample().message, now: now)!
        XCTAssertEqual(aggregator.ingest(bpm: received.bpm, from: .watch, at: received.measuredAt, now: now), 160)
        XCTAssertEqual(aggregator.timeUntilNextExpiry(now: now), 2)
        XCTAssertNil(aggregator.currentValue(now: t0.addingTimeInterval(10)))
        _ = aggregator.ingest(bpm: 170, from: .bluetooth, at: now)
        XCTAssertEqual(aggregator.ingest(bpm: 160, from: .watch, at: now), 170)
    }

    func testDeliveryAndInboxRecoverAfterClockMovesBackwards() {
        let transport = Transport()
        var inbox = WatchHeartRateInbox()
        transport.delivery.receive(sample())
        XCTAssertNotNil(inbox.accept(transport.sent[0], now: t0))
        transport.now = t0.addingTimeInterval(-60)
        transport.delivery.receive(sample(seconds: -60))
        XCTAssertEqual(transport.sent.count, 2)
        XCTAssertNotNil(inbox.accept(transport.sent[1], now: transport.now))
    }
}

final class WatchSessionReliabilityTests: XCTestCase {
    func testIdleAndAlreadyCompletedWorkoutsNeverStartASensorSession() {
        var lifecycle = WatchWorkoutSessionLifecycle()
        XCTAssertNil(lifecycle.preparationFinished())
        XCTAssertNil(lifecycle.desire(sessionStarted: false, complete: false, workoutID: nil))
        XCTAssertNil(lifecycle.desire(sessionStarted: true, complete: true, workoutID: "A"))
    }

    func testStartupWaitsForRecoveryAndAuthorizationAndUsesLatestIntent() {
        var lifecycle = WatchWorkoutSessionLifecycle()
        XCTAssertNil(lifecycle.desire(sessionStarted: true, complete: false, workoutID: "A"))
        XCTAssertNil(lifecycle.desire(sessionStarted: true, complete: false, workoutID: "B"))
        XCTAssertEqual(lifecycle.preparationFinished(), .start(workoutID: "B", token: 1))
        XCTAssertNil(lifecycle.preparationFinished())
        XCTAssertNil(lifecycle.desire(sessionStarted: true, complete: false, workoutID: "B"))
    }

    func testCompletionDuringStartupCleanupCancelsPendingStart() {
        var lifecycle = WatchWorkoutSessionLifecycle()
        _ = lifecycle.desire(sessionStarted: true, complete: false, workoutID: "A")
        XCTAssertNil(lifecycle.desire(sessionStarted: true, complete: true, workoutID: "A"))
        XCTAssertNil(lifecycle.preparationFinished())
    }

    func testRapidRestartWaitsForEndAndIgnoresOldCallbacks() {
        var lifecycle = WatchWorkoutSessionLifecycle()
        _ = lifecycle.preparationFinished()
        XCTAssertEqual(lifecycle.desire(sessionStarted: true, complete: false, workoutID: "A"), .start(workoutID: "A", token: 1))
        XCTAssertEqual(lifecycle.desire(sessionStarted: false, complete: false, workoutID: nil), .stop(token: 1))
        XCTAssertNil(lifecycle.desire(sessionStarted: true, complete: false, workoutID: "B"))
        XCTAssertNil(lifecycle.desire(sessionStarted: true, complete: false, workoutID: "C"))
        XCTAssertEqual(lifecycle.ended(token: 1), .start(workoutID: "C", token: 2))
        XCTAssertNil(lifecycle.ended(token: 1, failed: true))
        XCTAssertNil(lifecycle.desire(sessionStarted: true, complete: false, workoutID: "C"))
    }

    func testFailureDoesNotRestartEveryTimerTickButForegroundCanRetry() {
        var lifecycle = WatchWorkoutSessionLifecycle()
        _ = lifecycle.preparationFinished()
        _ = lifecycle.desire(sessionStarted: true, complete: false, workoutID: "A")
        XCTAssertNil(lifecycle.ended(token: 1, failed: true))
        for _ in 0..<60 {
            XCTAssertNil(lifecycle.desire(sessionStarted: true, complete: false, workoutID: "A"))
        }
        XCTAssertEqual(lifecycle.retry(), .start(workoutID: "A", token: 2))
    }

    func testUnexpectedEndDoesNotFightAnotherWorkoutApp() {
        var lifecycle = WatchWorkoutSessionLifecycle()
        _ = lifecycle.preparationFinished()
        _ = lifecycle.desire(sessionStarted: true, complete: false, workoutID: "A")
        XCTAssertNil(lifecycle.ended(token: 1))
        XCTAssertNil(lifecycle.desire(sessionStarted: true, complete: false, workoutID: "A"))
    }

    func testLateStateContextCannotReopenFinishedWorkout() {
        var inbox = WatchStateInbox()
        XCTAssertTrue(inbox.accept([WatchMessageKey.stateRevision: 10]))
        XCTAssertTrue(inbox.accept([WatchMessageKey.stateRevision: 12, WatchMessageKey.workoutComplete: true]))
        XCTAssertFalse(inbox.accept([WatchMessageKey.stateRevision: 11, WatchMessageKey.isRunning: true]))
        XCTAssertFalse(inbox.accept([WatchMessageKey.stateRevision: 12]))
        XCTAssertFalse(inbox.accept([WatchMessageKey.isRunning: true]))
        XCTAssertTrue(inbox.accept([WatchMessageKey.stateRevision: 13]))
    }

    func testLegacyStateWorksUntilVersionedStateArrives() {
        var inbox = WatchStateInbox()
        XCTAssertTrue(inbox.accept([:]))
        XCTAssertFalse(inbox.accept([WatchMessageKey.stateRevision: "invalid"]))
        XCTAssertFalse(inbox.accept([WatchMessageKey.stateRevision: -1]))
        XCTAssertTrue(inbox.accept([WatchMessageKey.stateRevision: 1]))
        XCTAssertFalse(inbox.accept([:]))
    }

    func testStateRevisionsIncreaseAcrossRelaunchClockCorrectionAndReinstall() {
        let first = WatchStateInbox.nextRevision(after: 0, now: Date(timeIntervalSince1970: 1000))
        let second = WatchStateInbox.nextRevision(after: first, now: Date(timeIntervalSince1970: 900))
        let reinstalled = WatchStateInbox.nextRevision(after: 0, now: Date(timeIntervalSince1970: 1100))
        XCTAssertGreaterThan(second, first)
        XCTAssertGreaterThan(reinstalled, second)
        var inbox = WatchStateInbox()
        let modernRevision: Int64 = 1_790_000_000_000
        XCTAssertTrue(inbox.accept([WatchMessageKey.stateRevision: modernRevision]))
        XCTAssertFalse(inbox.accept([WatchMessageKey.stateRevision: modernRevision - 1]))
        XCTAssertFalse(inbox.accept([WatchMessageKey.stateRevision: 1.5]))
    }

    func testMissingHeartRateRequestsAreBoundedAndStopAfterRecovery() {
        var policy = WatchHeartRateRefreshPolicy()
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(policy.shouldRequest(now: start, workoutActive: false, watchInstalled: true, hasFreshReading: false))
        XCTAssertFalse(policy.shouldRequest(now: start, workoutActive: true, watchInstalled: false, hasFreshReading: false))
        XCTAssertTrue(policy.shouldRequest(now: start, workoutActive: true, watchInstalled: true, hasFreshReading: false))
        for i in 1..<5 {
            XCTAssertFalse(policy.shouldRequest(now: start + Double(i), workoutActive: true, watchInstalled: true, hasFreshReading: false))
        }
        XCTAssertTrue(policy.shouldRequest(now: start + 5, workoutActive: true, watchInstalled: true, hasFreshReading: false))
        XCTAssertFalse(policy.shouldRequest(now: start + 6, workoutActive: true, watchInstalled: true, hasFreshReading: true))
        XCTAssertTrue(policy.shouldRequest(now: start + 20, workoutActive: true, watchInstalled: true, hasFreshReading: false))
    }
}

final class HeartRateMeasurementParserTests: XCTestCase {

    // MARK: - Value formats

    func testParsesUInt8HeartRate() {
        let reading = HeartRateMeasurementParser.parse(Data([0x00, 75]))
        XCTAssertEqual(reading?.bpm, 75)
        XCTAssertEqual(reading?.sensorContact, .notSupported)
        XCTAssertEqual(reading?.rrIntervals, [])
    }

    func testParsesUInt16HeartRateLittleEndian() {
        // 0x00B4 = 180
        let reading = HeartRateMeasurementParser.parse(Data([0x01, 0xB4, 0x00]))
        XCTAssertEqual(reading?.bpm, 180)
    }

    func testParsesUInt16MaxWithoutOverflow() {
        let reading = HeartRateMeasurementParser.parse(Data([0x01, 0xFF, 0xFF]))
        XCTAssertEqual(reading?.bpm, 65535)
        XCTAssertEqual(reading?.isPlausible, false)
    }

    // MARK: - Sensor contact bits (flags bits 1–2)

    func testSensorContactDetected() {
        let reading = HeartRateMeasurementParser.parse(Data([0b0000_0110, 80]))
        XCTAssertEqual(reading?.sensorContact, .detected)
    }

    func testSensorContactNotDetected() {
        let reading = HeartRateMeasurementParser.parse(Data([0b0000_0100, 80]))
        XCTAssertEqual(reading?.sensorContact, .notDetected)
    }

    func testSensorContactNotSupported() {
        for flags: UInt8 in [0b0000_0000, 0b0000_0010] {
            let reading = HeartRateMeasurementParser.parse(Data([flags, 80]))
            XCTAssertEqual(reading?.sensorContact, .notSupported)
        }
    }

    // MARK: - Optional fields and offsets

    func testSkipsEnergyExpendedField() {
        let reading = HeartRateMeasurementParser.parse(Data([0x08, 90, 0x10, 0x27]))
        XCTAssertEqual(reading?.bpm, 90)
        XCTAssertEqual(reading?.rrIntervals, [])
    }

    func testParsesRRIntervals() {
        // 1024/1024 = 1.0 s, 512/1024 = 0.5 s
        let reading = HeartRateMeasurementParser.parse(
            Data([0x10, 65, 0x00, 0x04, 0x00, 0x02]))
        XCTAssertEqual(reading?.bpm, 65)
        XCTAssertEqual(reading?.rrIntervals, [1.0, 0.5])
    }

    func testParsesRRIntervalsAfterEnergyExpended() {
        let reading = HeartRateMeasurementParser.parse(
            Data([0x18, 70, 0x34, 0x12, 0x00, 0x04]))
        XCTAssertEqual(reading?.bpm, 70)
        XCTAssertEqual(reading?.rrIntervals, [1.0])
    }

    func testToleratesTrailingOddByteInRRField() {
        let reading = HeartRateMeasurementParser.parse(
            Data([0x10, 65, 0x00, 0x04, 0x99]))
        XCTAssertEqual(reading?.bpm, 65)
        XCTAssertEqual(reading?.rrIntervals, [1.0])
    }

    // MARK: - Malformed payloads

    func testRejectsEmptyPayload() {
        XCTAssertNil(HeartRateMeasurementParser.parse(Data()))
    }

    func testRejectsFlagsOnlyPayload() {
        XCTAssertNil(HeartRateMeasurementParser.parse(Data([0x00])))
    }

    func testRejectsTruncatedUInt16Value() {
        XCTAssertNil(HeartRateMeasurementParser.parse(Data([0x01, 0x50])))
    }

    func testRejectsTruncatedEnergyExpended() {
        XCTAssertNil(HeartRateMeasurementParser.parse(Data([0x08, 90, 0x10])))
    }

    // MARK: - Data-slice safety

    func testParsesDataSliceWithNonZeroStartIndex() {
        // CoreBluetooth can hand back Data views whose startIndex isn't 0;
        // integer subscripting on the slice would trap if the parser assumed
        // zero-based indices.
        let framed = Data([0xDE, 0xAD, 0x00, 75])
        let slice = framed.dropFirst(2)
        XCTAssertNotEqual(slice.startIndex, 0)
        let reading = HeartRateMeasurementParser.parse(slice)
        XCTAssertEqual(reading?.bpm, 75)
    }

    // MARK: - Plausibility / usability

    func testPlausibilityBounds() {
        XCTAssertEqual(HeartRateMeasurementParser.parse(Data([0x00, 19]))?.isPlausible, false)
        XCTAssertEqual(HeartRateMeasurementParser.parse(Data([0x00, 20]))?.isPlausible, true)
        XCTAssertEqual(HeartRateMeasurementParser.parse(Data([0x00, 250]))?.isPlausible, true)
        XCTAssertEqual(HeartRateMeasurementParser.parse(Data([0x01, 0xFB, 0x00]))?.isPlausible, false) // 251
        XCTAssertEqual(HeartRateMeasurementParser.parse(Data([0x00, 0]))?.isPlausible, false)
    }

    func testContactLossMakesReadingUnusableEvenWhenPlausible() {
        let reading = HeartRateMeasurementParser.parse(Data([0b0000_0100, 140]))
        XCTAssertEqual(reading?.isPlausible, true)
        XCTAssertEqual(reading?.isUsable, false)
    }
}

final class HeartRateAggregatorTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func testSingleWatchSourceIsDisplayed() {
        var agg = HeartRateAggregator()
        XCTAssertEqual(agg.ingest(bpm: 142, from: .watch, at: t0), 142)
    }

    func testBluetoothWinsWhenBothLive() {
        var agg = HeartRateAggregator()
        _ = agg.ingest(bpm: 142, from: .watch, at: t0)
        XCTAssertEqual(agg.ingest(bpm: 150, from: .bluetooth, at: t0), 150)
        // Even when the Watch sample is newer, Bluetooth still wins.
        XCTAssertEqual(agg.ingest(bpm: 143, from: .watch, at: t0.addingTimeInterval(2)), 150)
    }

    func testFallsBackToWatchWhenBluetoothGoesStale() {
        var agg = HeartRateAggregator()
        _ = agg.ingest(bpm: 150, from: .bluetooth, at: t0)
        _ = agg.ingest(bpm: 142, from: .watch, at: t0.addingTimeInterval(8))
        XCTAssertEqual(agg.currentValue(now: t0.addingTimeInterval(11)), 142)
    }

    func testRecoversToBluetoothWhenItComesBack() {
        var agg = HeartRateAggregator()
        _ = agg.ingest(bpm: 142, from: .watch, at: t0)
        XCTAssertEqual(agg.ingest(bpm: 150, from: .bluetooth, at: t0.addingTimeInterval(1)), 150)
    }

    func testAllStaleClearsToNil() {
        var agg = HeartRateAggregator()
        _ = agg.ingest(bpm: 150, from: .bluetooth, at: t0)
        _ = agg.ingest(bpm: 142, from: .watch, at: t0)
        XCTAssertNil(agg.currentValue(now: t0.addingTimeInterval(10)))
    }

    func testFreshnessBoundaryIsExclusive() {
        var agg = HeartRateAggregator()
        _ = agg.ingest(bpm: 150, from: .bluetooth, at: t0)
        XCTAssertEqual(agg.currentValue(now: t0.addingTimeInterval(9.999)), 150)
        XCTAssertNil(agg.currentValue(now: t0.addingTimeInterval(10)))
    }

    func testClockMovingBackwardsReAnchorsInsteadOfPinningForever() {
        var agg = HeartRateAggregator()
        // Sample stamped in the (apparent) future — wall clock then corrected
        // backwards by NTP. Without re-anchoring it would stay fresh forever.
        _ = agg.ingest(bpm: 150, from: .bluetooth, at: t0.addingTimeInterval(100))
        XCTAssertEqual(agg.currentValue(now: t0), 150)   // re-anchored to t0
        XCTAssertEqual(agg.currentValue(now: t0.addingTimeInterval(9)), 150)
        XCTAssertNil(agg.currentValue(now: t0.addingTimeInterval(10)))
    }

    func testLiveSourceDrivesGlyph() {
        var agg = HeartRateAggregator()
        XCTAssertNil(agg.liveSource(now: t0))
        _ = agg.ingest(bpm: 142, from: .watch, at: t0)
        XCTAssertEqual(agg.liveSource(now: t0), .watch)
        _ = agg.ingest(bpm: 150, from: .bluetooth, at: t0)
        XCTAssertEqual(agg.liveSource(now: t0), .bluetooth)
        // Bluetooth stale, Watch refreshed → glyph flips back.
        _ = agg.ingest(bpm: 143, from: .watch, at: t0.addingTimeInterval(11))
        XCTAssertEqual(agg.liveSource(now: t0.addingTimeInterval(11)), .watch)
    }

    func testResetClearsEverything() {
        var agg = HeartRateAggregator()
        _ = agg.ingest(bpm: 150, from: .bluetooth, at: t0)
        agg.reset()
        XCTAssertNil(agg.currentValue(now: t0))
        XCTAssertNil(agg.liveSource(now: t0))
    }

    // MARK: - Configurable source priority (4.7)

    func testDefaultPriorityIsMonitorWatchAirPods() {
        XCTAssertEqual(HeartRateAggregator.defaultPriority, [.bluetooth, .watch, .appleSensor])
    }

    func testAppleSensorIsLowestByDefault() {
        var agg = HeartRateAggregator()
        _ = agg.ingest(bpm: 130, from: .appleSensor, at: t0)
        XCTAssertEqual(agg.currentValue(now: t0), 130)   // alone: AirPods supply the value
        _ = agg.ingest(bpm: 142, from: .watch, at: t0)
        XCTAssertEqual(agg.currentValue(now: t0), 142)   // Watch outranks AirPods
        _ = agg.ingest(bpm: 150, from: .bluetooth, at: t0)
        XCTAssertEqual(agg.currentValue(now: t0), 150)   // monitor outranks all
    }

    func testCustomPriorityReordersArbitration() {
        var agg = HeartRateAggregator(priority: [.appleSensor, .watch, .bluetooth])
        _ = agg.ingest(bpm: 150, from: .bluetooth, at: t0)
        _ = agg.ingest(bpm: 130, from: .appleSensor, at: t0)
        XCTAssertEqual(agg.currentValue(now: t0), 130)
        XCTAssertEqual(agg.liveSource(now: t0), .appleSensor)
    }

    func testFallsBackDownCustomPriorityWhenTopGoesStale() {
        var agg = HeartRateAggregator(priority: [.appleSensor, .bluetooth, .watch])
        _ = agg.ingest(bpm: 130, from: .appleSensor, at: t0)
        _ = agg.ingest(bpm: 150, from: .bluetooth, at: t0.addingTimeInterval(8))
        XCTAssertEqual(agg.currentValue(now: t0.addingTimeInterval(11)), 150)
    }

    func testPriorityRawRoundTrip() {
        let order: [HeartRateAggregator.Source] = [.watch, .appleSensor, .bluetooth]
        let raw = HeartRateAggregator.rawValue(for: order)
        XCTAssertEqual(raw, "watch,airpods,monitor")
        XCTAssertEqual(HeartRateAggregator.priority(fromRaw: raw), order)
    }

    func testPriorityParsingIsDefensive() {
        // Empty and garbage fall back to the default order.
        XCTAssertEqual(HeartRateAggregator.priority(fromRaw: ""), HeartRateAggregator.defaultPriority)
        XCTAssertEqual(HeartRateAggregator.priority(fromRaw: "garbage, ,,"), HeartRateAggregator.defaultPriority)
        // Partial list: named source first, missing ones appended in default
        // order — a future source can never become unreachable.
        XCTAssertEqual(HeartRateAggregator.priority(fromRaw: "airpods"), [.appleSensor, .bluetooth, .watch])
        // Duplicates keep their first position.
        XCTAssertEqual(HeartRateAggregator.priority(fromRaw: "watch,monitor,watch"), [.watch, .bluetooth, .appleSensor])
        // Whitespace tolerated (hand-edited defaults, future sync sources).
        XCTAssertEqual(HeartRateAggregator.priority(fromRaw: " watch , monitor , airpods "), [.watch, .bluetooth, .appleSensor])
    }
}
