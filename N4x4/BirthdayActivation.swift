// BirthdayActivation.swift
//
// Pure-Foundation activation logic for the 2 August easter egg, kept free of
// SwiftUI so it is unit-testable (N4x4Tests/BirthdayEasterEggTests.swift).
// The visuals live in BirthdayEasterEgg.swift.

import Foundation

enum BirthdayEasterEgg {
    /// DEBUG-only Settings toggle writes this key to preview the egg any day.
    /// Release builds must never read it (the key survives app updates, so a
    /// device that ever ran a debug build could otherwise stay in birthday
    /// mode forever).
    static let previewDefaultsKey = "birthdayPreviewEnabled"

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
