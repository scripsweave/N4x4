// BirthdayEasterEggTests.swift
// Locks down the 2 August activation check (BirthdayActivation.swift):
// fires all day on 2 August local time, every year, Gregorian regardless of
// the device's calendar setting, and never on any other day.

import XCTest
@testable import N4x4

final class BirthdayEasterEggTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let jhb = TimeZone(identifier: "Africa/Johannesburg")!

    private func date(_ year: Int, _ month: Int, _ day: Int,
                      _ hour: Int = 12, _ minute: Int = 0,
                      tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testFiresOnSecondOfAugust() {
        XCTAssertTrue(BirthdayEasterEgg.isTheDay(
            on: date(2026, 8, 2, tz: jhb), timeZone: jhb))
    }

    func testRecursEveryYear() {
        for year in 2026...2050 {
            XCTAssertTrue(BirthdayEasterEgg.isTheDay(
                on: date(year, 8, 2, tz: jhb), timeZone: jhb),
                "must recur annually — failed for \(year)")
        }
    }

    func testFiresForTheWholeLocalDay() {
        XCTAssertTrue(BirthdayEasterEgg.isTheDay(
            on: date(2026, 8, 2, 0, 0, tz: jhb), timeZone: jhb))
        XCTAssertTrue(BirthdayEasterEgg.isTheDay(
            on: date(2026, 8, 2, 23, 59, tz: jhb), timeZone: jhb))
    }

    func testDoesNotFireOnAdjacentDaysOrSwappedComponents() {
        XCTAssertFalse(BirthdayEasterEgg.isTheDay(
            on: date(2026, 8, 1, 23, 59, tz: jhb), timeZone: jhb))
        XCTAssertFalse(BirthdayEasterEgg.isTheDay(
            on: date(2026, 8, 3, 0, 0, tz: jhb), timeZone: jhb))
        // 8 February — the day/month-swap trap
        XCTAssertFalse(BirthdayEasterEgg.isTheDay(
            on: date(2026, 2, 8, tz: jhb), timeZone: jhb))
    }

    func testUsesLocalTimeZoneNotUTC() {
        // 1 Aug 23:00 UTC is already 2 Aug 01:00 in Johannesburg (UTC+2).
        let d = date(2026, 8, 1, 23, 0, tz: utc)
        XCTAssertTrue(BirthdayEasterEgg.isTheDay(on: d, timeZone: jhb))
        XCTAssertFalse(BirthdayEasterEgg.isTheDay(on: d, timeZone: utc))
    }

    // MARK: - One-shot manual trigger (Guide → Advanced → last tile)

    func testOneShotConsumesExactlyOnce() {
        let suite = "birthday-oneshot-test"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        XCTAssertFalse(BirthdayEasterEgg.consumeOneShot(in: defaults),
                       "must not fire before arming")
        BirthdayEasterEgg.armOneShot(in: defaults)
        XCTAssertTrue(BirthdayEasterEgg.consumeOneShot(in: defaults))
        XCTAssertFalse(BirthdayEasterEgg.consumeOneShot(in: defaults),
                       "consuming must clear the flag — one show, then normal")
        XCTAssertNil(defaults.object(forKey: BirthdayEasterEgg.oneShotDefaultsKey),
                     "the key must not linger in defaults")
    }

    // MARK: - Disco ball spin dynamics

    func testSpinReturnsToHouseSpeedAfterFlick() {
        let spin = DiscoBallSpin()
        spin.step(now: 0)
        spin.dragChanged(x: 0, time: 0.10, radius: 120)
        spin.dragChanged(x: 60, time: 0.20, radius: 120)
        spin.dragEnded(velocityX: 600, radius: 120)     // 5 rad/s flick
        XCTAssertEqual(spin.omega, 5.0, accuracy: 0.01)

        var t = 0.20
        while t < 30 { t += 1.0 / 60; spin.step(now: t) }
        XCTAssertEqual(spin.omega, DiscoBallSpin.defaultOmega, accuracy: 0.05,
                       "motor + friction must relax the ball back to default spin")
    }

    func testGrabStopsTheBallAndStillReleaseKeepsItStopped() {
        let spin = DiscoBallSpin()
        spin.step(now: 0)
        spin.step(now: 0.5)
        spin.dragChanged(x: 100, time: 0.6, radius: 120)   // catch it
        let caughtAngle = spin.angle
        spin.step(now: 1.5)                                 // held still
        XCTAssertEqual(spin.angle, caughtAngle,
                       "the finger owns the angle while grabbed")
        spin.dragEnded(velocityX: 0, radius: 120)
        XCTAssertEqual(spin.omega, 0, accuracy: 0.001,
                       "releasing without a flick leaves the ball stopped")

        var t = 1.5
        while t < 30 { t += 1.0 / 60; spin.step(now: t) }
        XCTAssertEqual(spin.omega, DiscoBallSpin.defaultOmega, accuracy: 0.05,
                       "the motor must spool a stopped ball back up")
    }

    func testFlickVelocityIsCapped() {
        let spin = DiscoBallSpin()
        spin.step(now: 0)
        spin.dragChanged(x: 0, time: 0.1, radius: 120)
        spin.dragEnded(velocityX: 1_000_000, radius: 120)
        XCTAssertEqual(spin.omega, DiscoBallSpin.maxOmega,
                       "a violent flick must clamp, not run away")
        spin.dragChanged(x: 0, time: 0.2, radius: 120)
        spin.dragEnded(velocityX: -1_000_000, radius: 120)
        XCTAssertEqual(spin.omega, -DiscoBallSpin.maxOmega,
                       "the cap applies in both directions")
    }

    // MARK: - Pendulum sway (4.13)

    func testSwaySettlesBackToAmbientAfterAFlick() {
        let swing = DiscoBallSwing()
        swing.step(now: 0)
        swing.kick(velocityX: 3_000)                  // a violent flick
        var t = 0.0
        var peak = 0.0
        while t < 2 {
            t += 1.0 / 60
            swing.step(now: t)
            peak = max(peak, abs(swing.offsetX))
        }
        XCTAssertGreaterThan(peak, DiscoBallSwing.ambientAmplitude * 1.5,
                             "a flick must visibly swing the ball")
        while t < 30 { t += 1.0 / 60; swing.step(now: t) }
        XCTAssertLessThanOrEqual(abs(swing.offsetX),
                                 DiscoBallSwing.ambientAmplitude + 0.35,
                                 "the impulse must damp out, leaving only the ambient sway")
    }

    func testAmbientSwayStaysWithinAmplitudeAndKeepsMoving() {
        let swing = DiscoBallSwing()
        var t = 0.0
        var seen: Set<Int> = []
        while t < 20 {
            t += 1.0 / 60
            swing.step(now: t)
            XCTAssertLessThanOrEqual(abs(swing.offsetX),
                                     DiscoBallSwing.ambientAmplitude + 0.001,
                                     "an untouched ball must not drift out of its ±2 pt sway")
            seen.insert(Int((swing.offsetX * 10).rounded()))
        }
        XCTAssertGreaterThan(seen.count, 10, "the ball must keep moving, not park")
    }

    func testSwayIgnoresABackwardsClock() {
        let swing = DiscoBallSwing()
        swing.step(now: 5)
        swing.kick(velocityX: 500)
        swing.step(now: 5.1)
        let before = swing.offsetX
        swing.step(now: 1)                            // clock jumps backwards
        XCTAssertEqual(swing.offsetX, before, accuracy: 0.5,
                       "a negative dt must not run the pendulum in reverse")
    }

    func testVerticalRiseIsZeroForADegenerateLength() {
        let swing = DiscoBallSwing()
        swing.step(now: 0.4)
        XCTAssertEqual(swing.verticalRise(pendulumLength: 0), 0)
        XCTAssertGreaterThanOrEqual(swing.verticalRise(pendulumLength: 400), 0,
                                    "the ball lifts, never sinks, at the ends of the arc")
    }

    // MARK: - Firework engine invariants (4.13)

    private let sky = CGSize(width: 390, height: 780)

    func testSparkCapHoldsUnderAContinuousShow() {
        let engine = FireworkEngine()
        var t = 0.0
        // three overlapping finales on top of the ambient stream
        engine.finale()
        engine.finale(startingIn: 0.5)
        engine.finale(startingIn: 1.0)
        while t < 60 {
            t += 1.0 / 60
            engine.step(now: t, in: sky)
            XCTAssertLessThanOrEqual(engine.sparkCount, FireworkEngine.sparkCap,
                                     "the spark cap must hold")
            XCTAssertLessThanOrEqual(engine.flashCount, 5)
            XCTAssertLessThanOrEqual(engine.smokeCount, 8)
        }
    }

    func testZeroBoundsProduceNoParticles() {
        let engine = FireworkEngine()
        engine.launch()
        engine.launchComet()
        XCTAssertEqual(engine.rocketCount, 0,
                       "a launch before layout has reported a size must no-op")
        engine.step(now: 0.016, in: .zero)
        engine.step(now: 0.5, in: .zero)
        XCTAssertEqual(engine.rocketCount, 0)
        XCTAssertEqual(engine.sparkCount, 0)
    }

    func testFinaleQueuesSevenRocketsAndDrains() {
        let engine = FireworkEngine()
        engine.finale(startingIn: 1.4)
        XCTAssertEqual(engine.pendingLaunchCount, 7)
        var t = 0.0
        while t < 5 { t += 1.0 / 60; engine.step(now: t, in: sky) }
        XCTAssertEqual(engine.pendingLaunchCount, 0,
                       "every queued rocket must lift off exactly once")
    }

    func testEngineIgnoresABackwardsClock() {
        let engine = FireworkEngine()
        engine.step(now: 0, in: sky)          // ambient rocket lifts off
        engine.step(now: 0.5, in: sky)
        XCTAssertGreaterThan(engine.rocketCount, 0, "precondition: something is flying")
        let before = engine.rocketPositions
        engine.step(now: 0.2, in: sky)        // clock jumps backwards
        XCTAssertEqual(engine.rocketPositions, before,
                       "a negative dt must freeze the sky, not rewind it")
    }

    func testBurstsReportStrengthForHaptics() {
        let engine = FireworkEngine()
        var strengths: [Double] = []
        engine.onBurst = { strengths.append($0) }
        engine.finale()
        var t = 0.0
        while t < 8 { t += 1.0 / 60; engine.step(now: t, in: sky) }
        XCTAssertGreaterThanOrEqual(strengths.count, 7,
                                    "every shell must report a burst")
        for s in strengths {
            XCTAssertGreaterThan(s, 0)
            XCTAssertLessThanOrEqual(s, 1, "haptic intensity is a 0…1 parameter")
        }
    }

    func testOnlyOneCometFliesAtATime() {
        let engine = FireworkEngine()
        engine.step(now: 0, in: sky)
        for _ in 0..<5 { engine.launchComet() }
        engine.step(now: 0.1, in: sky)
        XCTAssertLessThanOrEqual(engine.rocketCount, 3,
                                 "comets must not stack up (1 ambient + 1 comet at most)")
    }

    // MARK: - Show cooldown (4.13)

    func testShowRestartsOnlyAfterTheCooldown() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(BirthdayEasterEgg.shouldRestartShow(lastShownAt: nil, now: start),
                      "the first arrival always runs the show")
        XCTAssertFalse(BirthdayEasterEgg.shouldRestartShow(
            lastShownAt: start, now: start.addingTimeInterval(5)),
            "a quick app switch must not replay the finale")
        XCTAssertTrue(BirthdayEasterEgg.shouldRestartShow(
            lastShownAt: start,
            now: start.addingTimeInterval(BirthdayEasterEgg.showCooldown + 1)))
        XCTAssertTrue(BirthdayEasterEgg.shouldRestartShow(
            lastShownAt: start, now: start.addingTimeInterval(-3600)),
            "a backwards clock must not lock the show out")
    }

    // MARK: - The user's own birthday (4.13)

    func testCelebrationDayCoversTheUsersOwnBirthday() {
        let suite = "birthday-user-dob-test"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let march9 = date(2027, 3, 9, tz: jhb)
        XCTAssertFalse(BirthdayEasterEgg.isCelebrationDay(
            on: march9, timeZone: jhb, defaults: defaults),
            "no cached birthday means 2 August only")

        BirthdayEasterEgg.cacheUserBirthday(month: 3, day: 9, in: defaults)
        XCTAssertTrue(BirthdayEasterEgg.isCelebrationDay(
            on: march9, timeZone: jhb, defaults: defaults))
        XCTAssertTrue(BirthdayEasterEgg.isCelebrationDay(
            on: date(2027, 8, 2, tz: jhb), timeZone: jhb, defaults: defaults),
            "2 August must keep firing regardless of the user's own date")
        XCTAssertFalse(BirthdayEasterEgg.isCelebrationDay(
            on: date(2027, 3, 10, tz: jhb), timeZone: jhb, defaults: defaults))
        // the month/day-swap trap again, this time on the user's own date
        XCTAssertFalse(BirthdayEasterEgg.isCelebrationDay(
            on: date(2027, 9, 3, tz: jhb), timeZone: jhb, defaults: defaults))
    }

    func testGarbageBirthdayComponentsAreRejected() {
        let suite = "birthday-user-dob-garbage"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        BirthdayEasterEgg.cacheUserBirthday(month: 0, day: 0, in: defaults)
        XCTAssertNil(BirthdayEasterEgg.cachedUserBirthday(in: defaults))
        BirthdayEasterEgg.cacheUserBirthday(month: 13, day: 1, in: defaults)
        XCTAssertNil(BirthdayEasterEgg.cachedUserBirthday(in: defaults))
        BirthdayEasterEgg.cacheUserBirthday(month: 2, day: 29, in: defaults)
        XCTAssertEqual(BirthdayEasterEgg.cachedUserBirthday(in: defaults)?.day, 29,
                       "a 29 February birthday is legitimate")
    }

    func testMorningNudgesFireAtSixLocalAndDontDoubleUp() {
        let hers = BirthdayEasterEgg.nudgeComponents(month: 8, day: 2)
        XCTAssertEqual(hers.hour, 6)
        XCTAssertEqual(hers.minute, 0)
        XCTAssertEqual(hers.month, 8)
        XCTAssertEqual(hers.day, 2)
        XCTAssertNil(hers.year, "the trigger must repeat annually, not pin a year")

        XCTAssertTrue(BirthdayEasterEgg.needsOwnNudge(month: 3, day: 9))
        XCTAssertFalse(BirthdayEasterEgg.needsOwnNudge(month: 8, day: 2),
                       "a 2 August user must get one nudge, not two")
    }

    func testGregorianEvenIfDeviceCalendarDiffers() {
        // A phone set to the Islamic calendar reports different month/day
        // numbers for the same instant. The check must fire on the real
        // Gregorian 2 August anyway…
        var islamic = Calendar(identifier: .islamicUmmAlQura)
        islamic.timeZone = jhb
        let aug2 = date(2026, 8, 2, tz: jhb)
        let islamicComponents = islamic.dateComponents([.month, .day], from: aug2)
        XCTAssertFalse(islamicComponents.month == 8 && islamicComponents.day == 2,
                       "precondition: Islamic month/day differ from Gregorian here")
        XCTAssertTrue(BirthdayEasterEgg.isTheDay(on: aug2, timeZone: jhb))

        // …and must NOT fire on a day that is month 8 / day 2 only in the
        // Islamic calendar.
        if let trap = islamic.date(from: DateComponents(
            year: 1448, month: 8, day: 2, hour: 12)) {
            XCTAssertFalse(BirthdayEasterEgg.isTheDay(on: trap, timeZone: jhb),
                           "Islamic 8/2 must not trigger the Gregorian check")
        }
    }
}
