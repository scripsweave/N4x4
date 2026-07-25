# Birthday Easter Egg — 2 August 🪩

Annual easter egg, shipping from v4.10. Every 2 August (local time, any year)
the home screen's chrome START ring becomes a spinning mirror ball with
fireworks behind it and a "Happy Birthday 🫧!" message. Cosmetic only —
the ball is still the START button and the workout screen is untouched.

**From 4.13 it also fires on the user's own birthday** (HealthKit date of
birth, cached as month/day), both days get a 06:00 notification, and the show
is felt as well as seen. See "4.13 changes" below.

The look was locked through a live HTML motion mockup before any Swift was
written (artifact: <https://claude.ai/code/artifact/488e120c-93a8-4d44-9266-a9bd76945dee>,
source kept in that session's scratchpad only — the Swift is the canonical
implementation now).

---

## What the user sees on the day

1. **On every arrival at Home** (cold launch or return from background):
   the disco ball is spinning in the ring's place, the message rises from the
   bottom over ~4 s (0.8 s delay, ease-out) and parks near the top, and a
   seven-rocket **grand finale** is timed so the big bursts land as the
   message parks (~4.8 s), and a haptic flourish lands on the park. It replays
   on every arrival, deliberately — but not more than once every 90 s
   (`BirthdayEasterEgg.showCooldown`), so quick app switches don't restack it.
2. **Ambient mode** after the finale: a single firework every 0.9–1.7 s,
   all day.
3. **Gestures:**
   - Tap the ball → starts the workout (unchanged contract).
   - Long-press the ball (≥ 0.7 s) → manual grand finale, with an immediate
     haptic acknowledgement (the first shell is ~1.3 s of flight away).
   - **Drag the ball horizontally** → grabs it: the surface follows your
     finger (hold still to stop it dead), a flick throws it with your release
     velocity (capped at ±10 rad/s). Once free, a motor-plus-friction torque
     (`DiscoBallSpin`, exponential relaxation, τ = 4 s) eases it back to the
     house speed of 0.8 rad/s within ~12 s. The wandering room-light spots
     read the same rotation, so they whip around and freeze with the ball. A
     flick also shoves the ball on its wire (`DiscoBallSwing`), and a rumble
     haptic tracks |ω| for as long as it is turning faster than house speed.
   - Tap anywhere else → one firework bursts where you tapped
     (simultaneous gesture; all normal controls keep working).

4. **The message** parks just above the sphere's top edge (computed from the
   reported ball frame: `midY − 0.36 × slot side − 48 pt`, floored at 10% of
   screen height), never overlapping the ball.

---

## 4.13 changes

Thirteen items, in the order they were reviewed. All shipped together.

| # | Change | Where |
|---|---|---|
| 1 | **Arrival cooldown.** `beginShow()` used to replay the whole choreography on *every* foreground; twenty app switches on the day meant twenty finales. Now gated by `BirthdayEasterEgg.shouldRestartShow` (90 s). Inside the cooldown the message stays parked and ambient carries on. | `BirthdayActivation`, `BirthdayShowController` |
| 2 | **06:00 nudge on 2 August**, yearly repeating, title "Hey, 🫧 - Open N4x4". Everyone gets it (same reasoning as the egg being visible to all). | `scheduleMorningNudges()` |
| 3 | **Haptics.** A thud per shell (CoreHaptics transient + low tail, intensity from burst size, ×0.5 outside a finale), a three-thump flourish timed to the message parking, and a looping rumble whose intensity/sharpness track \|ω\| while the ball is spun. Silent at house speed. | `BirthdayHaptics` |
| 4 | **`dt` clamped at both ends** in `FireworkEngine.step`. It only clamped the top, and the clock does run backwards (see AGENTS pitfalls). | `FireworkEngine` |
| 5 | **`minimumScaleFactor(0.7)`** on the message — 28 pt heavy rounded truncated to "Happy Birth…" at SE width. | `BirthdayMessageView` |
| 6 | **Pendulum sway.** `DiscoBallSwing`: ambient ±2 pt from two detuned sines, plus a damped impulse on flick release. The wire hangs from a fixed anchor and tilts to the swung ball; a metal cap and eyelet were added where it meets the sphere. | `DiscoBallSwing`, `drawBall`, sky layer |
| 7 | **The room reacts.** Floor beams brighten with live bursts; a new `BirthdayLightSpillView` above the cards carries the wandering spots *and* the ball's bloom, clipped out of the sphere itself. | `BirthdayLightSpillView` |
| 8 | **Motion smear.** Above ~1.6 rad/s facet contrast fades, the glint cone widens and blooms are drawn as three copies displaced along x, so a hard flick reads as blur instead of strobe. | `drawBall` |
| 9 | **Burst aftermath.** Drifting smoke puffs (2.8 s), 30 % of peonies get a secondary break, one in five shells breaks low among the cards, and ~6 % of ambient launches are a comet that arcs across and falls past the content. | `FireworkEngine` |
| 11 | **Single physics owner.** `spin`/`swing` are stepped once per frame in `BirthdaySkyView` (always full-screen); the ball's canvas only reads them. Previously the ball stepped the spin and the sky's light spots read whatever angle they happened to see. | both canvases |
| 12 | **Long press 0.7 s** (was 0.5): a deliberate slow press meant for START fired the finale and never started the workout. | `DiscoBallStartButton` |
| 13 | **Engine + swing tests** — spark cap, zero bounds, finale drain, backwards clock, burst strengths, comet stacking, sway settling. 24 tests total. | `BirthdayEasterEggTests` |
| 14 | **The user's own birthday.** `dateOfBirth` added to the HealthKit read set, cached as month/day (`BirthdayEasterEgg.cacheUserBirthday`), and `isCelebrationDay()` is now the gate. They get their own 06:00 nudge too ("Happy Birthday! 🎉"), skipped if their birthday IS 2 August. | `TimerViewModel`, `BirthdayActivation` |

Item 10 (Reduce Motion / Low Power Mode gating) was considered and
**deliberately not implemented** — Jan's call. Two full-screen
`TimelineView(.animation)` canvases plus the spill layer run at display rate
for as long as Home is visible on the day, and ambient shells keep launching in
Low Power Mode. Revisit if battery complaints ever appear.

Deliberate consequences worth knowing:

- **Ambient shells buzz all day.** One lands every 0.9–1.7 s while Home is
  visible, and each one now fires a haptic (softened to ×0.5 outside a finale).
  This was raised as an annoyance risk and Jan chose it anyway. To dial it back,
  drop the `occasion` multiplier in `FireworkEngine.explode` or gate `onBurst`
  on `finaleWindowEnd`.
- **Haptics ignore the user's `hapticsEnabled` setting**, which governs interval
  cues; the Guide's own easter-egg confirmation ignores it too. One-line change
  if that turns out to be wrong.
- **Everyone gets the 🫧 notification on 2 August**, not just her. Consistent
  with the egg being visible to all users, but it is a 06:00 push, which is
  louder than a cosmetic surprise.

---

## Design decisions (locked — don't re-litigate casually)

| Decision | Why |
|---|---|
| Annual (month == 8 && day == 2, no year check) | Recurring is the better story; costs nothing |
| Visible to all users | Jan's call; long tradition of shipped easter eggs; App Store 2.3.1 only bans *functional* concealment, cosmetic surprises are fine |
| Home screen only | Never obscure live workout data |
| Programmatic rendering, no assets/deps | GIF = 256 colours + banding; Lottie = first external dependency; repo rule is Apple frameworks only |
| Physical glint model (facet mirror-reflection vs. 10 fixed room lights) | Random per-facet twinkle and drawn star shapes read as cartoon — Jan rejected them explicitly |
| Sparkle cone factor 3.0, spin 0.8 rad/s | Jan's slider values from the mockup |
| Brand amber → pink `#FF3E96` for the day (beams, tints, message, fireworks ~5/7 pink) | Her favourite colour |
| Message rises **once** and stays | Jan's spec (no loop) |

## Architecture

Two files plus three small diffs; delete the files, revert the diffs, and the
feature is gone (same rollback philosophy as `HomeWorkoutRedesign.swift`).

- **`N4x4/BirthdayEasterEgg.swift`** — everything visual:
  - `DiscoBallStartButton` — Canvas + `TimelineView(.animation)`; 16 latitude
    bands, ≤ 36 facets/band, real sphere projection, grout gaps, Lambert
    shading, pink/blue side tints, glint bloom rendering (hot core + soft
    halo + faint streak on the brightest; **no star shapes**).
  - `FireworkEngine` — plain class mutated inside the Canvas draw closure
    (nothing observes it). Peony / ring / willow / crackle bursts, secondary
    breaks, smoke, comets, spark cap 2600 enforced against the whole burst,
    rocket trails, `finale(startingIn:)` scheduling, and an `onBurst` strength
    callback the controller wires to the haptics. Each explosion
    also records a `Flash` (position + colour, 1.3 s life, max 5 live) that
    the ball reads as a light source: facets catch the burst through the same
    mirror-reflection test as the room lights, but with a wider cone (a burst
    is an extended source) and lerped toward the burst's COLOUR half-lifted
    to white — white-lifting made them indistinguishable from the ordinary
    room-light glints. Plus a colored wash (gain 0.30) on the side facing
    the burst.
  - `BirthdayShowController` — `ObservableObject`; owns the engine, the spin,
    the sway, the haptics, the message choreography (`beginShow()` + its 90 s
    cooldown), the session `epoch` (so Canvas trig runs on small numbers) and
    the ball's frame for the sky layer. `suspend()` stops the looping spin
    rumble when Home or the scene goes away.
  - `BirthdaySkyView` — full-screen Canvas *behind* the home content
    (`allowsHitTesting(false)`): fireworks, smoke, wandering light spots,
    pink/blue floor beams anchored under the ball (brightening with live
    bursts), hanging wire tilted to the swung ball. **This layer owns the
    clock**: spin, sway and particles are all stepped here, exactly once per
    frame, because it is the one layer guaranteed to be on screen.
  - `BirthdayLightSpillView` — Canvas *in front of* the home content: the same
    wandering spots plus the ball's own bloom, both clipped OUT of the sphere
    (it is the source, not a surface). Without it the reflections stopped dead
    at the edge of a card.
  - `BirthdayMessageView` — rises via two stacked `.animation(_:value:)`
    modifiers (4 s timing-curve for position/scale, 0.6 s ease-in for opacity).
  - `DiscoBallSpin` — angular state of the ball (plain class, injected time,
    unit-tested): motor at 0.8 rad/s, grab/flick via a drag gesture,
    exponential relaxation back to default after release.
  - `DiscoBallSwing` — the pendulum (plain class, injected time, unit-tested):
    ambient ±2 pt sway from two detuned sines that never stops, plus a damped
    oscillator that takes an impulse from a flick. Also reports the sub-pixel
    rise at the ends of the arc.
  - `BirthdayHaptics` — CoreHaptics with UIKit fallbacks: a thud per shell, the
    finale flourish, and a looping rumble driven by dynamic intensity/sharpness
    parameters while the ball spins above house speed. Engine `stoppedHandler`
    / `resetHandler` drop the cached player so an interruption can't leave it
    pushing parameters into a dead engine.
- **`N4x4/BirthdayActivation.swift`** — pure Foundation, unit-tested:
  `isTheDay(on:timeZone:)`, `isCelebrationDay(...)` (2 Aug + the cached user
  birthday), the one-shot manual trigger (`armOneShot` / `consumeOneShot`, key
  `birthdayOneShotPending`), the cached-birthday accessors, the show cooldown
  predicate and the nudge identifiers/components. **Keep it Foundation-only** —
  the `UserNotifications` half lives as an extension in `BirthdayEasterEgg.swift`
  so this file still compiles for the Linux SPM test recipe.
- **`HomeScreen`** (`HomeWorkoutRedesign.swift`) — the main integration point:
  ZStack wrap + conditional ball/ring swap + gesture + lifecycle triggers.
- **`TipsView.swift`** (Guide tab) — the hidden trigger (see below).
- **`TimerViewModel.swift`** — two small diffs: `dateOfBirth` in the HealthKit
  read set, and `refreshCachedUserBirthday()` called on grant/foreground.
  The 06:00 nudges are scheduled from inside
  `refreshNotificationPermissionState`'s completion (AGENTS rule).

## The hidden manual trigger (a true easter egg)

Guide tab → **Advanced** → press and hold the **last tile** ("Sleep Is Where
You Improve") for **2 seconds**. A success haptic is the only feedback. The
next arrival at the Home screen runs birthday mode for that app session;
consuming the flag clears it, so the next launch is normal again. Works in
every build configuration (it replaced the old DEBUG-only Settings toggle),
which also means it can be demoed on 1 Aug without touching the clock. Only
the last Advanced tile carries the gesture, so list scrolling is unaffected.
A freshly armed one-shot bypasses the 90 s arrival cooldown (it is an explicit
"show me now"), so repeating the press really does replay the whole opening.

## Reliability (the "will it actually fire?" checklist)

All verified by `N4x4Tests/BirthdayEasterEggTests.swift` (24 tests, green):

- **Explicitly Gregorian.** `Calendar.current` follows the device calendar
  setting; on an Islamic/Hebrew/Chinese-calendar phone "month 8 day 2" is a
  different Gregorian day. `isTheDay` builds its own Gregorian calendar.
- **Local time zone**, whole local day (00:00–23:59), every year.
- **Midnight crossover:** `HomeScreen` listens for
  `UIApplication.significantTimeChangeNotification` (fires at local midnight
  and on clock/zone changes), bumps a `@State` tick so `isBirthday`
  re-evaluates, and starts the show if the day just began. Foregrounding is
  separately covered by the `scenePhase` observer.
- **The manual trigger can't stick:** `consumeOneShot` clears the persisted
  flag the moment it's read; the session-only `@State` in `HomeScreen` dies
  with the process. A device can't stay in birthday mode past one session.
  (The old DEBUG-only `birthdayPreviewEnabled` toggle is gone; its key is
  simply never read any more.)

Not covered by tests (needs eyes on a device): the visuals themselves.

## Testing on a Mac

1. **Unit tests:** run the `N4x4Tests` scheme — `BirthdayEasterEggTests`
   must be green (they also run on Linux via the scratch-SPM recipe in the
   agent memory / handoff notes).
2. **Visual preview (any build):** Guide → Advanced → hold the last tile
   for 2 s (success haptic), then go to Home. One session of birthday mode;
   next launch is normal. Repeat the press to see it again.
3. **The honest end-to-end test:** build a **Release** configuration to a
   device, set the iPhone's date manually to 2 August (Settings → General →
   Date & Time), launch. This exercises the exact path she will hit —
   no manual trigger involved.
4. **On-device visual checklist** (first Xcode build of this code):
   - message parks just above the sphere — check the 48 pt clearance in
     `BirthdayMessageView.parkedY(in:)` feels right on device
   - grab/flick/stop the ball — the spin should feel like a real heavy ball
     (tuning knobs: `DiscoBallSpin.relaxationTau`, `maxOmega`)
   - spark motion-streaks: the mockup had persistent additive trails; the
     Swift approximates with velocity streaks — judge and tune
   - frame rate during a finale (~600 facet quads + up to 2600 sparks per
     frame; ProMotion should hold, but confirm)
   - beams sit under the ball; wire meets the ball's top.
5. **4.13 on-device checklist** (simulator-verified only so far — the ball, the
   eyelet, the tilted wire, the pulsing beams, the smoke and the motion smear
   were all confirmed in the iPhone 17 Pro simulator on 2026-07-25; haptics
   cannot be):
   - the per-shell thud: is the ambient one too present over a whole day? The
     dial is the `occasion` multiplier in `FireworkEngine.explode`.
   - the spin rumble: does it read as a heavy ball turning, or as a buzz?
     Knobs are the intensity/sharpness ramps in `BirthdayHaptics.spin`.
   - the finale flourish landing on the message parking (4.7 s).
   - the sway: ±2 pt ambient may be too subtle or too obvious on device
     (`DiscoBallSwing.ambientAmplitude`), and the flick shove is `0.012 ×`
     gesture velocity, capped at 18 pt/s.
   - frame rate during a hard flick: the widened glint cone × 3 smear copies is
     the most expensive state the ball has.
   - the low shells (1 in 5) burst among the cards — check they don't look like
     glitches behind the interval plan.

## Release constraints

- Must be **live on the App Store and installed on her phone before 2 Aug**.
  Review is typically < 48 h but don't cut it fine.
- Do **not** mention the easter egg in `whats_new.txt` / App Store notes —
  it's a surprise. "Small improvements" is fine.
- The Guide trigger works in TestFlight/App Store builds too — handy for a
  quick sanity check after release, and it self-clears after one session.
