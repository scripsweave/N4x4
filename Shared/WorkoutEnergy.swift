import Foundation

// MARK: - Existing Watch energy samples (never recreated on the phone)

struct WorkoutEnergySample: Codable, Equatable {
    let id: UUID
    let start: Double
    let end: Double
    let kilocalories: Double

    var isValid: Bool {
        start.isFinite && end.isFinite && end > start
            && kilocalories.isFinite && kilocalories >= 0
    }

    func isInside(_ timing: WorkoutActivityTiming) -> Bool {
        timing.isValid && timing.segments.contains { start >= $0.start && end <= $0.end }
    }
}

/// One sensor session. A retry/relaunch may create several for the same workout.
/// Numeric dates preserve the original Health sample boundaries across devices.
struct WorkoutEnergyReport: Codable, Equatable, Identifiable {
    let id: UUID
    let workoutID: UUID
    let start: Double
    var end: Double?
    var samples: [WorkoutEnergySample] = []
    var finalized = false

    var isValid: Bool {
        start.isFinite && (end.map { $0.isFinite && $0 >= start } ?? !finalized)
            && samples.count <= 10_000
            && samples.allSatisfy { $0.isValid && $0.start >= start && $0.end <= (end ?? .greatestFiniteMagnitude) }
            && Set(samples.map(\.id)).count == samples.count
    }
}

/// Manifests stay outside the UserDefaults History blob. On Watch these files
/// are also the durable, acknowledged transport queue. On phone they freeze
/// before the first Health write, alongside the export intent.
struct WorkoutEnergyStore {
    static let shared = WorkoutEnergyStore(directory: FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WorkoutEnergy", isDirectory: true))
    let directory: URL

    func reports(for workoutID: UUID) throws -> [WorkoutEnergyReport] {
        let url = directory.appendingPathComponent(workoutID.uuidString + ".json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let reports = try JSONDecoder().decode([WorkoutEnergyReport].self, from: Data(contentsOf: url))
        guard reports.allSatisfy({ $0.workoutID == workoutID && $0.isValid }) else { throw CocoaError(.fileReadCorruptFile) }
        return reports
    }

    func allReports() throws -> [WorkoutEnergyReport] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .flatMap { url -> [WorkoutEnergyReport] in
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return [] }
                return (try? reports(for: id)) ?? [] // Leave corrupt bytes untouched; other workouts still sync.
            }
    }

    func save(_ report: WorkoutEnergyReport) throws {
        guard report.isValid else { throw CocoaError(.fileReadCorruptFile) }
        var reports = try reports(for: report.workoutID)
        if let index = reports.firstIndex(where: { $0.id == report.id }) {
            // A delayed collecting packet cannot replace a sealed manifest.
            if reports[index].finalized { return }
            reports[index] = report
        } else { reports.append(report) }
        try write(reports, for: report.workoutID)
    }

    func remove(sessionID: UUID, workoutID: UUID) throws {
        try write(reports(for: workoutID).filter { $0.id != sessionID }, for: workoutID)
    }

    func delete(for workoutID: UUID) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(workoutID.uuidString + ".json"))
    }

    private func write(_ reports: [WorkoutEnergyReport], for id: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(id.uuidString + ".json")
        if reports.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        } else { try JSONEncoder().encode(reports).write(to: url, options: .atomic) }
    }

    func samples(for id: UUID, timing: WorkoutActivityTiming) throws -> [WorkoutEnergySample]? {
        let reports = try reports(for: id)
        guard !reports.isEmpty, reports.allSatisfy(\.finalized) else { return nil }
        var seen: Set<UUID> = []
        let samples = reports.flatMap(\.samples).filter { $0.isInside(timing) && seen.insert($0.id).inserted }
            .sorted { $0.start < $1.start }
        // Overlapping sensors/restarts must never double-count active energy.
        for (a, b) in zip(samples, samples.dropFirst()) where a.end > b.start {
            throw CocoaError(.fileReadCorruptFile)
        }
        return samples
    }
}
