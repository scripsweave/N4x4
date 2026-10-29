//
//  N4x4UITests.swift
//  N4x4UITests
//
//  Created by Jan van Rensburg on 9/12/24.
//

import XCTest

extension XCTestCase {
    func prepareNotificationAlertForUITests() {
        // Unit tests exercise reminder toggles in the app host. On a fresh
        // Cloud simulator their system alert can outlive that host process.
        // Clear this test-only alert before launch, and handle a delayed one.
        addUIInterruptionMonitor(withDescription: "Unit-test notification permission") { alert in
            guard alert.label.localizedCaseInsensitiveContains("Send You Notifications"),
                  alert.buttons["Allow"].exists else { return false }
            alert.buttons["Allow"].tap()
            return true
        }
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Send You Notifications")).firstMatch
        if alert.waitForExistence(timeout: 5), alert.buttons["Allow"].exists {
            alert.buttons["Allow"].tap()
        }
    }

    var reviewLaunchArguments: [String] {
        ["-hasCompletedOnboarding", "YES",
         "-hasSeenHRSourcesAnnouncement", "YES",
         "-hasSeenWatchUpgradePrompt", "YES",
         "-healthKitEnabled", "NO", "-healthKitUserOptedOut", "YES",
         "-workoutRemindersEnabled", "NO", "-notificationsEnabled", "NO",
         "-audioModeRaw", "Silent", "-hapticsEnabled", "NO",
         "-shownMilestonesData", "\"[1,5,10,25,50,100]\"",
         "-hasRequestedAppReview", "YES"]
    }
}

final class N4x4UITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
        prepareNotificationAlertForUITests()
        XCUIDevice.shared.orientation = .portrait

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        if app.state == .runningForeground {
            if app.alerts["Workout recovered"].exists {
                app.alerts["Workout recovered"].buttons["Discard Workout"].tap()
            }
            if app.buttons["Home"].isHittable { app.buttons["Home"].tap() }
            if app.buttons["FINISH"].isHittable {
                app.buttons["FINISH"].tap()
                app.alerts["Finish workout?"].buttons["Discard Workout"].tap()
            }
        }
        app.terminate()
    }

    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication,
                        scrollContainer: XCUIElement? = nil, maximumSwipes: Int = 8) {
        for _ in 0..<maximumSwipes {
            let tabBar = app.tabBars.firstMatch
            let horizontalBar = tabBar.exists && tabBar.isHittable && tabBar.frame.width > tabBar.frame.height
            let bottom = horizontalBar ? tabBar.frame.minY : app.frame.maxY
            if element.exists && element.isHittable && element.frame.minY >= 0 && element.frame.maxY <= bottom {
                return
            }
            if let scrollContainer, scrollContainer.exists && scrollContainer.isHittable {
                scrollContainer.swipeUp()
                continue
            }
            // Small swipes avoid scrolling straight past a large text control.
            // Duo can present the review as a popover. Swiping the application
            // can hit its dismiss region instead of scrolling the review.
            if element.exists {
                let identifier = element.identifier.isEmpty ? element.label : element.identifier
                let scrollView = app.scrollViews.containing(.any, identifier: identifier).firstMatch
                if scrollView.exists && scrollView.isHittable {
                    scrollView.swipeUp(velocity: .slow)
                    continue
                }
            }
            app.swipeUp(velocity: .slow)
        }
        keepScreenshot("Could not reveal control", app: app)
        print(app.debugDescription)
        XCTFail("Could not fully reveal \(element)")
    }

    private func confirmWorkoutDeletion(in app: XCUIApplication) {
        let alert = app.alerts["Delete workout?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Delete"].tap()
    }

    private func keepScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertVisible(_ element: XCUIElement, in app: XCUIApplication,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        if !element.isHittable {
            keepScreenshot("Control not hittable", app: app)
            print(app.debugDescription)
        }
        XCTAssertTrue(element.isHittable, file: file, line: line)
        // XCTest reports the app's portrait frame on some landscape simulators.
        // Use the screen capture for visual clipping checks, plus hit testing.
        XCTAssertGreaterThan(element.frame.width, 0, file: file, line: line)
    }

    func testWorkoutRotatesWithLargeHeartRateAndPreservesPausedTimer() {
        let app = XCUIApplication()
        app.launchArguments = reviewLaunchArguments + ["-warmupDuration", "0", "-highIntensityDuration", "240"]
        app.launchEnvironment["N4X4_DEMO_HEART_RATE"] = "166"
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        assertVisible(app.buttons["START"], in: app)
        keepScreenshot("Home portrait", app: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        assertVisible(app.buttons["START"], in: app)
        keepScreenshot("Home landscape", app: app)
        app.buttons["START"].tap()

        let reading = app.otherElements["live-heart-rate"]
        let countdown = app.staticTexts["workout-countdown"]
        assertVisible(app.buttons["PAUSE"], in: app)
        assertVisible(reading, in: app)
        XCTAssertEqual(reading.value as? String, "166 beats per minute")
        XCTAssertGreaterThanOrEqual(reading.frame.height, 60)
        keepScreenshot("Workout landscape left", app: app)
        app.buttons["PAUSE"].tap()
        assertVisible(app.buttons["RESUME"], in: app)
        let pausedTime = countdown.value as? String
        XCUIDevice.shared.orientation = .landscapeRight
        assertVisible(app.buttons["RESUME"], in: app)
        XCTAssertEqual(countdown.value as? String, pausedTime)
        keepScreenshot("Paused landscape right", app: app)
        XCUIDevice.shared.orientation = .portrait
        assertVisible(app.buttons["RESUME"], in: app)
        XCTAssertEqual(countdown.value as? String, pausedTime)
        app.buttons["RESUME"].tap()
        assertVisible(reading, in: app)
        XCTAssertEqual(reading.value as? String, "166 beats per minute")
        XCTAssertGreaterThanOrEqual(reading.frame.height, 50)
        keepScreenshot("Workout portrait", app: app)
        app.buttons["FINISH"].tap()
        app.alerts["Finish workout?"].buttons["Discard Workout"].tap()
        assertVisible(app.buttons["START"], in: app)
    }

    func testLargeTextKeepsHeartRateAndControlsAccessible() {
        let app = XCUIApplication()
        app.launchArguments = reviewLaunchArguments + ["-warmupDuration", "0", "-highIntensityDuration", "240",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment["N4X4_DEMO_HEART_RATE"] = "166"
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        app.buttons["START"].tap()
        let reading = app.otherElements["live-heart-rate"]
        reveal(reading, in: app)
        XCTAssertEqual(reading.value as? String, "166 beats per minute")
        keepScreenshot("Largest text portrait", app: app)
        reveal(app.buttons["PAUSE"], in: app)
        app.buttons["PAUSE"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        reveal(app.buttons["RESUME"], in: app)
        keepScreenshot("Largest text landscape", app: app)
        app.buttons["RESUME"].tap()
    }

    func testLandscapeWithoutHeartRateAndCompletion() {
        let app = XCUIApplication()
        app.launchArguments = reviewLaunchArguments + ["-numberOfIntervals", "1", "-warmupDuration", "0",
                                                       "-highIntensityDuration", "240", "-cooldownEnabled", "NO"]
        XCUIDevice.shared.orientation = .landscapeRight
        app.launch()
        app.buttons["START"].tap()
        assertVisible(app.buttons["PAUSE"], in: app)
        let reading = app.otherElements["live-heart-rate"]
        assertVisible(reading, in: app)
        XCTAssertEqual(reading.value as? String, "No reading")
        keepScreenshot("Landscape without HR", app: app)
        app.buttons["SKIP"].tap()
        if app.alerts["Skip interval now?"].exists {
            app.alerts["Skip interval now?"].buttons["Skip Now"].tap()
        }
        XCTAssertTrue(app.staticTexts["Saved to History"].waitForExistence(timeout: 10))
        assertVisible(app.buttons["Done"], in: app)
        keepScreenshot("Landscape saved summary", app: app)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 5))
    }

    func testCompletedWorkoutSurvivesRelaunchWithoutDoneAndCanBeDeleted() throws {
        let app = XCUIApplication()
        let timerArguments = ["-numberOfIntervals", "1", "-warmupDuration", "0",
                              "-highIntensityDuration", "1", "-cooldownEnabled", "NO"]
        app.launchArguments = reviewLaunchArguments + timerArguments + ["-workoutLogEntriesData", "\"[]\""]
        app.launch()
        let start = app.buttons["START"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        XCTAssertTrue(app.staticTexts["Saved to History"].waitForExistence(timeout: 10))
        let summaryScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        summaryScreenshot.name = "Automatically saved summary"
        summaryScreenshot.lifetime = .keepAlways
        add(summaryScreenshot)

        // The client must not have to tap Done to retain the finished workout.
        app.terminate()
        app.launchArguments = reviewLaunchArguments + timerArguments
        app.launch()
        app.buttons["History"].tap()
        let workouts = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout-"))
        reveal(workouts.firstMatch, in: app)
        XCTAssertEqual(workouts.count, 1)
        workouts.firstMatch.tap()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        confirmWorkoutDeletion(in: app)
        XCTAssertTrue(app.staticTexts["Completed workouts are saved here automatically."].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        app.buttons["History"].tap()
        reveal(app.staticTexts["Completed workouts are saved here automatically."], in: app)
        XCTAssertEqual(workouts.count, 0)

        // Done must also lead to a usable History sheet and nested detail.
        app.buttons["Home"].tap()
        app.buttons["START"].tap()
        XCTAssertTrue(app.staticTexts["Saved to History"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 5))
        reveal(workouts.firstMatch, in: app)
        workouts.firstMatch.tap()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5))
        app.buttons["Delete"].tap()
        confirmWorkoutDeletion(in: app)
        XCTAssertTrue(app.staticTexts["Completed workouts are saved here automatically."].waitForExistence(timeout: 5))
    }

    func testHistoryListsBothSameDayWorkoutsAndDeletesOnlySelectedSession() throws {
        let app = XCUIApplication()
        let firstID = "11111111-1111-1111-1111-111111111111"
        let secondID = "22222222-2222-2222-2222-222222222222"
        let date = ISO8601DateFormatter().string(from: Date())
        let rows: [[String: Any]] = [
            ["id": firstID, "completedAt": date, "workoutType": "Run", "notes": "First workout"],
            ["id": secondID, "completedAt": date, "workoutType": "Cycle", "notes": "Second workout"]
        ]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: rows), as: UTF8.self)
        // NSArgumentDomain parses property-list values. Quote JSON as a string
        // or Foundation silently ignores the unquoted array-of-objects argument.
        let argument = String(decoding: try JSONEncoder().encode(json), as: UTF8.self)
        app.launchArguments = reviewLaunchArguments + ["-workoutLogEntriesData", argument]
        app.launch()
        app.buttons["History"].tap()
        let first = app.buttons["workout-\(firstID)"]
        let second = app.buttons["workout-\(secondID)"]
        reveal(second, in: app)
        XCTAssertTrue(first.exists)
        let historyScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        historyScreenshot.name = "Two workouts on the same day"
        historyScreenshot.lifetime = .keepAlways
        add(historyScreenshot)
        second.tap()
        XCTAssertTrue(app.staticTexts["Second workout"].waitForExistence(timeout: 5))
        // A selected session must survive the compact/expanded navigation reflow.
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.staticTexts["Second workout"].waitForExistence(timeout: 5))
        keepScreenshot("Selected History session after resizing", app: app)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.staticTexts["Second workout"].waitForExistence(timeout: 5))
        app.buttons["Delete"].tap()
        app.alerts["Delete workout?"].buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Second workout"].exists)
        app.buttons["Delete"].tap()
        confirmWorkoutDeletion(in: app)
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertFalse(second.exists)
        first.tap()
        XCTAssertTrue(app.staticTexts["First workout"].waitForExistence(timeout: 5))
    }

    func testFullWorkoutExportOpensShareSheetFromSummaryAndHistory() throws {
        let app = XCUIApplication()
        let timerArguments = ["-numberOfIntervals", "1", "-warmupDuration", "0",
                              "-highIntensityDuration", "2", "-cooldownEnabled", "NO"]
        app.launchArguments = reviewLaunchArguments + timerArguments + ["-workoutLogEntriesData", "\"[]\""]
        app.launch()
        app.buttons["START"].tap()
        XCTAssertTrue(app.staticTexts["Saved to History"].waitForExistence(timeout: 10))
        app.buttons["session-share-menu"].tap()
        let export = app.buttons["export-workout"]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Share Image"].exists)
        export.tap()
        let save = app.cells["Save to Files"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), app.debugDescription)
        keepScreenshot("Full workout JSON share sheet", app: app)
        // The same saved workout must also export after relaunch, without
        // requiring Done or depending on system share-popover dismissal.
        app.terminate()
        app.launchArguments = reviewLaunchArguments + timerArguments
        app.launch()
        app.buttons["History"].tap()
        let workouts = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout-"))
        reveal(workouts.firstMatch, in: app)
        XCTAssertEqual(workouts.count, 1)
        workouts.firstMatch.tap()
        app.buttons["session-share-menu"].tap()
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        export.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 10), app.debugDescription)
    }

    func testLegacyWorkoutCanExportWithoutAnImageOrRecording() throws {
        let app = XCUIApplication()
        let id = UUID().uuidString
        let rows: [[String: Any]] = [["id": id,
            "completedAt": ISO8601DateFormatter().string(from: Date()),
            "workoutType": "Run", "notes": "An older workout without a recording"]]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: rows), as: UTF8.self)
        let argument = String(decoding: try JSONEncoder().encode(json), as: UTF8.self)
        app.launchArguments = reviewLaunchArguments + ["-workoutLogEntriesData", argument]
        app.launch()
        app.buttons["History"].tap()
        let workout = app.buttons["workout-\(id)"]
        reveal(workout, in: app)
        workout.tap()
        app.buttons["session-share-menu"].tap()
        let export = app.buttons["export-workout"]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Share Image"].exists)
        export.tap()
        XCTAssertTrue(app.cells["Save to Files"].waitForExistence(timeout: 10), app.debugDescription)
        app.cells["Save to Files"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 10), app.debugDescription)
        keepScreenshot("Workout JSON ready to save in Files", app: app)
    }

}

extension N4x4UITests {
    func testFinishInCooldownSavesAndOpensHistory() {
        let app = XCUIApplication()
        app.launchArguments = reviewLaunchArguments + ["-numberOfIntervals", "1", "-warmupDuration", "0", "-highIntensityDuration", "1", "-cooldownEnabled", "YES", "-cooldownDuration", "60", "-workoutLogEntriesData", "\"[]\""]
        app.launch()
        app.buttons["START"].tap()
        XCTAssertTrue(app.staticTexts["COOL DOWN"].waitForExistence(timeout: 10))
        app.buttons["FINISH"].tap()
        keepScreenshot("Finish offers saving and explicit discard", app: app)
        app.alerts["Finish workout?"].buttons["Finish & Save"].tap()
        XCTAssertTrue(app.staticTexts["Saved to History"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Norwegian 4×4 complete"].exists)
        app.buttons["Done"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout-"))
        reveal(rows.firstMatch, in: app)
        XCTAssertEqual(rows.count, 1)
        rows.firstMatch.tap()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5))
        keepScreenshot("Saved cooldown finish in History", app: app)
    }

    func testEarlyFinishSavesAndImmediateReviewNotesSurviveTermination() {
        let app = XCUIApplication()
        let timerArguments = ["-numberOfIntervals", "1", "-warmupDuration", "0", "-highIntensityDuration", "240", "-cooldownEnabled", "NO"]
        app.launchArguments = reviewLaunchArguments + timerArguments + ["-workoutLogEntriesData", "\"[]\""]
        app.launch()
        app.buttons["START"].tap()
        app.buttons["FINISH"].tap()
        app.alerts["Finish workout?"].buttons["Finish & Save"].tap()
        XCTAssertTrue(app.staticTexts["Workout ended early"].waitForExistence(timeout: 10))
        let notes = app.textFields["workout-notes"]
        reveal(notes, in: app)
        notes.tap()
        notes.typeText("Saved without Done")
        app.terminate()
        app.launchArguments = reviewLaunchArguments + timerArguments
        app.launch()
        app.buttons["History"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout-"))
        reveal(rows.firstMatch, in: app)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(app.staticTexts["Ended early"].exists)
        rows.firstMatch.tap()
        let savedNotes = app.staticTexts["Saved without Done"]
        reveal(savedNotes, in: app)
        XCTAssertTrue(savedNotes.exists)
        keepScreenshot("Review notes survive termination before Done", app: app)
    }

    func testInterruptedWorkoutRecoversPausedAndCanBeFinished() {
        let app = XCUIApplication()
        let timerArguments = ["-numberOfIntervals", "1", "-warmupDuration", "0", "-highIntensityDuration", "240", "-cooldownEnabled", "NO"]
        app.launchArguments = reviewLaunchArguments + timerArguments + ["-workoutLogEntriesData", "\"[]\""]
        app.launch()
        app.buttons["START"].tap()
        app.buttons["PAUSE"].tap() // Forces a checkpoint without timing a disk write.
        let remaining = app.staticTexts["workout-countdown"].value as? String
        app.terminate()
        app.launchArguments = reviewLaunchArguments + timerArguments
        app.launch()
        XCTAssertTrue(app.alerts["Workout recovered"].waitForExistence(timeout: 10))
        keepScreenshot("Recovered workout choices", app: app)
        app.alerts["Workout recovered"].buttons["Keep Paused"].tap()
        XCTAssertTrue(app.buttons["RESUME"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["workout-countdown"].value as? String, remaining)
        app.buttons["RESUME"].tap()
        app.buttons["FINISH"].tap()
        app.alerts["Finish workout?"].buttons["Finish & Save"].tap()
        XCTAssertTrue(app.staticTexts["Saved to History"].waitForExistence(timeout: 10))
        keepScreenshot("Recovered workout saved", app: app)
    }

    func testExplicitDiscardDoesNotReturnAfterRelaunch() {
        let app = XCUIApplication()
        let timerArguments = ["-warmupDuration", "0", "-highIntensityDuration", "240"]
        app.launchArguments = reviewLaunchArguments + timerArguments + ["-workoutLogEntriesData", "\"[]\""]
        app.launch()
        app.buttons["START"].tap()
        app.buttons["FINISH"].tap()
        app.alerts["Finish workout?"].buttons["Discard Workout"].tap()
        XCTAssertTrue(app.buttons["START"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = reviewLaunchArguments + timerArguments
        app.launch()
        XCTAssertTrue(app.buttons["START"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["Workout recovered"].exists)
    }
}

extension N4x4UITests {
    func testHealthDevicesShowsSwitchesAndConnectionsWithoutPrompting() {
        let app = XCUIApplication()
        app.launchArguments = reviewLaunchArguments + ["-AppleInterfaceStyle", "Light"]
        app.launch()
        app.buttons["Settings"].tap()
        let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Health & Devices")).firstMatch
        reveal(link, in: app)
        link.tap()
        let master = app.switches["healthEnabled"]
        XCTAssertTrue(master.waitForExistence(timeout: 5))
        XCTAssertEqual(master.value as? String, "0")
        XCTAssertFalse(app.switches["healthWorkoutLogging"].isEnabled)
        XCTAssertEqual(app.alerts.count, 0)
        let heartRatePermission = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Heart Rate write permission")).firstMatch
        reveal(heartRatePermission, in: app)
        XCTAssertTrue(heartRatePermission.exists)
        let energyPermission = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Active Energy write permission")).firstMatch
        reveal(energyPermission, in: app)
        XCTAssertTrue(energyPermission.exists)
        XCTAssertEqual(app.alerts.count, 0, "Viewing the new write-permission status must not prompt")
        keepScreenshot("Health and Devices - Health saving", app: app)
        let watch = app.buttons.containing(.staticText, identifier: "Apple Watch").firstMatch
        reveal(watch, in: app)
        keepScreenshot("Health and Devices - Connections", app: app)
        let diagnostics = app.buttons["Copy Diagnostics"]
        reveal(diagnostics, in: app)
        XCTAssertTrue(app.staticTexts["Health Readings"].exists)
        keepScreenshot("Health and Devices - Readings and diagnostics", app: app)
        diagnostics.tap()
        XCTAssertTrue(app.buttons["Diagnostics Copied"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testHealthDevicesSupportsLargestTextAndSearch() {
        let app = XCUIApplication()
        app.launchArguments = reviewLaunchArguments + ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"]
        app.launch()
        app.buttons["Settings"].tap()
        let search = app.searchFields.firstMatch
        // Vertical navigation bars can collapse search into a toolbar action.
        if !search.exists {
            let searchButton = app.buttons["Search"]
            if searchButton.waitForExistence(timeout: 5) { searchButton.tap() }
        }
        if !search.exists {
            keepScreenshot("Settings search unavailable", app: app)
            print(app.debugDescription)
        }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("airpods")
        let result = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Heart Rate Sources")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.navigationBars["Health & Devices"].waitForExistence(timeout: 5))
        keepScreenshot("Health and Devices - Largest text source priority", app: app)
        let diagnostics = app.buttons["Copy Diagnostics"]
        // At AX5 the Form can span many screens. Scroll the actual list;
        // a slow application-wide gesture can drag an editable source row.
        reveal(diagnostics, in: app, scrollContainer: app.collectionViews.firstMatch,
               maximumSwipes: 24)
        assertVisible(diagnostics, in: app)
        keepScreenshot("Health and Devices - Largest text help", app: app)
    }

    func testLegacyHealthRecoveryExplainsUncertaintyBeforeSaving() throws {
        let app = XCUIApplication()
        let id = "33333333-3333-3333-3333-333333333333"
        let row: [String: Any] = ["id": id, "completedAt": ISO8601DateFormatter().string(from: Date()),
            "workoutType": "Run", "notes": "Legacy session", "sessionBreakdown": ["totalDuration": 600]]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: [row]), as: UTF8.self)
        let argument = String(decoding: try JSONEncoder().encode(json), as: UTF8.self)
        app.launchArguments = reviewLaunchArguments + ["-workoutLogEntriesData", argument]
        app.launch()
        app.buttons["History"].tap()
        let workout = app.buttons["workout-\(id)"]
        reveal(workout, in: app)
        workout.tap()
        let save = app.buttons["Save to Apple Health"]
        reveal(save, in: app)
        save.tap()
        XCTAssertTrue(app.navigationBars["Save to Apple Health"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Estimated start"].exists)
        let confirm = app.buttons["Confirm & Save New Workout"]
        reveal(confirm, in: app)
        XCTAssertFalse(confirm.isEnabled, "Saving is disabled until both preferences and workout permission allow it")
        keepScreenshot("Health recovery - Confirm before exporting", app: app)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Health save status unknown"].exists)
    }
}

extension N4x4UITests {
    func testHistoryShowsWatchCaloriesAndExplainsPendingEnergy() throws {
        let app = XCUIApplication()
        let id = "44444444-4444-4444-4444-444444444444"
        for state in ["saved", "pending"] {
            let now = Date(), timestamp = Date().timeIntervalSince1970
            var export: [String: Any] = ["startTimestamp": timestamp - 600, "endTimestamp": timestamp,
                                         "state": state, "attempts": 0,
                                         "energyContent": state == "saved" ? "included" : "awaitingWatch"]
            if state == "saved" { export["activeEnergyKilocalories"] = 127.25 }
            let row: [String: Any] = ["id": id, "completedAt": ISO8601DateFormatter().string(from: now),
                                     "workoutType": "Run", "notes": "", "healthExport": export]
            let json = String(decoding: try JSONSerialization.data(withJSONObject: [row]), as: UTF8.self)
            let argument = String(decoding: try JSONEncoder().encode(json), as: UTF8.self)
            app.launchArguments = reviewLaunchArguments + ["-workoutLogEntriesData", argument]
            app.launch()
            app.buttons["History"].tap()
            let workout = app.buttons["workout-\(id)"]
            reveal(workout, in: app)
            workout.tap()
            let label = state == "saved" ? "127 kcal active energy from Apple Watch included." : "Waiting for Apple Watch calories."
            reveal(app.staticTexts[label], in: app)
            XCTAssertTrue(app.staticTexts[label].exists)
            if state == "pending" {
                let skip = app.buttons["Save Without Calories"]
                reveal(skip, in: app)
                XCTAssertTrue(skip.exists)
                XCTAssertFalse(skip.isEnabled, "Health is off in this UI test")
            }
            keepScreenshot("History calories - \(state)", app: app)
            XCTAssertEqual(app.alerts.count, 0)
            app.terminate()
        }
    }
}

extension N4x4UITests {
    func testHealthDevicesSeparatesPendingSavesFromConfirmedSaves() throws {
        let app = XCUIApplication()
        let now = Date()
        let timestamp = now.timeIntervalSince1970
        let date = ISO8601DateFormatter().string(from: now)
        let rows: [[String: Any]] = [
            ["id": UUID().uuidString, "completedAt": date, "workoutType": "Run", "notes": "",
             "healthExport": ["startTimestamp": timestamp - 600, "endTimestamp": timestamp,
                              "state": "pending", "attempts": 1, "lastError": "The save will retry when enabled."]],
            ["id": UUID().uuidString, "completedAt": date, "workoutType": "Run", "notes": "",
             "healthExport": ["startTimestamp": timestamp - 1800, "endTimestamp": timestamp - 1200,
                              "state": "saved", "attempts": 1, "savedAt": date, "healthID": UUID().uuidString]]
        ]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: rows), as: UTF8.self)
        let argument = String(decoding: try JSONEncoder().encode(json), as: UTF8.self)
        app.launchArguments = reviewLaunchArguments + ["-workoutLogEntriesData", argument, "-AppleInterfaceStyle", "Dark"]
        app.launch()
        app.buttons["Settings"].tap()
        let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Health & Devices")).firstMatch
        reveal(link, in: app)
        link.tap()
        let confirmed = app.staticTexts["Last confirmed save"]
        reveal(confirmed, in: app, scrollContainer: app.collectionViews.firstMatch)
        XCTAssertTrue(confirmed.waitForExistence(timeout: 5))
        let retry = app.buttons["Retry Pending Saves"]
        reveal(retry, in: app)
        XCTAssertFalse(retry.isEnabled)
        keepScreenshot("Health and Devices - Pending and confirmed saves", app: app)
    }
}

extension N4x4UITests {
    func testBonusRoundIsHiddenByDefaultAndCanBeQueuedAndUndone() {
        let app = XCUIApplication()
        let timer = ["-numberOfIntervals", "1", "-warmupDuration", "0", "-highIntensityDuration", "240", "-cooldownEnabled", "YES"]
        app.launchArguments = reviewLaunchArguments + timer + ["-bonusRoundEnabled", "NO"]
        app.launch()
        app.buttons["START"].tap()
        XCTAssertTrue(app.buttons["PAUSE"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["bonus-round-button"].exists)
        app.buttons["FINISH"].tap()
        app.alerts["Finish workout?"].buttons["Discard Workout"].tap()
        app.terminate()
        app.launchArguments = reviewLaunchArguments + timer + ["-bonusRoundEnabled", "YES"]
        app.launch()
        app.buttons["START"].tap()
        let bonus = app.buttons["bonus-round-button"]
        assertVisible(bonus, in: app)
        bonus.tap()
        XCTAssertTrue(app.staticTexts["ROUND 1 OF 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(bonus.label.contains("Undo"))
        keepScreenshot("Bonus round queued on final work interval", app: app)
        bonus.tap()
        XCTAssertTrue(app.staticTexts["ROUND 1 OF 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(bonus.label.contains("+1"))
        XCUIDevice.shared.orientation = .landscapeLeft
        assertVisible(bonus, in: app)
        keepScreenshot("Bonus round landscape", app: app)
        XCUIDevice.shared.orientation = .portrait
    }

    func testBonusSettingIsSearchableAndOffByDefault() {
        let app = XCUIApplication()
        app.launchArguments = reviewLaunchArguments + ["-bonusRoundEnabled", "NO"]
        app.launch()
        app.buttons["Settings"].tap()
        let search = app.searchFields.firstMatch
        if !search.exists, app.buttons["Search"].waitForExistence(timeout: 5) { app.buttons["Search"].tap() }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("bonus")
        let result = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Intervals & Durations")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        let setting = app.switches["bonus-round-setting"]
        reveal(setting, in: app)
        XCTAssertEqual(setting.value as? String, "0")
        keepScreenshot("Bonus round setting - off by default", app: app)
    }

    func testRenameHistoryWorkoutAndExportFITToFiles() throws {
        let app = XCUIApplication(), id = UUID().uuidString, now = Date()
        let timestamp = now.timeIntervalSince1970
        let row: [String: Any] = ["id": id, "completedAt": ISO8601DateFormatter().string(from: now),
            "workoutType": "Run", "notes": "", "sessionBreakdown": ["totalDuration": 60],
            "healthExport": ["startTimestamp": timestamp - 60, "endTimestamp": timestamp,
                             "expectedActiveDuration": 60, "attempts": 0, "state": "notRequested"]]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: [row]), as: UTF8.self)
        let argument = String(decoding: try JSONEncoder().encode(json), as: UTF8.self)
        app.launchArguments = reviewLaunchArguments + ["-workoutLogEntriesData", argument]
        app.launch()
        app.buttons["History"].tap()
        let workout = app.buttons["workout-\(id)"]
        reveal(workout, in: app)
        workout.tap()
        let title = app.textFields["history-workout-title"]
        reveal(title, in: app)
        title.tap()
        title.typeText("Hill session")
        app.buttons["session-share-menu"].tap()
        let fit = app.buttons["export-workout-fit"]
        XCTAssertTrue(fit.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["export-workout"].exists)
        fit.tap()
        let save = app.cells["Save to Files"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), app.debugDescription)
        keepScreenshot("FIT export share sheet", app: app)
        save.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 10), app.debugDescription)
        keepScreenshot("FIT activity ready to save in Files", app: app)
    }
}

extension N4x4UITests {
    private func openAudioSettings(_ app: XCUIApplication) {
        app.buttons["Settings"].tap()
        let audio = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Audio")).firstMatch
        reveal(audio, in: app)
        audio.tap()
        XCTAssertTrue(app.navigationBars["Audio"].waitForExistence(timeout: 5))
    }

    func testVoicePickerKeepsDefaultAndPersistsAnInstalledVoiceWithPreview() {
        let app = XCUIApplication()
        app.launchArguments = reviewLaunchArguments + ["-audioModeRaw", "Voice Prompts"]
        app.launch()
        openAudioSettings(app)
        let picker = app.descendants(matching: .any).matching(identifier: "speech-voice-picker").firstMatch
        reveal(picker, in: app)
        XCTAssertTrue((picker.value as? String)?.contains("Default (current voice)") == true || picker.label.contains("Default (current voice)"))
        XCTAssertEqual(app.alerts.count, 0, "Listing voices must not request authorization")
        keepScreenshot("Audio voices - unchanged default", app: app)
        picker.tap()
        let option = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "speech-voice-option-")).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 10), "Simulator must expose an Apple English voice")
        let selectedLabel = option.label
        option.tap()
        XCTAssertTrue(app.navigationBars["Audio"].waitForExistence(timeout: 5))
        let preview = app.buttons["speech-voice-preview"]
        reveal(preview, in: app)
        XCTAssertTrue(preview.isEnabled)
        preview.tap()
        XCTAssertEqual(app.alerts.count, 0)
        keepScreenshot("Audio voices - selected installed voice", app: app)
        app.terminate()
        app.launch()
        openAudioSettings(app)
        XCTAssertTrue((picker.value as? String)?.contains(selectedLabel) == true || picker.label.contains(selectedLabel), app.debugDescription)
        picker.tap()
        let defaultOption = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Default (current voice)")).firstMatch
        XCTAssertTrue(defaultOption.waitForExistence(timeout: 5))
        defaultOption.tap()
        XCTAssertTrue(app.navigationBars["Audio"].waitForExistence(timeout: 5))
    }

    func testMissingVoiceFallsBackAndPreviewIsDisabledDuringWorkout() {
        let app = XCUIApplication()
        app.launchArguments = reviewLaunchArguments + ["-audioModeRaw", "Voice Prompts",
            "-speechVoiceIdentifier", "com.apple.unavailable.n4x4-test", "-warmupDuration", "0",
            "-numberOfIntervals", "1", "-highIntensityDuration", "240"]
        app.launch()
        app.buttons["START"].tap()
        XCTAssertTrue(app.buttons["PAUSE"].waitForExistence(timeout: 5))
        openAudioSettings(app)
        let preview = app.buttons["speech-voice-preview"]
        reveal(preview, in: app)
        XCTAssertFalse(preview.isEnabled, "Preview must not interrupt active workout audio")
        let picker = app.descendants(matching: .any).matching(identifier: "speech-voice-picker").firstMatch
        XCTAssertTrue((picker.value as? String)?.contains("Unavailable voice") == true || picker.label.contains("Unavailable voice"))
        XCTAssertEqual(app.alerts.count, 0)
        keepScreenshot("Audio voices - unavailable fallback during workout", app: app)
    }
}
