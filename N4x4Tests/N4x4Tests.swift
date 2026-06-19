import XCTest
@testable import N4x4

final class N4x4Tests: XCTestCase {

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        [
            "numberOfIntervals",
            "warmupDuration",
            "highIntensityDuration",
            "restDuration",
            "alarmEnabled",
            "preventSleep",
            "userAge",
            "notificationsEnabled",
            "notificationPermissionRequested",
            "workoutRemindersEnabled",
            "workoutReminderDays",
            "workoutReminderMode",
            "workoutReminderWeekday",
            "healthKitEnabled",
            "hasCompletedOnboarding",
            "workoutLogEntriesData"
        ].forEach { defaults.removeObject(forKey: $0) }
    }

    func testSetupIntervalsIncludesWarmupAndCorrectPattern() {
        let vm = TimerViewModel()
        vm.numberOfIntervals = 3
        vm.warmupDuration = 120
        vm.highIntensityDuration = 240
        vm.restDuration = 180
        vm.setupIntervals()

        XCTAssertEqual(vm.intervals.count, 6)
        XCTAssertEqual(vm.intervals[0].type, .warmup)
        XCTAssertEqual(vm.intervals[1].type, .highIntensity)
        XCTAssertEqual(vm.intervals[2].type, .rest)
        XCTAssertEqual(vm.intervals[2].name, "Recovery")
        XCTAssertEqual(vm.intervals[3].type, .highIntensity)
        XCTAssertEqual(vm.intervals[4].type, .rest)
        XCTAssertEqual(vm.intervals[4].name, "Recovery")
        XCTAssertEqual(vm.intervals[5].type, .highIntensity)
    }

    func testCatchUpAdvancesAcrossMultipleIntervals() {
        let vm = TimerViewModel()
        vm.numberOfIntervals = 2
        vm.warmupDuration = 10
        vm.highIntensityDuration = 10
        vm.restDuration = 10
        vm.setupIntervals()

        vm.isRunning = true
        vm.currentIntervalIndex = 0
        vm.timeRemaining = 10

        let start = Date()
        vm.intervalEndTime = start.addingTimeInterval(10)

        vm.reconcileTimerState(now: start.addingTimeInterval(25), playAlarm: false)

        XCTAssertEqual(vm.currentIntervalIndex, 2, "Expected to advance warmup + first high interval")
        XCTAssertGreaterThan(vm.timeRemaining, 0)
        XCTAssertLessThanOrEqual(vm.timeRemaining, 10)
        XCTAssertTrue(vm.isRunning)
    }

    func testCatchUpCompletesWorkoutWhenFarPastEnd() {
        let vm = TimerViewModel()
        vm.numberOfIntervals = 1
        vm.warmupDuration = 5
        vm.highIntensityDuration = 5
        vm.setupIntervals()

        vm.isRunning = true
        vm.currentIntervalIndex = 0
        vm.timeRemaining = 5

        let start = Date()
        vm.intervalEndTime = start.addingTimeInterval(5)

        vm.reconcileTimerState(now: start.addingTimeInterval(20), playAlarm: false)

        XCTAssertTrue(vm.showPostWorkoutSummary)
        XCTAssertFalse(vm.isRunning)
        XCTAssertEqual(vm.timeRemaining, 0)
    }

    func testPauseAndResumeMaintainsRunningState() {
        let vm = TimerViewModel()
        vm.setupIntervals()

        vm.startTimer()
        XCTAssertTrue(vm.isRunning)

        vm.pause()
        XCTAssertFalse(vm.isRunning)

        vm.pause()
        XCTAssertTrue(vm.isRunning)
    }

    func testSkipAdvancesCurrentInterval() {
        let vm = TimerViewModel()
        vm.numberOfIntervals = 2
        vm.warmupDuration = 10
        vm.setupIntervals()
        vm.currentIntervalIndex = 0
        vm.timeRemaining = 10

        vm.skip()

        XCTAssertEqual(vm.currentIntervalIndex, 1)
    }

    func testSkipWhilePausedDoesNotStartElapsedCountdown() {
        let vm = TimerViewModel()
        vm.numberOfIntervals = 2
        vm.warmupDuration = 10
        vm.highIntensityDuration = 10
        vm.setupIntervals()
        vm.currentIntervalIndex = 0
        vm.timeRemaining = 10
        vm.isRunning = false

        vm.skip()

        XCTAssertEqual(vm.currentIntervalIndex, 1)
        XCTAssertNil(vm.intervalEndTime)
        XCTAssertFalse(vm.isRunning)
    }

    func testSkippingFinalIntervalWhileRunningEndsWorkoutWithoutRestartingTimer() {
        let vm = TimerViewModel()
        vm.numberOfIntervals = 1
        vm.warmupDuration = 0
        vm.highIntensityDuration = 10
        vm.setupIntervals()
        vm.currentIntervalIndex = 0
        vm.timeRemaining = 2
        vm.isRunning = true

        vm.skip()

        XCTAssertTrue(vm.showPostWorkoutSummary)
        XCTAssertFalse(vm.isRunning)
        XCTAssertNil(vm.intervalEndTime)
    }

    func testScheduleWorkoutReminderDisabledWithoutNotificationPermission() {
        let vm = TimerViewModel()
        vm.notificationPermissionState = .denied
        vm.workoutRemindersEnabled = true
        vm.scheduleWorkoutReminder()

        XCTAssertFalse(vm.workoutRemindersEnabled)
    }

    func testHealthKitSaveGuardWhenUnauthorized() {
        let vm = TimerViewModel()
        vm.healthKitEnabled = true
        vm.healthAuthorizationGranted = false

        vm.saveCompletedWorkoutToHealthKit()

        XCTAssertFalse(vm.healthAuthorizationGranted)
    }

    func testOnboardingFlowMovesForwardAndBackWithinBounds() {
        let flow = OnboardingFlowViewModel()

        XCTAssertEqual(flow.currentStep, .welcome)

        flow.next()
        XCTAssertEqual(flow.currentStep, .structure)

        flow.back()
        XCTAssertEqual(flow.currentStep, .welcome)

        flow.back()
        XCTAssertEqual(flow.currentStep, .welcome)
    }

    func testOnboardingFlowStopsAtLastStep() {
        let flow = OnboardingFlowViewModel()

        OnboardingFlowViewModel.Step.allCases.forEach { _ in
            flow.next()
        }

        XCTAssertEqual(flow.currentStep, .launch)
        XCTAssertTrue(flow.isLastStep)
    }

    func testOnboardingFlowIncludesReminderDayStep() {
        let flow = OnboardingFlowViewModel()

        flow.next() // structure
        flow.next() // age
        flow.next() // audioMode
        flow.next() // notifications
        flow.next() // reminder day

        XCTAssertEqual(flow.currentStep, .reminderDay)
    }

    func testWorkoutReminderModeDefaultsToWeeklyWeekday() {
        let vm = TimerViewModel()
        XCTAssertEqual(vm.workoutReminderMode, .weeklyWeekday)
    }

    func testSelectingWeeklyModeAutoPopulatesWeekday() {
        let vm = TimerViewModel()
        vm.workoutReminderWeekday = 0

        vm.workoutReminderMode = .weeklyWeekday

        XCTAssertTrue((1...7).contains(vm.workoutReminderWeekday))
        XCTAssertEqual(vm.workoutReminderMode, .weeklyWeekday)
    }

    func testReminderWeekdayTitlesIncludeMondayAndSunday() {
        let vm = TimerViewModel()

        XCTAssertEqual(vm.reminderWeekdayTitle(2), "Monday")
        XCTAssertEqual(vm.reminderWeekdayTitle(1), "Sunday")
    }

    func testSavingWorkoutLogEntryPersistsAndResets() {
        let vm = TimerViewModel()
        vm.selectedWorkoutType = .cycle
        vm.workoutNotesDraft = "Felt strong"
        vm.showPostWorkoutSummary = true

        vm.saveWorkoutLogEntryAndResetSession()

        XCTAssertEqual(vm.workoutLogEntries.count, 1)
        XCTAssertEqual(vm.workoutLogEntries.first?.workoutType, .cycle)
        XCTAssertEqual(vm.workoutLogEntries.first?.notes, "Felt strong")
        XCTAssertFalse(vm.showPostWorkoutSummary)
    }

    func testWorkoutTypeIncludesOtherOption() {
        XCTAssertTrue(WorkoutType.allCases.contains(.other))
        XCTAssertEqual(WorkoutType.allCases.count, 11)
    }

    func testWorkoutLogMigrationFromLegacySchemaPreservesEntry() {
        let legacyJson = "[{\"completedAt\":\"2026-02-18T10:00:00Z\"}]"
        UserDefaults.standard.set(legacyJson, forKey: "workoutLogEntriesData")

        let vm = TimerViewModel()

        XCTAssertEqual(vm.workoutLogEntries.count, 1)
        XCTAssertEqual(vm.workoutLogEntries.first?.workoutType, .norwegian4x4)
        XCTAssertEqual(vm.workoutLogEntries.first?.notes, "")
    }

    func testWorkoutLogMigrationDefaultsUnknownWorkoutTypeToNorwegian4x4() {
        let legacyJson = "[{\"completedAt\":\"2026-02-18T10:00:00Z\",\"workoutType\":\"SkiErg\",\"notes\":\"  hard effort  \"}]"
        UserDefaults.standard.set(legacyJson, forKey: "workoutLogEntriesData")

        let vm = TimerViewModel()

        XCTAssertEqual(vm.workoutLogEntries.count, 1)
        XCTAssertEqual(vm.workoutLogEntries.first?.workoutType, .norwegian4x4)
        XCTAssertEqual(vm.workoutLogEntries.first?.notes, "hard effort")
    }

    func testUserAgeSanitizationDoesNotLoopAndStaysBounded() {
        let vm = TimerViewModel()

        vm.userAge = 5
        XCTAssertEqual(vm.userAge, TimerViewModel.minimumSupportedAge)

        vm.userAge = 150
        XCTAssertEqual(vm.userAge, TimerViewModel.maximumSupportedAge)

        vm.userAge = 40
        XCTAssertEqual(vm.userAge, 40)
    }

    func testWorkoutReminderWeekdayInvalidValueSanitizesWithoutChangingMode() {
        let vm = TimerViewModel()
        vm.workoutReminderMode = .weeklyWeekday
        vm.workoutReminderWeekday = 3

        vm.workoutReminderWeekday = 999

        XCTAssertEqual(vm.workoutReminderWeekday, 0)
        XCTAssertEqual(vm.workoutReminderMode, .weeklyWeekday)
    }

    func testReminderModeAndDayTransitionsDoNotOscillate() {
        let vm = TimerViewModel()
        vm.workoutRemindersEnabled = false

        vm.workoutReminderMode = .weeklyWeekday
        let weeklyDay = vm.workoutReminderWeekday
        XCTAssertTrue((1...7).contains(weeklyDay))

        vm.workoutReminderMode = .weeklyWeekday
        XCTAssertEqual(vm.workoutReminderWeekday, weeklyDay)
    }

    // MARK: - Performance logging (Phase 1)

    func testSpeedConversionRoundTrips() {
        // 10 km/h ≈ 6.2137 mph; round-trip must return the original value.
        let kmh = 10.0
        let mph = PerformanceUnits.kmhToMph(kmh)
        XCTAssertEqual(mph, 6.21371, accuracy: 0.0001)
        XCTAssertEqual(PerformanceUnits.mphToKmh(mph), kmh, accuracy: 0.000001)
    }

    func testModalityMetricLocaleConversionFlag() {
        // Distance-based modalities convert with locale; cadence/level do not.
        XCTAssertTrue(TrainingModality.treadmill.performanceMetric.localeConverted)
        XCTAssertTrue(TrainingModality.outdoorRun.performanceMetric.localeConverted)
        XCTAssertFalse(TrainingModality.bike.performanceMetric.localeConverted)
        XCTAssertFalse(TrainingModality.stairClimber.performanceMetric.localeConverted)
        XCTAssertEqual(TrainingModality.treadmill.performanceMetric.imperialUnit, "mph")
    }

    func testWorkoutLogEntryCodableRoundTripWithPerformance() {
        let entry = WorkoutLogEntry(
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            workoutType: .treadmill,
            notes: "tempo",
            modality: .treadmill,
            intervalPerformances: [
                IntervalPerformance(intervalNumber: 1, primary: 12.0),
                IntervalPerformance(intervalNumber: 2, primary: 12.5),
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try! encoder.encode(entry)
        let decoded = try! decoder.decode(WorkoutLogEntry.self, from: data)

        XCTAssertEqual(decoded.modality, .treadmill)
        XCTAssertEqual(decoded.intervalPerformances?.count, 2)
        XCTAssertEqual(decoded.intervalPerformances?[1].primary, 12.5)
        XCTAssertEqual(decoded, entry)
    }

    func testLegacyEntryWithoutPerformanceDecodesToNil() {
        // An entry encoded before performance logging existed has no modality /
        // intervalPerformances keys. Synthesized Codable must decode them as nil.
        let legacyJSON = """
        [{"id":"\(UUID().uuidString)","completedAt":"2026-01-01T08:00:00Z",
          "workoutType":"Norwegian 4x4","notes":""}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try! decoder.decode([WorkoutLogEntry].self,
                                          from: legacyJSON.data(using: .utf8)!)
        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries[0].modality)
        XCTAssertNil(entries[0].intervalPerformances)
    }

    func testAveragePrimaryIgnoresBlanks() {
        let entry = WorkoutLogEntry(
            workoutType: .treadmill,
            notes: "",
            modality: .treadmill,
            intervalPerformances: [
                IntervalPerformance(intervalNumber: 1, primary: 10),
                IntervalPerformance(intervalNumber: 2, primary: nil),
                IntervalPerformance(intervalNumber: 3, primary: 14),
            ]
        )
        XCTAssertEqual(entry.averagePrimaryPerformance, 12.0)
    }

    func testLastLoggedPerformanceReturnsMostRecentForModality() {
        let vm = TimerViewModel()
        vm.workoutLogEntries = [
            WorkoutLogEntry(completedAt: Date(timeIntervalSince1970: 200),
                            workoutType: .treadmill, notes: "", modality: .treadmill,
                            intervalPerformances: [IntervalPerformance(intervalNumber: 1, primary: 13)]),
            WorkoutLogEntry(completedAt: Date(timeIntervalSince1970: 100),
                            workoutType: .treadmill, notes: "", modality: .treadmill,
                            intervalPerformances: [IntervalPerformance(intervalNumber: 1, primary: 11)]),
        ]
        XCTAssertEqual(vm.lastLoggedPerformance(for: .treadmill)?.first?.primary, 13)
        XCTAssertNil(vm.lastLoggedPerformance(for: .bike))
    }

}
