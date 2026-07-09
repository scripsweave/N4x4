# N4x4 — Session Handoff

_Last updated 2026-07-08._ Resume point for the code-review + Apple-Watch
integration work. Read this top to bottom before touching anything. **Nothing is
committed** — all work is in a dirty working tree (HEAD `acf8445`).

---

## TL;DR — where we are right now

- **iOS app builds, runs, installed on a physical iPhone.** ✅
- **Unit tests compile; test scheme wired up (⌘U).** ✅
- **Watch app: builds, deploys to the physical Watch, and WORKS.** ✅ Live HR
  streams to the phone; the countdown is smooth; play/pause/skip and zone
  feedback function. It is a proper COMPANION app (see "Watch target recreation").
- **Just written, NOT yet built/verified: the 5-item Apple Watch connectivity
  UX** (red heart, zone-nudge options, connection status + troubleshooting,
  upgrader onboarding). Phone-side only. See change items #1 and #13 below.
- **Complication (N4x4Complication) is DEFERRED** — deleted during the Watch
  recreation. Re-add later; not needed for HR.

### → THE VERY NEXT ACTION
**Build the N4x4 (iOS) scheme in Xcode (⌘B).** The 5-item connectivity feature
set (commit item #13) was written but never compiled here — expect possible
first-build errors and fix them. Then run to iPhone + Watch and spot-check:
red heart on both; Settings ▸ Apple Watch status row (tap → troubleshooting);
and the amber "No heart rate — tap for help" banner on the timer screen ~15 s
into a workout that has no HR.

### Open threads (in priority order)
1. Verify the 5-item connectivity UX compiles + behaves (above).
2. **Decision pending:** should zone-nudge **Voice** default ON? It currently
   defaults OFF (`zoneVoiceAlertsEnabled = false`). Haptic + Visual default ON.
3. **Known open bug:** Watch `HKWorkoutSession` leak on reset/abandon (see
   "Known open bug" section). Now unblocked; implement + device-test.
4. Re-add the Watch complication if still wanted.
5. Eventually: commit this large body of work (nothing committed yet).

---

## How to deploy to the physical Watch (reference — already working)

1. iPhone connected by cable, unlocked; Watch on wrist, unlocked, paired,
   Developer Mode on (Watch → Settings → Privacy & Security → Developer Mode).
2. Xcode scheme = **N4x4Watch Watch App**; destination = your iPhone → pick the
   **Watch** sub-item. ▶ (⌘R). First install takes minutes.
3. HR needs a physical Series 4+ Watch, never the Simulator. Grant the HealthKit
   prompt on the Watch or HR stays 0.

---

## Physical-file layout after the Xcode target setup

Xcode named the Watch app folder **`N4x4Watch Watch App/`** (its default), not
`N4x4Watch/`. Current on-disk reality:

- `N4x4Watch Watch App/` — the Watch **app** target. Contains our
  `N4x4WatchApp.swift`, `WatchSessionManager.swift`, `WatchTimerView.swift`,
  `WorkoutManager.swift` (all correct, one `@main`), plus Xcode's
  `Assets.xcassets` and `.entitlements`.
- `N4x4Complication/` — the widget-extension target. Contains our real
  `N4x4Complication 2.swift` (KEEP) plus the two boilerplate files to delete.
- `N4x4Watch/` — **leftover empty-ish folder** (just an old `Info.plist`) from
  the file moves. Harmless. Tidy up once the build is green. `git status` shows
  the old `N4x4Watch/*.swift` as deleted/renamed — that's the move, expected.
- `Shared/` — `WatchMessage.swift`, `ZoneFeedback.swift`,
  `ZoneFeedbackStyle.swift`. Already members of the iOS **N4x4** target;
  must ALSO be ticked into **N4x4Watch** (verify — see table).
- `N4x4Watch-Watch-App-Info.plist` — stray file Xcode dropped at repo root
  (untracked). Ignore/clean later.

The `.swift 2` naming and the split `N4x4Watch/` vs `N4x4Watch Watch App/`
folders are cosmetic; they compile fine. Optional cleanup later, not blocking.

---

## Target-membership table (verify each file in File Inspector, ⌥⌘1)

| File | Target(s) |
|---|---|
| `Shared/WatchMessage.swift` | N4x4 + **N4x4Watch** |
| `Shared/ZoneFeedback.swift` | N4x4 + **N4x4Watch** |
| `Shared/ZoneFeedbackStyle.swift` | N4x4 + **N4x4Watch** |
| `N4x4/PhoneSessionManager.swift` | **N4x4 only** (do NOT add to Watch) |
| `N4x4/Interval.swift` | N4x4 + **N4x4Watch** |
| `N4x4/N4x4LiveActivityAttributes.swift` | N4x4 + **N4x4Watch** |
| `N4x4Watch Watch App/N4x4WatchApp.swift` | N4x4Watch only |
| `N4x4Watch Watch App/WatchSessionManager.swift` | N4x4Watch only |
| `N4x4Watch Watch App/WatchTimerView.swift` | N4x4Watch only |
| `N4x4Watch Watch App/WorkoutManager.swift` | N4x4Watch only |
| `N4x4Complication/N4x4Complication 2.swift` | N4x4Complication only |

---

## What was changed this session (all uncommitted)

### 1. iOS target file memberships (BLOCKER fix) — `project.pbxproj`
The Watch/HR feature's files (`PhoneSessionManager.swift`, `Shared/*.swift`)
were committed to disk but in NO Xcode target, so `TimerViewModel.swift`
referenced undefined symbols → iOS app would not compile. Added all four to the
iOS **N4x4** target (new `Shared` group). Hand-edited pbxproj UUID prefix
`5EA10000…`. A backup of the pre-edit pbxproj is in the session scratchpad.

### 2. Bug #1 (ISSUES.md) — legacy weekday migration never fired
`TimerViewModel.init()` — the migration lived only in
`workoutReminderWeekday.didSet`, but `@AppStorage` doesn't fire `didSet` when
loading a persisted value at launch, so upgrading users lost their saved
reminder day (reminders silently reset to "today"). Now migrated explicitly at
the top of `init()`.

### 3. Performance "Set all" data-loss bug (HIGH)
`TimerViewModel.stampAllIntervals()` — used to overwrite every interval with
`performanceSetAll` on every keystroke; clearing the field (parses to nil) wiped
hand-tuned per-interval values. Now no-ops when the value is nil.

### 4. Misleading pre-fill average (MEDIUM)
`TimerViewModel.preparePerformanceDraft()` — "Set all" was seeded with the
average of heterogeneous intervals (a value matching no interval). Now only
pre-fills when all filled intervals share one value; else left nil.

### 5. Compiler-warning cleanups
- `TimerViewModel.usesImperialUnits` — dropped dead `#available(iOS 16)` branch
  and deprecated `usesMetricSystem`; uses `Locale.current.measurementSystem`
  (deployment target is 17.5+).
- `SpeechManager` — made `final` + `@unchecked Sendable` (singleton forced
  Sendability; all access is main-thread). Comment explains why.

### 6. Deployment-target mismatch fix — `project.pbxproj`
App + LiveActivity extension were set to **iOS 26.0** min (would lock out nearly
all users, and broke the test build since tests were 17.5 and couldn't import a
26.0 module). Confirmed no code uses iOS-18/26-only APIs. Lowered all four
26.0 entries to **17.5** to match the project baseline. User approved.

### 7. Test scheme + stale test fixes
- `N4x4.xcscheme` — the Test action had no `<Testables>` (⌘U was greyed out).
  Added the `N4x4Tests` target (blueprint `3DF13A502C9389C200DD18E7`).
- `N4x4Tests.swift` — `.structure` step case no longer exists → renamed to
  `.basics` (the compile error), and fixed the stale step-order comments in
  `testOnboardingFlowIncludesReminderDayStep`.

### 8. Watch/Complication targets created (user, in Xcode UI)
Followed `docs/Watch App - Manual Xcode Steps.md` + the corrections in
`docs/Watch App - HR Zone Feedback Handoff.md`. **Important correction applied:**
Watch min deployment is **watchOS 10.0** (not 9.0 — the code uses two-param
`onChange`). HealthKit capability + `NSHealth*` usage strings added to the Watch
target. iOS Background Modes → Workout processing verified.

### 9. Complication duplicate-file cleanup (user, in Xcode)
Deleted Xcode's auto-generated `N4x4Complication/N4x4ComplicationBundle.swift`
and `N4x4ComplicationControl.swift` (they clashed with our self-contained
`N4x4Complication 2.swift`, which has its own `@main` bundle). Fixed the 3
`@main`/redeclaration errors.

### 10. Added `import Combine` to the three Watch files (BUILD FIX)
`N4x4Watch Watch App/{WatchSessionManager,WatchTimerView,WorkoutManager}.swift`.
watchOS does not transitively expose Combine the way iOS does, so `@Published`,
`ObservableObject`, and `Timer.publish(...).autoconnect()` were unresolved
(6 errors). Adding `import Combine` cleared them.

### 12. watchOS countdown smoothness (BUG FIX)
`WatchTimerView` drove the countdown with `Timer.publish(every:1…)`, which
watchOS throttles to ~5 s. Replaced with `TimelineView(.periodic(from:.now,
by:1))`, computing remaining time against `context.date` (added
`WatchTimerState.timeRemaining(asOf:)` / `progressValue(asOf:)`). Removed the
temporary on-screen diagnostic line + its plumbing. Countdown now updates every
second.

### 13. Apple Watch connectivity UX (5-item feature set)
Live Watch state now flows to the UI and drives status/troubleshooting/onboarding.
- **Foundation:** `TimerViewModel` gained `@Published watchPaired /
  watchAppInstalled / watchReachable`, a `WatchConnectionStatus` enum +
  `watchConnectionStatus`, `workoutElapsedSeconds`, and `shouldWarnMissingHeartRate`.
  Fed by new `PhoneSessionManager` delegate methods `sessionWatchStateDidChange`
  / `sessionReachabilityDidChange` / activation → `refreshWatchState()` →
  `updateWatchConnectionState(...)`.
- **Item 1 — red heart:** heart icon is always red on phone (`TimerView`) and
  Watch (`WatchTimerView`); the BPM number keeps its zone colour.
- **Item 2 — nudges:** already existed (Settings ▸ Heart-Rate Zone Alerts:
  Haptic/Voice/Visual toggles; shared engine caps at one alert/min with a settle
  window). Voice defaults OFF. No rebuild needed — it just now fires because HR
  flows. If the user wants voice on by default, flip `zoneVoiceAlertsEnabled`
  default in `TimerViewModel`.
- **Items 3 & 4 — status + troubleshooting:** tappable status row in Settings ▸
  Apple Watch (always), and a tappable warning banner on the timer screen while a
  workout runs with a paired Watch but no HR (`shouldWarnMissingHeartRate`, 15 s
  grace). Both open `WatchTroubleshootingView`, an adaptive sheet that diagnoses
  no-watch / not-installed / not-reachable / connected-but-no-HR (the last walks
  through HealthKit permissions).
- **Item 5 — upgrader onboarding:** `WatchUpgradeOnboardingView`, a one-time
  full-screen sheet shown when a paired Watch is detected but our app isn't
  installed AND onboarding is already complete. Gated by
  `@AppStorage hasSeenWatchUpgradePrompt`.
- **New file:** `N4x4/WatchSetupViews.swift` (added to the N4x4 target in
  pbxproj, build-file UUIDs `5EA1…B5/F5`).
- **NOT yet verified on device** — written, cross-checked, lints clean, but not
  built. Build the N4x4 (iOS) scheme first.

### 11. Watch target recreation — standalone → companion (MAJOR)
The Watch target had been created as a **standalone / watch-only app** with its
own separate container (`janvanrensburg.N4x4Watch`, `WKWatchOnly = YES`). That
is fatal for this feature: WatchConnectivity (`WCSession`) only links an iPhone
app to ITS OWN companion Watch app, so the N4x4 phone app and that Watch app
would never connect — `isWatchAppInstalled` would be false and no state/HR would
flow. Fix:
1. Deleted the 3 bad targets (`N4x4Watch` container, `N4x4Watch Watch App`,
   `N4x4ComplicationExtension`) + their stale on-disk folders + orphaned
   `PBXFileSystemSynchronizedRootGroup` refs in pbxproj.
2. Recreated via **File > New > Target > watchOS > App**, choosing
   **"Watch App for Existing iOS App" → N4x4** (NOT "Watch-only App" — that was
   the original mistake). Product name `N4x4Watch`.
   Result: bundle id `Jan-van-Rensburg.N4x4.watchkitapp`,
   `WKCompanionAppBundleIdentifier = Jan-van-Rensburg.N4x4`, no `WKWatchOnly`,
   embedded in the N4x4 iPhone app. ✅
3. New target uses an Xcode-16 **synchronized folder group** — any `.swift` in
   `N4x4Watch Watch App/` auto-joins the target. Copied our 4 real Watch files
   back in (from the scratchpad backup); deleted Xcode's placeholder
   `ContentView.swift`.
4. Hand-edited pbxproj to add the 5 SHARED files to the Watch target's Sources
   phase (they live outside the synced folder): `Shared/WatchMessage.swift`,
   `Shared/ZoneFeedback.swift`, `Shared/ZoneFeedbackStyle.swift`,
   `N4x4/Interval.swift`, `N4x4/N4x4LiveActivityAttributes.swift`
   (build-file UUIDs `5EA1…C1–C5`).
5. Lowered `WATCHOS_DEPLOYMENT_TARGET` 26.5 → **10.0** (26.5 would lock out the
   Watch; code needs watchOS 10 for two-param onChange).
6. Added Watch HealthKit usage strings (`INFOPLIST_KEY_NSHealthShare/Update…`)
   to both Watch configs — `WorkoutManager.requestAuthorization` traps without
   them.
7. User added the **HealthKit capability** via Signing & Capabilities (must be
   done in Xcode UI — it provisions the device).
→ **N4x4Watch scheme builds.** Backup of all 5 Watch source files is in the
session scratchpad (`scratchpad/watch-backup/`).

---

## Review verdict on the pre-existing ISSUES.md

Reviewed the merged code against ISSUES.md #1–#5:
- **#1 (legacy weekday migration)** — was genuinely still broken → FIXED (item 2 above).
- **#2 (follow-up nags before first workout)** — already fixed in merged code
  (gated by `reminderActivationDate`). ISSUES.md is stale.
- **#3 (idle timer on appear)** — already fixed (`updateIdleTimer()` in `.onAppear`).
- **#4 (reminders enabled with zero days)** — already handled
  (`ensureDefaultReminderSelection()` + `selectedWeekdaysList` normalization).
- **#5 (timestamp drift)** — already resolved (marked in ISSUES.md).

`currentHeartRate` is correctly cleared in both `finishWorkout()` and `reset()`
(a concern I raised and then ruled out).

---

## KNOWN OPEN BUG — not yet fixed (needs the Watch target to exist)

**Watch `HKWorkoutSession` leaks on reset/abandon.**
`N4x4Watch Watch App/WatchTimerView.swift` stops the workout session only when
`state.workoutComplete` is true. If the user RESETS mid-session on the phone
(isRunning=false, workoutComplete=false), the Watch keeps its `HKWorkoutSession`
+ HR streaming alive indefinitely → battery drain. Also `WorkoutManager.stopWorkout()`
ends the session but never explicitly ends the builder.

Correct fix needs a new phone→Watch signal to distinguish *paused* (keep HR
running) from *reset/ended* (tear down). **Now UNBLOCKED** — the Watch target
compiles, so this can be implemented and device-tested. This is the next code
task after the user confirms basic device testing works. Ask the user before
implementing (they said to flag, not auto-fix).

---

## How to verify once the Watch build is green

1. Build **N4x4** scheme (iOS) — must still compile. ⌘U runs `N4x4Tests`.
   - Watch for `testWorkoutTypeIncludesOtherOption`: it asserts exactly **11**
     `WorkoutType` cases. If the count changed, that test (not app code) fails.
2. Build **N4x4Watch** scheme.
3. HR + zone feedback need PHYSICAL hardware (iPhone + Apple Watch Series 4+),
   never the Simulator. To verify end-to-end:
   - Start a workout; HR should appear on both devices within ~10 s.
   - During a work interval, ease right off for >70 s → expect one "push" wrist
     tap (+ spoken cue if Voice on), then silence for ~a minute.
   - Confirm NO alert fires in the first 60 s of any interval.
   - Toggle each channel (haptic/voice/visual) in Settings; confirm each works.

---

## Environment note (why CLI builds fail here)

This machine's Xcode wants the iOS **26.5** platform (only the 26.4 simulator
runtime is installed), so `xcodebuild` from the CLI can't enumerate a simulator
destination and refuses to fall back. All building/testing must be done in the
**Xcode GUI**, which uses the installed simulator SDK fine. `plutil -lint` and
`xcodebuild -list` still work for validating the project file.

---

## Reference docs (in `docs/`)

- `Watch App - Manual Xcode Steps.md` — the target-creation UI steps.
- `Watch App - HR Zone Feedback Handoff.md` — feature spec + the watchOS-10 and
  Info.plist corrections. Read both for Watch context.
- `AGENTS.md` — architecture rules (single ViewModel, notification identifier
  scheme, streak calc, reactive Watch broadcast). Follow it.
- `SESSION-HANDOFF.md` — the prior (pre-this-session) handoff.
