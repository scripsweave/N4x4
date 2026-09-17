// TimerViewModel.swift

import SwiftUI
import Combine
import AVFoundation
import CoreHaptics
import UserNotifications
import HealthKit
import ActivityKit
import StoreKit
#if canImport(UIKit)
import UIKit
#endif

// Small system boundaries let tests hold an in-flight add/update open and prove
// that End wins the race. All workout lifecycle decisions remain in the VM.
protocol IntervalNotificationCenter {
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: IntervalNotificationCenter {}

protocol WorkoutLiveActivityHandle {
    var id: String { get }
    func updateWorkout(_ state: N4x4LiveActivityAttributes.ContentState) async
    func endWorkout() async
}

extension Activity: WorkoutLiveActivityHandle where Attributes == N4x4LiveActivityAttributes {
    func updateWorkout(_ state: N4x4LiveActivityAttributes.ContentState) async {
        await update(.init(state: state, staleDate: nil))
    }

    func endWorkout() async {
        await end(nil, dismissalPolicy: .immediate)
    }
}

protocol WorkoutLiveActivityProvider {
    var activities: [any WorkoutLiveActivityHandle] { get }
    var areActivitiesEnabled: Bool { get }
    func request(start: Date, state: N4x4LiveActivityAttributes.ContentState) throws -> any WorkoutLiveActivityHandle
}

struct SystemWorkoutLiveActivityProvider: WorkoutLiveActivityProvider {
    var activities: [any WorkoutLiveActivityHandle] { Activity<N4x4LiveActivityAttributes>.activities }
    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func request(start: Date, state: N4x4LiveActivityAttributes.ContentState) throws -> any WorkoutLiveActivityHandle {
        try Activity<N4x4LiveActivityAttributes>.request(
            attributes: .init(workoutStartTime: start),
            content: .init(state: state, staleDate: nil), pushType: nil)
    }
}

enum PermissionState: Equatable {
    case unknown
    case notDetermined
    case granted
    case denied
    case unavailable

    var diagnosticLabel: String {
        switch self {
        case .unknown:       return "unknown"
        case .notDetermined: return "not asked yet"
        case .granted:       return "granted"
        case .denied:        return "denied"
        case .unavailable:   return "unavailable on this device"
        }
    }
}

enum AudioMode: String, CaseIterable, Identifiable {
    case voice  = "Voice Prompts"
    case alarm  = "Alarm"
    case silent = "Silent"
    var id: String { rawValue }
}

enum WorkoutReminderMode: String, CaseIterable, Identifiable {
    case weeklyWeekday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weeklyWeekday: return "Weekly on weekday"
        }
    }
}



enum WorkoutType: String, CaseIterable, Identifiable, Codable {
    case norwegian4x4 = "Norwegian 4x4"
    case run = "Run"
    case cycle = "Cycle"
    case kettlebell = "Kettlebells"
    case rowing = "Rowing"
    case treadmill = "Treadmill"
    case hillSprints = "Hill sprints"
    case stairs = "Stairs"
    case jumpRope = "Jump rope"
    case circuit = "Circuit"
    case sports = "Sports"
    case other = "Other"

    var id: String { rawValue }

    /// The list offered in pickers (post-workout Type and Settings default).
    /// `norwegian4x4` names the protocol, not an exercise — it stays in the
    /// enum only so logs saved before 4.5 still decode and display.
    static var selectableCases: [WorkoutType] {
        allCases.filter { $0 != .norwegian4x4 }
    }

    /// Modality used to choose the performance metric (speed vs cadence vs level).
    /// Every type maps to one so the performance section is always available;
    /// abstract types fall back to `.other` (speed).
    var trainingModality: TrainingModality {
        switch self {
        case .treadmill:               return .treadmill
        case .run, .hillSprints:       return .outdoorRun
        case .cycle:                   return .bike
        case .kettlebell:              return .kettlebell
        case .rowing:                  return .rowing
        case .stairs:                  return .stairClimber
        case .norwegian4x4, .jumpRope, .circuit, .sports, .other:
                                       return .other
        }
    }
}

struct WorkoutSessionBreakdown: Codable, Equatable {
    let totalDuration: TimeInterval
    let warmupDuration: TimeInterval
    let highIntensityDuration: TimeInterval
    let recoveryDuration: TimeInterval
    let cooldownDuration: TimeInterval
    let cooldownSkipped: Bool

    enum CodingKeys: String, CodingKey {
        case totalDuration
        case warmupDuration
        case highIntensityDuration
        case recoveryDuration
        case cooldownDuration
        case cooldownSkipped
    }

    init(
        totalDuration: TimeInterval,
        warmupDuration: TimeInterval,
        highIntensityDuration: TimeInterval,
        recoveryDuration: TimeInterval,
        cooldownDuration: TimeInterval,
        cooldownSkipped: Bool
    ) {
        self.totalDuration = totalDuration
        self.warmupDuration = warmupDuration
        self.highIntensityDuration = highIntensityDuration
        self.recoveryDuration = recoveryDuration
        self.cooldownDuration = cooldownDuration
        self.cooldownSkipped = cooldownSkipped
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .totalDuration) ?? 0
        warmupDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .warmupDuration) ?? 0
        highIntensityDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .highIntensityDuration) ?? 0
        recoveryDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .recoveryDuration) ?? 0
        cooldownDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .cooldownDuration) ?? 0
        cooldownSkipped = try container.decodeIfPresent(Bool.self, forKey: .cooldownSkipped) ?? false
    }
}

struct WorkoutLogEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let completedAt: Date
    let workoutType: WorkoutType
    let notes: String
    let sessionBreakdown: WorkoutSessionBreakdown?
    // Performance logging. Optional so older logs (encoded before this existed)
    // decode with these as nil — synthesized Codable maps missing keys to nil.
    let modality: TrainingModality?
    var intervalPerformances: [IntervalPerformance]?
    /// Inline heart-rate stats; the full series lives in HeartRateSeriesStore
    /// keyed by `id`. Optional for the same backward-compat reason as above.
    let hrSummary: HRSessionSummary?
    /// Missing on older records, which retain their original streak eligibility.
    let endedEarly: Bool?
    var countsTowardStreak: Bool { endedEarly != true }

    init(
        id: UUID = UUID(),
        completedAt: Date = Date(),
        workoutType: WorkoutType,
        notes: String,
        sessionBreakdown: WorkoutSessionBreakdown? = nil,
        modality: TrainingModality? = nil,
        intervalPerformances: [IntervalPerformance]? = nil,
        hrSummary: HRSessionSummary? = nil,
        endedEarly: Bool? = nil
    ) {
        self.id = id
        self.completedAt = completedAt
        self.workoutType = workoutType
        self.notes = notes
        self.sessionBreakdown = sessionBreakdown
        self.modality = modality
        self.intervalPerformances = intervalPerformances
        self.hrSummary = hrSummary
        self.endedEarly = endedEarly
    }

    /// Average of the logged primary values for this entry, ignoring blanks.
    var averagePrimaryPerformance: Double? {
        let values = (intervalPerformances ?? []).compactMap { $0.primary }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var weekOfYear: Int {
        Calendar.current.component(.weekOfYear, from: completedAt)
    }

    var year: Int {
        // Use yearForWeekOfYear (not .year) so the ISO week year matches weekOfYear.
        // Without this, Dec 29–31 in ISO week 1 of the next year gets year N-1, week 1 —
        // causing year-boundary streaks to break.
        Calendar.current.component(.yearForWeekOfYear, from: completedAt)
    }
}

struct VO2DataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

// MARK: - Training modality

enum TrainingModality: String, CaseIterable, Codable {
    case treadmill    = "Treadmill"
    case outdoorRun   = "Outdoor Run"
    case rowing       = "Rowing Machine"
    case bike         = "Stationary Bike"
    case stairClimber = "Stair Climber"
    case kettlebell   = "Kettlebells"
    case other        = "Other"

    var icon: String {
        switch self {
        case .treadmill:    return "figure.run"
        case .outdoorRun:   return "leaf.fill"
        case .rowing:       return "drop.fill"
        case .bike:         return "bicycle"
        case .stairClimber: return "arrow.up.circle.fill"
        case .kettlebell:   return "figure.strengthtraining.traditional"
        case .other:        return "ellipsis.circle.fill"
        }
    }

    var tagline: String {
        switch self {
        case .treadmill:    return "Precision control"
        case .outdoorRun:   return "The natural way"
        case .rowing:       return "Full body power"
        case .bike:         return "Low impact"
        case .stairClimber: return "Vertical power"
        case .kettlebell:   return "Strength meets cardio"
        case .other:        return "Any cardio works"
        }
    }

    var setup: String {
        switch self {
        case .treadmill:
            return "Set a constant incline of 3–5%. This forces your heart rate up without requiring sprint speeds that are dangerous or hard on joints."
        case .outdoorRun:
            return "Find a long, gentle hill (4–6% grade). If no hills are available, use a flat, unobstructed path with no stops."
        case .rowing:
            return "Set the damper (drag) to 4 or 6. High drag (10) causes muscle failure before heart failure — defeating the purpose."
        case .bike:
            return "Adjust the seat so your leg is almost fully extended at the bottom of the pedal stroke."
        case .stairClimber:
            return "Stand upright. Do not lean your weight onto the side handles — this reduces the load and defeats the purpose."
        case .kettlebell:
            return "Pick a bell you can swing continuously for 4 minutes with solid form — lighter than you think (12–16 kg is a common start). Clear space around you and keep your spine neutral."
        case .other:
            return "Choose any continuous cardio activity — elliptical, swimming, jump rope, cross-trainer. Warm up for 5 minutes at moderate effort before starting intervals."
        }
    }

    var workPhase: String {
        switch self {
        case .treadmill:
            return "Increase speed until you're at a heavy pant. You should be able to hold this for the full 4 minutes without grabbing the rails."
        case .outdoorRun:
            return "Run at a hard-sustainable pace — like a race pace you could only hold for about 10–12 minutes total."
        case .rowing:
            return "Focus on a powerful leg drive. Keep your Stroke Rate (SPM) between 24 and 28."
        case .bike:
            return "Maintain a high, consistent RPM — 80+ on a road bike or 60+ on an Air/Assault bike. Use your arms on an Air Bike to share the load."
        case .stairClimber:
            return "Increase speed until you can't breathe through your nose. Take full, consistent steps — not short choppy ones."
        case .kettlebell:
            return "Swing (or clean, or snatch) at a steady, continuous rhythm — hips drive, arms guide. If your grip or lower back fails before your lungs do, the bell is too heavy."
        case .other:
            return "Push to 85–95% of your max heart rate. Speaking more than a few words should feel impossible. Maintain this intensity for the full 4 minutes."
        }
    }

    var restPhase: String {
        switch self {
        case .treadmill:
            return "Reduce to a slow walk (2.5–3.0 mph). Keep the incline up to make the transition back to work easier."
        case .outdoorRun:
            return "Turn around and walk or jog slowly back down the hill. Movement must stay continuous."
        case .rowing:
            return "Keep the handle moving with very light tension. Focus on deep, rhythmic belly breaths."
        case .bike:
            return "Pedal very slowly with zero resistance. Do not stop moving your legs."
        case .stairClimber:
            return "Drop the machine to Level 1 or 2. Focus on standing tall to open up your lungs."
        case .kettlebell:
            return "Park the bell and keep walking — march in place, shake out your arms and grip, breathe deeply. Don't sit down."
        case .other:
            return "Drop to 60–70% max heart rate — a pace where you can speak in short sentences. Keep moving; don't stop completely."
        }
    }

    var workoutType: WorkoutType {
        switch self {
        case .treadmill:    return .treadmill
        case .outdoorRun:   return .run
        case .rowing:       return .rowing
        case .bike:         return .cycle
        case .stairClimber: return .stairs
        case .kettlebell:   return .kettlebell
        case .other:        return .other
        }
    }

    /// The performance metric logged per work interval for this modality.
    /// v1 surfaces only the primary; the descriptor is the single place to add
    /// per-modality metrics (and, later, a secondary) without touching the UI.
    var performanceMetric: ModalityMetric {
        switch self {
        case .treadmill, .outdoorRun, .other:
            // Distance-based: stored canonically in km/h, displayed per unit pref.
            return ModalityMetric(label: "Speed", unit: "km/h", step: 0.5, range: 1...25,
                                  imperialUnit: "mph", imperialStep: 0.5, imperialRange: 0.5...16)
        case .bike:
            return ModalityMetric(label: "Cadence", unit: "RPM", step: 1, range: 30...130,
                                  imperialUnit: nil, imperialStep: nil, imperialRange: nil)
        case .rowing:
            return ModalityMetric(label: "Stroke rate", unit: "SPM", step: 1, range: 14...40,
                                  imperialUnit: nil, imperialStep: nil, imperialRange: nil)
        case .stairClimber:
            return ModalityMetric(label: "Level", unit: "level", step: 1, range: 1...20,
                                  imperialUnit: nil, imperialStep: nil, imperialRange: nil)
        case .kettlebell:
            return ModalityMetric(label: "Reps", unit: "reps", step: 5, range: 10...250,
                                  imperialUnit: nil, imperialStep: nil, imperialRange: nil)
        }
    }
}

// MARK: - Performance logging

/// A logged performance value for a single work interval. `primary` is stored in
/// the modality's canonical unit (km/h for speed); `secondary` is reserved for a
/// future second metric (e.g. incline) and is not surfaced in v1.
struct IntervalPerformance: Codable, Equatable, Identifiable {
    var id: UUID
    var intervalNumber: Int   // 1-based work-interval index
    var primary: Double?
    var secondary: Double?
    /// Free-text per-interval note ("incline 4, felt strong"). Optional so
    /// pre-existing logs decode with it nil.
    var note: String?

    init(id: UUID = UUID(), intervalNumber: Int, primary: Double? = nil,
         secondary: Double? = nil, note: String? = nil) {
        self.id = id
        self.intervalNumber = intervalNumber
        self.primary = primary
        self.secondary = secondary
        self.note = note
    }
}

/// Describes the metric a modality logs: label, native (metric) unit + stepper
/// bounds, and optional imperial equivalents. `localeConverted` metrics (speed)
/// are stored canonically and converted for display; others (RPM, level) are not.
struct ModalityMetric: Equatable {
    let label: String
    let unit: String
    let step: Double
    let range: ClosedRange<Double>
    let imperialUnit: String?
    let imperialStep: Double?
    let imperialRange: ClosedRange<Double>?

    var localeConverted: Bool { imperialUnit != nil }
}

/// User preference for displayed units. `system` follows the device locale.
enum UnitPreference: String, CaseIterable, Identifiable, Codable {
    case system, metric, imperial
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system:   return "System"
        case .metric:   return "Metric"
        case .imperial: return "Imperial"
        }
    }
}

/// Pure unit conversion for canonical (metric) speed storage. Kept free of any
/// view-model state so it is trivially unit-testable.
enum PerformanceUnits {
    /// 1 mph in km/h.
    static let kmhPerMph = 1.609344
    static func kmhToMph(_ kmh: Double) -> Double { kmh / kmhPerMph }
    static func mphToKmh(_ mph: Double) -> Double { mph * kmhPerMph }
}

// MARK: - VO₂ max goal

enum BiologicalSex: String, CaseIterable {
    case male   = "Male"
    case female = "Female"
}

enum VO2TargetTier: String, CaseIterable {
    case good    = "Good"
    case amazing = "Amazing"
    case elite   = "Elite"

    var description: String {
        switch self {
        case .good:    return "Above average — a solid fitness baseline."
        case .amazing: return "Excellent cardio health, well ahead of most people."
        case .elite:   return "Top-tier athletic endurance."
        }
    }

    var symbolName: String {
        switch self {
        case .good:    return "checkmark.circle.fill"
        case .amazing: return "star.circle.fill"
        case .elite:   return "trophy.circle.fill"
        }
    }
}

class TimerViewModel: ObservableObject {
    static let minimumSupportedAge = 13
    static let maximumSupportedAge = 100
    private static let missedWorkoutFollowUpIdentifierPrefix = "workoutReminderFollowup_"
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private func missedWorkoutFollowUpIdentifier(for weekday: Int) -> String {
        return Self.missedWorkoutFollowUpIdentifierPrefix + "\(weekday)"
    }

    private func morningOfReminderIdentifier(for weekday: Int) -> String {
        return "workoutReminderMorningOf_\(weekday)"
    }

    // User settings stored in UserDefaults
    @AppStorage("numberOfIntervals") var numberOfIntervals: Int = 4 {
        didSet {
            let sanitized = max(1, numberOfIntervals)
            if sanitized != numberOfIntervals {
                numberOfIntervals = sanitized
                return
            }
            guard oldValue != numberOfIntervals else { return }
            updatePlanForNextWorkout()
        }
    }
    @AppStorage("warmupDuration") var warmupDuration: TimeInterval = 5 * 60 {
        didSet {
            guard oldValue != warmupDuration else { return }
            updatePlanForNextWorkout()
        }
    }
    @AppStorage("highIntensityDuration") var highIntensityDuration: TimeInterval = 4 * 60 {
        didSet {
            guard oldValue != highIntensityDuration else { return }
            updatePlanForNextWorkout()
        }
    }
    @AppStorage("restDuration") var restDuration: TimeInterval = 3 * 60 {
        didSet {
            guard oldValue != restDuration else { return }
            updatePlanForNextWorkout()
        }
    }
    @AppStorage("cooldownEnabled") var cooldownEnabled: Bool = true {
        didSet {
            guard oldValue != cooldownEnabled else { return }
            updatePlanForNextWorkout()
        }
    }
    @AppStorage("cooldownDuration") var cooldownDuration: TimeInterval = 3 * 60 {
        didSet {
            let sanitized = max(60, min(600, cooldownDuration))
            if sanitized != cooldownDuration {
                cooldownDuration = sanitized
                return
            }
            guard oldValue != cooldownDuration else { return }
            updatePlanForNextWorkout()
        }
    }
    @AppStorage("alarmEnabled") var alarmEnabled: Bool = true
    @AppStorage("audioModeRaw") private var audioModeRaw: String = AudioMode.voice.rawValue
    @AppStorage("halfwayVoicePromptsEnabled") var halfwayVoicePromptsEnabled: Bool = true
    @AppStorage("tenSecondVoicePromptsEnabled") var tenSecondVoicePromptsEnabled: Bool = true
    @AppStorage("confirmSkipCooldown") var confirmSkipCooldown: Bool = true
    @AppStorage("confirmSkipOtherIntervals") var confirmSkipOtherIntervals: Bool = false

    var audioMode: AudioMode {
        get { AudioMode(rawValue: audioModeRaw) ?? .alarm }
        set { audioModeRaw = newValue.rawValue }
    }

    @AppStorage("preventSleep") var preventSleep: Bool = true {
        didSet { updateIdleTimerState() }
    }
    // Interval haptics run on BOTH iPhone and Apple Watch and are independent
    // of the audio mode. Mirrored to the Watch like the zone-haptic setting.
    @AppStorage("hapticsEnabled") var hapticsEnabled: Bool = true {
        didSet { broadcastStateToWatch() }
    }
    @AppStorage("liveActivitiesEnabled") var liveActivitiesEnabled: Bool = true {
        didSet {
            guard oldValue != liveActivitiesEnabled else { return }
            if liveActivitiesEnabled {
                startLiveActivity()
            } else {
                endLiveActivity()
            }
        }
    }

    // Heart-rate zone alerts (require a paired Apple Watch streaming HR).
    // Visual = colour-code the HR readout; Haptic = wrist taps on the Watch;
    // Voice = spoken cue on the phone. Any combination. Rate-limited to one
    // nudge per minute, with a settling window after each interval starts.
    @AppStorage("zoneVisualAlertsEnabled") var zoneVisualAlertsEnabled: Bool = true
    @AppStorage("zoneHapticAlertsEnabled") var zoneHapticAlertsEnabled: Bool = true {
        didSet { broadcastStateToWatch() }
    }
    @AppStorage("zoneVoiceAlertsEnabled") var zoneVoiceAlertsEnabled: Bool = false

    // AirPods Pro 3 (and future Apple sensors) stream heart rate only through
    // an iOS 26 HKWorkoutSession on the iPhone — they don't broadcast the
    // standard Bluetooth HR profile. Opt-in because enabling it runs a system
    // workout session and prompts for HealthKit heart-rate access.
    @AppStorage("appleSensorHREnabled") var appleSensorHREnabled: Bool = false {
        didSet {
            guard oldValue != appleSensorHREnabled else { return }
            if appleSensorHREnabled {
                if #available(iOS 26.0, *) {
                    phoneWorkoutSession.requestAuthorization { [weak self] granted in
                        guard let self, granted else { return }
                        // Enabled mid-workout: attach right away.
                        if self.workoutStartDate != nil {
                            self.startPhoneWorkoutSessionIfNeeded()
                        }
                    }
                }
            } else {
                stopPhoneWorkoutSessionIfActive()
            }
        }
    }

    /// Heart-rate source priority as stored raw ("monitor,watch,airpods").
    /// Empty = default order. See HeartRateAggregator.priority(fromRaw:).
    @AppStorage("hrSourcePriorityRaw") var hrSourcePriorityRaw: String = "" {
        didSet {
            guard oldValue != hrSourcePriorityRaw else { return }
            heartRateAggregator.priority = HeartRateAggregator.priority(fromRaw: hrSourcePriorityRaw)
            // Re-arbitrate immediately so the displayed value follows the new order.
            currentHeartRate = heartRateAggregator.currentValue(now: Date())
        }
    }

    var heartRateSourcePriority: [HeartRateAggregator.Source] {
        get { HeartRateAggregator.priority(fromRaw: hrSourcePriorityRaw) }
        set { hrSourcePriorityRaw = HeartRateAggregator.rawValue(for: newValue) }
    }

    // Units for displayed/entered performance values. `system` follows the
    // device locale; metric/imperial force a choice.
    @AppStorage("unitPreference") private var unitPreferenceRaw: String = UnitPreference.system.rawValue
    var unitPreference: UnitPreference {
        get { UnitPreference(rawValue: unitPreferenceRaw) ?? .system }
        set { unitPreferenceRaw = newValue.rawValue }
    }
    /// Whether distance-based metrics (speed/pace) display in imperial units.
    var usesImperialUnits: Bool {
        switch unitPreference {
        case .metric:   return false
        case .imperial: return true
        case .system:
            // Deployment target is iOS 17.5+, so measurementSystem (iOS 16+) is
            // always available — no need for the deprecated usesMetricSystem.
            return Locale.current.measurementSystem != .metric
        }
    }

    @AppStorage("useCustomMaxHR") var useCustomMaxHR: Bool = false
    @AppStorage("customMaxHR") var customMaxHR: Int = 0
    @AppStorage("userAge") var userAge: Int = 40 {
        didSet {
            let sanitized = max(Self.minimumSupportedAge, min(Self.maximumSupportedAge, userAge))
            if sanitized != userAge {
                userAge = sanitized
                return
            }
            guard oldValue != userAge else { return }
        }
    }

    @AppStorage("userBiologicalSexRaw") var userBiologicalSexRaw: String = BiologicalSex.male.rawValue
    @AppStorage("vo2TargetTierRaw") var vo2TargetTierRaw: String = ""

    var userBiologicalSex: BiologicalSex {
        get { BiologicalSex(rawValue: userBiologicalSexRaw) ?? .male }
        set { userBiologicalSexRaw = newValue.rawValue }
    }

    var vo2TargetTier: VO2TargetTier? {
        get { VO2TargetTier(rawValue: vo2TargetTierRaw) }
        set { vo2TargetTierRaw = newValue?.rawValue ?? "" }
    }

    /// The target VO₂ max value (mL/kg/min) for the user's age, sex, and chosen tier.
    var vo2MaxTarget: Double? {
        guard let tier = vo2TargetTier else { return nil }
        return Self.vo2TargetValue(age: userAge, sex: userBiologicalSex, tier: tier)
    }

    /// Lookup table — thresholds (mL/kg/min) by age group, sex, and tier.
    /// Sources: ACSM Guidelines for Exercise Testing and Prescription.
    static func vo2TargetValue(age: Int, sex: BiologicalSex, tier: VO2TargetTier) -> Double {
        let ageGroup: Int
        switch age {
        case ..<30:   ageGroup = 0
        case 30..<40: ageGroup = 1
        case 40..<50: ageGroup = 2
        case 50..<60: ageGroup = 3
        case 60..<70: ageGroup = 4
        default:      ageGroup = 5
        }

        // [ageGroup][tier: good / amazing / elite]
        let table: [[Double]]
        switch sex {
        case .male:
            table = [
                [42, 52, 60], // <30
                [40, 49, 57], // 30–39
                [37, 45, 53], // 40–49
                [34, 41, 49], // 50–59
                [31, 37, 45], // 60–69
                [28, 33, 41], // 70+
            ]
        case .female:
            table = [
                [33, 41, 50], // <30
                [31, 38, 46], // 30–39
                [28, 35, 43], // 40–49
                [25, 31, 39], // 50–59
                [22, 28, 35], // 60–69
                [20, 25, 32], // 70+
            ]
        }

        let tierIndex: Int
        switch tier {
        case .good:    tierIndex = 0
        case .amazing: tierIndex = 1
        case .elite:   tierIndex = 2
        }
        return table[ageGroup][tierIndex]
    }

    @AppStorage("preferredModalityRaw") var preferredModalityRaw: String = ""

    var preferredModality: TrainingModality? {
        get { TrainingModality(rawValue: preferredModalityRaw) }
        set { preferredModalityRaw = newValue?.rawValue ?? "" }
    }

    /// The workout type pre-selected when logging a completed session,
    /// changeable in Settings. Empty for users who onboarded before this
    /// existed — `resolvedDefaultWorkoutType` then falls back to their
    /// onboarding modality choice.
    @AppStorage("defaultWorkoutTypeRaw") var defaultWorkoutTypeRaw: String = ""

    var defaultWorkoutType: WorkoutType? {
        get { WorkoutType(rawValue: defaultWorkoutTypeRaw) }
        set { defaultWorkoutTypeRaw = newValue?.rawValue ?? "" }
    }

    var resolvedDefaultWorkoutType: WorkoutType {
        defaultWorkoutType ?? preferredModality?.workoutType ?? .other
    }

    /// Single entry point for choosing how the user trains (onboarding and
    /// Settings both funnel through here) so the modality-driven guidance and
    /// the default log type never disagree.
    func setPreferredModality(_ modality: TrainingModality?) {
        preferredModality = modality
        defaultWorkoutType = modality?.workoutType
        if !isRunning && !showPostWorkoutSummary {
            selectedWorkoutType = resolvedDefaultWorkoutType
        }
    }

    /// Settings counterpart: picking a default workout type also retargets the
    /// modality so exercise guidance (Tips, onboarding) follows along.
    func setDefaultWorkoutType(_ type: WorkoutType) {
        defaultWorkoutType = type
        preferredModality = type.trainingModality
        if !isRunning && !showPostWorkoutSummary {
            selectedWorkoutType = type
        }
    }

    // Interval notifications
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = false {
        didSet {
            guard oldValue != notificationsEnabled else { return }
            if notificationsEnabled {
                ensureNotificationPermissionForToggles()
            } else {
                cancelIntervalNotifications()
                cancelRecoveryNudge()
            }
        }
    }
    @AppStorage("notificationPermissionRequested") var notificationPermissionRequested: Bool = false

    // Streak tracking
    @AppStorage("currentStreak") var currentStreak: Int = 0
    @AppStorage("longestStreak") var longestStreak: Int = 0
    @AppStorage("hasMadeCommitment") var hasMadeCommitment: Bool = false
    @AppStorage("committedWeeks") var committedWeeks: Int = 5  // Default 5-week commitment

    // Reminder notifications - now supports multiple days per week
    @AppStorage("workoutRemindersEnabled") var workoutRemindersEnabled: Bool = false {
        didSet {
            guard oldValue != workoutRemindersEnabled else { return }
            if workoutRemindersEnabled {
                raiseFamilyFlagsIfAllOff()
                ensureNotificationPermissionForToggles()
                ensureDefaultReminderSelection()
                reminderActivationDate = Date()
                scheduleWorkoutReminder()
            } else {
                cancelWorkoutReminder()
                cancelRecoveryNudge()
                reminderActivationDate = nil
            }
        }
    }
    // Per-family reminder toggles under the workoutRemindersEnabled master:
    // night-before (8pm), morning-of (8am), comeback nudges (daily 10am after a
    // missed day). The master follows the three — all off turns it off, any on
    // turns it on — so existing master-gated logic (recovery nudge, onboarding)
    // keeps working unchanged.
    @AppStorage("nightBeforeReminderEnabled") var nightBeforeReminderEnabled: Bool = true {
        didSet {
            guard oldValue != nightBeforeReminderEnabled else { return }
            reminderFamilyToggleChanged()
        }
    }
    @AppStorage("morningOfReminderEnabled") var morningOfReminderEnabled: Bool = true {
        didSet {
            guard oldValue != morningOfReminderEnabled else { return }
            reminderFamilyToggleChanged()
        }
    }
    @AppStorage("comebackNudgesEnabled") var comebackNudgesEnabled: Bool = true {
        didSet {
            guard oldValue != comebackNudgesEnabled else { return }
            reminderFamilyToggleChanged()
        }
    }

    /// Suppresses the family didSets while code (master didSet, migration,
    /// reset) writes the flags to keep the master == any-family-on invariant —
    /// only direct user toggles may drive derivation.
    private var isSyncingReminderFamilies = false

    private func reminderFamilyToggleChanged() {
        guard !isSyncingReminderFamilies else { return }
        let anyOn = nightBeforeReminderEnabled || morningOfReminderEnabled || comebackNudgesEnabled
        if anyOn != workoutRemindersEnabled {
            // The master's didSet cancels everything or schedules the enabled
            // families, so nothing more to do here.
            workoutRemindersEnabled = anyOn
        } else if workoutRemindersEnabled {
            // Master unchanged but the family mix did — rebuild the pending set
            // once the permission state is current (see AGENTS.md async rule).
            refreshNotificationPermissionState { [weak self] in
                self?.scheduleWorkoutReminder()
            }
        }
    }

    /// Invariant: workoutRemindersEnabled == (any family flag on). Called when
    /// the master turns on through a path that bypasses the family toggles
    /// (onboarding, old callers) while every family is off — enabling the
    /// master must enable something.
    private func raiseFamilyFlagsIfAllOff() {
        guard !nightBeforeReminderEnabled, !morningOfReminderEnabled, !comebackNudgesEnabled else { return }
        isSyncingReminderFamilies = true
        nightBeforeReminderEnabled = true
        morningOfReminderEnabled = true
        comebackNudgesEnabled = true
        isSyncingReminderFamilies = false
    }

    @AppStorage("workoutReminderDays") var workoutReminderDays: Int = 7 {
        didSet {
            let sanitized = max(1, workoutReminderDays)
            if sanitized != workoutReminderDays {
                workoutReminderDays = sanitized
                return
            }
            guard oldValue != workoutReminderDays else { return }
            if workoutRemindersEnabled {
                scheduleWorkoutReminder()
            }
        }
    }
    @AppStorage("workoutReminderMode") private var workoutReminderModeRaw: String = WorkoutReminderMode.weeklyWeekday.rawValue {
        didSet {
            let sanitized = WorkoutReminderMode(rawValue: workoutReminderModeRaw)?.rawValue ?? WorkoutReminderMode.weeklyWeekday.rawValue
            if sanitized != workoutReminderModeRaw {
                workoutReminderModeRaw = sanitized
                return
            }
            guard oldValue != workoutReminderModeRaw else { return }

            if workoutRemindersEnabled {
                scheduleWorkoutReminder()
            }
        }
    }
    // Store multiple weekdays as comma-separated string (e.g., "1,3,5" for Mon,Wed,Fri)
    @AppStorage("workoutReminderWeekdays") var workoutReminderWeekdays: String = "" {
        didSet {
            guard oldValue != workoutReminderWeekdays else { return }
            // Skip sync if this change came from our own @Published setter (infinite loop prevention)
            guard !isSyncingFromPublished else { return }
            
            // Sync @Published property when AppStorage changes externally
            if workoutReminderWeekdays.isEmpty {
                selectedWeekdaysList = []
            } else {
                selectedWeekdaysList = workoutReminderWeekdays
                    .split(separator: ",")
                    .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    .filter { (1...7).contains($0) }
            }
            if workoutRemindersEnabled, workoutReminderMode == .weeklyWeekday {
                scheduleWorkoutReminder()
            }
        }
    }

    // Flag to prevent circular sync between @Published and @AppStorage
    private var isSyncingFromPublished = false

    @AppStorage("workoutReminderActivationDate") private var workoutReminderActivationDateRaw: String = ""

    private var reminderActivationDate: Date? {
        get {
            guard !workoutReminderActivationDateRaw.isEmpty else { return nil }
            return Self.iso8601Formatter.date(from: workoutReminderActivationDateRaw)
        }
        set {
            workoutReminderActivationDateRaw = newValue.map { Self.iso8601Formatter.string(from: $0) } ?? ""
        }
    }

    // Legacy support for single weekday
    @AppStorage("workoutReminderWeekday") var workoutReminderWeekday: Int = 0 {
        didSet {
            // Migrate legacy single weekday to new format
            if workoutReminderWeekday > 0 && workoutReminderWeekdays.isEmpty {
                workoutReminderWeekdays = String(workoutReminderWeekday)
            }
        }
    }


    @AppStorage("workoutLogEntriesData") private var workoutLogEntriesData: String = "[]"
    @AppStorage("shownMilestonesData") private var shownMilestonesData: String = "[]"
    @Published var workoutLogEntries: [WorkoutLogEntry] = []
    @Published var selectedWorkoutType: WorkoutType = .other {
        didSet {
            guard oldValue != selectedWorkoutType else { return }
            if !isRestoringOrResetting, completedWorkoutEntryID != nil { preparePerformanceDraft() }
            saveReviewEditsIfNeeded()
        }
    }
    @Published var workoutNotesDraft: String = "" {
        didSet { saveReviewEditsIfNeeded() }
    }

    // Performance logging draft (post-workout summary, Phase 2). Values are in
    // the user's DISPLAY units; converted to canonical only at save time.
    /// "Set all" value that stamps every work interval.
    @Published var performanceSetAll: Double? = nil
    /// Free-text note per work interval, parallel to performanceDraft.
    @Published var performanceNotesDraft: [String] = [] {
        didSet { saveReviewEditsIfNeeded() }
    }
    /// One slot per work interval (1..numberOfIntervals). nil = left blank.
    @Published var performanceDraft: [Double?] = [] {
        didSet { saveReviewEditsIfNeeded() }
    }
    @Published var showPostWorkoutSummary: Bool = false
    /// Stable identity from automatic completion save through summary review.
    @Published private(set) var completedWorkoutEntryID: UUID?
    @Published private(set) var activeWorkoutID: UUID?
    @Published var showWorkoutRecovery = false
    @Published private(set) var workoutSaveError: String?
    @Published private(set) var historyRecoveryNotice: String?
    @Published private(set) var hasPendingWorkoutSave = false
    @Published private(set) var sessionEndedEarly = false
    private var isRestoringOrResetting = false
    private var preparedPerformanceType: WorkoutType?
    private var sessionWorkoutType: WorkoutType?
    private var completedSeriesNeedsSave = false
    private var lastCheckpointDate: Date?
    private var lastProgressDate: Date?
    private var unreadableLogData: String?
    private var unreadableCheckpointData: Data?
    var pendingWatchImports: [UUID: CompletedWatchWorkout] = [:]
    private let checkpointURL: URL
    let seriesSaver: (HeartRateSeries, UUID) -> Bool
    private var showHistoryAfterSummaryDismissal = false
    @Published var showWeeklyStreaks: Bool = false
    @Published var showMilestoneCelebration: Bool = false
    @Published var pendingMilestoneCount: Int = 0

    // MARK: - Apple Watch
    let phoneSessionManager = PhoneSessionManager()
    /// Live heart rate from whichever source is currently streaming (Apple
    /// Watch via WatchConnectivity, or a Bluetooth monitor via Core Bluetooth).
    /// nil when every source is stale — the UI shows "—", never a frozen number.
    @Published var currentHeartRate: Double? = nil
    /// Phone-side engine for spoken zone nudges. The Watch runs its own engine
    /// for haptics; the shared logic keeps the two channels consistent.
    private let zoneVoiceEngine = ZoneFeedbackEngine()

    // MARK: - Bluetooth heart rate monitor
    /// Chest straps / armbands. Lazy about permissions: it never touches
    /// CoreBluetooth until the user pairs (or has paired) a monitor.
    let bleHeartRateManager = BluetoothHeartRateManager()
    /// Arbitrates between sources: Bluetooth wins when live, Watch fills in,
    /// stale sources age out (see HeartRateAggregator for the policy).
    private var heartRateAggregator = HeartRateAggregator()

    // MARK: - Phone workout session (AirPods HR, iOS 26+)

    /// Backing store because a stored property can't carry an @available
    /// constraint; created lazily on first use through `phoneWorkoutSession`.
    private var phoneWorkoutSessionStore: AnyObject?

    @available(iOS 26.0, *)
    private var phoneWorkoutSession: PhoneWorkoutSessionManager {
        if let existing = phoneWorkoutSessionStore as? PhoneWorkoutSessionManager {
            return existing
        }
        let manager = PhoneWorkoutSessionManager()
        manager.onReading = { [weak self] bpm in
            self?.ingestHeartRate(bpm, from: .appleSensor)
        }
        phoneWorkoutSessionStore = manager
        return manager
    }

    /// Start the iPhone workout session so AirPods (etc.) stream heart rate.
    /// No-op below iOS 26 or when the user hasn't opted in.
    private func startPhoneWorkoutSessionIfNeeded() {
        guard appleSensorHREnabled else { return }
        if #available(iOS 26.0, *) {
            phoneWorkoutSession.startWorkout()
        }
    }

    private func stopPhoneWorkoutSessionIfActive() {
        guard phoneWorkoutSessionStore != nil else { return }
        if #available(iOS 26.0, *) {
            phoneWorkoutSession.stopWorkout()
        }
    }
    private var heartRateStalenessWork: DispatchWorkItem?

    // Live WatchConnectivity state, mirrored from PhoneSessionManager's delegate
    // callbacks (see updateWatchConnectionState) so SwiftUI can react to it.
    /// An Apple Watch is paired to this iPhone (whether or not our app is on it).
    @Published var watchPaired: Bool = false
    /// Our N4x4 Watch app is installed on the paired Watch.
    @Published var watchAppInstalled: Bool = false
    /// The Watch app is currently reachable (foreground / active session).
    @Published var watchReachable: Bool = false
    var isWatchAppInstalled: Bool { watchAppInstalled }

    /// One-time upsell shown to users who upgraded from a pre-Watch build: they
    /// have a paired Watch but haven't set our Watch app up yet.
    @AppStorage("hasSeenWatchUpgradePrompt") var hasSeenWatchUpgradePrompt: Bool = false
    @Published var showWatchUpgradePrompt: Bool = false

    /// One-time post-update announcement: live heart rate now works with Apple
    /// Watch, Garmin, and WHOOP. Upgraders only — fresh installs meet heart-rate
    /// setup inside onboarding, so the flag is burned there instead.
    @AppStorage("hasSeenHRSourcesAnnouncement") var hasSeenHRSourcesAnnouncement: Bool = false
    @Published var showHRSourcesAnnouncement: Bool = false

    /// Call on main-screen appear. Decides once per install whether to show the
    /// heart-rate-sources announcement.
    func evaluateHRSourcesAnnouncement() {
        guard !hasSeenHRSourcesAnnouncement, !showHRSourcesAnnouncement else { return }
        guard UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") else {
            // Fresh install: onboarding covers heart-rate setup; never announce.
            hasSeenHRSourcesAnnouncement = true
            return
        }
        guard workoutStartDate == nil else { return } // never pop over an active or recovered workout
        guard !showWatchUpgradePrompt else { return } // one prompt per launch
        showHRSourcesAnnouncement = true
    }

    private var watchBroadcastCancellable: AnyCancellable?
    private var idleTimerCancellable: AnyCancellable?
    private var liveActivityHRCancellable: AnyCancellable?

    /// High-level connection state for status display and troubleshooting.
    enum WatchConnectionStatus {
        case noWatchPaired    // no Apple Watch paired to this iPhone
        case appNotInstalled  // Watch paired, but the N4x4 Watch app isn't installed
        case notReachable     // installed but not currently reachable
        case connected        // installed and reachable
    }

    var watchConnectionStatus: WatchConnectionStatus {
        if !watchPaired { return .noWatchPaired }
        if !watchAppInstalled { return .appNotInstalled }
        if !watchReachable { return .notReachable }
        return .connected
    }

    /// True when the user has a paired Apple Watch but the N4x4 Watch app isn't
    /// installed on it — i.e. the Watch "doesn't show up" in the app and the user
    /// may want to set it up. Drives the Home "connect your Watch" banner.
    /// (Deliberately ignores mere unreachability, which is normal when the Watch
    /// app simply isn't open.)
    var watchAppMissingOnPairedWatch: Bool {
        watchPaired && !watchAppInstalled
    }

    /// Seconds since the current workout began (0 if not started). Recomputed on
    /// every timer tick, so views that read it re-evaluate each second.
    var workoutElapsedSeconds: TimeInterval {
        guard let start = workoutStartDate else { return 0 }
        return max(0, Date().timeIntervalSince(start))
    }

    /// True when we should warn on the timer screen that HR isn't coming through:
    /// a workout is running, the user owns at least one HR source (a paired
    /// Watch or a remembered Bluetooth monitor), but no reading has arrived
    /// after a short settling window. The troubleshooting sheet diagnoses why.
    var shouldWarnMissingHeartRate: Bool {
        isRunning
            && (watchPaired || bleHeartRateManager.hasRememberedMonitor)
            && currentHeartRate == nil
            && workoutElapsedSeconds > 15
    }

    /// SF Symbol for the small badge next to the BPM readout indicating where
    /// the number comes from. nil when no source is live.
    var heartRateSourceSymbol: String? {
        switch heartRateAggregator.liveSource(now: Date()) {
        case .bluetooth:   return "sensor.tag.radiowaves.forward"
        case .watch:       return "applewatch"
        case .appleSensor: return "airpods"
        case nil:          return nil
        }
    }

    /// Human label for the live heart-rate source ("Apple Watch" or the
    /// monitor's name). nil when no source is live.
    var heartRateSourceLabel: String? {
        switch heartRateAggregator.liveSource(now: Date()) {
        case .bluetooth:   return bleHeartRateManager.rememberedName ?? "Heart Rate Monitor"
        case .watch:       return "Apple Watch"
        case .appleSensor: return "AirPods"
        case nil:          return nil
        }
    }

    /// One-line hint for the workout screen when HR is expected but missing,
    /// phrased for whichever source the user actually owns.
    var missingHeartRateHint: String {
        if watchPaired && !watchAppInstalled {
            return "Set up N4x4 on your Watch"
        }
        if !watchPaired && bleHeartRateManager.hasRememberedMonitor {
            return "Check your heart rate monitor"
        }
        return "Waiting for heart rate…"
    }

    /// Called by PhoneSessionManager whenever WCSession state changes.
    func updateWatchConnectionState(paired: Bool, installed: Bool, reachable: Bool) {
        watchPaired = paired
        watchAppInstalled = installed
        watchReachable = reachable
        evaluateWatchUpgradePrompt()
    }

    /// Surface the one-time upgrade prompt when a paired Watch is present but our
    /// app isn't installed there yet.
    private func evaluateWatchUpgradePrompt() {
        guard !hasSeenWatchUpgradePrompt, !showWatchUpgradePrompt else { return }
        // Only for existing users; brand-new users see Watch setup as part of the
        // regular onboarding flow, so don't compete with it.
        guard UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") else { return }
        // One prompt per launch — the HR-sources announcement wins ties and
        // covers the Watch pitch anyway; this one can fire on a later launch.
        guard !showHRSourcesAnnouncement, workoutStartDate == nil else { return }
        if watchPaired && !watchAppInstalled {
            showWatchUpgradePrompt = true
        }
    }

    private static let milestones = [1, 5, 10, 25, 50, 100]

    private var shownMilestones: Set<Int> {
        get {
            let arr = (try? JSONDecoder().decode([Int].self, from: Data(shownMilestonesData.utf8))) ?? []
            return Set(arr)
        }
        set {
            let arr = Array(newValue).sorted()
            shownMilestonesData = (try? String(data: JSONEncoder().encode(arr), encoding: .utf8)) ?? "[]"
        }
    }

    private func checkForMilestone() {
        let count = workoutLogEntries.filter(\.countsTowardStreak).count
        guard Self.milestones.contains(count), !shownMilestones.contains(count) else { return }
        var shown = shownMilestones
        shown.insert(count)
        shownMilestones = shown
        pendingMilestoneCount = count
        showMilestoneCelebration = true
    }

    func dismissMilestoneCelebration() {
        showMilestoneCelebration = false
        // Wait for the fullScreenCover dismiss animation (~0.35s) to fully complete
        // before presenting the sheet. Firing too early causes the sheet to appear
        // and immediately be torn down as the cover finishes its exit, which triggers
        // onDisappear and sets showWeeklyStreaks = false after ~1 second.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.showWeeklyStreaks = true
        }
    }

    // HealthKit
    @AppStorage("healthKitEnabled") var healthKitEnabled: Bool = false
    /// Set only when the user switches "Enable Apple Health" off themselves.
    /// `healthKitEnabled` also gets cleared when iOS revokes access, so this is
    /// what tells the two apart — without it, re-arming the connection after a
    /// revoke would also override a deliberate opt-out on the next foreground.
    @AppStorage("healthKitUserOptedOut") var healthKitUserOptedOut: Bool = false
    @AppStorage("logWorkoutsToHealthKit") var logWorkoutsToHealthKit: Bool = true
    @Published var healthAuthorizationGranted: Bool = false
    @Published var vo2DataPoints: [VO2DataPoint] = []
    /// When the last VO₂ query came back, and what it said if it failed.
    /// Both exist for the Troubleshoot page — a user who sees no chart needs to
    /// know whether the read ran at all, not just that the graph is missing.
    @Published var lastVO2FetchDate: Date?
    @Published var lastVO2FetchError: String?

    @Published var notificationPermissionState: PermissionState = .unknown
    @Published var healthKitPermissionState: PermissionState = .unknown

    var workoutReminderMode: WorkoutReminderMode {
        get { WorkoutReminderMode(rawValue: workoutReminderModeRaw) ?? .weeklyWeekday }
        set {
            let sanitized = newValue
            guard workoutReminderModeRaw != sanitized.rawValue else { return }
            workoutReminderModeRaw = sanitized.rawValue
        }
    }

    static let reminderWeekdayOptions: [(value: Int, title: String)] = [
        (2, "Monday"),
        (3, "Tuesday"),
        (4, "Wednesday"),
        (5, "Thursday"),
        (6, "Friday"),
        (7, "Saturday"),
        (1, "Sunday")
    ]

    // MARK: - Settings row summaries (top-level value previews)

    /// "Tue · Thu" — days shown in display order; "Off" when reminders are
    /// disabled or no day is selected.
    var reminderDaysSummary: String {
        guard workoutRemindersEnabled else { return "Off" }
        let selected = selectedWeekdaysList
        let names = Self.reminderWeekdayOptions
            .filter { selected.contains($0.value) }
            .map { String($0.title.prefix(3)) }
        return names.isEmpty ? "Off" : names.joined(separator: " · ")
    }

    /// "4 × 4:00" — interval count × high-intensity duration.
    var intervalPlanSummary: String {
        let secs = Int(highIntensityDuration)
        return "\(numberOfIntervals) × \(secs / 60):" + String(format: "%02d", secs % 60)
    }

    // MARK: - Multi-day Reminder Helpers

    // @Published property for stable in-memory state (synced with AppStorage)
    @Published var selectedWeekdaysList: [Int] = [] {
        didSet {
            guard oldValue.sorted() != selectedWeekdaysList.sorted() else { return }

            var normalized = selectedWeekdaysList
            if normalized.isEmpty, workoutRemindersEnabled {
                // Keep reminder scheduling deterministic: if the user deselects every day while
                // reminders remain enabled, immediately pin the schedule to "today" and surface it
                // back in the UI instead of silently falling back each time we reschedule.
                normalized = [Calendar.current.component(.weekday, from: Date())]
                selectedWeekdaysList = normalized
                return
            }

            // Sync to AppStorage when value changes (via flag to prevent circular sync)
            isSyncingFromPublished = true
            let sorted = normalized.sorted()
            workoutReminderWeekdays = sorted.map { String($0) }.joined(separator: ",")
            isSyncingFromPublished = false
            if workoutRemindersEnabled {
                reminderActivationDate = Date()
            }
        }
    }

    var selectedWeekdays: [Int] {
        get { selectedWeekdaysList }
        set { selectedWeekdaysList = newValue }
    }

    func toggleWeekday(_ weekday: Int) {
        var days = selectedWeekdaysList
        if days.contains(weekday) {
            days.removeAll { $0 == weekday }
        } else {
            days.append(weekday)
        }
        selectedWeekdaysList = days
    }

    private func ensureDefaultReminderSelection() {
        guard selectedWeekdaysList.isEmpty else { return }
        let today = Calendar.current.component(.weekday, from: Date())
        selectedWeekdaysList = [today]
    }
    
    /// Force sync selected days to AppStorage and schedule reminders
    /// Used by onboarding to ensure reminders are scheduled after user selects days
    func enableRemindersWithSelectedDays() {
        workoutReminderMode = .weeklyWeekday
        // Force sync to AppStorage immediately
        isSyncingFromPublished = true
        let sorted = selectedWeekdaysList.sorted()
        workoutReminderWeekdays = sorted.map { String($0) }.joined(separator: ",")
        isSyncingFromPublished = false
        // Now enable reminders (this will trigger scheduling)
        workoutRemindersEnabled = true
    }

    func isWeekdaySelected(_ weekday: Int) -> Bool {
        selectedWeekdaysList.contains(weekday)
    }

    // MARK: - Streak Calculation

    var currentWeekStreak: Int {
        calculateCurrentStreak()
    }

    private func calculateCurrentStreak() -> Int {
        guard !workoutLogEntries.isEmpty else { return 0 }

        let calendar = Calendar.current
        let now = Date()
        var streak = 0
        var expectedWeek = calendar.component(.weekOfYear, from: now)
        // Must use yearForWeekOfYear to stay consistent with WorkoutLogEntry.year (S2)
        var expectedYear = calendar.component(.yearForWeekOfYear, from: now)

        // Get unique weeks from workout entries using a Hashable key
        struct WeekKey: Hashable { let year: Int; let week: Int }
        let uniqueWeeks: Set<WeekKey> = Set(workoutLogEntries.filter(\.countsTowardStreak).map { WeekKey(year: $0.year, week: $0.weekOfYear) })
        let sortedWeeks = uniqueWeeks.sorted { lhs, rhs in
            if lhs.year != rhs.year { return lhs.year > rhs.year }
            return lhs.week > rhs.week
        }

        // Steps back one ISO week, crossing year boundaries without hard-coding 52.
        func previousWeek(fromYear year: Int, week: Int) -> (Int, Int) {
            var newWeek = week - 1
            var newYear = year
            if newWeek < 1 {
                newYear -= 1
                if let lastDay = calendar.date(from: DateComponents(year: newYear, month: 12, day: 28)) {
                    newWeek = calendar.component(.weekOfYear, from: lastDay)
                } else {
                    newWeek = 52 // fallback; in practice calendar.date never fails for Dec 28
                }
            }
            return (newYear, newWeek)
        }

        var allowedHeadGap = true

        // Check from current week backwards, allowing a single head gap when the
        // user hasn't trained yet this week but has a streak leading into it.
        for key in sortedWeeks {
            if key.year == expectedYear && key.week == expectedWeek {
                // Once the current week is matched, the head-gap forgiveness is
                // spent — it must only excuse a not-yet-trained *current* week,
                // never a missed week later in the streak.
                allowedHeadGap = false
                streak += 1
                (expectedYear, expectedWeek) = previousWeek(fromYear: expectedYear, week: expectedWeek)
                continue
            }

            if allowedHeadGap {
                let (gapYear, gapWeek) = previousWeek(fromYear: expectedYear, week: expectedWeek)
                if key.year == gapYear && key.week == gapWeek {
                    allowedHeadGap = false
                    streak += 1
                    (expectedYear, expectedWeek) = previousWeek(fromYear: gapYear, week: gapWeek)
                    continue
                }
            }

            break
        }

        return streak
    }

    func updateStreakOnWorkoutComplete() {
        // Always recalculate — the stored value could be stale (e.g. user missed weeks since last open).
        currentStreak = calculateCurrentStreak()
        if currentStreak > longestStreak {
            longestStreak = currentStreak
        }
    }

    /// Recalculates and syncs the stored streak. Call on app foreground and app launch.
    func refreshStreak() {
        let recalculated = calculateCurrentStreak()
        if recalculated != currentStreak {
            currentStreak = recalculated
        }
    }

    // MARK: - Success Messages

    static let successMessages: [String] = [
        "Crushing it, Viking! 🪓",
        "Another workout, another victory! ⚔️",
        "Your VO2 max is thanking you! 💪",
        "Stronger than yesterday! 🔥",
        "Viking tradition: never skip training! 🛡️",
        "Epic workout complete! 🏆",
        "You're becoming unstoppable! ⭐",
        "The forge grows stronger! 🔨",
        "Discipline is your superpower! 🎯",
        "One workout at a time! 👊"
    ]

    var randomSuccessMessage: String {
        Self.successMessages.randomElement() ?? "Great job, Viking!"
    }

    let healthStore = HKHealthStore()
    private var isSchedulingWorkoutReminder = false
    private var isResolvingNotificationPermission = false
    private var isRequestingNotificationAuthorization = false

    // Timer properties
    @Published var currentIntervalIndex: Int = 0
    @Published var timeRemaining: TimeInterval = 0
    @Published var isRunning: Bool = false

    // Interval counts
    @Published var highIntensityCount: Int = 0
    @Published var restCount: Int = 0

    // Completion message display control
    @Published var showCompletionMessage: Bool = false

    // Actual elapsed time captured for the current session (supports skips).
    @Published var elapsedWarmupTime: TimeInterval = 0
    @Published var elapsedHighIntensityTime: TimeInterval = 0
    @Published var elapsedRecoveryTime: TimeInterval = 0
    @Published var elapsedCooldownTime: TimeInterval = 0

    var intervals: [Interval] = []
    var timer: AnyCancellable?
    var player: AVAudioPlayer?
    /// Lazily created for the long interval-change buzz; kept so repeated
    /// buzzes don't rebuild the engine. Nil on devices without haptics.
    private var hapticEngine: CHHapticEngine?
    var intervalEndTime: Date?
    var workoutStartDate: Date?
    var workoutCompletionDate: Date?
    @Published var cooldownCompletionNotice: Bool = false
    private var skippedCooldownThisSession: Bool = false

    // Live Activity
    private var liveActivity: (any WorkoutLiveActivityHandle)?
    private let liveActivityProvider: any WorkoutLiveActivityProvider
    private(set) var liveActivityTask: Task<Void, Never>?
    private let intervalNotificationCenter: any IntervalNotificationCenter
    private var intervalNotificationGeneration = UUID()
    private(set) var intervalNotificationTask: Task<Void, Never>?
    private static let intervalNotificationID = "nextInterval"

    // Voice prompt state — reset on every interval change, reset, and skip
    private var halfwayPromptFired = false
    private var tenSecondPromptFired = false
    // Pre-interval countdown haptics: one flag per tap so each fires once per
    // interval (reset alongside the voice-prompt flags).
    private var countdownTap1Fired = false
    private var countdownTap2Fired = false

    var maximumHeartRate: Int {
        if useCustomMaxHR && customMaxHR > 0 {
            return customMaxHR
        }
        if userAge >= 40 {
            return max(1, Int((208.0 - 0.7 * Double(userAge)).rounded()))
        }
        return max(1, 220 - userAge)
    }

    var highIntensityTargetRange: ClosedRange<Int> {
        let lower = Int((Double(maximumHeartRate) * 0.85).rounded())
        let upper = Int((Double(maximumHeartRate) * 0.95).rounded())
        return lower...upper
    }

    var recoveryTargetRange: ClosedRange<Int> {
        let lower = Int((Double(maximumHeartRate) * 0.60).rounded())
        let upper = Int((Double(maximumHeartRate) * 0.70).rounded())
        return lower...upper
    }

    var currentIntervalType: IntervalType? {
        guard intervals.indices.contains(currentIntervalIndex) else { return nil }
        return intervals[currentIntervalIndex].type
    }

    /// Current phase mapped to the shared WorkoutPhase type used in Watch
    /// messages and the zone-feedback engine.
    var currentWorkoutPhase: WorkoutPhase {
        switch currentIntervalType {
        case .highIntensity: return .highIntensity
        case .rest:          return .rest
        case .cooldown:      return .cooldown
        default:             return .warmup
        }
    }

    /// Target HR range for the current phase, or nil for warmup/cooldown
    /// (phases that carry no zone target and therefore never trigger an alert).
    var currentPhaseHRRange: ClosedRange<Int>? {
        switch currentIntervalType {
        case .highIntensity: return highIntensityTargetRange
        case .rest:          return recoveryTargetRange
        default:             return nil
        }
    }

    func shouldConfirmSkipCurrentInterval() -> Bool {
        guard let type = currentIntervalType else { return false }
        switch type {
        case .cooldown:
            return confirmSkipCooldown
        default:
            return confirmSkipOtherIntervals
        }
    }

    var currentSessionBreakdown: WorkoutSessionBreakdown {
        let total = elapsedWarmupTime + elapsedHighIntensityTime + elapsedRecoveryTime + elapsedCooldownTime
        return WorkoutSessionBreakdown(
            totalDuration: total,
            warmupDuration: elapsedWarmupTime,
            highIntensityDuration: elapsedHighIntensityTime,
            recoveryDuration: elapsedRecoveryTime,
            cooldownDuration: elapsedCooldownTime,
            cooldownSkipped: skippedCooldownThisSession
        )
    }

    private func addElapsed(_ seconds: TimeInterval, for type: IntervalType) {
        let clamped = max(0, seconds)
        guard clamped > 0 else { return }
        switch type {
        case .warmup:
            elapsedWarmupTime += clamped
        case .highIntensity:
            elapsedHighIntensityTime += clamped
        case .rest:
            elapsedRecoveryTime += clamped
        case .cooldown:
            elapsedCooldownTime += clamped
        }
    }

    private func resetElapsedTracking() {
        elapsedWarmupTime = 0
        elapsedHighIntensityTime = 0
        elapsedRecoveryTime = 0
        elapsedCooldownTime = 0
    }

    init(intervalNotificationCenter: any IntervalNotificationCenter = UNUserNotificationCenter.current(),
         liveActivityProvider: any WorkoutLiveActivityProvider = SystemWorkoutLiveActivityProvider(),
         checkpointURL: URL = TimerViewModel.defaultCheckpointURL,
         seriesSaver: @escaping (HeartRateSeries, UUID) -> Bool = { HeartRateSeriesStore.save($0, for: $1) }) {
        self.checkpointURL = checkpointURL
        self.seriesSaver = seriesSaver
        self.intervalNotificationCenter = intervalNotificationCenter
        self.liveActivityProvider = liveActivityProvider
        // Migrate the legacy single-weekday setting to the multi-day format.
        // @AppStorage loads a persisted value WITHOUT firing didSet, so the
        // migration in workoutReminderWeekday.didSet never runs at launch for
        // existing users — their saved day would otherwise be dropped and
        // reminders silently reset to "today". Seed it explicitly here so the
        // subsequent sync below picks it up.
        if workoutReminderWeekday > 0 && workoutReminderWeekdays.isEmpty {
            workoutReminderWeekdays = String(workoutReminderWeekday)
        }

        // Initialize selectedWeekdaysList from AppStorage
        if !workoutReminderWeekdays.isEmpty {
            selectedWeekdaysList = workoutReminderWeekdays
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .filter { (1...7).contains($0) }
        }

        if numberOfIntervals < 1 {
            numberOfIntervals = 4
        }
        if workoutReminderDays < 1 {
            workoutReminderDays = 7
        }
        if workoutReminderModeRaw.isEmpty {
            workoutReminderModeRaw = WorkoutReminderMode.weeklyWeekday.rawValue
        }
        if workoutReminderMode == .weeklyWeekday && workoutReminderWeekday == 0 {
            workoutReminderWeekday = Self.defaultWorkoutReminderWeekday()
        }
        userAge = max(Self.minimumSupportedAge, min(Self.maximumSupportedAge, userAge))
        cooldownDuration = max(60, min(600, cooldownDuration))

        // One-time migration from the old alarmEnabled bool to AudioMode.
        // Users who had alarm on (or are brand new) get Voice Prompts as the new default.
        // Only users who explicitly disabled alarm stay on Silent.
        if UserDefaults.standard.object(forKey: "audioModeRaw") == nil {
            audioMode = alarmEnabled ? .voice : .silent
        }

        // One-time 4.6 migration: sync the per-family reminder flags to the
        // master so the invariant (master == any family on) holds from day one.
        // Without this, an install with reminders OFF would show three ON
        // family toggles that do nothing.
        if !UserDefaults.standard.bool(forKey: "reminderFamilyFlagsSynced") {
            isSyncingReminderFamilies = true
            nightBeforeReminderEnabled = workoutRemindersEnabled
            morningOfReminderEnabled = workoutRemindersEnabled
            comebackNudgesEnabled = workoutRemindersEnabled
            isSyncingReminderFamilies = false
            UserDefaults.standard.set(true, forKey: "reminderFamilyFlagsSynced")
        }

        setupIntervals()
        loadWorkoutLogEntries()
        selectedWorkoutType = resolvedDefaultWorkoutType
        heartRateAggregator.priority = HeartRateAggregator.priority(fromRaw: hrSourcePriorityRaw)

        // Apple Watch connectivity: the phone is the source of truth and
        // broadcasts timer state; the Watch sends commands and streamed HR back.
        phoneSessionManager.timerViewModel = self
        phoneSessionManager.activate()

        // Bluetooth heart rate monitor: readings join the same funnel as the
        // Watch. startIfRemembered() is a no-op for users who never paired
        // one, so this can't trigger a Bluetooth permission prompt at launch.
        bleHeartRateManager.onReading = { [weak self] reading in
            self?.ingestHeartRate(Double(reading.bpm), from: .bluetooth)
        }
        bleHeartRateManager.startIfRemembered()

        // Broadcast to the Watch reactively whenever the state it renders
        // changes. Observing these published properties covers every timer
        // transition (intervalEndTime always changes alongside isRunning or the
        // interval index). Debounced so one action sends a single update, and
        // it removes the need to hand-place broadcast calls at every mutation.
        let watchTriggers: [AnyPublisher<Void, Never>] = [
            $isRunning.map { _ in () }.eraseToAnyPublisher(),
            $currentIntervalIndex.map { _ in () }.eraseToAnyPublisher(),
            $highIntensityCount.map { _ in () }.eraseToAnyPublisher(),
            $showPostWorkoutSummary.map { _ in () }.eraseToAnyPublisher(),
            $completedWorkoutEntryID.map { _ in () }.eraseToAnyPublisher(),
            $activeWorkoutID.map { _ in () }.eraseToAnyPublisher(),
            $hasPendingWorkoutSave.map { _ in () }.eraseToAnyPublisher(),
        ]
        watchBroadcastCancellable = Publishers.MergeMany(watchTriggers)
            .debounce(for: .milliseconds(80), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.broadcastStateToWatch() }

        // Keep the screen awake while a workout is running (if the user opted in).
        // Managed here rather than in a view because the active UI lives in the
        // redesigned screens; the old TimerView's idle-timer wiring never runs.
        idleTimerCancellable = $isRunning
            .sink { [weak self] _ in
                // Defer so isRunning has settled to its new value before we read it.
                DispatchQueue.main.async { self?.updateIdleTimerState() }
            }

        // Push the live heart rate to the Live Activity / Dynamic Island. Reduce
        // to integer bpm and drop repeats so we only spend an ActivityKit update
        // when the shown number actually changes, then throttle to at most one
        // every few seconds to stay well inside the update budget.
        liveActivityHRCancellable = $currentHeartRate
            .map { $0.map { Int($0.rounded()) } ?? 0 }
            .removeDuplicates()
            .throttle(for: .seconds(3), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                guard let self, self.liveActivity != nil, self.isRunning else { return }
                self.updateLiveActivity(isRunning: true)
            }

        // Recovery starts paused, so abandon old system surfaces before restoring.
        // Capture activities now before async cleanup could see a new workout.
        endLiveActivity()
        cancelIntervalNotifications()
        restoreSessionCheckpoint()

        // Sync the stored streak value immediately on launch (S1).
        // Previously currentStreak was only ever increased, so a missed-week streak
        // would never be reflected until the user started a new run of workouts.
        refreshStreak()

        if workoutRemindersEnabled && reminderActivationDate == nil {
            reminderActivationDate = Date()
        }

        // N1 fix: refreshNotificationPermissionState is async. Previously, scheduling
        // calls were made synchronously after it returned, so notificationPermissionState
        // was still .unknown and every guard failed silently. Now we schedule inside the
        // completion block where the state is guaranteed to be current.
        refreshNotificationPermissionState { [weak self] in
            guard let self else { return }
            if self.workoutRemindersEnabled {
                self.rescheduleRemindersOnAppLaunch()
                self.scheduleWorkoutReminder()
            }
        }

        refreshHealthKitAuthorizationState()

        if healthKitEnabled {
            if healthKitPermissionState == .granted {
                fetchVO2MaxSamples()
            } else {
                requestHealthKitAuthorizationIfNeeded()
            }
        }
    }

    var sessionIntervalCount: Int { intervals.filter { $0.type == .highIntensity }.count }

    private func updatePlanForNextWorkout() {
        guard workoutStartDate == nil, completedWorkoutEntryID == nil else { return }
        setupIntervals()
    }

    func setupIntervals() {
        intervals.removeAll()
        highIntensityCount = 0
        restCount = 0
        resetElapsedTracking()

        if warmupDuration > 0 {
            let warmup = Interval(name: "Warm Up", duration: warmupDuration, type: .warmup)
            intervals.append(warmup)
        }

        for i in 1...numberOfIntervals {
            let highIntensity = Interval(name: "High Intensity", duration: highIntensityDuration, type: .highIntensity)
            intervals.append(highIntensity)

            if i < numberOfIntervals {
                let rest = Interval(name: "Recovery", duration: restDuration, type: .rest)
                intervals.append(rest)
            }
        }

        if cooldownEnabled {
            let cooldown = Interval(name: "Cool Down", duration: cooldownDuration, type: .cooldown)
            intervals.append(cooldown)
        }

        currentIntervalIndex = 0
        timeRemaining = intervals.first?.duration ?? 0
        intervalEndTime = nil
        updateCounts()
    }

    func updateCounts() {
        guard !intervals.isEmpty, intervals.indices.contains(currentIntervalIndex) else {
            highIntensityCount = 0
            restCount = 0
            return
        }

        let traversed = intervals.prefix(currentIntervalIndex + 1)
        highIntensityCount = traversed.filter { $0.type == .highIntensity }.count
        restCount = traversed.filter { $0.type == .rest }.count
    }

    func startTimer(now: Date = Date()) {
        guard workoutCompletionDate == nil, !intervals.isEmpty,
              intervals.indices.contains(currentIntervalIndex) else { return }

        timer?.cancel()
        timer = nil

        cancelRecoveryNudge()
        showWorkoutRecovery = false
        isRunning = true
        // Keep the audio session (and the app) alive while the phone is
        // locked so voice prompts fire on time. Idempotent across resumes.
        SpeechManager.shared.beginWorkoutAudio()
        if workoutStartDate == nil {
            workoutStartDate = now
            activeWorkoutID = UUID()
            sessionWorkoutType = resolvedDefaultWorkoutType
            // Fresh workout: start the fine-grained HR recording.
            hrRecorder = HeartRateSeriesRecorder(startedAt: now)
            completedSeries = nil
            recorderBeginCurrentInterval(at: now)
        }
        // Also restart streaming after restoring a paused session on relaunch.
        startPhoneWorkoutSessionIfNeeded()
        startLiveActivity()
        if intervalEndTime == nil {
            intervalEndTime = now.addingTimeInterval(timeRemaining)
        }

        reconcileTimerState(now: now, playAlarm: false)
        guard isRunning else { return }

        speakIntervalCueIfNeeded()
        speakWarmupStartIfNeeded()

        saveSessionCheckpoint(now: now, force: true)
        scheduleNextIntervalNotification()

        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    func stopTimer() {
        isRunning = false
        timer?.cancel()
        timer = nil
        cancelIntervalNotifications()
    }

    func tick() {
        guard isRunning else { return }
        reconcileTimerState(now: Date(), playAlarm: true)
    }

    func reconcileTimerState(now: Date = Date(), playAlarm: Bool) {
        guard isRunning else { return }
        lastProgressDate = now
        defer { if workoutCompletionDate == nil { saveSessionCheckpoint(now: now) } }
        guard !intervals.isEmpty, intervals.indices.contains(currentIntervalIndex) else {
            stopTimer()
            endLiveActivity()
            return
        }

        #if DEBUG && targetEnvironment(simulator)
        // Opt-in simulator fixture for layout tests; never compiled into device
        // or release builds. Use the real funnel so zone colour and expiry match.
        if let value = ProcessInfo.processInfo.environment["N4X4_DEMO_HEART_RATE"],
           let bpm = Double(value), (40...210).contains(bpm) {
            ingestHeartRate(bpm, from: .watch)
        }
        #endif

        if intervalEndTime == nil {
            intervalEndTime = now.addingTimeInterval(timeRemaining)
        }

        guard let endTime = intervalEndTime else { return }

        if now < endTime {
            let previousRemaining = timeRemaining
            let newRemaining = max(0, endTime.timeIntervalSince(now))
            addElapsed(previousRemaining - newRemaining, for: intervals[currentIntervalIndex].type)
            timeRemaining = newRemaining

            // Halfway voice prompt
            let halfwayPoint = intervals[currentIntervalIndex].duration / 2
            if timeRemaining <= halfwayPoint {
                speakHalfway()
            }

            // 10-second warning
            if timeRemaining <= 10 && timeRemaining > 0 {
                speakTenSeconds()
            }

            // Countdown haptics: two short taps as the interval boundary
            // approaches. The long buzz plays at the transition itself; after
            // the final interval nothing follows, so the taps stand alone.
            if timeRemaining <= 3 { playCountdownTapIfNeeded(&countdownTap1Fired) }
            if timeRemaining <= 2 { playCountdownTapIfNeeded(&countdownTap2Fired) }

            return
        }

        var cursor = currentIntervalIndex
        var intervalEndCursor = endTime
        var advanced = false

        // Consume remainder of the interval we were in before advancing.
        addElapsed(timeRemaining, for: intervals[cursor].type)

        while now >= intervalEndCursor {
            advanced = true
            if cursor + 1 >= intervals.count {
                currentIntervalIndex = cursor
                updateCounts()
                finishWorkout(at: intervalEndCursor)
                return
            }

            cursor += 1
            recorderBeginInterval(at: cursor, time: intervalEndCursor)
            let intervalDuration = intervals[cursor].duration
            intervalEndCursor = intervalEndCursor.addingTimeInterval(intervalDuration)

            if now >= intervalEndCursor {
                // This whole interval elapsed while app/timer was not reconciling.
                addElapsed(intervalDuration, for: intervals[cursor].type)
            } else {
                // We are partway through this interval.
                let remaining = max(0, intervalEndCursor.timeIntervalSince(now))
                addElapsed(intervalDuration - remaining, for: intervals[cursor].type)
            }
        }

        currentIntervalIndex = cursor
        updateCounts()
        intervalEndTime = intervalEndCursor
        timeRemaining = max(0, intervalEndCursor.timeIntervalSince(now))

        if advanced {
            // Haptics are their own channel: the long buzz closes the countdown
            // taps on every natural transition, independent of the audio mode
            // (previously only manual skips buzzed).
            resetPromptFlags()
            triggerIntervalHaptic()
            saveSessionCheckpoint(now: now, force: true)
            if playAlarm {
                playAlarmIfNeeded()
            }
            cancelIntervalNotifications()
            scheduleNextIntervalNotification()
            // Push the new interval to the Dynamic Island / Live Activity. The
            // natural (countdown-driven) advance happens here, not in
            // moveToNextInterval, so without this the island froze on the first
            // interval's state and its countdown end-time fell into the past.
            updateLiveActivity(isRunning: true)
        }
    }

    func finishWorkout(at completionTime: Date = Date()) {
        // Timer reconciliation and Watch commands can both reach completion.
        // Save the workout (and Apple Health record) only once per session.
        guard workoutCompletionDate == nil else { return }
        triggerCompletionHaptic()
        stopTimer()
        endLiveActivity()
        stopPhoneWorkoutSessionIfActive()
        // Seal the HR recording before HR state is cleared; the post-workout
        // summary charts render from completedSeries.
        if let recorder = hrRecorder, let start = workoutStartDate {
            completedSeries = recorder.finish(at: max(0, completionTime.timeIntervalSince(start)))
        }
        completedSeriesNeedsSave = completedSeries != nil
        hrRecorder = nil
        clearHeartRateState()
        workoutCompletionDate = completionTime
        showWorkoutRecovery = false
        sessionEndedEarly = elapsedHighIntensityTime + 0.01 < intervals.filter { $0.type == .highIntensity }.reduce(0) { $0 + $1.duration }
        speakWorkoutComplete()
        // Safe while the completion phrase is speaking: teardown defers to
        // the speech-finished callback.
        SpeechManager.shared.endWorkoutAudio()
        intervalEndTime = nil
        timeRemaining = 0
        showCompletionMessage = false

        isRestoringOrResetting = true
        selectedWorkoutType = sessionWorkoutType ?? resolvedDefaultWorkoutType
        workoutNotesDraft = ""
        performanceDraft = []
        performanceNotesDraft = []
        performanceSetAll = nil
        preparedPerformanceType = nil
        isRestoringOrResetting = false
        persistCompletedWorkout()

        let finishedOnCooldown = intervals.indices.contains(currentIntervalIndex) && intervals[currentIntervalIndex].type == .cooldown
        let showCooldownMoment = finishedOnCooldown && !skippedCooldownThisSession
        if showCooldownMoment {
            cooldownCompletionNotice = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            let completedID = completedWorkoutEntryID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, self.completedWorkoutEntryID == completedID,
                      self.workoutCompletionDate != nil else { return }
                self.showPostWorkoutSummary = true
                self.cooldownCompletionNotice = false
            }
        } else {
            showPostWorkoutSummary = true
            cooldownCompletionNotice = false
        }

        if workoutRemindersEnabled {
            scheduleWorkoutReminder()
        }
        if healthKitEnabled {
            saveCompletedWorkoutToHealthKit()
            fetchVO2MaxSamples()
        }
    }

    func moveToNextInterval(now: Date = Date()) {
        // The long buzz belongs to a NEW interval starting — skipping the last
        // interval goes straight to completion, which has its own (taps-only)
        // haptic in finishWorkout.
        if currentIntervalIndex + 1 < intervals.count {
            triggerIntervalHaptic()
        }
        resetPromptFlags()
        if currentIntervalIndex + 1 < intervals.count {
            currentIntervalIndex += 1
            timeRemaining = intervals[currentIntervalIndex].duration
            intervalEndTime = isRunning ? now.addingTimeInterval(timeRemaining) : nil

            cancelIntervalNotifications()
            updateCounts()
            recorderBeginCurrentInterval(at: now)
            saveSessionCheckpoint(now: now, force: true)
            if isRunning {
                scheduleNextIntervalNotification()
                updateLiveActivity(isRunning: true)
            }
        } else {
            finishWorkout(at: now)
        }
    }

    func pause(now: Date = Date()) {
        if isRunning {
            // Reconcile once at tap time so elapsed accounting remains accurate between ticks.
            reconcileTimerState(now: now, playAlarm: false)
            guard isRunning else { return }

            SpeechManager.shared.stopSpeaking()
            timeRemaining = max(0, intervalEndTime?.timeIntervalSince(now) ?? timeRemaining)
            stopTimer()
            SpeechManager.shared.endWorkoutAudio()
            updateLiveActivity(isRunning: false)
            saveSessionCheckpoint(now: now, force: true)
        } else {
            intervalEndTime = now.addingTimeInterval(timeRemaining)
            startTimer(now: now)
            updateLiveActivity(isRunning: true)
        }
    }

    func skip(now: Date = Date()) {
        guard workoutStartDate != nil, workoutCompletionDate == nil,
              intervals.indices.contains(currentIntervalIndex) else { return }

        if isRunning {
            // Reconcile once at tap time so elapsed accounting remains accurate between ticks.
            reconcileTimerState(now: now, playAlarm: false)
            guard isRunning, intervals.indices.contains(currentIntervalIndex) else { return }
        }

        // Cancel any in-flight speech for the interval we're leaving so
        // prompts don't bleed into the next interval after a skip.
        SpeechManager.shared.stopSpeaking()
        if audioMode != .voice {
            playAlarmIfNeeded()
        }
        cancelIntervalNotifications()
        if intervals[currentIntervalIndex].type == .cooldown {
            skippedCooldownThisSession = true
        }
        let wasRunning = isRunning
        moveToNextInterval(now: now)

        if wasRunning, !showPostWorkoutSummary {
            startTimer(now: now)
        }
    }

    func reset() {
        guard !hasPendingWorkoutSave else { return }
        if let id = activeWorkoutID, workoutCompletionDate == nil { rememberDiscardedPhoneWorkout(id) }
        removeSessionCheckpoint()
        isRestoringOrResetting = true
        defer { isRestoringOrResetting = false }
        activeWorkoutID = nil
        sessionWorkoutType = nil
        showWorkoutRecovery = false
        sessionEndedEarly = false
        preparedPerformanceType = nil
        completedSeriesNeedsSave = false
        lastCheckpointDate = nil
        lastProgressDate = nil
        SpeechManager.shared.stopSpeaking()
        SpeechManager.shared.endWorkoutAudio()
        stopPhoneWorkoutSessionIfActive()
        hrRecorder = nil
        completedSeries = nil
        completedWorkoutEntryID = nil
        workoutNotesDraft = ""
        performanceDraft = []
        performanceNotesDraft = []
        performanceSetAll = nil
        resetPromptFlags()
        stopTimer()
        endLiveActivity()
        setupIntervals()
        loadWorkoutLogEntries()
        isRunning = false
        showCompletionMessage = false
        showPostWorkoutSummary = false
        intervalEndTime = nil
        workoutStartDate = nil
        workoutCompletionDate = nil
        cooldownCompletionNotice = false
        skippedCooldownThisSession = false
        clearHeartRateState()
    }

    func scheduleNextIntervalNotification() {
        guard isRunning, workoutCompletionDate == nil, notificationsEnabled,
              intervals.indices.contains(currentIntervalIndex),
              currentIntervalIndex + 1 < intervals.count else { return }

        let nextInterval = intervals[currentIntervalIndex + 1]
        let timeInterval = max(1, timeRemaining)
        scheduleNotification(identifier: "nextInterval", title: "N4x4 Interval", body: "Next interval: \(nextInterval.name) is starting.", in: timeInterval, repeats: false)
    }

    /// Reschedules reminders on app launch to handle missed workout days
    /// This ensures follow-ups are resent if user didn't open app for a while
    func rescheduleRemindersOnAppLaunch() {
        guard workoutRemindersEnabled, workoutReminderMode == .weeklyWeekday else { return }
        
        let weekdays = selectedWeekdaysList
        guard !weekdays.isEmpty else { return }
        
        // For each selected weekday, check if we missed the workout window and reschedule follow-ups
        for weekday in weekdays {
            // Cancel existing follow-ups for this weekday
            cancelMissedWorkoutFollowUpReminder(for: weekday)
            
            // Reschedule follow-ups (this will check if workout was logged and handle accordingly)
            scheduleMissedWorkoutFollowUpReminder(forScheduledWeekday: weekday)
        }
    }

    func scheduleWorkoutReminder() {
        guard !isSchedulingWorkoutReminder else { return }
        isSchedulingWorkoutReminder = true
        defer { isSchedulingWorkoutReminder = false }

        guard workoutRemindersEnabled else { return }
        guard notificationPermissionState == .granted else {
            // Only turn off the toggle when permission is definitively denied/unavailable.
            // If state is .unknown or .notDetermined the async refresh hasn't settled yet —
            // silently disabling reminders here would lose the user's setting (G4).
            if notificationPermissionState == .denied || notificationPermissionState == .unavailable {
                if workoutRemindersEnabled { workoutRemindersEnabled = false }
            }
            return
        }

        if reminderActivationDate == nil {
            reminderActivationDate = Date()
        }

        cancelWorkoutReminder()
        cancelMissedWorkoutFollowUpReminder()

        // Only weekly weekday mode is supported
        let weekdays = selectedWeekdays
        if weekdays.isEmpty {
            // Default to today if no days selected
            let today = Calendar.current.component(.weekday, from: Date())
            scheduleWeeklyWorkoutReminder(weekday: today)
            scheduleMissedWorkoutFollowUpReminder(forScheduledWeekday: today)
        } else {
            // Schedule for each selected weekday
            for weekday in weekdays {
                scheduleWeeklyWorkoutReminder(weekday: weekday)
                scheduleMissedWorkoutFollowUpReminder(forScheduledWeekday: weekday)
            }
        }
    }

    func cancelWorkoutReminder() {
        cancelAllWeeklyReminders()
        cancelMissedWorkoutFollowUpReminder()
    }

    // MARK: - 48h recovery nudge

    private static let recoveryNudgeIdentifier = "recoveryNudge"

    private func scheduleRecoveryNudge(afterCount count: Int) {
        // Recovery nudges are an extension of workout reminders, not interval cues, so
        // honor the reminder toggle (and permission state) before queuing the 48h alert.
        guard workoutRemindersEnabled, notificationPermissionState == .granted else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.recoveryNudgeIdentifier]
        )
        let nextCount = count + 1
        let bodies = [
            "Your muscles have rebuilt. Ready for session #\(nextCount)?",
            "48 hours of recovery done. Your body is primed — session #\(nextCount) is waiting.",
            "Recovery complete. Time to earn session #\(nextCount).",
            "Your cardiovascular system is ready. Session #\(nextCount) is calling.",
        ]
        let content = UNMutableNotificationContent()
        content.title = "Ready to train again"
        content.body = bodies[count % bodies.count]
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 48 * 3600, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.recoveryNudgeIdentifier, content: content, trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error { print("Error scheduling recovery nudge: \(error)") }
        }
    }

    private func cancelRecoveryNudge() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.recoveryNudgeIdentifier]
        )
    }

    private func scheduleWeeklyWorkoutReminder(weekday: Int) {
        guard (1...7).contains(weekday) else { return }
        guard nightBeforeReminderEnabled else { return }
        guard notificationPermissionState == .granted else { return }

        let content = UNMutableNotificationContent()
        // Fun Viking messages for night-before reminder
        let nightMessages: [(String, String)] = [
            ("Tomorrow is workout day, Viking! 🪓", "You committed to train tomorrow. Ready to crush it?"),
            ("Your Viking workout awaits tomorrow", "Don't let your training slip - N4x4 is ready when you are."),
            ("Heads up, Viking! 📢", "You have a workout scheduled for tomorrow. Let's go!"),
            ("Training day tomorrow! ⚔️", "Your body is waiting. Tomorrow we ride!"),
            ("Reminder: Viking duty calls tomorrow", "You've got this. Tomorrow's workout is calling your name.")
        ]
        let msg = nightMessages.randomElement()!
        content.title = msg.0
        content.body = msg.1
        content.sound = .default

        // Schedule for 8pm the day BEFORE the workout day
        var components = DateComponents()
        components.weekday = weekday
        components.hour = 20  // 8pm
        components.minute = 0
        
        // For repeats, we need to schedule for day-before so it fires correctly each week
        // Actually, for repeating weekly, we set the weekday and it repeats - but we want day-before
        // Let's adjust: schedule for (weekday - 1) at 8pm to be the day before
        let dayBeforeWeekday = weekday == 1 ? 7 : weekday - 1  // Sunday -> Saturday
        components.weekday = dayBeforeWeekday

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        // Use unique identifier per weekday
        let request = UNNotificationRequest(identifier: "workoutReminder_\(weekday)", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling weekly reminder: \(error.localizedDescription)")
            }
        }
    }
    
    private func cancelAllWeeklyReminders() {
        // Cancel night-before, morning-of (N4: new repeating trigger), and legacy identifiers.
        var identifiers = ["workoutReminder"]
        for weekday in 1...7 {
            identifiers.append("workoutReminder_\(weekday)")
            identifiers.append(morningOfReminderIdentifier(for: weekday))
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }



    /// Saves the completed workout before presenting its review, then updates
    /// that same entry when the user finishes editing optional details.
    @discardableResult
    private func persistCompletedWorkout() -> Bool {
        guard let completionDate = workoutCompletionDate else { return false }
        let isNewEntry = completedWorkoutEntryID == nil
        let entryID = completedWorkoutEntryID ?? activeWorkoutID ?? UUID()
        // A deleted workout must never be resurrected by a late review action.
        guard isNewEntry || workoutLogEntries.contains(where: { $0.id == entryID }) else { return false }
        let modality = selectedWorkoutType.trainingModality
        let entry = WorkoutLogEntry(
            id: entryID, completedAt: completionDate, workoutType: selectedWorkoutType,
            notes: workoutNotesDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            sessionBreakdown: currentSessionBreakdown, modality: modality,
            intervalPerformances: builtPerformances(for: modality),
            hrSummary: completedSeries.flatMap { HeartRateSeriesAnalytics.summary(for: $0) },
            endedEarly: sessionEndedEarly
        )
        if let index = workoutLogEntries.firstIndex(where: { $0.id == entryID }) {
            workoutLogEntries[index] = entry
        } else {
            workoutLogEntries.append(entry)
        }
        workoutLogEntries.sort { $0.completedAt > $1.completedAt }
        activeWorkoutID = entryID
        completedWorkoutEntryID = entryID
        hasPendingWorkoutSave = true
        // Keep a recoverable copy until both the log and series have been written.
        saveSessionCheckpoint(force: true)
        if completedSeriesNeedsSave, let series = completedSeries {
            completedSeriesNeedsSave = !seriesSaver(series, entryID)
        }
        let logSaved = persistWorkoutLogEntries()
        hasPendingWorkoutSave = !logSaved || completedSeriesNeedsSave
        if hasPendingWorkoutSave {
            workoutSaveError = "Your workout hasn't finished saving. Keep it here and try again."
        } else {
            if pendingWatchImports.isEmpty { workoutSaveError = nil }
            removeSessionCheckpoint()
        }
        if isNewEntry {
            updateStreakOnWorkoutComplete()
            if entry.countsTowardStreak {
                cancelMissedWorkoutFollowUpIfCompletedToday()
                scheduleRecoveryNudge(afterCount: workoutLogEntries.filter(\.countsTowardStreak).count)
            }
        }
        return !hasPendingWorkoutSave
    }

    private func saveReviewEditsIfNeeded() {
        guard !isRestoringOrResetting, completedWorkoutEntryID != nil else { return }
        persistCompletedWorkout()
    }

    @discardableResult
    func completeWorkoutReview() -> Bool {
        guard let id = completedWorkoutEntryID,
              workoutLogEntries.contains(where: { $0.id == id }),
              persistCompletedWorkout() else { return false }
        showHistoryAfterSummaryDismissal = true
        reset()
        return true
    }

    /// Wait until the summary has actually closed before presenting another
    /// sheet or the milestone celebration.
    func postWorkoutSummaryDidDismiss() {
        // Swiping the saved summary away is equivalent to Done.
        if completedWorkoutEntryID != nil, !completeWorkoutReview() {
            DispatchQueue.main.async { [weak self] in self?.showPostWorkoutSummary = true }
            return
        }
        guard showHistoryAfterSummaryDismissal else { return }
        showHistoryAfterSummaryDismissal = false
        checkForMilestone()
        if !showMilestoneCelebration {
            showWeeklyStreaks = true
        }
        maybeRequestAppReview()
    }

    /// Flag so the App Store rating prompt is only ever requested once.
    @AppStorage("hasRequestedAppReview") private var hasRequestedAppReview = false

    /// Ask for an App Store rating after a few successful sessions, and only
    /// once. Fired from a natural high point (a just-saved workout), never
    /// mid-flow. The first eligible count (3) is not a milestone count, so it
    /// never collides with the milestone celebration. Apple additionally
    /// throttles how often the system prompt can appear.
    private func maybeRequestAppReview() {
        guard !hasRequestedAppReview, workoutLogEntries.count >= 3 else { return }
        guard !showMilestoneCelebration else { return }
        hasRequestedAppReview = true
        Task { @MainActor in
            // Let the summary dismiss and the streak view settle first.
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            else { return }
            AppStore.requestReview(in: scene)
        }
    }

    /// Also handles abandoning an unfinished workout, which has no log entry.
    func deleteCurrentWorkoutAndResetSession() {
        showHistoryAfterSummaryDismissal = false
        hasPendingWorkoutSave = false
        workoutSaveError = nil
        removeSessionCheckpoint()
        if let id = completedWorkoutEntryID {
            deleteWorkoutLogEntry(id: id)
        }
        reset()
    }

    /// Permanently removes a saved workout and its persisted heart-rate series.
    func deleteWorkoutLogEntry(id: UUID) {
        guard workoutLogEntries.contains(where: { $0.id == id }) else { return }
        rememberDiscardedPhoneWorkout(id)
        workoutLogEntries.removeAll { $0.id == id }
        HeartRateSeriesStore.delete(for: id)
        persistWorkoutLogEntries()
        refreshStreak()
    }

    /// The most recent logged performance set for a modality, available for
    /// comparisons without treating old values as this workout’s performance.
    /// `workoutLogEntries` is kept newest-first, so the first match wins.
    func lastLoggedPerformance(for modality: TrainingModality) -> [IntervalPerformance]? {
        workoutLogEntries.first {
            $0.id != completedWorkoutEntryID && $0.modality == modality
                && !($0.intervalPerformances ?? []).isEmpty
        }?.intervalPerformances
    }

    // MARK: - Performance draft (post-workout summary)

    /// Metric descriptor for the currently selected workout type.
    var currentPerformanceMetric: ModalityMetric {
        selectedWorkoutType.trainingModality.performanceMetric
    }

    /// Unit label to show next to performance values, honouring the unit preference.
    var currentPerformanceUnit: String {
        let metric = currentPerformanceMetric
        if metric.localeConverted, usesImperialUnits, let imperial = metric.imperialUnit {
            return imperial
        }
        return metric.unit
    }

    /// Convert a canonical (stored) value to the user's display units.
    func displayValue(_ canonical: Double, for modality: TrainingModality) -> Double {
        guard modality.performanceMetric.localeConverted, usesImperialUnits else { return canonical }
        return PerformanceUnits.kmhToMph(canonical)
    }

    /// Convert a value entered in display units back to canonical for storage.
    func canonicalValue(_ display: Double, for modality: TrainingModality) -> Double {
        guard modality.performanceMetric.localeConverted, usesImperialUnits else { return display }
        return PerformanceUnits.mphToKmh(display)
    }

    /// Size the review to this session’s frozen plan. Start with blank values:
    /// live autosaving must never turn last session’s performance into new data.
    /// Repeated appearances preserve edits; a new workout type clears values.
    func preparePerformanceDraft() {
        guard preparedPerformanceType != selectedWorkoutType else { return }
        preparedPerformanceType = selectedWorkoutType
        isRestoringOrResetting = true
        defer { isRestoringOrResetting = false; saveReviewEditsIfNeeded() }
        let count = max(0, sessionIntervalCount)
        // Notes are session-specific — never prefilled from history. Preserve
        // anything already typed this session (the draft is re-prepared when
        // the workout type changes).
        if performanceNotesDraft.count != count {
            performanceNotesDraft = Array(repeating: "", count: count)
        }

        performanceSetAll = nil
        performanceDraft = Array(repeating: nil, count: count)
    }

    /// Stamp every work interval with the current "set all" value (the default
    /// behaviour: same value across intervals, individually editable afterward).
    func stampAllIntervals() {
        // Only stamp when "Set all" holds a real value. Clearing the field (or a
        // partial/invalid keystroke, which parses to nil) must NOT wipe the
        // per-interval draft the user may have hand-tuned.
        guard !performanceDraft.isEmpty, let value = performanceSetAll else { return }
        performanceDraft = Array(repeating: value, count: performanceDraft.count)
    }

    /// Convert the draft (display units) into stored performances (canonical),
    /// dropping blanks. Returns nil when nothing was logged.
    private func builtPerformances(for modality: TrainingModality) -> [IntervalPerformance]? {
        let built: [IntervalPerformance] = performanceDraft.enumerated().compactMap { index, value in
            let note = performanceNotesDraft.indices.contains(index)
                ? performanceNotesDraft[index].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            // Keep the interval when it has a value OR a note — a note-only
            // interval ("rower level 6, felt heavy") is worth saving.
            guard value != nil || !note.isEmpty else { return nil }
            return IntervalPerformance(intervalNumber: index + 1,
                                       primary: value.map { canonicalValue($0, for: modality) },
                                       note: note.isEmpty ? nil : note)
        }
        return built.isEmpty ? nil : built
    }

    private func loadWorkoutLogEntries() {
        let raw = workoutLogEntriesData
        guard let data = raw.data(using: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([WorkoutLogEntry].self, from: data) {
            workoutLogEntries = decoded.filter { !isDiscardedPhoneWorkout($0.id) }.sorted { $0.completedAt > $1.completedAt }
            return
        }
        // Recover one row/field at a time. A bad HR summary must not erase
        // another workout's notes, breakdown or performance values.
        unreadableLogData = raw
        let rows = (try? JSONSerialization.jsonObject(with: data)) as? [Any] ?? []
        workoutLogEntries = rows.compactMap { value -> WorkoutLogEntry? in
            guard let row = value as? [String: Any],
                  let rowData = try? JSONSerialization.data(withJSONObject: row) else { return nil }
            if let entry = try? decoder.decode(WorkoutLogEntry.self, from: rowData) { return entry }
            func field<T: Decodable>(_ key: String, as type: T.Type) -> T? {
                guard let value = row[key], !(value is NSNull),
                      let fieldData = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed) else { return nil }
                return try? decoder.decode(type, from: fieldData)
            }
            guard let date = field("completedAt", as: Date.self) else { return nil }
            return WorkoutLogEntry(
                id: field("id", as: UUID.self) ?? UUID(), completedAt: date,
                workoutType: field("workoutType", as: WorkoutType.self) ?? .norwegian4x4,
                notes: (field("notes", as: String.self) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                sessionBreakdown: field("sessionBreakdown", as: WorkoutSessionBreakdown.self),
                modality: field("modality", as: TrainingModality.self),
                intervalPerformances: field("intervalPerformances", as: [IntervalPerformance].self),
                hrSummary: field("hrSummary", as: HRSessionSummary.self),
                endedEarly: field("endedEarly", as: Bool.self)
            )
        }.filter { !isDiscardedPhoneWorkout($0.id) }.sorted { $0.completedAt > $1.completedAt }
        // Never replace unreadable storage until its original bytes are safe.
        if persistWorkoutLogEntries() {
            historyRecoveryNotice = "Some older workout details needed recovery. The original data has been kept on this iPhone."
        }
    }

    func isWorkoutPersistedInLog(_ id: UUID) -> Bool {
        guard let data = workoutLogEntriesData.data(using: .utf8) else { return false }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([WorkoutLogEntry].self, from: data))?.contains { $0.id == id } == true
    }

    @discardableResult
    func persistWorkoutLogEntries() -> Bool {
        do {
            if let raw = unreadableLogData {
                try preserveRecoveryData(Data(raw.utf8), name: "workout-history")
                unreadableLogData = nil
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(workoutLogEntries)
            workoutLogEntriesData = String(decoding: data, as: UTF8.self)
            return true
        } catch {
            workoutSaveError = "Workout history couldn't be saved. Your existing data has been kept. Try again after freeing some storage."
            return false
        }
    }

    private func cancelMissedWorkoutFollowUpReminder(for weekday: Int? = nil) {
        // N2 fix: also cancel the _daily_DD one-shot identifiers produced by scheduleRecurringFollowUp.
        // Previously only the base identifier was cancelled, so daily follow-ups accumulated in the
        // system and kept firing even after the user logged a workout.
        let weekdaysToCancel = weekday.map { [$0] } ?? Array(1...7)
        var identifiers: [String] = []
        for wd in weekdaysToCancel {
            identifiers.append(missedWorkoutFollowUpIdentifier(for: wd)) // legacy one-shot morning-of
            for day in 1...31 {
                identifiers.append("\(missedWorkoutFollowUpIdentifier(for: wd))_daily_\(day)")
            }
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func scheduleMissedWorkoutFollowUpReminder(forScheduledWeekday weekday: Int) {
        guard notificationPermissionState == .granted else { return }
        guard morningOfReminderEnabled else {
            // Comeback nudges are independent of the morning-of family.
            scheduleRecurringFollowUp(for: weekday)
            return
        }

        // N4 fix: use a weekly repeating calendar trigger instead of a one-shot date trigger.
        // The old approach only fired once; since rescheduleRemindersOnAppLaunch was broken (N1),
        // the morning-of notification effectively never repeated after the first week.
        // A repeating trigger persists in the system without needing the app to launch.
        // The identifier is replaced each time this runs (e.g. app foreground), which also
        // rotates the message — slightly better UX than always the same baked-in string.
        let morningMessages: [(String, String)] = [
            ("Rise and grind, Viking! ☀️", "Your workout is waiting. There's no time like the present!"),
            ("Morning workout energy! ⚡", "The best time to train is now. Let's go!"),
            ("Your Viking workout awaits", "Today is your training day. Don't break the streak!"),
            ("Time to conquer, Viking! 🛡️", "Your body is ready. Are you?"),
            ("No more waiting - it's go time! 🎯", "You've committed to train today. Let's do this!")
        ]
        let msg = morningMessages.randomElement()!
        let morningContent = UNMutableNotificationContent()
        morningContent.title = msg.0
        morningContent.body = msg.1
        morningContent.sound = .default

        var morningComponents = DateComponents()
        morningComponents.weekday = weekday
        morningComponents.hour = 8
        morningComponents.minute = 0

        let morningTrigger = UNCalendarNotificationTrigger(dateMatching: morningComponents, repeats: true)
        let morningRequest = UNNotificationRequest(
            identifier: morningOfReminderIdentifier(for: weekday),
            content: morningContent,
            trigger: morningTrigger
        )
        UNUserNotificationCenter.current().add(morningRequest) { error in
            if let error = error {
                print("Error scheduling morning-of reminder: \(error.localizedDescription)")
            }
        }

        // One-shot daily follow-ups for each day until the next workout day.
        // These are cancelled immediately when the user logs a workout (cancelMissedWorkoutFollowUpIfCompletedToday).
        scheduleRecurringFollowUp(for: weekday)
    }
    
    private func scheduleRecurringFollowUp(for weekday: Int) {
        guard comebackNudgesEnabled else { return }
        guard notificationPermissionState == .granted else { return }

        let calendar = Calendar.current
        let now = Date()
        guard let activationDate = reminderActivationDate else { return }

        guard let lastScheduled = previousOccurrence(ofWeekday: weekday, from: now) else { return }
        let startOfLast = calendar.startOfDay(for: lastScheduled)
        guard let nextScheduled = calendar.date(byAdding: .day, value: 7, to: startOfLast) else { return }
        if startOfLast < calendar.startOfDay(for: activationDate) {
            return
        }

        // Follow-ups only start the day *after* the scheduled workout day.
        guard let followUpWindowStart = calendar.date(byAdding: .day, value: 1, to: startOfLast), now >= followUpWindowStart else {
            return
        }

        // If a workout was logged during this weekly cycle already, skip nagging.
        if didLogWorkout(between: startOfLast, and: nextScheduled) {
            return
        }

        // Start scheduling from either the day after the missed workout or today, whichever is later.
        var currentDate = max(followUpWindowStart, calendar.startOfDay(for: now))
        let dayBeforeNext = calendar.date(byAdding: .day, value: -1, to: nextScheduled) ?? nextScheduled

        while currentDate <= dayBeforeNext {
            var notificationComponents = calendar.dateComponents([.year, .month, .day], from: currentDate)
            notificationComponents.hour = 10  // 10am follow-up
            notificationComponents.minute = 0

            if let scheduledDate = calendar.date(from: notificationComponents), scheduledDate <= now {
                // Skip past-due slots so we don't blast the user with an immediate notification
                // when they open the app after 10am; future dates will still fire at 10am.
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? dayBeforeNext.addingTimeInterval(1)
                continue
            }

            let nagMessages: [(String, String)] = [
                ("You missed one day, Viking. No biggie. 🪓", "It's never too late. There's no time like the present."),
                ("Yesterday slipped by - no worries! ⏳", "Your streak isn't dead. Train today and come back stronger!"),
                ("Vikings don't quit - they adapt! ⚔️", "One missed day doesn't define you. Let's get back on the horse!"),
                ("Hey Viking, you okay? 💪", "We miss your energy. Today's a fresh start - let's go!"),
                ("Don't let one day become two! 🚨", "Your future self will thank you. Time to train!"),
                ("The storm doesn't stop the Viking! 🌩️", "Life happens. But your training? That's up to you."),
                ("Vikings rise, even after a fall! 🆙", "One workout is all it takes to get back on track.")
            ]
            let msg = nagMessages.randomElement()!
            let content = UNMutableNotificationContent()
            content.title = msg.0
            content.body = msg.1
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: notificationComponents, repeats: false)
            let identifier = "\(missedWorkoutFollowUpIdentifier(for: weekday))_daily_\(calendar.component(.day, from: currentDate))"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Error scheduling daily follow-up: \(error.localizedDescription)")
                }
            }

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDay
        }
    }

    private func previousOccurrence(ofWeekday weekday: Int, from date: Date) -> Date? {
        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour = 9
        comps.minute = 0

        return Calendar.current.nextDate(
            after: date,
            matching: comps,
            matchingPolicy: .nextTime,
            direction: .backward
        )
    }

    private func didLogWorkout(between start: Date, and end: Date) -> Bool {
        workoutLogEntries.contains { entry in
            entry.completedAt >= start && entry.completedAt < end
        }
    }

    private func hasLoggedWorkout(on date: Date) -> Bool {
        workoutLogEntries.contains { Calendar.current.isDate($0.completedAt, inSameDayAs: date) }
    }

    func cancelMissedWorkoutFollowUpIfCompletedToday() {
        guard workoutReminderMode == .weeklyWeekday else { return }
        // Any logged workout counts as a comeback, so clear all pending follow-ups.
        cancelMissedWorkoutFollowUpReminder()
    }

    func resetSettingsToDefaults() {
        numberOfIntervals = 4
        warmupDuration = 5 * 60
        highIntensityDuration = 4 * 60
        restDuration = 3 * 60
        cooldownEnabled = true
        cooldownDuration = 5 * 60
        alarmEnabled = true
        halfwayVoicePromptsEnabled = true
        tenSecondVoicePromptsEnabled = true
        confirmSkipCooldown = true
        confirmSkipOtherIntervals = false
        preventSleep = true
        hapticsEnabled = true
        liveActivitiesEnabled = true
        userAge = 40
        userBiologicalSexRaw = BiologicalSex.male.rawValue
        vo2TargetTierRaw = ""
        preferredModalityRaw = ""
        defaultWorkoutTypeRaw = ""

        notificationsEnabled = false
        workoutRemindersEnabled = false
        // Families follow the master (off) — they come back on together when
        // reminders are re-enabled (raiseFamilyFlagsIfAllOff).
        isSyncingReminderFamilies = true
        nightBeforeReminderEnabled = false
        morningOfReminderEnabled = false
        comebackNudgesEnabled = false
        isSyncingReminderFamilies = false
        workoutReminderDays = 7
        workoutReminderMode = .weeklyWeekday
        workoutReminderWeekdays = ""
        reminderActivationDate = nil
        
        // Reset streaks but keep commitment
        currentStreak = 0
        longestStreak = 0

        healthKitEnabled = false
        healthKitUserOptedOut = false
        logWorkoutsToHealthKit = true
        healthAuthorizationGranted = false
        vo2DataPoints = []
        lastVO2FetchDate = nil
        lastVO2FetchError = nil
        cancelWorkoutReminder()
        cancelMissedWorkoutFollowUpReminder()

        zoneVisualAlertsEnabled = true
        zoneHapticAlertsEnabled = true
        zoneVoiceAlertsEnabled = false
        appleSensorHREnabled = false
        hrSourcePriorityRaw = ""
        unitPreference = .system
        clearHeartRateState()
        bleHeartRateManager.forgetMonitor()
    }

    // MARK: - Apple Watch & Heart-Rate Zone Feedback

    /// Push the current timer state to a paired Watch. No-op when no Watch app
    /// is installed/reachable, so it's safe to call from every action site.
    func broadcastStateToWatch() {
        phoneSessionManager.sendStateUpdate(to: self)
    }

    /// Single funnel for live heart rate from any source. The aggregator
    /// decides what to display (Bluetooth beats Watch when both are live);
    /// the voice zone engine always evaluates the displayed value, so a
    /// lower-priority source can never drive coaching.
    // MARK: - Heart-rate series recording

    /// Records the live HR stream + interval timeline for the running workout.
    private var hrRecorder: HeartRateSeriesRecorder?
    /// Saved at completion and retained in memory while the summary is open.
    @Published var completedSeries: HeartRateSeries?

    /// Seconds since the workout started, nil when no workout is in progress.
    private var recorderOffset: Double? {
        workoutStartDate.map { Date().timeIntervalSince($0) }
    }

    private func recorderSpanDescriptor(for index: Int)
        -> (kind: String, work: Int, lo: Int, hi: Int)? {
        guard intervals.indices.contains(index) else { return nil }
        switch intervals[index].type {
        case .warmup:
            return (HeartRateSeries.IntervalSpan.kindWarmup, 0, 0, 0)
        case .highIntensity:
            let workNumber = intervals[0...index].filter { $0.type == .highIntensity }.count
            return (HeartRateSeries.IntervalSpan.kindWork, workNumber,
                    highIntensityTargetRange.lowerBound, highIntensityTargetRange.upperBound)
        case .rest:
            return (HeartRateSeries.IntervalSpan.kindRecovery, 0,
                    recoveryTargetRange.lowerBound, recoveryTargetRange.upperBound)
        case .cooldown:
            return (HeartRateSeries.IntervalSpan.kindCooldown, 0, 0, 0)
        }
    }

    /// Close the previous span and open one for the current interval. Call at
    /// workout start and after every interval advance.
    func recorderBeginCurrentInterval(at time: Date = Date()) {
        recorderBeginInterval(at: currentIntervalIndex, time: time)
    }

    private func recorderBeginInterval(at index: Int, time: Date) {
        guard let recorder = hrRecorder, let start = workoutStartDate,
              let d = recorderSpanDescriptor(for: index) else { return }
        let offset = max(0, time.timeIntervalSince(start))
        recorder.beginInterval(kind: d.kind, workNumber: d.work,
                               targetLo: d.lo, targetHi: d.hi, at: offset)
    }

    func ingestHeartRate(_ bpm: Double, from source: HeartRateAggregator.Source) {
        currentHeartRate = heartRateAggregator.ingest(bpm: bpm, from: source, at: Date())
        scheduleHeartRateStalenessSweep()
        if let displayed = currentHeartRate {
            evaluateZoneVoiceFeedback(bpm: displayed)
            // Record the aggregator's accepted value (not the raw reading) so
            // the saved series matches what the user saw. Paused time records
            // nothing — charts show the gap.
            if isRunning, let offset = recorderOffset {
                hrRecorder?.record(bpm: displayed, at: offset)
            }
        }
    }

    /// Clears the displayed heart rate shortly after the last source stops
    /// sending. Rescheduled on every sample, so it only ever fires once the
    /// stream has actually gone quiet — no permanent timer needed, and it
    /// works outside workouts too (when tick() isn't running).
    private func scheduleHeartRateStalenessSweep() {
        heartRateStalenessWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.currentHeartRate = self.heartRateAggregator.currentValue(now: Date())
            if self.currentHeartRate != nil {
                self.scheduleHeartRateStalenessSweep()
            }
        }
        heartRateStalenessWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + heartRateAggregator.freshnessWindow + 0.5,
            execute: work
        )
    }

    /// Drop all remembered heart-rate samples (workout ended or reset). A
    /// still-connected Bluetooth monitor will simply repopulate on its next
    /// notification, which is deliberate — recovery HR is worth seeing.
    private func clearHeartRateState() {
        heartRateStalenessWork?.cancel()
        heartRateStalenessWork = nil
        heartRateAggregator.reset()
        currentHeartRate = nil
        zoneVoiceEngine.reset()
    }

    /// Current zone classification for the live reading — drives HR colour-coding.
    func currentZoneStatus(for bpm: Double) -> HRZoneStatus {
        let range = currentPhaseHRRange
        return zoneVoiceEngine.status(phase: currentWorkoutPhase, bpm: bpm,
                                      low: range?.lowerBound ?? 0,
                                      high: range?.upperBound ?? 0)
    }

    private func evaluateZoneVoiceFeedback(bpm: Double) {
        guard isRunning, zoneVoiceAlertsEnabled, bpm > 0 else { return }
        guard let range = currentPhaseHRRange,
              intervals.indices.contains(currentIntervalIndex) else { return }

        let elapsed = intervals[currentIntervalIndex].duration - timeRemaining
        let alert = zoneVoiceEngine.evaluate(
            intervalKey: currentIntervalIndex,
            phase: currentWorkoutPhase,
            bpm: bpm,
            low: range.lowerBound,
            high: range.upperBound,
            secondsSinceIntervalStart: max(0, elapsed),
            now: Date()
        )
        guard let alert else { return }
        speakZoneAlert(alert, phase: currentWorkoutPhase)
    }

    private func speakZoneAlert(_ alert: ZoneAlertKind, phase: WorkoutPhase) {
        let phrase: String
        switch (alert, phase) {
        case (.pushHarder, _):
            phrase = "Pick up the pace. You're below your target zone."
        case (.easeOff, .rest):
            phrase = "Bring your heart rate down to recover."
        case (.easeOff, _):
            phrase = "Ease off slightly. You're above your target zone."
        }
        SpeechManager.shared.speak(phrase)
    }

    // MARK: - Keep screen awake

    /// Disables the idle timer (screen auto-lock) while a workout is running and
    /// the user has opted in. Re-enables it otherwise. Called reactively from an
    /// `isRunning` subscription, from `preventSleep`'s didSet, and on foreground.
    func updateIdleTimerState() {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = isRunning && preventSleep
        #endif
    }

    // MARK: - Live Activity

    /// Builds the current ContentState from live timer state.
    private func liveActivityContentState(isRunning: Bool) -> N4x4LiveActivityAttributes.ContentState {
        guard intervals.indices.contains(currentIntervalIndex) else {
            return N4x4LiveActivityAttributes.ContentState(
                intervalName: "Workout",
                phase: .warmup,
                intervalEndTime: Date(),
                isRunning: false,
                currentInterval: 1,
                totalIntervals: sessionIntervalCount,
                hrLow: 0, hrHigh: 0
            )
        }
        let interval = intervals[currentIntervalIndex]
        let phase: WorkoutPhase = {
            switch interval.type {
            case .warmup:        return .warmup
            case .highIntensity: return .highIntensity
            case .rest:          return .rest
            case .cooldown:      return .cooldown
            }
        }()
        let completedHIT = intervals[0...currentIntervalIndex]
            .filter { $0.type == .highIntensity }.count
        let totalHIT = max(1, intervals.filter { $0.type == .highIntensity }.count)
        let endTime = isRunning
            ? (intervalEndTime ?? Date().addingTimeInterval(timeRemaining))
            : Date().addingTimeInterval(timeRemaining)
        let maxHR = maximumHeartRate
        let (hrLow, hrHigh): (Int, Int) = {
            // Round (not truncate) so the Dynamic Island matches the target
            // ranges shown in-app and on the Watch.
            func bound(_ pct: Double) -> Int { Int((Double(maxHR) * pct).rounded()) }
            switch phase {
            case .highIntensity: return (bound(0.85), bound(0.95))
            case .warmup:        return (bound(0.60), bound(0.70))
            case .rest:          return (bound(0.60), bound(0.70))
            case .cooldown:      return (bound(0.50), bound(0.60))
            }
        }()
        return N4x4LiveActivityAttributes.ContentState(
            intervalName: interval.name,
            phase: phase,
            intervalEndTime: endTime,
            isRunning: isRunning,
            currentInterval: max(1, completedHIT),
            totalIntervals: totalHIT,
            hrLow: hrLow,
            hrHigh: hrHigh,
            currentHR: currentHeartRate.map { Int($0.rounded()) } ?? 0
        )
    }

    func startLiveActivity() {
        guard isRunning, workoutStartDate != nil, workoutCompletionDate == nil,
              liveActivitiesEnabled, liveActivityProvider.areActivitiesEnabled,
              liveActivity == nil else { return }
        do {
            liveActivity = try liveActivityProvider.request(
                start: workoutStartDate ?? Date(), state: liveActivityContentState(isRunning: true))
        } catch {
            print("Live Activity start failed: \(error)")
        }
    }

    func updateLiveActivity(isRunning: Bool) {
        guard let activity = liveActivity else { return }
        let state = liveActivityContentState(isRunning: isRunning)
        let previous = liveActivityTask
        liveActivityTask = Task { @MainActor [weak self] in
            await previous?.value
            // An update queued before End must never follow the end request.
            guard self?.liveActivity?.id == activity.id else { return }
            await activity.updateWorkout(state)
        }
    }

    func endLiveActivity() {
        // The in-memory reference can be lost after relaunch or an interrupted
        // request. End every activity for this app, including any orphan.
        var activities = liveActivityProvider.activities
        if let liveActivity, !activities.contains(where: { $0.id == liveActivity.id }) {
            activities.append(liveActivity)
        }
        liveActivity = nil
        let previous = liveActivityTask
        liveActivityTask = Task { @MainActor in
            await previous?.value
            for activity in activities {
                await activity.endWorkout()
            }
        }
    }

    /// Long buzz at the moment a new interval starts — the close of the
    /// two-short-taps countdown played in the final 3 seconds.
    private func triggerIntervalHaptic() {
        guard hapticsEnabled else { return }
        playLongHaptic()
    }

    /// The workout's end is signalled by the two countdown taps alone — no
    /// long buzz, since no new interval starts. If the last interval was
    /// skipped the taps never fired, so play them back-to-back now.
    private func triggerCompletionHaptic() {
        guard hapticsEnabled, !countdownTap1Fired else { return }
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            generator.impactOccurred()
        }
    }

    private func playCountdownTapIfNeeded(_ fired: inout Bool) {
        guard !fired else { return }
        fired = true
        guard hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    /// A genuinely long (~0.6 s) vibration needs CoreHaptics; the transient
    /// UIKit generators can only tap. Falls back to a heavy tap on devices
    /// without a haptic engine (or if the engine fails to start).
    private func playLongHaptic() {
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            if hapticEngine == nil { hapticEngine = try? CHHapticEngine() }
            if let engine = hapticEngine {
                do {
                    try engine.start()
                    let event = CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
                        ],
                        relativeTime: 0,
                        duration: 0.6
                    )
                    let pattern = try CHHapticPattern(events: [event], parameters: [])
                    try engine.makePlayer(with: pattern).start(atTime: 0)
                    return
                } catch {
                    // fall through to the transient tap
                }
            }
        }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    func playAlarmIfNeeded() {
        switch audioMode {
        case .alarm:
            playAlarm()
        case .voice:
            resetPromptFlags()
            speakIntervalCueIfNeeded()
        case .silent:
            break
        }
    }

    func playAlarm() {
        guard let url = Bundle.main.url(forResource: "alarm", withExtension: "mp3") else { return }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch {
            print("Error playing alarm sound: \(error.localizedDescription)")
        }
    }

    // MARK: - Voice Prompts

    private func resetPromptFlags() {
        halfwayPromptFired = false
        tenSecondPromptFired = false
        countdownTap1Fired = false
        countdownTap2Fired = false
    }

    /// Returns a natural-language string for a duration in seconds, e.g. "2 minutes", "1 minute and 30 seconds".
    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let mins = total / 60
        let secs = total % 60
        switch (mins, secs) {
        case (0, let s):
            return s == 1 ? "1 second" : "\(s) seconds"
        case (let m, 0):
            return m == 1 ? "1 minute" : "\(m) minutes"
        default:
            let mPart = mins == 1 ? "1 minute" : "\(mins) minutes"
            let sPart = secs == 1 ? "1 second" : "\(secs) seconds"
            return "\(mPart) and \(sPart)"
        }
    }

    /// Speaks an HR-target cue at the start of every High Intensity and every Recovery interval.
    func speakIntervalCueIfNeeded() {
        guard audioMode == .voice else { return }
        guard intervals.indices.contains(currentIntervalIndex) else { return }
        let interval = intervals[currentIntervalIndex]
        let mins = Int(interval.duration / 60)
        let minWord = mins == 1 ? "minute" : "minutes"
        switch interval.type {
        case .highIntensity:
            let lower = highIntensityTargetRange.lowerBound
            let upper = highIntensityTargetRange.upperBound
            SpeechManager.shared.speak("High intensity starting now for \(mins) \(minWord). Target heart rate: \(lower) to \(upper) beats per minute.")
        case .rest:
            let lower = recoveryTargetRange.lowerBound
            let upper = recoveryTargetRange.upperBound
            SpeechManager.shared.speak("Recovery starting now for \(mins) \(minWord). Bring your heart rate down to \(lower) to \(upper) beats per minute.")
        case .cooldown:
            SpeechManager.shared.speak("Cooldown starting now for \(mins) \(minWord). Keep moving at an easy pace and recover.")
        case .warmup:
            break
        }
    }

    private func speakWarmupStartIfNeeded() {
        guard audioMode == .voice else { return }
        guard currentIntervalIndex == 0 else { return }
        guard intervals.indices.contains(0), intervals[0].type == .warmup else { return }
        let minutes = Int(intervals[0].duration / 60)
        let descriptor: String
        if minutes <= 0 {
            descriptor = formatTimeRemaining(intervals[0].duration)
        } else {
            descriptor = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        SpeechManager.shared.speak("Workout started. Warm up for \(descriptor).")
    }

    /// Halfway prompt: HIT gets time remaining + Viking phrase; Recovery gets time remaining only.
    private func speakHalfway() {
        guard audioMode == .voice, halfwayVoicePromptsEnabled, !halfwayPromptFired else { return }
        guard intervals.indices.contains(currentIntervalIndex) else { return }
        let interval = intervals[currentIntervalIndex]
        guard interval.duration >= 60 else { return }
        switch interval.type {
        case .highIntensity:
            halfwayPromptFired = true
            let timeStr = formatTimeRemaining(timeRemaining)
            let phrase = AudioPrompts.halfway.randomElement()!
            SpeechManager.shared.speak("Halfway through interval. \(timeStr) remaining. \(phrase)")
        case .rest:
            halfwayPromptFired = true
            let timeStr = formatTimeRemaining(timeRemaining)
            SpeechManager.shared.speak("Halfway through recovery. \(timeStr) remaining.")
        case .warmup:
            halfwayPromptFired = true
            let timeStr = formatTimeRemaining(timeRemaining)
            SpeechManager.shared.speak("Halfway through warmup. \(timeStr) remaining.")
        case .cooldown:
            halfwayPromptFired = true
            let timeStr = formatTimeRemaining(timeRemaining)
            SpeechManager.shared.speak("Halfway through cooldown. \(timeStr) remaining.")
        }
    }

    /// 10-second warning before any interval ends.
    private func speakTenSeconds() {
        guard audioMode == .voice, tenSecondVoicePromptsEnabled, !tenSecondPromptFired else { return }
        guard intervals.indices.contains(currentIntervalIndex) else { return }
        guard intervals[currentIntervalIndex].duration > 10 else { return }
        tenSecondPromptFired = true
        let message: String
        switch intervals[currentIntervalIndex].type {
        case .warmup:
            message = "10 seconds until your first interval."
        case .highIntensity:
            message = "10 seconds of high intensity remaining."
        case .rest:
            message = "10 seconds of recovery remaining."
        case .cooldown:
            message = "10 seconds until workout complete."
        }
        SpeechManager.shared.speak(message)
    }

    /// Fires a Viking celebration phrase when the workout finishes.
    private func speakWorkoutComplete() {
        guard audioMode == .voice else { return }
        let phrase = AudioPrompts.workoutComplete.randomElement()!
        SpeechManager.shared.speak("Workout complete. Well done! \(phrase)")
    }

    func ensureNotificationPermissionForToggles() {
        guard !isResolvingNotificationPermission else { return }
        isResolvingNotificationPermission = true

        refreshNotificationPermissionState { [weak self] in
            guard let self else { return }
            defer { self.isResolvingNotificationPermission = false }

            switch self.notificationPermissionState {
            case .notDetermined, .unknown:
                self.requestNotificationPermission()
            case .denied, .unavailable:
                if self.notificationsEnabled {
                    self.notificationsEnabled = false
                }
                if self.workoutRemindersEnabled {
                    self.workoutRemindersEnabled = false
                }
            case .granted:
                if self.workoutRemindersEnabled {
                    self.scheduleWorkoutReminder()
                }
            }
        }
    }

    func refreshNotificationPermissionState(completion: (() -> Void)? = nil) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    self.notificationPermissionState = .granted
                case .denied:
                    self.notificationPermissionState = .denied
                case .notDetermined:
                    self.notificationPermissionState = .notDetermined
                @unknown default:
                    self.notificationPermissionState = .unknown
                }
                completion?()
            }
        }
    }

    // Request notification permission
    func requestNotificationPermission() {
        guard !isRequestingNotificationAuthorization else { return }
        isRequestingNotificationAuthorization = true

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Error requesting notification permission: \(error.localizedDescription)")
            }

            DispatchQueue.main.async {
                self.isRequestingNotificationAuthorization = false
                self.notificationPermissionRequested = true
                self.notificationPermissionState = granted ? .granted : .denied
                if !granted {
                    if self.notificationsEnabled {
                        self.notificationsEnabled = false
                    }
                    if self.workoutRemindersEnabled {
                        self.workoutRemindersEnabled = false
                    }
                } else if self.workoutRemindersEnabled {
                    self.scheduleWorkoutReminder()
                }
            }
        }
    }

    // Shared notification helper — used only for in-workout interval cues.
    // N6 fix: guard only on notificationsEnabled. The old guard also passed when
    // workoutRemindersEnabled was true, which caused interval cues to fire even when
    // the user had explicitly disabled them.
    /// Interval cues only. Reminders and birthday nudges have separate owners.
    func scheduleNotification(identifier: String, title: String, body: String, in timeInterval: TimeInterval, repeats: Bool) {
        guard identifier == Self.intervalNotificationID, isRunning, workoutCompletionDate == nil,
              notificationsEnabled, notificationPermissionState == .granted else { return }

        cancelIntervalNotifications()
        let generation = intervalNotificationGeneration
        let previous = intervalNotificationTask
        let center = intervalNotificationCenter
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, timeInterval), repeats: repeats)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        intervalNotificationTask = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, self.intervalNotificationGeneration == generation,
                  self.isRunning, self.workoutCompletionDate == nil else { return }
            do {
                try await center.add(request)
            } catch {
                print("Error scheduling notification: \(error.localizedDescription)")
            }
            // End/pause may have happened while add was suspended. Drain this
            // request before allowing a subsequent workout's add to proceed.
            if self.intervalNotificationGeneration != generation || !self.isRunning {
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
                center.removeDeliveredNotifications(withIdentifiers: [identifier])
            }
        }
    }

    private func cancelIntervalNotifications() {
        intervalNotificationGeneration = UUID()
        let ids = [Self.intervalNotificationID]
        let center = intervalNotificationCenter
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
        let previous = intervalNotificationTask
        intervalNotificationTask = Task { @MainActor in
            await previous?.value
            // removePending alone can run before an in-flight add is accepted.
            center.removePendingNotificationRequests(withIdentifiers: ids)
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    // MARK: - HealthKit

    func requestHealthKitAuthorizationIfNeeded(completion: (() -> Void)? = nil) {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthKitEnabled = false
            healthAuthorizationGranted = false
            healthKitPermissionState = .unavailable
            completion?()
            return
        }

        guard let vo2Type = HKObjectType.quantityType(forIdentifier: .vo2Max) else {
            healthKitPermissionState = .unavailable
            completion?()
            return
        }

        // Date of birth drives the birthday easter egg (BirthdayActivation.swift):
        // read-only characteristic, cached as month/day so nothing on the home
        // screen has to touch HealthKit. Optional on purpose — a user who never
        // entered a birthday just doesn't get that half of the feature.
        var readTypes: Set<HKObjectType> = [vo2Type, HKObjectType.workoutType()]
        if let dobType = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) {
            readTypes.insert(dobType)
        }
        let writeTypes: Set<HKSampleType> = [HKObjectType.workoutType()]

        healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { success, error in
            if let error = error {
                print("HealthKit authorization error: \(error.localizedDescription)")
            }

            DispatchQueue.main.async {
                self.healthAuthorizationGranted = success
                self.refreshHealthKitAuthorizationState()
                self.healthKitEnabled = success
                if success { self.healthKitUserOptedOut = false }
                if success {
                    self.fetchVO2MaxSamples()
                    self.refreshCachedUserBirthday()
                }
                completion?()
            }
        }
    }

    /// Caches the user's birthday (month/day only) for the easter egg. The
    /// characteristic read throws until HealthKit has been authorized for it,
    /// and returns components with no month/day if the user never entered one —
    /// both are silent no-ops, leaving the egg on its 2 August schedule.
    func refreshCachedUserBirthday() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard let components = try? healthStore.dateOfBirthComponents(),
              let month = components.month, let day = components.day else { return }
        let hadBirthday = BirthdayEasterEgg.cachedUserBirthday() != nil
        BirthdayEasterEgg.cacheUserBirthday(month: month, day: day)
        // First grant of the day-of-birth read lands after refreshOnForeground's
        // notification completion has already run, so schedule the nudge here
        // rather than making the user wait for the next foreground.
        if !hadBirthday, notificationPermissionState == .granted {
            BirthdayEasterEgg.scheduleMorningNudges()
        }
    }

    func refreshHealthKitAuthorizationState() {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthKitPermissionState = .unavailable
            healthAuthorizationGranted = false
            return
        }

        let workoutStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        switch workoutStatus {
        case .sharingAuthorized:
            healthKitPermissionState = .granted
            healthAuthorizationGranted = true
            // Re-arm after an iOS-side revoke. `healthKitEnabled` is persisted and
            // the .sharingDenied branch below clears it, so a user who hits "Turn
            // Off All" in Settings > Privacy > Health and then re-grants every
            // toggle would otherwise stay disconnected forever: fetchVO2MaxSamples()
            // is guarded on this flag, so the VO2 card would never come back.
            if !healthKitUserOptedOut { healthKitEnabled = true }
        case .sharingDenied:
            healthKitPermissionState = .denied
            healthAuthorizationGranted = false
            healthKitEnabled = false
        case .notDetermined:
            healthKitPermissionState = .notDetermined
            healthAuthorizationGranted = false
        @unknown default:
            healthKitPermissionState = .unknown
            healthAuthorizationGranted = false
        }
    }

    func fetchVO2MaxSamples() {
        guard healthKitEnabled else { return }
        guard let vo2Type = HKObjectType.quantityType(forIdentifier: .vo2Max) else { return }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: vo2Type, predicate: nil, limit: 60, sortDescriptors: [sortDescriptor]) { _, samples, error in
            if let error = error {
                print("VO2 fetch error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.lastVO2FetchError = error.localizedDescription
                    self.lastVO2FetchDate = Date()
                }
                return
            }

            let unit = HKUnit(from: "mL/kg*min")
            let mapped = (samples as? [HKQuantitySample])?.map { sample in
                VO2DataPoint(date: sample.startDate, value: sample.quantity.doubleValue(for: unit))
            }.reversed().map { $0 } ?? []

            DispatchQueue.main.async {
                self.vo2DataPoints = mapped
                self.lastVO2FetchError = nil
                self.lastVO2FetchDate = Date()
            }
        }

        healthStore.execute(query)
    }

    func saveCompletedWorkoutToHealthKit() {
        let endDate = workoutCompletionDate ?? Date()
        let startDate = workoutStartDate ?? endDate.addingTimeInterval(-totalWorkoutDuration())
        saveWorkoutToHealthKit(start: startDate, end: endDate)
    }

    /// Writes one HIIT workout record to Health for the given span. Used for
    /// the just-finished phone session and for workouts imported from a
    /// standalone Watch run (the Watch never saves — see AGENTS.md).
    func saveWorkoutToHealthKit(start startDate: Date, end endDate: Date) {
        guard healthKitEnabled, healthAuthorizationGranted, logWorkoutsToHealthKit else { return }
        guard endDate > startDate else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = .highIntensityIntervalTraining
        config.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())

        builder.beginCollection(withStart: startDate) { _, beginError in
            if let beginError = beginError {
                print("Workout beginCollection error: \(beginError.localizedDescription)")
                return
            }

            builder.endCollection(withEnd: endDate) { _, endError in
                if let endError = endError {
                    print("Workout endCollection error: \(endError.localizedDescription)")
                    return
                }

                builder.finishWorkout { _, finishError in
                    if let finishError = finishError {
                        print("Workout finish error: \(finishError.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Called when the app returns to the foreground. Refreshes streaks, permissions,
    /// and reschedules one-shot daily follow-up notifications.
    func refreshOnForeground() {
        if workoutStartDate == nil || workoutCompletionDate != nil {
            endLiveActivity()
            cancelIntervalNotifications()
        } else if !isRunning {
            cancelIntervalNotifications()
        }
        if hasPendingWorkoutSave || !pendingWatchImports.isEmpty { retryWorkoutSave() }
        // S1: keep the stored streak in sync with the log (it was previously only ever increased).
        refreshStreak()

        // isIdleTimerDisabled only has effect while the app is foreground+active,
        // so re-assert it here after returning from the background.
        updateIdleTimerState()

        // N1: reschedule one-shot daily follow-ups inside the async permission completion,
        // so notificationPermissionState is guaranteed to be current when we check it.
        refreshNotificationPermissionState { [weak self] in
            guard let self else { return }
            if self.workoutRemindersEnabled {
                self.rescheduleRemindersOnAppLaunch()
            }
            // The 06:00 birthday nudges sit outside the workout-reminder
            // families on purpose: they're once a year and they're the only
            // thing that stops the easter egg being missed entirely.
            if self.notificationPermissionState == .granted {
                BirthdayEasterEgg.scheduleMorningNudges()
            }
        }

        refreshHealthKitAuthorizationState()

        if healthKitEnabled {
            if healthKitPermissionState == .granted {
                fetchVO2MaxSamples()
                refreshCachedUserBirthday()
            } else {
                requestHealthKitAuthorizationIfNeeded()
            }
        }

        // If a remembered Bluetooth monitor hit its connect-retry cap while we
        // were backgrounded, give it a fresh start.
        bleHeartRateManager.reconnectIfNeeded()
    }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    /// Deep link into the Health app so the user can check Cardio Fitness for
    /// themselves. Requires "x-apple-health" in LSApplicationQueriesSchemes.
    static var canOpenHealthApp: Bool {
        guard let url = URL(string: "x-apple-health://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    func openHealthApp() {
        guard let url = URL(string: "x-apple-health://") else { return }
        UIApplication.shared.open(url)
    }

    /// One-tap repair for a connection that went stale — clears the opt-out,
    /// re-arms the flag and re-runs authorization so the VO₂ read fires again.
    /// This is the fix for the case where access was revoked in iOS Settings
    /// and then granted back: the persisted flag alone can't tell that apart
    /// from the user switching Apple Health off inside N4x4.
    func reconnectAppleHealth() {
        healthKitUserOptedOut = false
        healthKitEnabled = true
        requestHealthKitAuthorizationIfNeeded()
    }

    /// Plain-text summary the user can paste into a support email, so a "no
    /// graph" report arrives with the answer already in it.
    func healthDiagnosticsSummary() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var lines: [String] = []
        lines.append("N4x4 \(version) (\(build)) · iOS \(UIDevice.current.systemVersion)")
        lines.append("Health data available: \(HKHealthStore.isHealthDataAvailable() ? "yes" : "no")")
        lines.append("Apple Health enabled in N4x4: \(healthKitEnabled ? "yes" : "no")")
        lines.append("User opted out in-app: \(healthKitUserOptedOut ? "yes" : "no")")
        lines.append("Workout permission: \(healthKitPermissionState.diagnosticLabel)")
        lines.append("VO₂ max readings found: \(vo2DataPoints.count)")
        if let latest = vo2DataPoints.max(by: { $0.date < $1.date }) {
            lines.append("Latest reading: \(String(format: "%.1f", latest.value)) mL/kg·min on \(formatter.string(from: latest.date))")
        }
        if let fetched = lastVO2FetchDate {
            lines.append("Last checked: \(formatter.string(from: fetched))")
        } else {
            lines.append("Last checked: never")
        }
        if let error = lastVO2FetchError {
            lines.append("Last error: \(error)")
        }
        return lines.joined(separator: "\n")
    }

    func reminderWeekdayTitle(_ weekday: Int) -> String {
        Self.reminderWeekdayOptions.first(where: { $0.value == weekday })?.title ?? "Not set"
    }

    static func defaultWorkoutReminderWeekday() -> Int {
        Calendar.current.component(.weekday, from: Date())
    }

    func totalWorkoutDuration() -> TimeInterval {
        intervals.reduce(0) { $0 + $1.duration }
    }
}

// MARK: - AudioPrompts

enum AudioPrompts {
    /// Played at the halfway point of each High Intensity interval.
    static let halfway: [String] = [
        "Halfway there, Viking — the hard part's already behind you!",
        "Halfway done — Odin smiles upon you!",
        "Half the battle won — finish what you started!",
        "The longship is halfway home — keep rowing!",
        "Your ancestors didn't stop halfway through a raid!",
        "Half done! The mead hall is getting closer!",
        "You're at the midpoint — stay fierce!",
        "Halfway through the storm — hold your ground!",
        "The finish is now closer than the start — push on!",
        "Half done — your VO2 max is climbing right now!",
        "Midpoint cleared — the Viking in you is just warming up!",
        "Halfway through — don't waste the effort you've already put in!",
        "You've made it halfway. No turning back now!",
        "The sagas are written in the second half — go write yours!",
        "Halfway done — your future self will thank you at the mead hall!",
        "Keep going, warrior — you're on the home stretch!",
        "Halfway! Valhalla gets closer with every second!",
        "You've conquered half — now finish the conquest!",
        "Halfway! Remember why you started — own the finish!",
        "Half done — unleash everything you have left!"
    ]

    /// Played when the full workout finishes.
    static let workoutComplete: [String] = [
        "Valhalla is earned, not given — and today you earned it!",
        "Another saga written. Odin is proud.",
        "The raid is complete. You conquered every interval!",
        "Warriors don't quit — and you proved it today!",
        "The longship has returned victorious. Well done, Viking!",
        "You showed up, you pushed hard, and you won.",
        "Your VO2 max just got a little stronger. That's a Viking win.",
        "The mead hall awaits. You've earned your rest.",
        "Every interval, every drop of sweat — it all counted.",
        "Thor himself would raise a horn to that effort!",
        "Legend built, one interval at a time. See you next session!",
        "The forge has made you stronger. Rest now, warrior.",
        "Not everyone trains like a Viking — you just proved you do.",
        "That's how sagas begin. Keep showing up.",
        "You're writing your fitness story one workout at a time. Chapter done.",
        "Strength, grit, and glory — you brought all three today.",
        "The ancestors are smiling. That was a great workout.",
        "Done. Stronger. Ready for the next raid.",
        "That's the N4x4 way. Feel that — that's progress.",
        "Odin counted every second. He's impressed."
    ]
}

// MARK: - Durable phone-session recovery

private struct PhoneWorkoutCheckpoint: Codable {
    let version: Int
    let id: UUID
    let startedAt: Date
    let savedAt: Date
    let progressAt: Date
    let intervals: [Interval]
    let currentIndex: Int
    let remaining: Double
    let breakdown: WorkoutSessionBreakdown
    let workoutType: WorkoutType
    let recorder: HeartRateSeriesRecorder?
    let completedSeries: HeartRateSeries?
    let completedEntry: WorkoutLogEntry?
}

extension TimerViewModel {
    static var defaultCheckpointURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhoneWorkout/current.json")
    }

    /// Save the work actually done, whether running, paused or recovered.
    func finishAndSaveWorkout(for expectedID: UUID? = nil, now: Date = Date()) {
        if let expectedID, expectedID != activeWorkoutID { return }
        guard workoutStartDate != nil, workoutCompletionDate == nil else { return }
        if isRunning { reconcileTimerState(now: now, playAlarm: false) }
        guard workoutCompletionDate == nil else { return }
        if intervals.contains(where: { $0.type == .cooldown }),
           elapsedCooldownTime < intervals.filter({ $0.type == .cooldown }).reduce(0, { $0 + $1.duration }) {
            skippedCooldownThisSession = true
        }
        finishWorkout(at: isRunning ? now : (lastProgressDate ?? now))
    }

    func discardActiveWorkout(for expectedID: UUID? = nil) {
        if let expectedID, expectedID != activeWorkoutID { return }
        // A delayed discard of an active session must never delete a completion.
        guard workoutCompletionDate == nil else { return }
        reset()
    }

    func reportWorkoutSaveFailure(_ message: String) { workoutSaveError = message }

    func didSaveWatchImport(_ id: UUID) {
        pendingWatchImports.removeValue(forKey: id)
        if pendingWatchImports.isEmpty, !hasPendingWorkoutSave, workoutStartDate == nil { workoutSaveError = nil }
    }

    func retryWorkoutSave() {
        for record in Array(pendingWatchImports.values) {
            importWatchWorkout(record)
            if canAcknowledgeWatchWorkout(record.id) { phoneSessionManager.acknowledgeStoredWatchWorkout(record.id) }
        }
        if workoutCompletionDate != nil {
            persistCompletedWorkout()
        } else if workoutStartDate != nil {
            if isRunning { reconcileTimerState(now: Date(), playAlarm: false) }
            saveSessionCheckpoint(force: true)
        } else if pendingWatchImports.isEmpty, persistWorkoutLogEntries() {
            workoutSaveError = nil
        }
    }

    /// Called on background entry as well as on timer boundaries and controls.
    func checkpointOnBackground() {
        if isRunning { reconcileTimerState(now: Date(), playAlarm: false) }
        if workoutCompletionDate == nil { saveSessionCheckpoint(force: true) }
        else if hasPendingWorkoutSave { persistCompletedWorkout() }
    }

    @discardableResult
    private func saveSessionCheckpoint(now: Date = Date(), force: Bool = false) -> Bool {
        guard let id = activeWorkoutID, let start = workoutStartDate else { return false }
        if !force, let last = lastCheckpointDate, (0..<5).contains(now.timeIntervalSince(last)) { return true }
        let snapshot = PhoneWorkoutCheckpoint(
            version: 1, id: id, startedAt: start, savedAt: now,
            progressAt: lastProgressDate ?? start, intervals: intervals,
            currentIndex: currentIntervalIndex, remaining: timeRemaining,
            breakdown: currentSessionBreakdown, workoutType: sessionWorkoutType ?? selectedWorkoutType,
            recorder: hrRecorder, completedSeries: completedSeries,
            completedEntry: completedWorkoutEntryID.flatMap { id in workoutLogEntries.first { $0.id == id } }
        )
        do {
            if let unreadableCheckpointData {
                try preserveRecoveryData(unreadableCheckpointData, name: "phone-session")
                self.unreadableCheckpointData = nil
            }
            try FileManager.default.createDirectory(at: checkpointURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: checkpointURL, options: .atomic)
            lastCheckpointDate = now
            if workoutCompletionDate == nil, pendingWatchImports.isEmpty { workoutSaveError = nil }
            return true
        } catch {
            workoutSaveError = "Your latest progress couldn't be saved. Free some storage and try again."
            return false
        }
    }

    private func restoreSessionCheckpoint() {
        guard FileManager.default.fileExists(atPath: checkpointURL.path) else { return }
        do {
            let data = try Data(contentsOf: checkpointURL)
            let snapshot: PhoneWorkoutCheckpoint
            do {
                snapshot = try JSONDecoder().decode(PhoneWorkoutCheckpoint.self, from: data)
                guard snapshot.version == 1, !snapshot.intervals.isEmpty,
                      snapshot.intervals.indices.contains(snapshot.currentIndex),
                      snapshot.remaining.isFinite, snapshot.remaining >= 0,
                      snapshot.intervals.allSatisfy({ $0.duration.isFinite && $0.duration >= 0 }) else {
                    throw CocoaError(.coderReadCorrupt)
                }
            } catch {
                unreadableCheckpointData = data
                try preserveRecoveryData(data, name: "phone-session")
                unreadableCheckpointData = nil
                removeSessionCheckpoint()
                historyRecoveryNotice = "An interrupted workout couldn't be read. Its original data has been kept for recovery."
                return
            }
            if isDiscardedPhoneWorkout(snapshot.id) {
                removeSessionCheckpoint()
                return
            }
            if let entry = snapshot.completedEntry,
               workoutLogEntries.contains(where: { stored in
                   stored.id == entry.id && abs(stored.completedAt.timeIntervalSince(entry.completedAt)) < 1
                       && stored.workoutType == entry.workoutType && stored.notes == entry.notes
                       && stored.sessionBreakdown == entry.sessionBreakdown && stored.modality == entry.modality
                       && stored.intervalPerformances == entry.intervalPerformances && stored.hrSummary == entry.hrSummary
                       && stored.endedEarly == entry.endedEarly
               }),
               snapshot.completedSeries == nil || HeartRateSeriesStore.load(for: entry.id) == snapshot.completedSeries {
                // A crash after committing History but before removing the checkpoint.
                removeSessionCheckpoint()
                return
            }
            isRestoringOrResetting = true
            activeWorkoutID = snapshot.id
            workoutStartDate = snapshot.startedAt
            sessionWorkoutType = snapshot.workoutType
            selectedWorkoutType = snapshot.workoutType
            intervals = snapshot.intervals
            currentIntervalIndex = snapshot.currentIndex
            timeRemaining = snapshot.remaining
            elapsedWarmupTime = snapshot.breakdown.warmupDuration
            elapsedHighIntensityTime = snapshot.breakdown.highIntensityDuration
            elapsedRecoveryTime = snapshot.breakdown.recoveryDuration
            elapsedCooldownTime = snapshot.breakdown.cooldownDuration
            skippedCooldownThisSession = snapshot.breakdown.cooldownSkipped
            hrRecorder = snapshot.recorder
            lastProgressDate = snapshot.progressAt
            // Do not invent exercise while the process was absent. Resume from
            // the last checkpoint, paused, with the original plan and identity.
            isRunning = false
            intervalEndTime = nil
            updateCounts()
            if let entry = snapshot.completedEntry {
                workoutCompletionDate = entry.completedAt
                completedSeries = snapshot.completedSeries
                hrRecorder = nil
                completedSeriesNeedsSave = completedSeries != nil
                selectedWorkoutType = entry.workoutType
                workoutNotesDraft = entry.notes
                sessionEndedEarly = entry.endedEarly == true
                performanceDraft = (1...max(1, sessionIntervalCount)).map { number in
                    entry.intervalPerformances?.first { $0.intervalNumber == number }?.primary
                        .map { displayValue($0, for: entry.workoutType.trainingModality) }
                }
                performanceNotesDraft = (1...max(1, sessionIntervalCount)).map { number in
                    entry.intervalPerformances?.first { $0.intervalNumber == number }?.note ?? ""
                }
                preparedPerformanceType = selectedWorkoutType
                // Upsert under the original ID, including when a previous log
                // write succeeded but its series write failed.
                completedWorkoutEntryID = nil
                isRestoringOrResetting = false
                persistCompletedWorkout()
                showPostWorkoutSummary = true
            } else {
                isRestoringOrResetting = false
                showWorkoutRecovery = true
            }
        } catch {
            isRestoringOrResetting = false
            workoutSaveError = "Your interrupted workout couldn't be opened. Its saved data is still on this iPhone."
        }
    }

    private func removeSessionCheckpoint() {
        guard FileManager.default.fileExists(atPath: checkpointURL.path) else { return }
        try? FileManager.default.removeItem(at: checkpointURL)
    }

    private func preserveRecoveryData(_ data: Data, name: String) throws {
        let directory = checkpointURL.deletingLastPathComponent().appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name)-\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
    }

    private func rememberDiscardedPhoneWorkout(_ id: UUID) {
        var ids = Set(UserDefaults.standard.stringArray(forKey: "discardedPhoneWorkoutIDs") ?? [])
        ids.insert(id.uuidString)
        UserDefaults.standard.set(Array(ids), forKey: "discardedPhoneWorkoutIDs")
    }

    func isDiscardedPhoneWorkout(_ id: UUID) -> Bool {
        (UserDefaults.standard.stringArray(forKey: "discardedPhoneWorkoutIDs") ?? []).contains(id.uuidString)
    }

    /// Separate, ID-bound commands prevent an old finish/discard from deleting
    /// a just-saved workout or affecting a newer session.
    func handleWorkoutCommand(_ command: String, workoutID: UUID) {
        switch command {
        case WatchMessageKey.cmdFinish:
            guard workoutID == activeWorkoutID else { return }
            finishAndSaveWorkout()
        case WatchMessageKey.cmdDiscard:
            guard workoutID == activeWorkoutID, workoutCompletionDate == nil else { return }
            discardActiveWorkout()
        case WatchMessageKey.cmdDeleteCompleted:
            guard workoutLogEntries.contains(where: { $0.id == workoutID }) else { return }
            if workoutID == completedWorkoutEntryID { deleteCurrentWorkoutAndResetSession() }
            else { deleteWorkoutLogEntry(id: workoutID) }
        default:
            break
        }
    }
}
