# N4x4 — Session Handoff (birthday egg polish round, Mac session)

_Last updated 2026-07-26._ Covers the thirteen-item review-and-polish round on
the 2 August easter egg and the 4.13 bump. Supersedes
[`SESSION-HANDOFF-2026-07-23.md`](SESSION-HANDOFF-2026-07-23.md) for current
state.

Current marketing version: **4.13**, pushed as `25ee1bb` on 2026-07-25.
(4.6/4.7/4.10 remain burned numbers — never reuse.)

> **Unlike the Linux sessions: this all compiled and ran.** Xcode 26.6 was
> available. The app builds clean, 115 unit tests pass, and the egg was
> driven in the iPhone 17 Pro simulator and inspected frame by frame. The one
> thing a simulator physically cannot do is haptics — see "What still needs
> your thumb" below.

---

## TL;DR

Jan asked for a brainstorm on the shipped egg, then picked thirteen of the
fifteen suggestions. All thirteen shipped in one commit. Full per-item table
with the reasoning lives in **`docs/Birthday-Easter-Egg.md` § 4.13 changes** —
read that, not this file, for the detail.

The headline four:

- **Haptics** (`BirthdayHaptics`, new): a thud per shell, a flourish timed to
  the message parking, a rumble that tracks the spin. CoreHaptics with UIKit
  fallbacks.
- **The ball hangs now** (`DiscoBallSwing`, new): ambient sway, a shove on
  flick release, a wire that tilts to follow, and a cap + eyelet at the join.
- **The room reacts** (`BirthdayLightSpillView`, new): reflections cross the
  cards instead of stopping at their edge, and the beams pulse with bursts.
- **The egg is no longer only hers**: it fires on the user's own birthday too
  (HealthKit `dateOfBirth`, cached as month/day), and both days get a 06:00
  notification.

Three real defects were found and fixed on the way, all now AGENTS.md pitfall
rows:

1. **The spark cap was a lie.** `count < 2600` was checked *before* appending
   up to 210 sparks, so the true ceiling was 2809. Found by a new test, not by
   reading. Now `count + n <= cap`.
2. **`FireworkEngine.step` clamped `dt` at one end only.** The clock does run
   backwards in the field, and the documented way to test this very feature is
   to set the phone's date by hand.
3. **The spill layer washed the ball pale.** Additive light drawn over the
   object throwing it. Only visible by looking at the render; clipped out of
   the sphere now.

## What still needs your thumb

Everything visual was confirmed in the simulator. Everything tactile was not,
because it cannot be. In rough order of how likely it is to need changing:

1. **The per-shell thud.** One ambient shell lands every 0.9–1.7 s while Home
   is visible, all day, and each fires a haptic. Jan chose this knowing the
   risk; ambient bursts are already at half strength. If it's too much, the
   single dial is the `occasion` multiplier in `FireworkEngine.explode`, or
   gate `onBurst` on `finaleWindowEnd` to silence ambient entirely.
2. **The spin rumble.** Should read as a heavy ball turning, not a buzz. Knobs
   are the intensity/sharpness ramps in `BirthdayHaptics.spin` (currently
   `0.22 + 0.6k` and `0.08 + 0.55k`, `k` from |ω|).
3. **The flourish** at 4.7 s — it should land as the message parks, not after.
4. **The sway.** `DiscoBallSwing.ambientAmplitude` is 2 pt; the flick shove is
   `0.012 ×` gesture velocity capped at 18 pt/s. Both are guesses at what
   "heavy" feels like at phone scale.
5. **Frame rate during a hard flick** — the widened glint cone times three
   smear copies is the most expensive state the ball has. ProMotion should
   hold; confirm.
6. **Low shells** (1 in 5) now break among the cards. Check they read as
   depth, not as glitches behind the interval plan.

## Driving the egg without waiting for August

The Guide trigger still works (Guide → Advanced → hold the last tile 2 s →
success haptic → next arrival at Home). A freshly armed one-shot now **skips
the 90 s arrival cooldown**, so repeating the press really does replay the
whole opening.

For an agent session with a simulator, this is faster than tapping through:

```bash
xcodebuild -project N4x4.xcodeproj -scheme N4x4 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
APP=$(find ~/Library/Developer/Xcode/DerivedData/N4x4-*/Build/Products/Debug-iphonesimulator \
      -maxdepth 1 -name "N4x4.app" | head -1)
xcrun simctl boot 'iPhone 17 Pro'; xcrun simctl install booted "$APP"

# skip first-run sheets, then arm the egg directly
for k in hasCompletedOnboarding hasSeenHRSourcesAnnouncement \
         hasSeenWatchUpgradePrompt birthdayOneShotPending; do
  xcrun simctl spawn booted defaults write Jan-van-Rensburg.N4x4 "$k" -bool true
done
xcrun simctl launch booted Jan-van-Rensburg.N4x4
sleep 6 && xcrun simctl io booted screenshot /tmp/egg.png
```

`simctl` has no tap primitive, so gestures (spin, long-press) still need a
human or a real device. To see the motion smear without a gesture, temporarily
raise `DiscoBallSpin.defaultOmega` to ~7 and rebuild — that is how item 8 was
verified. **Revert it**; the tests will catch you if you don't.

## Watch out for

- **`whats_new.txt` and the ASC notes: still no mention of the egg.** The file
  in `N4x4/whats_new.txt` is stale (it still describes the AirPods Pro 3 / HR
  release) and was deliberately left alone — 4.13 contains nothing else
  user-facing to announce.
- **Adding `dateOfBirth` to the HealthKit read set re-prompts** users who
  already granted. The purpose string was amended to "…and your date of birth."
  — accurate without spoiling the surprise.
- **The 06:00 nudge on 2 August goes to every user**, not just her, which is
  consistent with the egg being visible to all but is louder than a cosmetic
  surprise. Identifiers and the reasoning are in the AGENTS.md notification
  table. It requires notification permission and never asks for it.
- **Haptics ignore the user's `hapticsEnabled` setting** (that flag governs
  interval cues; the Guide's own easter-egg confirmation ignores it too).
  One-line change if that turns out to be wrong.
- **`website/norway/` is untracked** and unrelated to this work. Left alone
  deliberately — don't sweep it into a release commit.

## The deadline, restated

The egg must be **live on the App Store and installed on her phone before
2 August**. As of writing that is seven days. Xcode Cloud is building 4.13
from `25ee1bb`; that is the build to submit. Review is usually under 48 h.
Don't cut it fine, and confirm her phone has actually updated.

## Verification state, precisely

| Thing | How verified |
|---|---|
| App target compiles | `xcodebuild build`, iPhone 17 Pro simulator, clean |
| Unit tests | 115/115 green, of which 24 are `BirthdayEasterEggTests` |
| Ball, eyelet, tilted wire, pulsing beams, smoke, low shells, burst reflections | Simulator screenshots, inspected |
| Motion smear | Simulator, with `defaultOmega` temporarily at 7 (reverted) |
| Spill layer not washing the ball | Simulator, before/after |
| Haptics | **Not verified.** Impossible in a simulator |
| Sway feel, flick shove | **Not verified** beyond the unit tests on the maths |
| The 06:00 notifications actually firing | **Not verified** — only the trigger components are unit-tested |
| Anything on a real device | **Not verified** — no device in this session |
