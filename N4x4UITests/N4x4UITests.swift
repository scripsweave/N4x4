//
//  N4x4UITests.swift
//  N4x4UITests
//
//  Created by Jan van Rensburg on 9/12/24.
//

import XCTest

final class N4x4UITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        if app.state == .runningForeground {
            if app.alerts["Workout recovered"].exists {
                app.alerts["Workout recovered"].buttons["Discard Workout"].tap()
            }
            if app.tabBars.buttons["Home"].isHittable { app.tabBars.buttons["Home"].tap() }
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

    private var reviewLaunchArguments: [String] {
        ["-hasCompletedOnboarding", "YES",
         "-hasSeenHRSourcesAnnouncement", "YES",
         "-hasSeenWatchUpgradePrompt", "YES",
         "-healthKitEnabled", "NO", "-healthKitUserOptedOut", "YES",
         "-workoutRemindersEnabled", "NO", "-notificationsEnabled", "NO",
         "-audioModeRaw", "Silent", "-hapticsEnabled", "NO",
         "-shownMilestonesData", "\"[1,5,10,25,50,100]\"",
         "-hasRequestedAppReview", "YES"]
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            let tabBar = app.tabBars.firstMatch
            let bottom = tabBar.exists && tabBar.isHittable ? tabBar.frame.minY : app.frame.maxY
            if element.exists && element.isHittable && element.frame.minY >= 0 && element.frame.maxY <= bottom {
                return
            }
            // Small swipes avoid scrolling straight past a large text control.
            app.swipeUp(velocity: .slow)
        }
        keepScreenshot("Could not reveal control", app: app)
        print(app.debugDescription)
        XCTFail("Could not fully reveal \(element)")
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
        assertVisible(app.navigationBars.buttons["Done"], in: app)
        keepScreenshot("Landscape saved summary", app: app)
        app.navigationBars.buttons["Done"].tap()
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
        app.tabBars.buttons["History"].tap()
        let workouts = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout-"))
        reveal(workouts.firstMatch, in: app)
        XCTAssertEqual(workouts.count, 1)
        workouts.firstMatch.tap()
        let delete = app.navigationBars.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        app.alerts["Delete workout?"].buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Completed workouts are saved here automatically."].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        app.tabBars.buttons["History"].tap()
        reveal(app.staticTexts["Completed workouts are saved here automatically."], in: app)
        XCTAssertEqual(workouts.count, 0)

        // Done must also lead to a usable History sheet and nested detail.
        app.tabBars.buttons["Home"].tap()
        app.buttons["START"].tap()
        XCTAssertTrue(app.staticTexts["Saved to History"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 5))
        reveal(workouts.firstMatch, in: app)
        workouts.firstMatch.tap()
        XCTAssertTrue(app.navigationBars.buttons["Delete"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Delete"].tap()
        app.alerts["Delete workout?"].buttons["Delete"].tap()
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
        app.tabBars.buttons["History"].tap()
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
        app.navigationBars.buttons["Delete"].tap()
        app.alerts["Delete workout?"].buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Second workout"].exists)
        app.navigationBars.buttons["Delete"].tap()
        app.alerts["Delete workout?"].buttons["Delete"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertFalse(second.exists)
        first.tap()
        XCTAssertTrue(app.staticTexts["First workout"].waitForExistence(timeout: 5))
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
        app.navigationBars.buttons["Done"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout-"))
        reveal(rows.firstMatch, in: app)
        XCTAssertEqual(rows.count, 1)
        rows.firstMatch.tap()
        XCTAssertTrue(app.navigationBars.buttons["Delete"].waitForExistence(timeout: 5))
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
        app.tabBars.buttons["History"].tap()
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
