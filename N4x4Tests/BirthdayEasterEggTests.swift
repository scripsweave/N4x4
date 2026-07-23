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
