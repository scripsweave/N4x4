// HeartRateMeasurementParser.swift
// Pure parser for the Bluetooth SIG Heart Rate Measurement characteristic
// (0x2A37), per the Heart Rate Service 1.0 specification. No CoreBluetooth
// import — fully unit-testable off-device.
//
// Payload layout:
//   byte 0        flags
//     bit 0       HR value format: 0 = UInt8, 1 = UInt16 little-endian
//     bits 1–2    sensor contact: 0b0x = not supported, 0b10 = supported but
//                 no contact, 0b11 = contact detected
//     bit 3       energy-expended field present (UInt16 LE)
//     bit 4       RR-interval fields present (UInt16 LE each, units of 1/1024 s)
//   then          HR value, energy expended (if present), RR intervals (if present)

import Foundation

/// One decoded heart-rate notification from a BLE monitor.
struct HeartRateReading: Equatable {
    enum SensorContact: Equatable {
        case notSupported   // device doesn't report contact — assume it's worn
        case notDetected    // strap is on but not against skin / too dry
        case detected
    }

    let bpm: Int
    let sensorContact: SensorContact
    /// Beat-to-beat intervals in seconds, if the device sends them. Unused in
    /// v1 (future HRV work) but parsing them validates our field offsets.
    let rrIntervals: [Double]

    /// A reading worth displaying and coaching on. 20–250 covers every human
    /// heart rate; anything outside is sensor noise or a device quirk (some
    /// straps send 0 while acquiring a signal).
    var isPlausible: Bool { (20...250).contains(bpm) }

    /// A reading safe to feed the zone engine: plausible AND not from a strap
    /// that reports it has lost skin contact (those readings are garbage and
    /// would fire false "push harder" alerts).
    var isUsable: Bool { isPlausible && sensorContact != .notDetected }
}

enum HeartRateMeasurementParser {

    /// Returns nil for structurally malformed payloads (too short for what the
    /// flags promise). Values that parse but are implausible are returned —
    /// callers filter via `isUsable` — so the UI can still distinguish
    /// "strap talking but no signal yet" from "strap silent".
    static func parse(_ data: Data) -> HeartRateReading? {
        // Copy to a plain array: `Data` from CoreBluetooth can be a slice whose
        // startIndex isn't 0, so raw integer subscripting would trap.
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return nil }

        let flags = bytes[0]
        var offset = 1

        // Heart rate value.
        let bpm: Int
        if flags & 0x01 != 0 {
            guard bytes.count >= offset + 2 else { return nil }
            bpm = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2
        } else {
            guard bytes.count >= offset + 1 else { return nil }
            bpm = Int(bytes[offset])
            offset += 1
        }

        // Sensor contact.
        let contact: HeartRateReading.SensorContact
        switch (flags >> 1) & 0b11 {
        case 0b10: contact = .notDetected
        case 0b11: contact = .detected
        default:   contact = .notSupported
        }

        // Energy expended — skip if present. A device that sets the flag but
        // truncates the field is malformed enough to reject.
        if flags & 0x08 != 0 {
            guard bytes.count >= offset + 2 else { return nil }
            offset += 2
        }

        // RR intervals — as many complete UInt16s as remain. A trailing odd
        // byte is tolerated (ignored) rather than rejecting the whole reading.
        var rrIntervals: [Double] = []
        if flags & 0x10 != 0 {
            while bytes.count >= offset + 2 {
                let raw = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
                rrIntervals.append(Double(raw) / 1024.0)
                offset += 2
            }
        }

        return HeartRateReading(bpm: bpm, sensorContact: contact, rrIntervals: rrIntervals)
    }
}
