import Foundation

/// FIT activity file, not a planned workout. No GPS, distance or speed is
/// invented. Kept independent of HealthKit and the sharing UI for validation.
struct WorkoutFITExport {
    let entry: WorkoutLogEntry
    let series: HeartRateSeries?
    var energyReports: [WorkoutEnergyReport]? = nil
    private static let epoch: Double = 631_065_600 // 1989-12-31 UTC

    private var timeline: (start: Double, end: Double, active: Double, timing: WorkoutActivityTiming?)? {
        let health = entry.healthExport.flatMap { $0.isValid ? $0 : nil }
        guard let start = health?.startTimestamp ?? series?.startedAt.timeIntervalSince1970 else { return nil }
        let end = health?.endTimestamp ?? entry.completedAt.timeIntervalSince1970
        let timing = [health?.activityTiming, series?.activityTiming].compactMap { $0 }
            .first { $0.isValid && abs($0.start - start) < 1 && abs(($0.end ?? 0) - end) < 1 }
        guard let active = timing?.activeDuration ?? entry.sessionBreakdown?.totalDuration ?? health?.expectedActiveDuration,
              start.isFinite, end.isFinite, active.isFinite, active > 0, end > start,
              active <= end - start + 0.001, active < Double(UInt32.max) / 1000, start >= Self.epoch,
              end - Self.epoch < Double(UInt32.max), end - start < Double(UInt32.max) / 1000 else { return nil }
        return (start, end, active, timing)
    }

    var isAvailable: Bool { timeline != nil }

    func data() throws -> Data {
        guard let time = timeline else { throw CocoaError(.fileWriteInapplicableStringEncoding) }
        let sport = entry.workoutType.fitSport
        var file = FITWriter()
        let serial = entry.id.uuidString.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        file.message(0, fields: [.byte(0, 4), .u16(1, 255), .u16(2, 1),
                                .u32(3, max(1, serial), type: 0x8C), .date(4, time.start), .string(8, "N4x4")])

        struct TimedMessage {
            let date: Double
            let order: Int
            let global: UInt16
            let fields: [FITField]
        }
        var messages: [TimedMessage] = []
        // Timestamp-only records retain real session boundaries even without HR.
        for date in [time.start, time.end] {
            messages.append(.init(date: date, order: 1, global: 20, fields: [.date(253, date)]))
        }
        let sampleStart = series.map { abs($0.startedAt.timeIntervalSince1970 - time.start) < 1
            ? time.start : $0.startedAt.timeIntervalSince1970 } ?? time.start
        var heartRates: [(date: Double, bpm: UInt8)] = []
        for sample in series?.samples ?? [] {
            let date = sampleStart + sample.t
            guard sample.t.isFinite, sample.t >= 0, sample.bpm.isFinite, sample.bpm >= 1, sample.bpm <= 254,
                  date >= time.start, date <= time.end else { continue }
            heartRates.append((date, UInt8(sample.bpm.rounded())))
            messages.append(.init(date: date, order: 1, global: 20,
                                  fields: [.date(253, date), .byte(3, UInt8(sample.bpm.rounded()), type: 2)]))
        }
        if let timing = time.timing {
            for segment in timing.segments {
                for (date, type) in [(segment.start, UInt8(0)), (segment.end, UInt8(4))] {
                    messages.append(.init(date: date, order: type == 0 ? 0 : 3, global: 21,
                        fields: [.date(253, date), .byte(0, 0), .byte(1, type), .byte(4, 0, type: 2)]))
                }
            }
        }
        let spans = (series?.spans ?? []).filter {
            $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start
                && sampleStart + $0.start >= time.start && sampleStart + $0.end <= time.end + 0.001
        }
        // Detailed lap active times require a real pause timeline. Older files
        // without it use one aggregate lap with their known session active time.
        let detailed = time.timing != nil && !spans.isEmpty
        let laps: [(start: Double, end: Double, active: Double, intensity: UInt8)] = detailed ? spans.map { span in
            let start = sampleStart + span.start, end = min(time.end, sampleStart + span.end)
            let active = time.timing!.segments.reduce(0.0) { $0 + max(0, min(end, $1.end) - max(start, $1.start)) }
            let intensity: UInt8 = span.kind == "warmup" ? 2 : (span.kind == "cooldown" ? 3 : (span.kind == "recovery" ? 4 : 0))
            return (start, end, active, intensity)
        } : [(time.start, time.end, time.active, UInt8(0))]
        guard laps.count < Int(UInt16.max) else { throw CocoaError(.fileWriteInapplicableStringEncoding) }
        for (index, lap) in laps.enumerated() {
            messages.append(.init(date: lap.end, order: 2, global: 19, fields: [
                .u16(254, UInt16(index)), .date(253, lap.end), .byte(0, 9), .byte(1, 1), .date(2, lap.start),
                .milliseconds(7, lap.end - lap.start), .milliseconds(8, lap.active),
                .byte(23, lap.intensity), .byte(24, 0), .byte(25, sport.sport), .byte(39, sport.subSport)
            ]))
        }
        // Integer FIT timestamps must be chronological after quantization too.
        messages.sort {
            let a = floor($0.date), b = floor($1.date)
            if a != b { return a < b }
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.order < $1.order
        }
        for message in messages { file.message(message.global, fields: message.fields) }
        var session: [FITField] = [.u16(254, 0), .date(253, time.end), .byte(0, 8), .byte(1, 1),
            .date(2, time.start), .byte(5, sport.sport), .byte(6, sport.subSport),
            .milliseconds(7, time.end - time.start), .milliseconds(8, time.active),
            .u16(25, 0), .u16(26, UInt16(laps.count)), .string(110, entry.displayTitle)]
        if let average = heartRates.isEmpty ? nil : heartRates.map({ Double($0.bpm) }).reduce(0, +) / Double(heartRates.count),
           let peak = heartRates.map(\.bpm).max() {
            session += [.byte(16, UInt8(average.rounded()), type: 2), .byte(17, peak, type: 2)]
        }
        let manifestCalories: Double? = time.timing.flatMap { timing in
            guard let reports = energyReports, !reports.isEmpty,
                  reports.allSatisfy({ $0.workoutID == entry.id && $0.finalized && $0.isValid }) else { return nil }
            var seen: Set<UUID> = []
            let samples = reports.flatMap(\.samples).filter { $0.isInside(timing) && seen.insert($0.id).inserted }.sorted { $0.start < $1.start }
            guard !zip(samples, samples.dropFirst()).contains(where: { $0.end > $1.start }) else { return nil }
            return samples.isEmpty ? nil : samples.reduce(0) { $0 + $1.kilocalories }
        }
        let savedCalories = entry.healthExport?.energyContent == .included ? entry.healthExport?.activeEnergyKilocalories : nil
        if let calories = manifestCalories ?? savedCalories,
           calories.isFinite, calories >= 0, calories.rounded() < Double(UInt16.max) {
            session.append(.u16(11, UInt16(calories.rounded())))
        }
        file.message(18, fields: session)
        file.message(34, fields: [.date(253, time.end), .milliseconds(0, time.active),
                                  .u16(1, 1), .byte(2, 0), .byte(3, 26), .byte(4, 1)])
        return file.finished()
    }
}

extension WorkoutType {
    var fitSport: (sport: UInt8, subSport: UInt8) {
        switch self {
        case .run, .hillSprints: return (1, 0)
        case .treadmill: return (1, 1)
        case .cycle: return (2, 0)
        case .rowing: return (15, 14)
        case .elliptical: return (4, 15)
        case .stairs: return (48, 16)
        default: return (62, 0)
        }
    }
}

private struct FITField {
    let number: UInt8
    let type: UInt8
    let bytes: [UInt8]
    static func byte(_ number: UInt8, _ value: UInt8, type: UInt8 = 0) -> Self { .init(number: number, type: type, bytes: [value]) }
    static func u16(_ number: UInt8, _ value: UInt16) -> Self { .init(number: number, type: 0x84, bytes: [UInt8(truncatingIfNeeded: value), UInt8(value >> 8)]) }
    static func u32(_ number: UInt8, _ value: UInt32, type: UInt8 = 0x86) -> Self {
        .init(number: number, type: type, bytes: (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    static func date(_ number: UInt8, _ unix: Double) -> Self { .u32(number, UInt32(floor(unix - 631_065_600))) }
    static func milliseconds(_ number: UInt8, _ seconds: Double) -> Self { .u32(number, UInt32((seconds * 1000).rounded())) }
    static func string(_ number: UInt8, _ text: String) -> Self {
        // UTF-8 prefix must end on a whole scalar; FIT strings are NUL terminated.
        var bytes: [UInt8] = []
        for scalar in text.unicodeScalars {
            let next = Array(String(scalar).utf8)
            if bytes.count + next.count > 240 { break }
            bytes += next
        }
        return .init(number: number, type: 7, bytes: bytes + [0])
    }
}

private struct FITWriter {
    private var payload: [UInt8] = []
    mutating func message(_ global: UInt16, fields: [FITField]) {
        // Reuse local message 0 with an explicit definition each time. This
        // small encoder deliberately avoids compressed timestamps/developer data.
        payload += [0x40, 0, 0, UInt8(truncatingIfNeeded: global), UInt8(global >> 8), UInt8(fields.count)]
        for field in fields { payload += [field.number, UInt8(field.bytes.count), field.type] }
        payload += [0]
        for field in fields { payload += field.bytes }
    }
    func finished() -> Data {
        let size = UInt32(payload.count)
        var header: [UInt8] = [14, 0x20, 0xE2, 0x52] // FIT 2.0, profile 21.218.
        header += (0..<4).map { UInt8(truncatingIfNeeded: size >> ($0 * 8)) }
        header += [46, 70, 73, 84]
        let headerCRC = Self.crc(header)
        header += [UInt8(truncatingIfNeeded: headerCRC), UInt8(headerCRC >> 8)]
        var bytes = header + payload
        let crc = Self.crc(bytes)
        bytes += [UInt8(truncatingIfNeeded: crc), UInt8(crc >> 8)]
        return Data(bytes)
    }
    private static func crc(_ bytes: [UInt8]) -> UInt16 {
        bytes.reduce(UInt16(0)) { initial, byte in
            var crc = initial ^ UInt16(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xA001 : crc >> 1 }
            return crc
        }
    }
}
