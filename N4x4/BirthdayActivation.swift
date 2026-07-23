// BirthdayActivation.swift
//
// Pure-Foundation activation logic for the 2 August easter egg, kept free of
// SwiftUI so it is unit-testable (N4x4Tests/BirthdayEasterEggTests.swift).
// The visuals live in BirthdayEasterEgg.swift.

import Foundation

enum BirthdayEasterEgg {
    /// The hidden manual trigger (a long press on the last Advanced tile in
    /// the Guide) arms this key. The next arrival at Home consumes it and
    /// runs birthday mode once — consuming clears the key, so the flag can
    /// never stick a device in birthday mode.
    static let oneShotDefaultsKey = "birthdayOneShotPending"

    static func armOneShot(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: oneShotDefaultsKey)
    }

    /// True exactly once per arming — reading clears the flag.
    static func consumeOneShot(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.bool(forKey: oneShotDefaultsKey) else { return false }
        defaults.removeObject(forKey: oneShotDefaultsKey)
        return true
    }

    /// True on 2 August in the given (device-local) time zone — any year; the
    /// annual recurrence is deliberate. Explicitly Gregorian: `Calendar.current`
    /// follows the user's calendar setting, and in the Islamic/Hebrew/Chinese
    /// calendars "month 8, day 2" is a different Gregorian day entirely.
    static func isTheDay(on date: Date = Date(),
                         timeZone: TimeZone = .current) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.month, .day], from: date)
        return c.month == 8 && c.day == 2
    }
}
