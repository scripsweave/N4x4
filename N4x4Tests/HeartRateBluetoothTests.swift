// HeartRateBluetoothTests.swift
// Unit tests for the pure BLE heart-rate logic: the 0x2A37 packet parser and
// the source aggregator. No CoreBluetooth — these run anywhere.

import XCTest
@testable import N4x4

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
}
