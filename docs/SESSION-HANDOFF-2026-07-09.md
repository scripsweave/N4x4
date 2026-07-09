# N4x4 — Session Handoff

_Last updated 2026-07-09._ Covers the marketing-website rework, the Apple Watch
UI/advertising alignment, and two on-device bug fixes. Read top to bottom.

Everything described here **is committed and pushed** to
`feature/home-workout-redesign` (remote `origin`, HEAD `37255b6`). The branch is
**25 commits ahead of `main`** and has **not** been merged or PR'd yet.

---

## TL;DR — where we are

- **Website (`website-v2/`)** reworked to the app's dark/charcoal aesthetic with
  amber/blue/green accents, real device screenshots, a two-column hero, and a
  dedicated Apple Watch section. ✅ Rendered and verified across desktop/mobile.
- **Apple Watch on the website** now uses a **real Apple Watch Ultra frame** (the
  user-supplied render, keyed to a transparent-screen PNG) with the live N4x4
  face composited into the screen. Placed beside the phone with a gap, not
  tilted. ✅
- **Real watchOS app UI** (`WatchTimerView.swift`) was restyled to **match the
  advertised design** (two-line header, big BPM ring, SPEED UP/SLOW DOWN cue,
  TARGET range) and keeps pause/skip. ✅ Builds clean for watchOS 26.5.
- **App Store watch screenshot** (`~/Desktop/n4x4-appstore/03-watch.png`)
  rebuilt around the same Ultra frame. ✅ Exactly 1290×2796.
- **Two on-device fixes:** the phone Home START ring no longer overlaps the
  interval timeline (and the "N4x4" title was removed); the watch ring no longer
  clips on small watches (40 mm Series 4). ✅
- **History calendar bug** (first days of month not rendering) fixed earlier in
  the branch. ✅

### → Likely next actions
1. Decide whether to **open a PR / merge `feature/home-workout-redesign` → `main`**
   (25 commits; not yet requested).
2. **Device-verify the two fixes on real hardware** (see "Not verified live").
3. Optionally **commit the App Store PNGs into the repo** — they currently live
   only on the Desktop (see "App Store deliverables").

---

## What changed this session (by area)

### 1. Website — `website-v2/`
- `index.html`, `styles.css`: full visual rework to match the app. New sections:
  two-column hero (statement left, phone + watch right), "See it in action"
  screenshot showcase, dedicated **Apple Watch** section, plus the existing
  science/protocol/trust/equipment/CTA sections retuned to the palette.
- Palette retuned in `:root`: charcoal surfaces, `--amber #FF9400`,
  `--blue #2E85FF`, `--green #33C78C`. Most rules key off `--amber`/`--orange`.
- Device screenshots added: `images/screen-home.png`, `screen-workout.png`,
  `screen-history.png` (copied from app captures).
- **Hero is two-column at ≥1000 px**, single-column centered below that, and the
  text column width is bounded so it can't overflow narrow screens
  (`html,body { overflow-x:hidden }` guard in place).

### 2. Apple Watch frame on the website
- Source: `~/Library/Mobile Documents/.../Downloads/AW Ultra.png` (447×636). It is
  a **flattened preview** — no real alpha; the screen + background were a baked
  light checkerboard.
- I **keyed it** into a real transparent-screen PNG:
  `website-v2/images/watch-ultra-frame.png`. Technique: flood-fill light-neutral
  pixels (min channel ≥ 216) from the four corners **and** the centre, then 2-px
  dilate into the anti-aliased fringe; make those regions transparent, keep the
  titanium/band opaque. Titanium highlights aren't connected to those regions so
  they aren't punched out.
- **Screen cutout geometry (measured):** left 12.1 %, top 21.7 %, width 70.0 %,
  height 59.3 % of the frame image (offset left because the crown is on the right).
  In CSS the `.watch-face` sits at `left:11.3%; top:20.9%; width:71.5%; height:61%`
  (slightly larger than the hole; the excess hides behind the opaque bezel).
- Structure: `.watch-device` → `.watch-face` (black, z-index 1, holds the face
  SVG) **behind** `.watch-frame` (the PNG, z-index 2). The transparent screen
  reveals the face; the bezel frames it.

### 3. Real watchOS UI — `N4x4Watch Watch App/WatchTimerView.swift`
- Restyled to the advertised layout: header (phase name + `INTERVAL n / N · m:ss`),
  progress ring with big BPM + `BPM`, `▲ SPEED UP`/`▼ SLOW DOWN`/`✓ IN ZONE` cue,
  `TARGET lo–hi`, plus pause/skip. Countdown kept in the header.
- Wrapped in a `ScrollView` so dense content never clips on small models.
- **Ring scales to screen width:** `WKInterfaceDevice.current().screenBounds.width
  * 0.60` capped at 132 pt (was a fixed 124 pt that clipped on 40 mm).
- Target bounds come from `WatchTimerState.hrLow`/`hrHigh` (0 ⇒ no target line).

### 4. Phone Home — `N4x4/HomeWorkoutRedesign.swift`
- Removed the `-78` pull-up that dragged the interval timeline across the START
  ring's bottom stroke; timeline now sits below the ring (bottom-anchored layout
  pushes the ring up). Removed the "N4x4" title.

### 5. App Store screenshots — `~/Desktop/n4x4-appstore/` (NOT in repo)
- `03-watch.png` rebuilt: framed Ultra watch + live face on the family's
  dark + amber-glow background with the "Your Apple Watch, your coach" caption.
  Regeneration script: `<scratchpad>/make_watch_as.py` (transient; renders the
  framed watch via headless Chrome to a transparent PNG, then composites with PIL).
- `01-home.png`, `02-zones.png`, `04-history.png` unchanged.

---

## Design invariant to preserve

**The website watch mockup and the real watch UI must stay identical.** If you
restyle one, restyle the other in the same change:
- Real app: `N4x4Watch Watch App/WatchTimerView.swift`
- Website: the `.watch-face` SVG in `website-v2/index.html` (appears twice — hero
  and Watch section)

Shared face content: header `HIGH INTENSITY` + `INTERVAL 3 / 4 · 4:00`, ring
around `172` / `BPM`, `▲ SPEED UP`, `TARGET 158–172`.

---

## Build / verify notes

- **Watch build:** `xcodebuild build -scheme "N4x4Watch Watch App" -destination
  'id=<watch-sim-id>' ENABLE_DEBUG_DYLIB=NO`. Builds clean for watchOS 26.5.
- **iOS build:** `-scheme N4x4 -destination 'id=<iphone-sim-id>'
  ENABLE_DEBUG_DYLIB=NO` (the `ENABLE_DEBUG_DYLIB=NO` flag avoids the blank-screen
  debug-dylib issue under `simctl launch`).
- **Website preview:** headless Chrome caches `styles.css` between runs — inline
  the CSS into a temp HTML when screenshotting, or you'll see stale styles. The
  headless window also clamps to ~500 px minimum width, so a "390 px" capture
  shows the left 390 px of a 500 px layout (looks clipped but isn't).

## Not verified live (do on real hardware)

- **Watch running-state UI** (172 BPM / SPEED UP / TARGET): the watchOS simulator
  shows a HealthKit permission modal that `simctl` can't dismiss, and the running
  state (HR, zone) is streamed from the paired phone, absent in a watch-only sim.
  Verified by compile + parity with the website mockup. Confirm on the Series 4.
- **Phone Home VO₂-data layout:** verified the no-data layout on the Pro Max sim;
  the data layout (VO₂ card present) was reasoned about, not captured (needs
  HealthKit VO₂ data in the sim).

## App Store deliverables

`~/Desktop/n4x4-appstore/{01-home,02-zones,03-watch,04-history}.png`, all exactly
1290×2796 (6.9"). These are **not** version-controlled. The repo's `AppStore/`
folder only holds an unrelated February screenshot. Decide whether to commit them.

## Housekeeping

- Untracked repo `memory/` folder (project notes) was intentionally left
  uncommitted — it predates this session and may be local-only.
- Redesign still lives behind the `useRedesignedUI` flag in the app (single-file
  `HomeWorkoutRedesign.swift`), rollback-safe.
