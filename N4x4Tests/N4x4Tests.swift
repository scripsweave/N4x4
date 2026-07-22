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
            "workoutLogEntriesData",
            "unitPreference",
            "preferredModalityRaw",
            "defaultWorkoutTypeRaw",
            "nightBeforeReminderEnabled",
            "morningOfReminderEnabled",
            "comebackNudgesEnabled",
            "reminderFamilyFlagsSynced",
            "workoutReminderWeekdays"
        ].forEach { defaults.removeObject(forKey: $0) }
    }

    func testSetupIntervalsIncludesWarmupAndCorrectPattern() {
        let vm = TimerViewModel()
        vm.cooldownEnabled = false   // isolate the warmup + work/recovery pattern
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

    func testSetupIntervalsAppendsCooldownWhenEnabled() {
        let vm = TimerViewModel()
        vm.cooldownEnabled = true
        vm.numberOfIntervals = 2
        vm.warmupDuration = 120
        vm.highIntensityDuration = 240
        vm.restDuration = 180
        vm.setupIntervals()

        // warmup + [HI, rest, HI] + cooldown
        XCTAssertEqual(vm.intervals.count, 5)
        XCTAssertEqual(vm.intervals.last?.type, .cooldown)
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
        vm.cooldownEnabled = false   // completion is being tested, not the cooldown tail
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
        vm.cooldownEnabled = false   // so the high-intensity interval is the final one
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
        XCTAssertEqual(flow.currentStep, .basics)

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

        flow.next() // basics
        flow.next() // modality
        flow.next() // age
        flow.next() // vo2Goal
        flow.next() // reminderDay

        XCTAssertEqual(flow.currentStep, .reminderDay)
    }

    func testWorkoutReminderModeDefaultsToWeeklyWeekday() {
        let vm = TimerViewModel()
        XCTAssertEqual(vm.workoutReminderMode, .weeklyWeekday)
    }

    func testSelectingWeekdaysSyncsAndStaysValid() {
        // The reminder model is multi-day now (selectedWeekdaysList); the legacy
        // single `workoutReminderWeekday` is only a migration shim.
        let vm = TimerViewModel()
        vm.selectedWeekdaysList = [2, 5, 7]

        XCTAssertEqual(vm.selectedWeekdaysList.sorted(), [2, 5, 7])
        XCTAssertTrue(vm.selectedWeekdaysList.allSatisfy { (1...7).contains($0) })
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
        XCTAssertTrue(WorkoutType.allCases.contains(.kettlebell))
        XCTAssertEqual(WorkoutType.allCases.count, 12)
    }

    func testSelectableWorkoutTypesExcludeProtocolName() {
        // "Norwegian 4x4" is the protocol, not an exercise — it must never be
        // offered in pickers, but stays in the enum so old logs decode.
        XCTAssertFalse(WorkoutType.selectableCases.contains(.norwegian4x4))
        XCTAssertEqual(WorkoutType.selectableCases.count, WorkoutType.allCases.count - 1)
        XCTAssertNotNil(WorkoutType(rawValue: "Norwegian 4x4"))
    }

    func testDefaultWorkoutTypeDrivesSelectedTypeOnLaunch() {
        UserDefaults.standard.set(WorkoutType.kettlebell.rawValue, forKey: "defaultWorkoutTypeRaw")

        let vm = TimerViewModel()

        XCTAssertEqual(vm.selectedWorkoutType, .kettlebell)
    }

    func testResolvedDefaultFallsBackToPreferredModality() {
        // Users who onboarded before the explicit default existed only have a
        // modality stored — it must keep working as the default.
        UserDefaults.standard.set(TrainingModality.bike.rawValue, forKey: "preferredModalityRaw")

        let vm = TimerViewModel()

        XCTAssertEqual(vm.resolvedDefaultWorkoutType, .cycle)
        XCTAssertEqual(vm.selectedWorkoutType, .cycle)
    }

    func testSetDefaultWorkoutTypeSyncsModality() {
        let vm = TimerViewModel()

        vm.setDefaultWorkoutType(.kettlebell)

        XCTAssertEqual(vm.defaultWorkoutType, .kettlebell)
        XCTAssertEqual(vm.preferredModality, .kettlebell)
        XCTAssertEqual(vm.selectedWorkoutType, .kettlebell)
    }

    func testSetPreferredModalitySyncsDefaultWorkoutType() {
        let vm = TimerViewModel()

        vm.setPreferredModality(.rowing)

        XCTAssertEqual(vm.defaultWorkoutType, .rowing)
        XCTAssertEqual(vm.resolvedDefaultWorkoutType, .rowing)
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

    func testInvalidReminderWeekdaysAreFilteredOut() {
        // Out-of-range weekday values from stored strings must be dropped so the
        // schedule only ever contains valid 1...7 days.
        let vm = TimerViewModel()
        vm.workoutReminderWeekdays = "999,3,0,7"

        XCTAssertEqual(vm.selectedWeekdaysList.sorted(), [3, 7])
        XCTAssertEqual(vm.workoutReminderMode, .weeklyWeekday)
    }

    // MARK: - Reminder family toggles (4.6)

    func testFamilyFlagsSyncToMasterOnFirstLaunch() {
        // Reminders off + factory-default family flags (true) would show three
        // ON toggles that do nothing — the migration must pull them down.
        let vm = TimerViewModel()

        XCTAssertFalse(vm.workoutRemindersEnabled)
        XCTAssertFalse(vm.nightBeforeReminderEnabled)
        XCTAssertFalse(vm.morningOfReminderEnabled)
        XCTAssertFalse(vm.comebackNudgesEnabled)
    }

    func testEnablingOneFamilyTurnsMasterOn() {
        let vm = TimerViewModel()

        vm.morningOfReminderEnabled = true

        XCTAssertTrue(vm.workoutRemindersEnabled)
        XCTAssertFalse(vm.nightBeforeReminderEnabled)
        XCTAssertFalse(vm.comebackNudgesEnabled)
    }

    func testDisablingLastFamilyTurnsMasterOff() {
        let vm = TimerViewModel()
        vm.nightBeforeReminderEnabled = true
        XCTAssertTrue(vm.workoutRemindersEnabled)

        vm.nightBeforeReminderEnabled = false

        XCTAssertFalse(vm.workoutRemindersEnabled)
    }

    func testEnablingMasterDirectlyRaisesAllFamilies() {
        // Onboarding sets the master straight to true — with every family off
        // that must raise all three, or nothing would ever be scheduled.
        let vm = TimerViewModel()

        vm.workoutRemindersEnabled = true

        XCTAssertTrue(vm.nightBeforeReminderEnabled)
        XCTAssertTrue(vm.morningOfReminderEnabled)
        XCTAssertTrue(vm.comebackNudgesEnabled)
    }

    // MARK: - Settings row summaries (4.6)

    func testReminderDaysSummaryFormatsSelectedDays() {
        let vm = TimerViewModel()
        XCTAssertEqual(vm.reminderDaysSummary, "Off")

        vm.workoutReminderWeekdays = "3,5"   // Tuesday, Thursday
        vm.nightBeforeReminderEnabled = true // master follows

        XCTAssertEqual(vm.reminderDaysSummary, "Tue · Thu")
    }

    func testIntervalPlanSummaryFormatsCountAndDuration() {
        let vm = TimerViewModel()
        vm.numberOfIntervals = 4
        vm.highIntensityDuration = 240

        XCTAssertEqual(vm.intervalPlanSummary, "4 × 4:00")

        vm.numberOfIntervals = 3
        vm.highIntensityDuration = 90

        XCTAssertEqual(vm.intervalPlanSummary, "3 × 1:30")
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

    // MARK: - Streak calculation

    private func makeEntry(_ date: Date) -> WorkoutLogEntry {
        WorkoutLogEntry(completedAt: date, workoutType: .norwegian4x4,
                        notes: "", modality: nil, intervalPerformances: nil)
    }

    func testStreakBreaksOnMissedMiddleWeek() {
        // Trained this week and two weeks ago, but skipped last week: the missed
        // week must break the streak (regression for the head-gap-forgiveness bug).
        let vm = TimerViewModel()
        let cal = Calendar.current, now = Date()
        vm.workoutLogEntries = [
            makeEntry(now),
            makeEntry(cal.date(byAdding: .weekOfYear, value: -2, to: now)!),
        ]
        XCTAssertEqual(vm.currentWeekStreak, 1)
    }

    func testStreakCountsConsecutiveWeeks() {
        let vm = TimerViewModel()
        let cal = Calendar.current, now = Date()
        vm.workoutLogEntries = [
            makeEntry(now),
            makeEntry(cal.date(byAdding: .weekOfYear, value: -1, to: now)!),
            makeEntry(cal.date(byAdding: .weekOfYear, value: -2, to: now)!),
        ]
        XCTAssertEqual(vm.currentWeekStreak, 3)
    }

    func testStreakForgivesNotYetTrainedCurrentWeek() {
        // No workout yet this week, but trained the prior two weeks: the head gap
        // legitimately forgives the current week, so the streak is 2.
        let vm = TimerViewModel()
        let cal = Calendar.current, now = Date()
        vm.workoutLogEntries = [
            makeEntry(cal.date(byAdding: .weekOfYear, value: -1, to: now)!),
            makeEntry(cal.date(byAdding: .weekOfYear, value: -2, to: now)!),
        ]
        XCTAssertEqual(vm.currentWeekStreak, 2)
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

    // MARK: - Performance capture (Phase 2)

    func testStampAllIntervalsFillsEveryInterval() {
        let vm = TimerViewModel()
        vm.numberOfIntervals = 4
        vm.selectedWorkoutType = .treadmill
        vm.preparePerformanceDraft()
        XCTAssertEqual(vm.performanceDraft.count, 4)

        vm.performanceSetAll = 12.0
        vm.stampAllIntervals()
        XCTAssertEqual(vm.performanceDraft, [12.0, 12.0, 12.0, 12.0])
    }

    func testSavePersistsPerformanceInCanonicalUnitsMetric() {
        let vm = TimerViewModel()
        vm.unitPreference = .metric              // display == canonical (km/h)
        vm.numberOfIntervals = 2
        vm.selectedWorkoutType = .treadmill
        vm.preparePerformanceDraft()
        vm.performanceDraft = [12.0, 13.0]
        vm.saveWorkoutLogEntryAndResetSession()

        let entry = vm.workoutLogEntries.first
        XCTAssertEqual(entry?.modality, .treadmill)
        XCTAssertEqual(entry?.intervalPerformances?.map { $0.primary }, [12.0, 13.0])
        XCTAssertEqual(entry?.intervalPerformances?.map { $0.intervalNumber }, [1, 2])
    }

    func testImperialSpeedStoredAsCanonicalKmh() {
        let vm = TimerViewModel()
        vm.unitPreference = .imperial            // entered mph -> stored km/h
        vm.numberOfIntervals = 1
        vm.selectedWorkoutType = .treadmill
        vm.preparePerformanceDraft()
        vm.performanceDraft = [6.21371]          // mph ≈ 10 km/h
        vm.saveWorkoutLogEntryAndResetSession()

        let stored = vm.workoutLogEntries.first?.intervalPerformances?.first?.primary
        XCTAssertEqual(stored ?? 0, 10.0, accuracy: 0.001)
    }

    func testBlankDraftStoresNoPerformances() {
        let vm = TimerViewModel()
        vm.numberOfIntervals = 3
        vm.selectedWorkoutType = .treadmill
        vm.preparePerformanceDraft()             // all nil (no prior data)
        vm.saveWorkoutLogEntryAndResetSession()

        XCTAssertNil(vm.workoutLogEntries.first?.intervalPerformances)
    }

}

// MARK: - Heart-rate series recording

final class HeartRateSeriesTests: XCTestCase {

    private func span(_ kind: String, _ start: Double, _ end: Double,
                      work: Int = 0, lo: Int = 0, hi: Int = 0) -> HeartRateSeries.IntervalSpan {
        .init(kind: kind, workNumber: work, start: start, end: end, targetLo: lo, targetHi: hi)
    }

    func testRecorderBucketsSamplesToTwoSeconds() {
        let r = HeartRateSeriesRecorder()
        r.record(bpm: 100, at: 0)
        r.record(bpm: 101, at: 0.5)   // dropped: same bucket
        r.record(bpm: 102, at: 1.9)   // dropped
        r.record(bpm: 103, at: 2.0)   // kept
        r.record(bpm: 104, at: 3.9)   // dropped
        r.record(bpm: 105, at: 4.1)   // kept
        XCTAssertEqual(r.samples.map(\.bpm), [100, 103, 105])
    }

    func testRecorderRejectsGarbage() {
        let r = HeartRateSeriesRecorder()
        r.record(bpm: 0, at: 0)
        r.record(bpm: -10, at: 2)
        r.record(bpm: 120, at: -1)
        XCTAssertTrue(r.samples.isEmpty)
    }

    func testRecorderBuildsSpansAcrossIntervalChanges() {
        let r = HeartRateSeriesRecorder()
        r.beginInterval(kind: "warmup", workNumber: 0, targetLo: 0, targetHi: 0, at: 0)
        r.beginInterval(kind: "work", workNumber: 1, targetLo: 150, targetHi: 170, at: 600)
        r.beginInterval(kind: "recovery", workNumber: 0, targetLo: 110, targetHi: 130, at: 840)
        let series = r.finish(at: 1020)
        XCTAssertEqual(series.spans.map(\.kind), ["warmup", "work", "recovery"])
        XCTAssertEqual(series.spans[1].start, 600)
        XCTAssertEqual(series.spans[1].end, 840)
        XCTAssertEqual(series.spans[1].workNumber, 1)
        XCTAssertEqual(series.spans[2].end, 1020)
    }

    func testRecorderDropsZeroLengthSpans() {
        let r = HeartRateSeriesRecorder()
        r.beginInterval(kind: "warmup", workNumber: 0, targetLo: 0, targetHi: 0, at: 0)
        // Double advance in the same instant (skip tapped twice).
        r.beginInterval(kind: "work", workNumber: 1, targetLo: 150, targetHi: 170, at: 300)
        r.beginInterval(kind: "recovery", workNumber: 0, targetLo: 110, targetHi: 130, at: 300.1)
        let series = r.finish(at: 500)
        XCTAssertEqual(series.spans.map(\.kind), ["warmup", "recovery"])
    }

    func testInZonePctCountsOnlyInZoneTime() {
        // 10 samples 2 s apart: first 5 below target, last 5 inside.
        let samples = (0..<10).map {
            HeartRateSeries.Sample(t: Double($0 * 2), bpm: $0 < 5 ? 140 : 160)
        }
        let s = HeartRateSeries(
            samples: samples,
            spans: [span("work", 0, 18, work: 1, lo: 150, hi: 170)],
            startedAt: Date(timeIntervalSince1970: 0))
        // 9 gaps of 2 s; the first 4 lead from below-zone samples, gap 5 leads
        // from sample index 4 (below), gaps 6-9 lead from in-zone samples.
        XCTAssertEqual(HeartRateSeriesAnalytics.inZonePct(s, span: s.spans[0]), 44)
    }

    func testInZonePctNilWithoutTargetOrSamples() {
        let s = HeartRateSeries(
            samples: [.init(t: 0, bpm: 100), .init(t: 2, bpm: 100)],
            spans: [span("warmup", 0, 10), span("work", 20, 30, work: 1, lo: 150, hi: 170)],
            startedAt: Date(timeIntervalSince1970: 0))
        XCTAssertNil(HeartRateSeriesAnalytics.inZonePct(s, span: s.spans[0]), "no target")
        XCTAssertNil(HeartRateSeriesAnalytics.inZonePct(s, span: s.spans[1]), "no samples in span")
    }

    func testTimeToZone() {
        let samples = [
            HeartRateSeries.Sample(t: 100, bpm: 120),
            HeartRateSeries.Sample(t: 130, bpm: 149),
            HeartRateSeries.Sample(t: 160, bpm: 151),
        ]
        let work = span("work", 100, 340, work: 1, lo: 150, hi: 170)
        let s = HeartRateSeries(samples: samples, spans: [work],
                                startedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(HeartRateSeriesAnalytics.timeToZone(s, span: work), 60)
    }

    func testTimeToZoneNilWhenNeverReached() {
        let samples = [HeartRateSeries.Sample(t: 100, bpm: 120)]
        let work = span("work", 100, 340, work: 1, lo: 150, hi: 170)
        let s = HeartRateSeries(samples: samples, spans: [work],
                                startedAt: Date(timeIntervalSince1970: 0))
        XCTAssertNil(HeartRateSeriesAnalytics.timeToZone(s, span: work))
    }

    func testSparklineDownsamples() {
        let flat = HeartRateSeriesAnalytics.sparkline(from: Array(repeating: 150.0, count: 800), points: 40)
        XCTAssertEqual(flat.count, 40)
        XCTAssertTrue(flat.allSatisfy { $0 == 150 })

        let short = HeartRateSeriesAnalytics.sparkline(from: [100, 110, 120], points: 40)
        XCTAssertEqual(short, [100, 110, 120], "shorter than target passes through")
    }

    func testSummaryNilForTinySeries() {
        let s = HeartRateSeries(samples: [.init(t: 0, bpm: 100)], spans: [],
                                startedAt: Date(timeIntervalSince1970: 0))
        XCTAssertNil(HeartRateSeriesAnalytics.summary(for: s))
    }

    func testSummaryStats() {
        let samples = (0..<100).map { HeartRateSeries.Sample(t: Double($0 * 2), bpm: 150) }
        let s = HeartRateSeries(
            samples: samples,
            spans: [span("work", 0, 200, work: 1, lo: 140, hi: 160)],
            startedAt: Date(timeIntervalSince1970: 0))
        let summary = HeartRateSeriesAnalytics.summary(for: s)
        XCTAssertEqual(summary?.avgBPM, 150)
        XCTAssertEqual(summary?.maxBPM, 150)
        XCTAssertEqual(summary?.workInZonePct, 100)
        XCTAssertEqual(summary?.sparkline.count, 40)
    }

    func testStoreRoundTripAndDelete() {
        let id = UUID()
        let s = HeartRateSeries(
            samples: [.init(t: 0, bpm: 100), .init(t: 2, bpm: 110)],
            spans: [span("work", 0, 240, work: 1, lo: 150, hi: 170)],
            startedAt: Date(timeIntervalSince1970: 1000))
        HeartRateSeriesStore.save(s, for: id)
        XCTAssertEqual(HeartRateSeriesStore.load(for: id), s)
        HeartRateSeriesStore.delete(for: id)
        XCTAssertNil(HeartRateSeriesStore.load(for: id))
    }
}
