# Larger workout target heart-rate range — 5.4

Addresses RWaltonMouw's review asking for easier-to-read target BPM numbers
on the phone. The 5.2 live-reading enlargement left the target in caption text.

## Changes

- `HRZoneBar` now uses bold rounded title text for the target range: 28 pt in
  portrait and 34 pt in landscape at the default text size, previously 12 pt.
  The range uses the primary text colour and the unit moves into `TARGET BPM`.
- Native text styles follow Dynamic Type. The horizontal layout requires the
  guidance's natural width, falling back to a stack when needed instead of
  squeezing the target. Coaching appears below the target.
- VoiceOver exposes the range as one element: “Target heart rate”, with the
  bounds and “beats per minute” as its value.
- Follow-up: compact portrait previously hid the entire heart-rate heading.
  The card now always shows `CURRENT HEART RATE` and the same pulsing heart
  icon as landscape (an outline heart without a reading). Only the optional
  source label and zone labels are hidden in compact mode. The existing
  pulsing-heart component respects Reduce Motion. Accessibility text sizes
  place the source below the heading so it cannot squeeze the heading.
- Landscape gives the HR panel more width (timer column 34%, formerly 38%;
  column spacing 20 pt, formerly 24; HR row spacing 8 pt, formerly 16). The
  initial SE check caught the stacked panel pushing Pause below the visible
  area; this adjustment keeps the large live reading and target side by side
  at the default text size.
- Work/recovery target calculations and instant zone colours are unchanged.
- Version 5.4 is set in all six shipping configurations (phone, Watch and
  Live Activity, Debug/Release). Xcode Cloud supplies the delivery build number.
- Portrait countdown follow-up: the ring diameter grows by 10%, capped at
  330 pt and the available width. Its countdown and phase text already scale
  with the diameter, so both grow proportionally. Landscape is unchanged.

## Verification

- Release 5.4: unsigned generic-iOS Release build passed, including embedded
  Watch and Live Activity. All three built Info.plists report 5.4.
  Build log: `/tmp/N4x4-5.4-release.log`.
- Final portrait ring enlargement: Xcode build and the SE rotation/paused
  timer UI test passed (`/tmp/N4x4-portrait-ring.xcresult`). Screenshot review
  confirms the larger ring and text, heart icon/heading, full target range,
  and both controls fit in portrait. Preview:
  `/tmp/N4x4-larger-portrait-ring.png`. The interactive demo was updated.
- Heading/icon follow-up: simulator build and the live-HR rotation/paused
  timer test passed on SE 3. Result:
  `/tmp/N4x4-current-hr-layout-verified.xcresult`. Largest-text and no-monitor
  tests passed before the source label was moved below the heading at
  accessibility sizes. A combined test run exposed existing teardown state
  leakage (a recovered-workout alert in the next test); the rotation test was
  verified independently on a clean simulator. A separate test-runner bundle
  cache failure was resolved by erasing that temporary device.
- An interactive SE demo is left available as `N4x4 Current HR SE`, with
  `N4X4_DEMO_HEART_RATE=166`. This is simulated HR, not a physical sensor.
- Xcode simulator build passed (phone, embedded Watch and Live Activity).
- iPhone SE 3, iOS 26.5: all three existing UI scenarios passed on the
  target-range change: rotation with live HR and a paused timer, largest Dynamic
  Type, and no-monitor layout plus completion.
  Result: `/tmp/N4x4-target-range-SE-verified.xcresult`.
- iPhone 17 Pro, iOS 26.5: the same three scenarios passed; the two landscape
  scenarios passed again after reallocating column width. The rotation check
  passed again on the final implementation.
  Results: `/tmp/N4x4-target-range-Pro.xcresult`,
  `/tmp/N4x4-target-range-Pro-final.xcresult`,
  `/tmp/N4x4-target-range-Pro-verified.xcresult`.
- Visually checked SE portrait, landscape and largest-text screenshots: full
  target range is readable; default-size Pause and Skip remain visible.
  Previews: `/tmp/N4x4-target-range-portrait.png` and
  `/tmp/N4x4-target-range-landscape.png`.
- Design review: **8/10**. Reaching 10/10 still requires physical-device
  VoiceOver / exercise-distance readability checks and cleanup of surrounding
  legacy fixed typography and the truncated HR source label at accessibility
  sizes. These are not claimed as verified by simulator tests.
- `git diff --check` passed. Xcode's diagnostic collection repeats the local
  CommandLineTools `simctl` lookup warning; test execution uses the explicit
  Xcode developer directory and succeeds.
