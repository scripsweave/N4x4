// TimerViewModel.swift

import SwiftUI
import Combine
import AVFoundation
import UserNotifications
import HealthKit

enum PermissionState: Equatable {
    case unknown
    case notDetermined
    case granted
    case denied
    case unavailable
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
    case rowing = "Rowing"
    case treadmill = "Treadmill"
    case hillSprints = "Hill sprints"
    case stairs = "Stairs"
    case jumpRope = "Jump rope"
    case circuit = "Circuit"
    case sports = "Sports"
    case other = "Other"

    var id: String { rawValue }
}

struct WorkoutLogEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let completedAt: Date
    let workoutType: WorkoutType
    let notes: String

    init(id: UUID = UUID(), completedAt: Date = Date(), workoutType: WorkoutType, notes: String) {
        self.id = id
        self.completedAt = completedAt
        self.workoutType = workoutType
        self.notes = notes
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

private struct LegacyWorkoutLogEntryV1: Decodable {
    let id: UUID?
    let completedAt: Date
}

private struct LegacyWorkoutLogEntryV2: Decodable {
    let id: UUID?
    let completedAt: Date
    let workoutType: String?
    let notes: String?
}

struct VO2DataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

class TimerViewModel: ObservableObject {
    static let minimumSupportedAge = 13
    static let maximumSupportedAge = 100
    private static let missedWorkoutFollowUpIdentifierPrefix = "workoutReminderFollowup_"
    
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
            reset()
        }
    }
    @AppStorage("warmupDuration") var warmupDuration: TimeInterval = 5 * 60 {
        didSet {
            guard oldValue != warmupDuration else { return }
            reset()
        }
    }
    @AppStorage("highIntensityDuration") var highIntensityDuration: TimeInterval = 4 * 60 {
        didSet {
            guard oldValue != highIntensityDuration else { return }
            reset()
        }
    }
    @AppStorage("restDuration") var restDuration: TimeInterval = 3 * 60 {
        didSet {
            guard oldValue != restDuration else { return }
            reset()
        }
    }
    @AppStorage("alarmEnabled") var alarmEnabled: Bool = true
    @AppStorage("audioModeRaw") private var audioModeRaw: String = AudioMode.voice.rawValue

    var audioMode: AudioMode {
        get { AudioMode(rawValue: audioModeRaw) ?? .alarm }
        set { audioModeRaw = newValue.rawValue }
    }

    @AppStorage("preventSleep") var preventSleep: Bool = true
    @AppStorage("hapticsEnabled") var hapticsEnabled: Bool = true
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

    // Interval notifications
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = false {
        didSet {
            guard oldValue != notificationsEnabled else { return }
            if notificationsEnabled {
                ensureNotificationPermissionForToggles()
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
                ensureNotificationPermissionForToggles()
                scheduleWorkoutReminder()
            } else {
                cancelWorkoutReminder()
            }
        }
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

    // Legacy support for single weekday
    @AppStorage("workoutReminderWeekday") var workoutReminderWeekday: Int = 0 {
        didSet {
            // Migrate legacy single weekday to new format
            if oldValue > 0 && workoutReminderWeekdays.isEmpty {
                workoutReminderWeekdays = String(oldValue)
            }
        }
    }


    @AppStorage("workoutLogEntriesData") private var workoutLogEntriesData: String = "[]"
    @Published var workoutLogEntries: [WorkoutLogEntry] = []
    @Published var selectedWorkoutType: WorkoutType = .norwegian4x4
    @Published var workoutNotesDraft: String = ""
    @Published var showPostWorkoutSummary: Bool = false
    @Published var showWeeklyStreaks: Bool = false

    // HealthKit
    @AppStorage("healthKitEnabled") var healthKitEnabled: Bool = false
    @AppStorage("logWorkoutsToHealthKit") var logWorkoutsToHealthKit: Bool = true
    @Published var healthAuthorizationGranted: Bool = false
    @Published var vo2DataPoints: [VO2DataPoint] = []

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

    // MARK: - Multi-day Reminder Helpers

    // @Published property for stable in-memory state (synced with AppStorage)
    @Published var selectedWeekdaysList: [Int] = [] {
        didSet {
            // Sync to AppStorage when value changes (via flag to prevent circular sync)
            isSyncingFromPublished = true
            let sorted = selectedWeekdaysList.sorted()
            workoutReminderWeekdays = sorted.map { String($0) }.joined(separator: ",")
            isSyncingFromPublished = false
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
        let uniqueWeeks: Set<WeekKey> = Set(workoutLogEntries.map { WeekKey(year: $0.year, week: $0.weekOfYear) })
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

    private let healthStore = HKHealthStore()
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

    var intervals: [Interval] = []
    var timer: AnyCancellable?
    var player: AVAudioPlayer?
    var intervalEndTime: Date?
    var workoutStartDate: Date?

    // Voice prompt state — reset on every interval change, reset, and skip
    private var halfwayPromptFired = false
    private var tenSecondPromptFired = false

    var maximumHeartRate: Int {
        max(1, 220 - userAge)
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

    init() {
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

        // One-time migration from the old alarmEnabled bool to AudioMode.
        // Users who had alarm on (or are brand new) get Voice Prompts as the new default.
        // Only users who explicitly disabled alarm stay on Silent.
        if UserDefaults.standard.object(forKey: "audioModeRaw") == nil {
            audioMode = alarmEnabled ? .voice : .silent
        }

        setupIntervals()
        loadWorkoutLogEntries()

        // Sync the stored streak value immediately on launch (S1).
        // Previously currentStreak was only ever increased, so a missed-week streak
        // would never be reflected until the user started a new run of workouts.
        refreshStreak()

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
            requestHealthKitAuthorizationIfNeeded()
        }
    }

    func setupIntervals() {
        intervals.removeAll()
        highIntensityCount = 0
        restCount = 0

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

    func startTimer() {
        guard !intervals.isEmpty, intervals.indices.contains(currentIntervalIndex) else { return }

        timer?.cancel()
        timer = nil

        isRunning = true
        if workoutStartDate == nil {
            workoutStartDate = Date()
        }
        if intervalEndTime == nil {
            intervalEndTime = Date().addingTimeInterval(timeRemaining)
        }

        reconcileTimerState(now: Date(), playAlarm: false)
        guard isRunning else { return }

        speakIntervalCueIfNeeded()
        speakWarmupStartIfNeeded()

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["nextInterval"])
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
    }

    func tick() {
        guard isRunning else { return }
        reconcileTimerState(now: Date(), playAlarm: true)
    }

    func reconcileTimerState(now: Date = Date(), playAlarm: Bool) {
        guard isRunning else { return }
        guard !intervals.isEmpty, intervals.indices.contains(currentIntervalIndex) else {
            stopTimer()
            return
        }

        if intervalEndTime == nil {
            intervalEndTime = now.addingTimeInterval(timeRemaining)
        }

        guard let endTime = intervalEndTime else { return }

        if now < endTime {
            timeRemaining = max(0, endTime.timeIntervalSince(now))

            // Halfway voice prompt
            let halfwayPoint = intervals[currentIntervalIndex].duration / 2
            if timeRemaining <= halfwayPoint {
                speakHalfway()
            }

            // 10-second warning
            if timeRemaining <= 10 && timeRemaining > 0 {
                speakTenSeconds()
            }

            return
        }

        var cursor = currentIntervalIndex
        var intervalEndCursor = endTime
        var advanced = false

        while now >= intervalEndCursor {
            advanced = true
            if cursor + 1 >= intervals.count {
                finishWorkout()
                return
            }

            cursor += 1
            intervalEndCursor = intervalEndCursor.addingTimeInterval(intervals[cursor].duration)
        }

        currentIntervalIndex = cursor
        updateCounts()
        intervalEndTime = intervalEndCursor
        timeRemaining = max(0, intervalEndCursor.timeIntervalSince(now))

        if advanced {
            if playAlarm {
                playAlarmIfNeeded()
            }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["nextInterval"])
            scheduleNextIntervalNotification()
        }
    }

    func finishWorkout() {
        triggerCompletionHaptic()
        stopTimer()
        speakWorkoutComplete()
        intervalEndTime = nil
        timeRemaining = 0
        showCompletionMessage = false
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["nextInterval"])

        selectedWorkoutType = .norwegian4x4
        workoutNotesDraft = ""
        showPostWorkoutSummary = true
        
        // Update streak
        updateStreakOnWorkoutComplete()

        if workoutRemindersEnabled {
            scheduleWorkoutReminder()
        }
        if healthKitEnabled {
            saveCompletedWorkoutToHealthKit()
            fetchVO2MaxSamples()
        }
    }

    func moveToNextInterval() {
        resetPromptFlags()
        triggerIntervalHaptic()
        if currentIntervalIndex + 1 < intervals.count {
            currentIntervalIndex += 1
            timeRemaining = intervals[currentIntervalIndex].duration
            intervalEndTime = isRunning ? Date().addingTimeInterval(timeRemaining) : nil

            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["nextInterval"])
            updateCounts()
            if isRunning {
                scheduleNextIntervalNotification()
            }
        } else {
            finishWorkout()
        }
    }

    func pause() {
        if isRunning {
            SpeechManager.shared.stopSpeaking()
            timeRemaining = max(0, intervalEndTime?.timeIntervalSinceNow ?? timeRemaining)
            stopTimer()
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["nextInterval"])
        } else {
            intervalEndTime = Date().addingTimeInterval(timeRemaining)
            scheduleNextIntervalNotification()
            startTimer()
        }
    }

    func skip() {
        guard intervals.indices.contains(currentIntervalIndex) else { return }

        // Cancel any in-flight speech for the interval we're leaving so
        // prompts don't bleed into the next interval after a skip.
        SpeechManager.shared.stopSpeaking()
        if audioMode != .voice {
            playAlarmIfNeeded()
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["nextInterval"])
        let wasRunning = isRunning
        moveToNextInterval()

        if wasRunning, !showPostWorkoutSummary {
            startTimer()
        }
    }

    func reset() {
        SpeechManager.shared.stopSpeaking()
        resetPromptFlags()
        stopTimer()
        setupIntervals()
        loadWorkoutLogEntries()
        isRunning = false
        showCompletionMessage = false
        showPostWorkoutSummary = false
        intervalEndTime = nil
        workoutStartDate = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["nextInterval"])
    }

    func scheduleNextIntervalNotification() {
        guard notificationsEnabled else { return }
        guard currentIntervalIndex + 1 < intervals.count else { return }

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

    private func scheduleWeeklyWorkoutReminder(weekday: Int) {
        guard (1...7).contains(weekday) else { return }
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



    func saveWorkoutLogEntryAndResetSession() {
        let trimmedNotes = workoutNotesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = WorkoutLogEntry(
            completedAt: Date(),
            workoutType: selectedWorkoutType,
            notes: trimmedNotes
        )
        workoutLogEntries.insert(entry, at: 0)
        persistWorkoutLogEntries()
        cancelMissedWorkoutFollowUpIfCompletedToday()
        showPostWorkoutSummary = false
        showWeeklyStreaks = true
        reset()
    }

    func closePostWorkoutSummaryWithoutSaving() {
        showPostWorkoutSummary = false
        reset()
    }

    private func loadWorkoutLogEntries() {
        guard let data = workoutLogEntriesData.data(using: .utf8) else {
            workoutLogEntries = []
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let decoded = try? decoder.decode([WorkoutLogEntry].self, from: data) {
            workoutLogEntries = decoded.sorted { $0.completedAt > $1.completedAt }
            return
        }

        if let legacyV2 = try? decoder.decode([LegacyWorkoutLogEntryV2].self, from: data) {
            workoutLogEntries = legacyV2
                .map {
                    WorkoutLogEntry(
                        id: $0.id ?? UUID(),
                        completedAt: $0.completedAt,
                        workoutType: WorkoutType(rawValue: $0.workoutType ?? "") ?? .norwegian4x4,
                        notes: ($0.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                .sorted { $0.completedAt > $1.completedAt }
            persistWorkoutLogEntries()
            return
        }

        if let legacyV1 = try? decoder.decode([LegacyWorkoutLogEntryV1].self, from: data) {
            workoutLogEntries = legacyV1
                .map {
                    WorkoutLogEntry(
                        id: $0.id ?? UUID(),
                        completedAt: $0.completedAt,
                        workoutType: .norwegian4x4,
                        notes: ""
                    )
                }
                .sorted { $0.completedAt > $1.completedAt }
            persistWorkoutLogEntries()
            return
        }

        workoutLogEntries = []
    }

    private func persistWorkoutLogEntries() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(workoutLogEntries), let json = String(data: data, encoding: .utf8) {
            workoutLogEntriesData = json
        } else {
            // G5: surface encode failures so they're visible in logs rather than silently losing data.
            print("[N4x4] Warning: Failed to persist workout log entries — workout data may not be saved.")
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
        guard notificationPermissionState == .granted else { return }

        let calendar = Calendar.current
        let now = Date()

        guard let lastScheduled = previousOccurrence(ofWeekday: weekday, from: now) else { return }
        let startOfLast = calendar.startOfDay(for: lastScheduled)
        guard let nextScheduled = calendar.date(byAdding: .day, value: 7, to: startOfLast) else { return }

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

    private func cancelMissedWorkoutFollowUpIfCompletedToday() {
        guard workoutReminderMode == .weeklyWeekday else { return }
        // Any logged workout counts as a comeback, so clear all pending follow-ups.
        cancelMissedWorkoutFollowUpReminder()
    }

    func resetSettingsToDefaults() {
        numberOfIntervals = 4
        warmupDuration = 5 * 60
        highIntensityDuration = 4 * 60
        restDuration = 3 * 60
        alarmEnabled = true
        preventSleep = true
        hapticsEnabled = true
        userAge = 40

        notificationsEnabled = false
        workoutRemindersEnabled = false
        workoutReminderDays = 7
        workoutReminderMode = .weeklyWeekday
        workoutReminderWeekdays = ""
        
        // Reset streaks but keep commitment
        currentStreak = 0
        longestStreak = 0

        healthKitEnabled = false
        logWorkoutsToHealthKit = true
        healthAuthorizationGranted = false
        vo2DataPoints = []
        cancelWorkoutReminder()
        cancelMissedWorkoutFollowUpReminder()
    }

    private func triggerIntervalHaptic() {
        guard hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    private func triggerCompletionHaptic() {
        guard hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
        default:
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
        guard audioMode == .voice, !halfwayPromptFired else { return }
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
        default:
            break
        }
    }

    /// 10-second warning before any interval ends.
    private func speakTenSeconds() {
        guard audioMode == .voice, !tenSecondPromptFired else { return }
        guard intervals.indices.contains(currentIntervalIndex) else { return }
        guard intervals[currentIntervalIndex].duration > 10 else { return }
        tenSecondPromptFired = true
        SpeechManager.shared.speak("10 seconds of interval remaining.")
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
    func scheduleNotification(identifier: String, title: String, body: String, in timeInterval: TimeInterval, repeats: Bool) {
        guard notificationsEnabled else { return }
        guard notificationPermissionState == .granted else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, timeInterval), repeats: repeats)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - HealthKit

    func requestHealthKitAuthorizationIfNeeded() {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthKitEnabled = false
            healthAuthorizationGranted = false
            healthKitPermissionState = .unavailable
            return
        }

        guard let vo2Type = HKObjectType.quantityType(forIdentifier: .vo2Max) else {
            healthKitPermissionState = .unavailable
            return
        }

        let readTypes: Set<HKObjectType> = [vo2Type, HKObjectType.workoutType()]
        let writeTypes: Set<HKSampleType> = [HKObjectType.workoutType()]

        healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { success, error in
            DispatchQueue.main.async {
                self.healthAuthorizationGranted = success
                self.refreshHealthKitAuthorizationState()
                self.healthKitEnabled = success
            }

            if let error = error {
                print("HealthKit authorization error: \(error.localizedDescription)")
            }

            if success {
                self.fetchVO2MaxSamples()
            }
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

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(sampleType: vo2Type, predicate: nil, limit: 60, sortDescriptors: [sortDescriptor]) { _, samples, error in
            if let error = error {
                print("VO2 fetch error: \(error.localizedDescription)")
                return
            }

            let unit = HKUnit(from: "mL/kg*min")
            let mapped = (samples as? [HKQuantitySample])?.map { sample in
                VO2DataPoint(date: sample.startDate, value: sample.quantity.doubleValue(for: unit))
            } ?? []

            DispatchQueue.main.async {
                self.vo2DataPoints = mapped
            }
        }

        healthStore.execute(query)
    }

    func saveCompletedWorkoutToHealthKit() {
        guard healthKitEnabled, healthAuthorizationGranted, logWorkoutsToHealthKit else { return }

        let endDate = Date()
        let startDate = workoutStartDate ?? endDate.addingTimeInterval(-totalWorkoutDuration())

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
        // S1: keep the stored streak in sync with the log (it was previously only ever increased).
        refreshStreak()

        // N1: reschedule one-shot daily follow-ups inside the async permission completion,
        // so notificationPermissionState is guaranteed to be current when we check it.
        refreshNotificationPermissionState { [weak self] in
            guard let self else { return }
            if self.workoutRemindersEnabled {
                self.rescheduleRemindersOnAppLaunch()
            }
        }

        refreshHealthKitAuthorizationState()
    }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
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
