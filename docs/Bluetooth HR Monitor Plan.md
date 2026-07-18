# Bluetooth Heart Rate Monitor Support — Implementation Plan

> **Status (2026-07-18): Phases 1–3 implemented** (all code, UI, config, and
> unit tests; parser/aggregator tests run green on a Linux Swift toolchain).
> Phase 4 remains: build in Xcode, run the hardware matrix in §5 on a physical
> iPhone with a real strap, verify locked-phone background streaming, and
> update App Store metadata. CoreBluetooth does not run in the Simulator.
> Also verify on a 4.7" (SE-class) device that the onboarding heart-rate card
> fits with the scan list expanded (capped at 4 rows, but untested at that size).

Add support for standard Bluetooth LE heart rate monitors (chest straps, armbands)
as a second live heart-rate source alongside the Apple Watch, via Core Bluetooth.
Zero new dependencies — Core Bluetooth is an Apple framework, keeping the
"Apple frameworks only" rule intact.

**Why this is a natural fit:** every BLE heart rate monitor on the market
(Polar, Garmin, Wahoo, CooSpo, …) implements the Bluetooth SIG **Heart Rate
Service** (`0x180D`) with the **Heart Rate Measurement** characteristic
(`0x2A37`, notify). One implementation covers them all — there is no
per-vendor work. Chest straps are also *more* accurate than wrist optical
sensors during HIIT, which is exactly this app's use case.

---

## 1. What exists today (the seam we plug into)

Live HR already flows into one funnel on the phone:

```
Watch HKLiveWorkoutBuilder ─▶ WCSession ─▶ PhoneSessionManager (line 145)
                                            └▶ TimerViewModel.ingestStreamedHeartRate(bpm)   (line 2101)
                                                ├▶ currentHeartRate: Double?                  (line 708)
                                                └▶ ZoneFeedbackEngine (voice nudges)
```

- `Shared/ZoneFeedback.swift` — the zone/alert engine — is **pure and
  source-agnostic**. Zero changes needed.
- All HR display components (`PulsingHeart`, `HRZoneBar`, `WorkoutRing` in
  `HomeWorkoutRedesign.swift`) read `viewModel.currentHeartRate`. Zero changes
  needed for display to "just work".
- **Gaps this feature must address:**
  - No `HeartRateSource` abstraction — Watch assumptions leak into
    `shouldWarnMissingHeartRate` (`TimerViewModel.swift:766`, gated on
    `watchPaired`) and settings copy ("Requires a paired Apple Watch").
  - No staleness handling: if the Watch stops streaming, the last
    `currentHeartRate` is displayed forever. With two sources this becomes an
    arbitration bug, so we fix it properly (and Watch-only users benefit too).
  - No Bluetooth plist keys, no `bluetooth-central` background mode.

---

## 2. Architecture

### 2.1 New files (all iOS target only)

```
N4x4/Bluetooth/
├── HeartRateMeasurementParser.swift   Pure. Parses 0x2A37 payloads. Unit-tested.
├── HeartRateAggregator.swift          Pure. Source arbitration + staleness. Unit-tested.
├── BluetoothHeartRateManager.swift    CBCentralManager + CBPeripheralDelegate. The only
│                                      file that imports CoreBluetooth.
└── HeartRateMonitorViews.swift        Settings sheet, scanner list, onboarding step content.
```

### 2.2 `HeartRateMeasurementParser` (pure, ~60 lines)

Per the Bluetooth SIG spec for `0x2A37`:

- Flags byte (offset 0):
  - bit 0 — HR value format: 0 = `UInt8` at offset 1, 1 = `UInt16` little-endian at offsets 1–2.
  - bits 1–2 — sensor contact: `0b10` = contact supported but **not detected**,
    `0b11` = contact detected, `0b0x` = not supported (treat as detected).
  - bit 3 — energy expended present (skip 2 bytes if we ever read RR).
  - bit 4 — RR intervals present (ignore in v1; note for future HRV work).

Output: `struct HeartRateReading { let bpm: Int; let sensorContact: SensorContact }`.
Returns `nil` for malformed/empty payloads. Sanity clamp: accept 20–250 bpm only.

### 2.3 `HeartRateAggregator` (pure, ~70 lines)

The arbitration policy, kept out of the manager so it's trivially testable:

```swift
struct HeartRateAggregator {
    enum Source { case bluetooth, watch }
    // Returns the value to display after ingesting a sample.
    mutating func ingest(bpm: Double, from: Source, at now: Date) -> Double?
    // Called on every timer tick; returns nil when all sources have gone stale.
    mutating func currentValue(now: Date) -> Double?
}
```

**Policy (deliberately zero-config — no "source picker" setting):**
- A source is *live* if its last sample is < 10 s old (straps notify ~1 Hz;
  the Watch streams every few seconds — 10 s covers both with margin).
- When both are live, **Bluetooth wins** — a dedicated strap is the more
  accurate sensor and the user made an explicit choice by wearing it.
- When the preferred source goes stale, fall back to the other seamlessly.
- When both are stale, the value becomes `nil` → UI shows "—" instead of a
  frozen number. (This fixes the existing staleness gap for Watch-only users.)
- BLE samples with `sensorContact == .notDetected` are **not ingested** —
  a strap flapping loose must not fire "push harder" voice alerts.

### 2.4 `BluetoothHeartRateManager` (~300 lines)

`final class BluetoothHeartRateManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate`

Owned by `TimerViewModel` as a `let`, mirroring `phoneSessionManager`
(`TimerViewModel.swift:705`). Callbacks to the VM via two closures set at init
(`onReading: (HeartRateReading) -> Void`, avoids retain cycles / keeps the VM
as the single owner of state).

**Published state (drives all UI):**

```swift
enum MonitorState: Equatable {
    case bluetoothUnavailable   // unsupported / unauthorized / powered off (with reason)
    case idle                   // no remembered device, not scanning
    case scanning
    case connecting(name: String)
    case searching(name: String)   // remembered device, pending connection (strap not worn / out of range)
    case connected(name: String)
}
@Published private(set) var state: MonitorState
@Published private(set) var discovered: [DiscoveredMonitor]   // id, name, rssi
@Published private(set) var batteryPercent: Int?
@Published private(set) var latestReading: HeartRateReading?  // for live preview in settings/onboarding
```

**Key design decisions:**

1. **Lazy `CBCentralManager`** — the manager is only instantiated the first
   time the user taps "Connect a monitor" (or at launch if a device is already
   remembered, which implies permission was already granted). Instantiating
   `CBCentralManager` is what triggers the Bluetooth permission prompt; it must
   never fire at app launch for users who don't care about straps.

2. **Connection is independent of the workout lifecycle.** Once a device is
   remembered, we issue a *pending* `connect()` at app launch. Pending
   connections have no timeout and negligible battery cost; the strap only
   powers on when worn, at which point iOS completes the connection within
   seconds. Result: the user puts the strap on, opens the app, and their pulse
   is already beating on screen before they press Start. No connect latency at
   "Go", no coupling to `startTimer()`.

3. **Remembering a device**: persist `peripheral.identifier.uuidString` in
   `@AppStorage("bleMonitorPeripheralID")` (+ `bleMonitorName` for display
   while searching). Reconnect via
   `retrievePeripherals(withIdentifiers:)` → `connect()`. One remembered
   device at a time — "Forget" clears it. Switching = scan + tap a different
   device (implicitly forgets the old one).

4. **Reconnect rules:**
   - `didDisconnectPeripheral` (not user-initiated) → immediately re-issue
     `connect()` (pending). No retry loops or timers needed — iOS holds the
     pending connection.
   - `centralManagerDidUpdateState` → `.poweredOn`: re-retrieve + reconnect
     the remembered device. `.poweredOff`/`.unauthorized`: publish
     `bluetoothUnavailable`, drop the peripheral reference; the aggregator's
     staleness handles the display fallback automatically.
   - `didFailToConnect` → retry once after 2 s, then sit in `.searching`.

5. **Scan hygiene**: scan **only** with `withServices: [CBUUID(string: "180D")]`
   (never nil — filters the whole BLE neighborhood down to HR monitors and is
   required for background scanning later). Stop scanning on connect, on sheet
   dismiss, and after 30 s idle. Names from `peripheral.name` with
   `CBAdvertisementDataLocalNameKey` fallback, else "Heart Rate Monitor".

6. **On connect**: discover `180D` → subscribe (`setNotifyValue(true)`) to
   `2A37`. Also discover Battery Service `180F` → read `2A19` once for the
   battery badge (best-effort; many straps expose it, some don't).

7. **Not in v1** (documented, deliberate): CoreBluetooth state restoration
   (`CBCentralManagerOptionRestoreIdentifierKey`). The `bluetooth-central`
   background mode keeps notifications flowing while the phone is locked
   mid-workout, which is the actual user need. Relaunch-from-terminated
   restoration adds AppDelegate complexity for a marginal case; revisit if
   field reports demand it.

### 2.5 `TimerViewModel` integration (~60 lines changed)

- Generalize the funnel:

  ```swift
  func ingestHeartRate(_ bpm: Double, from source: HeartRateAggregator.Source) {
      currentHeartRate = aggregator.ingest(bpm: bpm, from: source, at: Date())
      if let hr = currentHeartRate { evaluateZoneVoiceFeedback(bpm: hr) }
  }
  ```

  `PhoneSessionManager` (line 147) calls it with `.watch`; the BLE manager's
  closure calls it with `.bluetooth`. Keep `ingestStreamedHeartRate` as a
  one-line deprecated shim or update the single call site — the latter.

- In `tick()`: `currentHeartRate = aggregator.currentValue(now:)` so stale
  values clear within a second of a source dying.

- `shouldWarnMissingHeartRate` (line 766) becomes source-aware:

  ```swift
  isRunning && (watchPaired || bleMonitorRemembered)
      && currentHeartRate == nil && workoutElapsedSeconds > 15
  ```

- Reset points (lines 1427, 1542, 2087): keep clearing `currentHeartRate`;
  also reset the aggregator. Do **not** disconnect the strap — the connection
  outlives workouts by design.

- New computed `heartRateSourceGlyph` for the small source indicator
  (see 3.4).

**Explicit non-goal:** the Watch keeps running its own haptic zone engine off
its own sensor. If a user wears both strap and Watch, phone voice/visual use
the strap while Watch haptics use wrist HR — the values converge and the
shared `ZoneFeedbackEngine` rules are identical, so no user-visible
inconsistency. Mirroring strap HR to the Watch is a future nicety, not v1.

### 2.6 Project configuration

In `project.pbxproj` (both Debug/Release of the iOS target, matching the
existing `INFOPLIST_KEY_` pattern):

- `INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription = "N4x4 connects to Bluetooth heart rate monitors like chest straps to show your live heart rate and coach you into your target zone."`

In `N4x4/Info.plist` (currently an empty dict — arrays don't fit the
`INFOPLIST_KEY_` mechanism well):

```xml
<key>UIBackgroundModes</key>
<array><string>bluetooth-central</string></array>
```

This keeps HR notifications (and therefore voice zone coaching) flowing when
the phone locks during a 4-minute interval. No entitlement changes needed.

---

## 3. User experience

### 3.1 Guiding principles

- **The permission prompt never ambushes anyone.** `CBCentralManager` is
  created only after an explicit "Connect" tap. Skippers never see a
  Bluetooth dialog.
- **Zero configuration after pairing.** No source picker, no "reconnect"
  button in the happy path. Wear the strap → it connects → BLE wins → Watch
  fills gaps. The only management verbs are *Connect*, *Switch*, *Forget*.
- **The reward is immediate and visceral**: the moment a device connects, the
  user sees the existing `PulsingHeart` beating at *their actual pulse*.
  Every entry point (onboarding, settings, troubleshooting) ends on that
  moment.

### 3.2 One reusable pairing component

`MonitorPairingView` — a single component embedded in all three entry points
(onboarding step, settings sheet, workout troubleshooting), so the flow is
learned once and maintained once. Dark `Palette` styling to match the
redesigned UI. States map 1:1 to `MonitorState`:

1. **Intro** — heart icon, one line: "Chest straps and armbands with
   Bluetooth work with N4x4." Primary button: **Connect a monitor** (this tap
   creates the central manager → permission prompt → scan).
2. **Scanning** — `PulsingHeart` (slow idle pulse) + "Looking for monitors
   nearby… Make sure yours is worn — most only wake up on skin contact."
   Devices appear in a list as discovered (name + signal dots), tap to connect.
   The skin-contact hint is the single highest-value line of copy in this
   feature; it preempts the #1 support question.
3. **Connecting** — brief spinner state on the tapped row.
4. **Connected** — success card: device name, **live BPM with `PulsingHeart`
   beating at the real rate**, battery badge if available. Primary button
   continues (onboarding) or dismisses (settings).
5. **Unavailable** — Bluetooth off → "Turn on Bluetooth in Control Center";
   denied → deep link to the app's Settings page
   (`UIApplication.openSettingsURLString`). Plain words, one action each.

### 3.3 Onboarding (first-time users)

Insert **one** new step into `OnboardingFlowViewModel.Step`
(`ContentView.swift:5-16`): `heartRate`, placed **after `.health`, before
`.launch`** — it joins the existing permission cluster (notifications →
health → heart-rate source) rather than interrupting the goal-setting
narrative, and it's the natural last question: "how will we see your effort?"

Step content (title: **"See your heart rate live"**):

- One promise line: "N4x4 coaches you into the right zone — it needs a live
  heart rate to do that."
- Two option cards:
  - **Apple Watch** — "Just wear it. Nothing to set up." Shown with a
    checkmark when `watchPaired` — most Watch users tap Continue and move on.
  - **Bluetooth monitor** — "Chest strap or armband." Tapping expands the
    embedded `MonitorPairingView` inline (no sheet-on-cover stacking).
- Secondary button: **Set up later** — footer: "You can connect one anytime
  in Settings." The step is skippable like every step after welcome; the
  existing `OnboardingPrimaryButtonStyle`/`SecondaryButtonStyle` are reused.

No new upsell banner for existing users — the Settings row plus the
troubleshooting path (3.5) cover later discovery without nagging.

### 3.4 During a workout

- HR display: unchanged components; `currentHeartRate == nil` now renders "—"
  (it already renders conditionally, so this is mostly free).
- Add a subtle source glyph next to the BPM readout: `applewatch` or a small
  Bluetooth heart icon (`Palette.textTertiary`, caption size). Silent
  reassurance about where the number comes from — no text, no state to manage.

### 3.5 Settings & troubleshooting

New section in `SettingsView` directly below "Apple Watch" (line 123),
mirroring its row pattern exactly:

- **"Heart Rate Monitor"** section, one row:
  - Nothing remembered → heart icon + "Connect a monitor…" → sheet with
    `MonitorPairingView`.
  - Remembered → status dot (green connected / orange searching / gray BT off)
    + device name + battery % + chevron → management sheet: live status card
    (name, live BPM preview, battery), **Switch monitor** (scan list), and
    **Forget This Monitor** (red).
- Copy updates:
  - Zone-alerts footer (line 166): "Requires a paired Apple Watch streaming
    heart rate" → "Requires live heart rate from an Apple Watch or a
    Bluetooth heart rate monitor."
  - Apple Watch section footnote (line 146): drop "The iPhone has no
    heart-rate sensor of its own" or amend to mention Bluetooth monitors.
- `WatchTroubleshootingView` (`WatchSetupViews.swift:13`) — the sheet behind
  the in-workout "no heart rate" warning — gains a final row for every
  non-connected state: "Have a Bluetooth chest strap? Connect it instead."
  → `MonitorPairingView`. This is the highest-intent entry point in the app:
  the user is mid-workout actively wanting HR.

---

## 4. Reliability rules (the "boring correctness" list)

| Scenario | Behavior |
|---|---|
| Strap taken off mid-workout | Sensor-contact bit stops ingestion → aggregator stale in 10 s → falls back to Watch or "—"; no frozen number, no false "push harder" |
| Bluetooth toggled off mid-workout | `bluetoothUnavailable` published; display falls back via staleness; on re-enable, auto-reconnect with no user action |
| Walk out of range, come back | `didDisconnect` → pending reconnect → resumes silently |
| Strap battery dies | Same as out-of-range; battery badge gave advance warning |
| Both Watch + strap live | Strap wins (accuracy); Watch haptics keep using wrist HR (values converge) |
| Phone locked during interval | `bluetooth-central` background mode keeps notifications + voice coaching alive |
| Two straps at the gym | Scan lists all; user picks by name; only the remembered ID auto-reconnects |
| Malformed / zero / absurd packets | Parser returns nil or clamps to 20–250; never displayed, never fed to the zone engine |
| Permission denied then regretted | Unavailable state deep-links to system Settings |
| App relaunch | Remembered ID → lazy manager init → pending connect; no prompt, no spinner |

---

## 5. Testing

**Unit tests (new, in N4x4Tests — pure logic, no CoreBluetooth):**
- `HeartRateMeasurementParserTests` — flag matrix: uint8/uint16 values,
  contact detected/undetected/unsupported, energy-expended offset handling,
  empty/short payloads, clamp boundaries (19, 20, 250, 251).
- `HeartRateAggregatorTests` — BLE-beats-Watch when both live; fallback on
  staleness in both directions; both-stale → nil; contact-lost sample rejected.

**Simulator development:** CoreBluetooth does not function in the iOS
Simulator. Add a `#if DEBUG` `SimulatedHeartRateMonitor` behind the same
closure interface (sine-wave 95–175 bpm) toggled by a hidden gesture or launch
argument, so all UI states are buildable and screenshot-able without hardware.

**Hardware matrix (manual, physical iPhone):** one session each with a
Polar H10, Wahoo TICKR, and a budget CooSpo strap (three firmware
personalities cover the field), running the scenario table in §4 — plus the
existing Watch regression checklist from
`docs/Watch App - HR Zone Feedback Handoff.md` to confirm nothing regressed
for Watch-only users.

---

## 6. Delivery phases

**Phase 1 — Plumbing (no UI).** Parser, aggregator, manager, plist keys,
`TimerViewModel` funnel generalization + tick-based staleness, unit tests
green. Verify on hardware with a debug auto-connect. *Watch-only behavior
must be bit-identical after this phase (except stale values now clearing —
a fix).*

**Phase 2 — Settings.** `MonitorPairingView`, settings section + management
sheet, copy updates, simulated monitor for DEBUG. This alone ships the
feature for anyone who looks in Settings.

**Phase 3 — Onboarding + contextual entry.** New `.heartRate` step,
troubleshooting-sheet path, source glyph, `shouldWarnMissingHeartRate` update.

**Phase 4 — Hardening + release.** Hardware matrix, locked-phone background
run, App Store metadata (what's-new + description gain "works with Bluetooth
chest straps"), update `AGENTS.md`/`memory/MEMORY.md` with the new
architecture facts.

Rough size: ~500 lines of new non-UI code + tests, ~450 lines of UI, ~80
lines modified in existing files. Each phase is independently shippable.

## 7. Out of scope (recorded so they're decisions, not omissions)

- RR-interval capture for HRV (parser flag already identified; ignore in v1).
- Mirroring strap HR to the Watch for haptics.
- Multiple simultaneous monitors / sensor fusion.
- ANT+ (needs MFi hardware bridge; BLE covers virtually all modern straps).
- CoreBluetooth state restoration (see §2.4 item 7).
- Writing strap HR samples to HealthKit (Watch workouts already save HR;
  phone-only strap workouts could add this later via `HKQuantitySeries`).
