# N4x4 — Session Handoff

_Last updated 2026-07-20._ Covers the real-time heart-rate release (Apple Watch
+ Garmin + WHOOP + Bluetooth straps), the reimagined post-workout experience,
the marketing rewrite, and the release/versioning setup. Supersedes
[`SESSION-HANDOFF-2026-07-10.md`](SESSION-HANDOFF-2026-07-10.md) for current state.

Everything here is committed and pushed to **`main`** (remote `origin`).
Current marketing version: **4.5** (see "Releasing" below for why it climbed).

---

## TL;DR

- **Big feature arc landed this cycle:** the Bluetooth HR work (Garmin/WHOOP/
  straps) was extended, live heart rate is now zone-colour-coded on iPhone and
  Watch, voice prompts survive a locked phone, and the post-workout experience
  was rebuilt around per-interval charts + notes + history.
- **iOS app + watch app + Live Activity build clean, zero warnings** (generic
  iOS Simulator destination, `CODE_SIGNING_ALLOWED=NO`).
- **Unit tests could not run locally:** this Mac's CoreSimulator is a version
  behind Xcode 26.6, so no simulator boots. The new pure logic
  (`HeartRateSeries*`) was verified by executing 14 assertions directly on the
  macOS Swift toolchain; the XCTest additions compile but need a working
  simulator (or CI) to run.
- **Marketing rewritten** (App Store copy + website) from a feature list to an
  outcome/feeling frame, with the science claims tempered to defensible
  association language and cited. All flagged credibility leaks fixed.
- **Releases go through Xcode Cloud, triggered from GitHub** — read "Releasing".

---

## What shipped this session (newest first)

Commits `35f2c52` → `fcacc82` on `main`.

### Real-time heart rate + coaching
- **Bluetooth HR monitors** (`N4x4/Bluetooth/`): the pairing scan now also
  surfaces devices the system already holds a connection to
  (`retrieveConnectedPeripherals`, badged "Paired to iPhone"), and detects
  paired-but-not-broadcasting Garmin/WHOOP via their proprietary GATT service
  UUIDs so they appear by name with a hint instead of an empty list.
- **Honest connection state:** a device that connects but sends no reading (a
  Garmin with Broadcast Heart Rate off, or a notify-subscribe refusal) now
  shows "Available, not connected" + a prominent **Help Me Connect** button
  after a 12 s grace period, instead of a false "Connected" + eternal spinner.
  Driven by `BluetoothHeartRateManager.notifySubscribeFailed`.
- **Device guide** (`HeartRateMonitorViews.swift`, `HeartRateDeviceGuideView`):
  per-model broadcast steps verified against Garmin owner's manuals and WHOOP
  sources. Garmin split into families (Forerunner / fēnix-epix-Instinct /
  Venu-vívoactive / fēnix 6 + FR 245/945 / older ANT+-only). Note: FR 245/945
  broadcast HR over ANT+ only from the standard menu; BLE needs Virtual Run.
  Older models (fēnix 3/5, FR 235, Venu 1, vívoactive 3/4, vívosmart) are
  ANT+-only and can never reach an iPhone.
- **Zone-coded heart rate** (`Shared/ZoneFeedbackStyle.swift`
  `HRZoneStatus.tint`): the live BPM number turns **orange when below** the
  target zone and **red when above**, green in zone — on the phone
  (`HomeWorkoutRedesign.swift`) and the watch (`WatchTimerView.swift`). The
  colour is instant; the spoken/haptic nudges remain debounced. Website watch
  mockup kept in sync (parity rule).
- **Update announcement** (`HeartRateSourcesAnnouncementView`): one-time sheet
  for upgraders about Apple Watch / Garmin / WHOOP support, "Dismiss" /
  "Show me how" → device guide. Existing-users-only, never over a workout.

### Locked-phone voice prompts
- `Info.plist` `UIBackgroundModes` gained `audio`. `SpeechManager` runs a
  zero-volume silent-loop keepalive during a workout (generated in memory,
  `.mixWithOthers`) so iOS never suspends the app mid-session; prompts fire on
  time with the screen locked and music ducked. Interruption observer resumes
  after calls/Siri. Lifecycle wired in `TimerViewModel` (start/pause/finish/reset).

### Reimagined post-workout experience
- **Fine-grained HR recording** (`N4x4/HeartRateSeries.swift`): a
  `HeartRateSeriesRecorder` samples the accepted BPM at 2 s buckets plus the
  interval timeline as it actually unfolded; sealed on finish into a
  `HeartRateSeries` saved one-JSON-file-per-workout under Application Support
  (`HeartRateSeriesStore`, keyed by log-entry UUID). Only a small
  `HRSessionSummary` (avg/max, work in-zone %, 40-pt sparkline) lives inline on
  `WorkoutLogEntry`, so history rows never touch the filesystem.
- **New summary + history UI** (`N4x4/SessionDetailViews.swift`): full-session
  strip chart with per-interval target bands and a zone-coloured HR line;
  swipeable interval cards with in-zone ring, avg/peak, time-to-zone, a dashed
  **ghost** overlay of the previous same-modality session, and per-interval
  performance value + free-text note (`IntervalPerformance.note`). Shareable
  session card via `ImageRenderer` + `ShareLink`. `PostWorkoutSummaryRedesignView`
  replaced the old Form; `SessionDetailSheet` gives the same read-only view from
  History ("View full session").

### Settings & feedback
- **Submit Feedback** row near the top of Settings → `mailto:feedback@n4x4.app`
  subject "N4x4 Feedback", body prefilled with app/OS/device (built from
  `URLComponents` + `utsname`).
- **App Store rating prompt** (`TimerViewModel.maybeRequestAppReview`):
  `AppStore.requestReview(in:)` after the 3rd saved workout, once
  (`hasRequestedAppReview`), skipped during a milestone celebration.

### Default protocol change
- **Default cooldown 5 → 3 min**, so a default session is exactly **33 minutes**
  (5 warmup + 4×4 work + 3×3 recovery + 3 cooldown). This makes the long-standing
  "33 minutes" brand claim true. Affects new installs only; existing users keep
  their stored `cooldownDuration`.

---

## Marketing (copy only, not app code)

- **App Store copy:** `docs/app-store-description-2026-07-19.md` is the
  paste-source (subtitle, promotional text, description, What's New, screenshot
  captions). Rewritten job-first; science tempered + cited; all blocks verified
  within App Store Connect limits. Upload screenshots in the caption doc's
  recommended order (zones → watch → summary → history → home) from the
  **`6.7in/`** folder (1284×2778 — the slot the listing uses).
- **Website** (`website/index.html` + new `website/privacy.html`): product-led
  hero, reordered so product precedes the deep science, new "Bring your own
  sensor" supported-devices section, fixed the broken Privacy Policy link,
  tempered mortality/"once a week is all it takes" absolutes into association
  language with study links, fixed the self-contradicting watch face (172 at
  top of zone + "Speed Up" → 148 below zone), and dropped aggressive-influencer
  tone.
- **App Store assets** regenerated for consistency: `05-summary` card (33:00),
  and all watch assets (5 watch-slot sizes via `AppStore/make-watch-screen.html`,
  framed `03-watch` via `AppStore/make-watch-face.html` composited into the
  frame). See `AppStore/README.md`.

---

## Build / verify

- iOS build (all targets): `xcodebuild -project N4x4.xcodeproj -scheme N4x4
  -destination 'generic/platform=iOS Simulator' -configuration Debug build
  CODE_SIGNING_ALLOWED=NO` → **BUILD SUCCEEDED, 0 warnings.** (Only the benign
  "No AppIntents.framework dependency found" note remains.)
- **Tests can't run here:** CoreSimulator (1051.54.0) is older than Xcode 26.6
  expects (1051.55.0), so no simulator boots. Run Software Update, then
  `xcodebuild test` works again. The `HeartRateSeries` logic was executed green
  on the plain toolchain (14 assertions).

---

## Releasing (READ THIS — it caused version churn this session)

**Xcode Cloud builds and delivers to App Store Connect on every push to the
GitHub branch it watches (`main`).** There is no `ci_scripts/` in the repo; the
trigger is configured in App Store Connect. Consequences:

- Every commit pushed to `main` triggers a build + App Store delivery.
- Once a version reaches App Store Connect and is submitted/approved, its
  "train" closes; the next upload at the **same** `MARKETING_VERSION` is
  rejected (ITMS-90186 / ITMS-90062). This burned 4.2 → 4.3 → 4.4 → 4.5.
- **Apple compares version components numerically:** `4.21` reads as
  "four-twenty-one" and is HIGHER than `4.9`. Avoid leading zeros; the next
  version after 4.5 should be `4.6`, not `4.10`-style surprises.

**Recommended (not yet done):** change the Xcode Cloud workflow Start Condition
from "Branch Changes on main" to **"Tag Changes" `v*`**, so only an intentional
`git tag v4.6 && git push origin v4.6` ships. Until then, only bump
`MARKETING_VERSION` (all 6 shipping configs in `project.pbxproj` — app, watch,
Live Activity × Debug/Release) when you actually intend to release, and expect
every push to `main` to attempt a delivery.

---

## Known follow-ups

1. **Update CoreSimulator** (Software Update) so the unit suite and on-device/
   simulator verification work again.
2. **Real device pass** still owed on: locked-phone voice prompts with music;
   Garmin broadcast + the "Available, not connected" → Help Me Connect flow;
   the zone colour flipping on phone + watch; the post-workout charts against a
   real recorded session; feedback mail prefill.
3. **Screenshots are still mockup-built**, now consistent and honest; a real
   capture once the simulator works would be beyond reproach.
4. **Hero headline** changed from "More life." to "Exactly hard enough." — the
   single most visible brand change; confirm it sits right or revert.
5. **Xcode Cloud trigger** → move to tag-based (above).
6. **Confirm `feedback@n4x4.app` receives mail** before release; it's baked into
   the binary.
