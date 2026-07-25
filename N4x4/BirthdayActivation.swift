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
        return c.month == herMonth && c.day == herDay
    }

    /// 2 August: the fixed date the egg was built for.
    static let herMonth = 8
    static let herDay = 2

    // MARK: - The user's own birthday (4.13+)

    /// Month/day of the user's birthday, cached from the HealthKit
    /// `dateOfBirth` characteristic (`TimerViewModel.refreshCachedUserBirthday`).
    /// Cached rather than read live so the home screen never has to touch
    /// HealthKit to decide whether to draw a disco ball.
    static let userBirthdayMonthKey = "birthdayUserMonth"
    static let userBirthdayDayKey = "birthdayUserDay"

    static func cacheUserBirthday(month: Int, day: Int,
                                  in defaults: UserDefaults = .standard) {
        guard (1...12).contains(month), (1...31).contains(day) else { return }
        defaults.set(month, forKey: userBirthdayMonthKey)
        defaults.set(day, forKey: userBirthdayDayKey)
    }

    /// Nil until HealthKit has handed over a date of birth (the user may never
    /// have entered one, and the read needs authorization).
    static func cachedUserBirthday(in defaults: UserDefaults = .standard)
        -> (month: Int, day: Int)? {
        let month = defaults.integer(forKey: userBirthdayMonthKey)
        let day = defaults.integer(forKey: userBirthdayDayKey)
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        return (month, day)
    }

    /// The gate the home screen actually uses: 2 August for everyone, plus the
    /// user's own birthday if we know it. Same Gregorian, local-day rules.
    static func isCelebrationDay(on date: Date = Date(),
                                 timeZone: TimeZone = .current,
                                 defaults: UserDefaults = .standard) -> Bool {
        if isTheDay(on: date, timeZone: timeZone) { return true }
        guard let own = cachedUserBirthday(in: defaults) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.month, .day], from: date)
        return c.month == own.month && c.day == own.day
    }

    // MARK: - Show cooldown

    /// Arriving at Home replays the whole choreography deliberately, but a
    /// quick app switch shouldn't: twenty foregrounds on the day would mean
    /// twenty finales and twenty message rises. Inside the cooldown the
    /// ambient show simply carries on.
    static let showCooldown: TimeInterval = 90

    static func shouldRestartShow(lastShownAt: Date?,
                                  now: Date = Date(),
                                  cooldown: TimeInterval = showCooldown) -> Bool {
        guard let last = lastShownAt else { return true }
        let elapsed = now.timeIntervalSince(last)
        // A backwards clock (midnight zone change, manual date edit) must not
        // lock the show out for 90 s of wall time that never arrives.
        return elapsed < 0 || elapsed >= cooldown
    }

    // MARK: - Morning nudges

    /// 06:00 local on the day. Sent so the surprise isn't missed entirely by a
    /// phone that stays in a pocket; the show itself only runs on Home.
    static let nudgeHour = 6

    static let hersNudgeIdentifier = "birthdayNudge_0802"
    static let usersNudgeIdentifier = "birthdayNudge_user"

    /// Yearly repeating trigger components. Month + day + hour + minute with
    /// `repeats: true` fires once a year, so the system holds it without the
    /// app ever launching again.
    static func nudgeComponents(month: Int, day: Int) -> DateComponents {
        DateComponents(month: month, day: day, hour: nudgeHour, minute: 0)
    }

    /// The user's own nudge is skipped when their birthday IS 2 August —
    /// otherwise they'd get two notifications one minute apart.
    static func needsOwnNudge(month: Int, day: Int) -> Bool {
        !(month == herMonth && day == herDay)
    }
}
