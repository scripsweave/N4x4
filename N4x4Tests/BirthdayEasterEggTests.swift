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
