// Timestamped, latest-only delivery. Shared so dropped sends and delayed
// callbacks can be tested without HealthKit, WatchConnectivity or a sensor.
import Foundation

struct WatchHeartRateSample: Equatable {
    static let maximumAge: TimeInterval = 10
    let bpm: Double
    let measuredAt: Date

    func isFresh(at now: Date) -> Bool {
        let age = now.timeIntervalSince(measuredAt)
        return bpm.isFinite && (1...300).contains(bpm)
            && age.isFinite && age >= -2 && age < Self.maximumAge
    }

    var message: [String: Any] {
        [WatchMessageKey.messageType: WatchMessageKey.heartRate,
         WatchMessageKey.hrBPM: bpm,
         WatchMessageKey.hrTimestamp: measuredAt.timeIntervalSince1970]
    }

    init(bpm: Double, measuredAt: Date) {
        self.bpm = bpm
        self.measuredAt = measuredAt
    }

    init?(message: [String: Any]) {
        guard message[WatchMessageKey.messageType] as? String == WatchMessageKey.heartRate,
              let bpm = message[WatchMessageKey.hrBPM] as? Double,
              let timestamp = message[WatchMessageKey.hrTimestamp] as? Double,
              timestamp.isFinite else { return nil }
        self.init(bpm: bpm, measuredAt: Date(timeIntervalSince1970: timestamp))
    }
}

/// Live messages, retries and application context can deliver the same sample
/// or arrive out of order. Neither may refresh an old reading's expiry.
struct WatchHeartRateInbox {
    private var lastMeasuredAt: Date?

    mutating func accept(_ message: [String: Any], now: Date) -> WatchHeartRateSample? {
        guard let sample = WatchHeartRateSample(message: message), sample.isFresh(at: now) else { return nil }
        // Recover if the devices' wall clock was moved backwards.
        if let lastMeasuredAt, lastMeasuredAt.timeIntervalSince(now) > 2 {
            self.lastMeasuredAt = nil
        }
        guard lastMeasuredAt.map({ sample.measuredAt > $0 }) ?? true else { return nil }
        lastMeasuredAt = sample.measuredAt
        return sample
    }
}

/// All entry points and transport callbacks run on the main queue. Only the
/// newest sample is retained; there is never a queue of historical live HR.
final class WatchHeartRateDelivery {
    typealias Send = ([String: Any], @escaping () -> Void) -> Void
    private let now: () -> Date
    private let activated: () -> Bool
    private let reachable: () -> Bool
    private let send: Send
    private let saveContext: ([String: Any]) -> Void
    private let retryLater: (@escaping () -> Void) -> Void
    private var latest: WatchHeartRateSample?
    private var generation = 0

    init(now: @escaping () -> Date = Date.init,
         activated: @escaping () -> Bool,
         reachable: @escaping () -> Bool,
         send: @escaping Send,
         saveContext: @escaping ([String: Any]) -> Void,
         retryLater: @escaping (@escaping () -> Void) -> Void) {
        self.now = now
        self.activated = activated
        self.reachable = reachable
        self.send = send
        self.saveContext = saveContext
        self.retryLater = retryLater
    }

    func receive(_ sample: WatchHeartRateSample) {
        if let latest, latest.measuredAt.timeIntervalSince(now()) > 2 {
            reset()
        }
        guard sample.isFresh(at: now()),
              latest.map({ sample.measuredAt > $0.measuredAt }) ?? true else { return }
        latest = sample
        resendLatest()
    }

    func reset() {
        latest = nil
        generation += 1
    }

    /// Used on activation, foreground, reconnection and a phone refresh request.
    func resendLatest() {
        generation += 1
        sendLatest(generation: generation, mayRetry: true)
    }

    private func sendLatest(generation expected: Int, mayRetry: Bool) {
        guard expected == generation, activated(), let sample = latest,
              sample.isFresh(at: now()) else { return }
        guard reachable() else {
            saveContext(sample.message)
            return
        }
        send(sample.message) { [weak self] in
            guard let self, expected == self.generation,
                  self.activated(), sample == self.latest,
                  sample.isFresh(at: self.now()) else { return }
            // A transient send failure used to silently drop this reading.
            self.saveContext(sample.message)
            if mayRetry {
                self.retryLater { [weak self] in
                    self?.sendLatest(generation: expected, mayRetry: false)
                }
            }
        }
    }
}
