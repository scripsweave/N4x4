# N4x4 — Session Handoff

_Last updated 2026-07-22._ Covers the default-workout/Kettlebells/haptics work,
the settings redesign (iOS Settings style), AirPods Pro 3 live heart rate
(iOS 26), and the 4.7 marketing pass. Supersedes
[`SESSION-HANDOFF-2026-07-20.md`](SESSION-HANDOFF-2026-07-20.md) for current state.

Everything here is committed and pushed to **`main`** (remote `origin`).
Current marketing version: **4.7** (4.6 was bumped and superseded same-day,
never uploaded).

---

## TL;DR

- **Five commits landed:** `464ad20` (default workout, Kettlebells, haptics
  rework) → `53d6c9c` (settings redesign plan) → `d8d94ff` (settings redesign
  implemented, Tips → Home, 4.6) → `07db4a0` (AirPods Pro 3 live HR, source
  priority, 4.7) → `5c65279` (marketing: new screenshot, iPhone frames, copy).
- **Developed on a Linux box with no Xcode.** Everything parse-checks
  (`swiftc -parse`, Swift 6.1 Linux toolchain) and the pure logic ran green in
  SPM harnesses (32 HR-logic tests + 6 model-compat tests against the exact
  repo files). **Nothing has been built with Xcode yet — that is the first
  thing to do on a Mac** (see checklist).
- **AirPods HR requires the Xcode 26 SDK** to compile
  (`PhoneWorkoutSessionManager.swift` uses iPhone `HKWorkoutSession`, iOS 26+).

## What shipped (newest first)

### Marketing 4.7 (`5c65279`)
- New App Store card `06-heart-rate.png` "Any heart rate monitor" (Watch Ultra
  with live face, Garmin FR965, AirPods Pro 3). Generator:
  `AppStore/make-hr-sources-screenshot.html`. Device-image provenance and the
  Garmin licensing note are in `AppStore/README.md`.
- **All phone cards re-framed as iPhone 16 Pro** (titanium rim, bezel, island,
  side buttons) — old thin outline read as Android. CSS frame in
  `make-summary-screenshot.html`; `make-iphone-frame.py` paints the full-body
  variant onto the composed cards 01/02/04. Website `.device img` got the same
  look. `assets/watch-ultra-framed.png` screen corners were rounded (they poked
  out square).
- 05-summary regenerated with the new frame **and 4.6 layout parity** (Workout
  Type at top). Copy: `docs/app-store-description-2026-07-22.md` is paste-ready
  (recommended screenshot order puts 06 second); `whats_new.txt` matches.

### AirPods Pro 3 live HR + source priority, v4.7 (`07db4a0`)
- `PhoneWorkoutSessionManager.swift` (@available iOS 26): iPhone
  `HKWorkoutSession` → live HR from system-paired sensors (AirPods Pro 3).
  Session ends WITHOUT saving (builder discarded, mirrors the watch manager) —
  `saveCompletedWorkoutToHealthKit()` stays the single workout record.
- `HeartRateAggregator` now arbitrates by a configurable priority
  (default monitor > Watch > AirPods; stored raw in `hrSourcePriorityRaw`,
  defensive parse). New source `.appleSensor` ("airpods").
- Settings → Devices & Health → **Heart Rate Sources**: AirPods toggle
  (iOS 26-gated, `appleSensorHREnabled`) + drag-to-reorder priority list.
  Onboarding heart-rate step gained an AirPods opt-in row.
- AirPods do NOT broadcast standard Bluetooth HR (Powerbeats Pro 2 do, and
  already work via the BLE manager).

### Settings redesign, Tips → Home, v4.6 (`d8d94ff`)
- `SettingsView.swift` = searchable iOS-style top level (icon tiles + value
  previews, most-used pinned first); all detail pages in
  `N4x4/SettingsSubpages.swift`. Local `@AppStorage` mirrors on views drive
  refresh; writes with side effects go through the view model.
- **Reminders split into three family toggles** (night-before / morning-of /
  comeback nudges) gating the existing scheduler families. Invariant:
  `workoutRemindersEnabled == any family on` — kept by a one-time migration
  (`reminderFamilyFlagsSynced`), `raiseFamilyFlagsIfAllOff()` in the master's
  didSet, and reset alignment. See AGENTS.md.
- Training Tips moved to the Home header (bolt-heart TIPS button).

### Default workout, Kettlebells, haptics (`464ad20`)
- "Norwegian 4x4" is the protocol, not a workout type: hidden from all pickers
  via `WorkoutType.selectableCases` (enum case retained so old logs decode).
- Default workout type setting (`defaultWorkoutTypeRaw`) pre-selects the
  post-workout Type; syncs with `preferredModality` both ways.
- Kettlebells = full modality (onboarding, guidance text, reps metric).
- Haptics rework: independent channel from audio mode, on phone AND watch.
  Countdown = two taps at T-3s/T-2s + long CoreHaptics buzz at the transition;
  end of final interval = taps only (completion buzz removed). Watch mirrors
  via `intervalHapticsEnabled` in the WCSession payload.
  **Interpretation of Jan's spec awaiting his on-device confirmation** (see
  auto-memory `haptics-spec-interpretation`).

## First-run checklist on a Mac (nothing verified on-device yet)

1. **Build all targets with Xcode 26** — new files `SettingsSubpages.swift` and
   `PhoneWorkoutSessionManager.swift` were added to `project.pbxproj` by hand
   (synthetic UUIDs `5E52…C1–C4`); Xcode will complain immediately if a
   reference is wrong.
2. **Run the full XCTest suite** (new tests: reminder-family derivation +
   migration, summaries, selectable workout types, default workout, aggregator
   priority).
3. **AirPods Pro 3 on-device:** HR flows during a workout (badge shows
   AirPods), exactly ONE workout in Apple Health afterwards, and check whether
   background streaming with the phone locked needs a capability checkbox
   (unresolved — see auto-memory `airpods-hr-device-verification`).
4. **Feel the haptic countdown** (interpretation call: taps-only at the end).
5. **Settings UI sanity:** drag-to-reorder in Heart Rate Sources renders
   handles (`.environment(\.editMode, .constant(.active))` inside a Form).
6. **Check App Store Connect for stray Xcode Cloud builds.** Per AGENTS.md,
   every push to `main` attempts a build+delivery — today pushed three times
   (4.6 at `d8d94ff`, then 4.7 twice). If Cloud delivered a 4.6 build, ignore
   it; ship 4.7. This is exactly the argument for the tag-based trigger
   recommended in AGENTS.md (still not done).
7. **Release:** upload via Xcode Cloud as before; screenshots + paste-ready
   copy in `docs/app-store-description-2026-07-22.md` (upload order there).

## Regenerating marketing assets (now possible on Linux too)

Headless Chrome renders the HTML cards; Pillow (venv) does the reframing and
resizes — see `AppStore/README.md` for the exact commands. The screenshot
family rule stands: mockups must visually match the real UI
(`make-summary-screenshot.html` ↔ `PostWorkoutSummaryRedesignView`,
watch face ↔ `WatchTimerView`).
