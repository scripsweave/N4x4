# N4x4 App - Memory

## Overview
SwiftUI iOS fitness app for the Norwegian 4x4 HIIT protocol. Guides users through interval workouts with heart rate zones, tracks weekly streaks, integrates with Apple Health.

**App Store**: https://apps.apple.com/app/n4x4/id6686407796
**Version**: 2.0

## Architecture
- **Pattern**: MVVM
- **Central ViewModel**: `TimerViewModel.swift` (~1300 lines) — all core business logic
- **Entry**: `N4x4App.swift` → `ContentView.swift` → `TimerView.swift` (post-onboarding)
- **No external dependencies** — only Apple frameworks

## Recent Work
- **Bluetooth HR monitors (2026-07-18)** — chest straps/armbands via Core Bluetooth join the Watch as live HR sources. Plan: `docs/Bluetooth HR Monitor Plan.md`. Code: `N4x4/Bluetooth/` (parser + aggregator pure & tested, manager, views). One funnel: `TimerViewModel.ingestHeartRate(_:from:)`; BLE beats Watch; 10 s staleness clears frozen readings. New onboarding step `.heartRate`; Settings section "Heart Rate Monitor"; troubleshooting sheet offers the strap path. Config: `NSBluetoothAlwaysUsageDescription` (pbxproj), `bluetooth-central` background mode (N4x4/Info.plist). Rules in AGENTS.md §Bluetooth. Needs on-device verification (CoreBluetooth ≠ Simulator).
- [Home/Workout redesign](home-workout-redesign.md) — dark premium 2-screen redesign on branch `feature/home-workout-redesign`; behind `useRedesignedUI` flag in ContentView, all in `HomeWorkoutRedesign.swift`.
- [simctl blank-screen gotcha](simctl-blank-screen-debug-dylib.md) — headless screenshots need `ENABLE_DEBUG_DYLIB=NO` + a freshly-erased sim.

## Key Files
```
N4x4/
├── N4x4App.swift              App entry + AppDelegate (audio session, notifications)
├── ContentView.swift          Root view + 8-step onboarding flow
├── TimerViewModel.swift       ALL business logic: timer, streaks, health, notifications, voice
├── TimerView.swift            Main workout UI: countdown ring, HR zones, controls
├── SettingsView.swift         Settings: intervals, audio mode, notifications, health, age
├── StreakCard.swift           Streak visualization: calendar, flame, milestones
├── HeartRateGuidanceCard.swift  HR zone education card
├── HelpView.swift             Marketing/onboarding help screen
├── SpeechManager.swift        AVSpeechSynthesizer singleton with audio session ducking
├── Interval.swift             Interval data model (warmup/highIntensity/rest)
└── Extensions.swift           TimeInterval formatting utility
```

## Data Models
- **WorkoutLogEntry**: UUID, completedAt: Date, workoutType, notes — stored as JSON in UserDefaults
- **Interval**: name, duration, type (.warmup/.highIntensity/.rest)
- **VO2DataPoint**: date + value (mL/kg*min) — read from HealthKit
- **WorkoutType enum**: norwegian4x4, run, cycle, rowing, treadmill, hillSprints, stairs, jumpRope, circuit, sports, other

## Persistence
- `@AppStorage` (UserDefaults) for settings and streaks
- `workoutLogEntriesData`: JSON-encoded array of WorkoutLogEntry
- Reminder weekdays stored as comma-separated string ("1,3,5")
- Data migration support from V1/V2 formats

## Default Workout Structure
- Warmup: 5 min
- High Intensity: 4 min × 4 rounds
- Recovery: 3 min (between rounds)
- Total: ~22 min

## Heart Rate Zones
- Max HR = 220 - userAge (ages 13-100)
- High Intensity: 85-95% of Max HR
- Recovery: 60-70% of Max HR

## Streak Logic
- Counts **consecutive weeks** (not days) with ≥1 workout
- Uses (year, weekOfYear) pairs — backwards scan from current week
- Tracks currentStreak and longestStreak

## Notification System
- **Interval cues**: fire at end of current interval (non-repeating)
- **Reminders**: night-before (8 PM), morning-of (8 AM), daily follow-up (10 AM)
- Multi-day support: unique notification per weekday selection
- Viking/warrior themed motivational messages
- Reschedules on app launch; cancels if workout logged

## HealthKit Integration
- **Read**: VO2 Max samples (last 60) → trend chart on TimerView
- **Write**: Saves completed workouts as HIIT activities via HKWorkoutBuilder
- Conditional Charts API (iOS 16+)

## Timer Implementation
- `Timer.publish()` with Combine `sink` for 1-second ticks
- `intervalEndTime: Date?` for accurate tracking
- `reconcileTimerState()` handles backgrounding gaps
- `isSyncingFromPublished` flag prevents circular AppStorage ↔ @Published syncs

## Audio System
- `AudioMode` enum: `.voice` (default) / `.alarm` / `.silent`
- `@AppStorage("audioModeRaw")` — persisted, computed `audioMode` var
- Migration: if `audioModeRaw` absent, `alarmEnabled ? .voice : .silent`
- Voice prompts: `SpeechManager.shared.speak()` with `.duckOthers` ducking
- Prompt schedule: HIT/Recovery start (HR targets), HIT/Recovery halfway, 10s warning, workout complete
- Flags `halfwayPromptFired` + `tenSecondPromptFired` reset on every interval change
- See `memory/voice-prompts.md` for full detail

## User Flows

### Onboarding (8 steps, skippable except step 1)
Welcome → Structure → Age → Audio Mode → Notifications → Reminder Days → HealthKit → Launch

### Workout Flow
Idle → Active (ring animates, color: blue/red/green by phase) → Interval transition (audio + notification) → Complete → PostWorkoutSummaryView sheet → StreakHistoryView

### Post-Workout
- Shows date in title, workout type picker, notes field
- Done saves entry, updates streak, navigates to Weekly Streaks

## View Hierarchy
```
ContentView
├── OnboardingView (full-screen cover)
└── TimerView
    ├── Circular progress ring (color by interval type)
    ├── HR zone display
    ├── Play/Pause + Skip buttons
    ├── VO2 chart (HealthKit)
    ├── Nav buttons (Reset, History/Streaks, Settings)
    ├── PostWorkoutSummaryView (sheet)
    └── StreakHistoryView (sheet)
```

## Post-v2.0 Bug Fixes (see docs/Version 2.0 Fixes.md)
- **N1**: Reminder scheduling moved into async completion block (was silent race condition)
- **N2**: `cancelMissedWorkoutFollowUpReminder` now cancels `_daily_DD` variants (days 1–31)
- **N4**: Morning-of reminder changed to weekly repeating trigger (was one-shot, never repeated)
- **N5**: `scheduleRecurringFollowUp` checks today's workout, not a future date
- **N6**: `scheduleNotification` guard uses only `notificationsEnabled` (not `|| workoutRemindersEnabled`)
- **S1**: `currentStreak` now recalculated on launch/foreground/completion (was only incremented)
- **S2**: `WorkoutLogEntry.year` uses `.yearForWeekOfYear` (was `.year`, broke Dec 29–31 streaks)
- **S3/S4**: Dynamic last-week lookup replaces hardcoded 52; force-unwrap removed
- **G1**: `AudioManager.swift` deleted (dead code; ViewModel owns audio directly)
- **G2**: `@ViewBuilder` removed from `timeString(_:)` in TimerView
- **G3**: `workoutOnDay` returns most-recent workout (was first match)
- **G4**: Permission guard only disables reminders on `.denied`/`.unavailable`, not `.unknown`
- **G5**: `persistWorkoutLogEntries` logs encode failures instead of silently dropping data

## Voice Prompt Rules (from voice-prompts.md)
- `speakIntervalCueIfNeeded()` fires at every HIT and Recovery interval start
- `speakHalfway()` fires once per interval (flag), HIT and Recovery only, duration ≥ 60s
- `speakTenSeconds()` fires once per interval (flag), duration > 10s, no Viking phrase
- Migration must use `alarmEnabled ? .voice : .silent` (not `.alarm`) so new users get Voice
- `resetPromptFlags()` must be called in `playAlarmIfNeeded()` voice case AND `moveToNextInterval()` AND `reset()`

## Key Rules (from AGENTS.md)
- Always schedule notifications INSIDE async completion blocks, never synchronously after
- Cancel `_daily_DD` variants (1–31) when cancelling follow-up notifications
- Use `.yearForWeekOfYear` (not `.year`) for streak week calculations
- Call `refreshStreak()` on launch AND foreground, not just on workout completion
- Notification identifiers: `workoutReminder_N` (night-before), `workoutReminderMorningOf_N` (morning-of), `workoutReminderFollowup_N_daily_DD` (one-shot follow-ups)
