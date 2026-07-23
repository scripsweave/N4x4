# Birthday Easter Egg — 2 August 🪩

Annual easter egg, shipping from v4.10. Every 2 August (local time, any year)
the home screen's chrome START ring becomes a spinning mirror ball with
fireworks behind it and a "Happy birthday to 🫧" message. Cosmetic only —
the ball is still the START button and the workout screen is untouched.

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
   message parks (~4.8 s). It replays on every arrival, deliberately.
2. **Ambient mode** after the finale: a single firework every 0.9–1.7 s,
   all day.
3. **Gestures:**
   - Tap the ball → starts the workout (unchanged contract).
   - Long-press the ball (≥ 0.5 s) → manual grand finale.
   - **Drag the ball horizontally** → grabs it: the surface follows your
     finger (hold still to stop it dead), a flick throws it with your release
     velocity (capped at ±10 rad/s). Once free, a motor-plus-friction torque
     (`DiscoBallSpin`, exponential relaxation, τ = 4 s) eases it back to the
     house speed of 0.8 rad/s within ~12 s. The wandering room-light spots
     read the same rotation, so they whip around and freeze with the ball.
   - Tap anywhere else → one firework bursts where you tapped
     (simultaneous gesture; all normal controls keep working).

4. **The message** parks just above the sphere's top edge (computed from the
   reported ball frame: `midY − 0.36 × slot side − 48 pt`, floored at 10% of
   screen height), never overlapping the ball.

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

Three files; delete the first, revert the two small diffs, and the feature is
gone (same rollback philosophy as `HomeWorkoutRedesign.swift`).

- **`N4x4/BirthdayEasterEgg.swift`** — everything visual:
  - `DiscoBallStartButton` — Canvas + `TimelineView(.animation)`; 16 latitude
    bands, ≤ 36 facets/band, real sphere projection, grout gaps, Lambert
    shading, pink/blue side tints, glint bloom rendering (hot core + soft
    halo + faint streak on the brightest; **no star shapes**).
  - `FireworkEngine` — plain class mutated inside the Canvas draw closure
    (nothing observes it). Peony / ring / willow / crackle bursts, spark cap
    2600, rocket trails, `finale(startingIn:)` scheduling. Each explosion
    also records a `Flash` (position + colour, 1.3 s life, max 5 live) that
    the ball reads as a light source: facets catch the burst through the same
    mirror-reflection test as the room lights, but with a wider cone (a burst
    is an extended source) and lerped toward the burst's COLOUR half-lifted
    to white — white-lifting made them indistinguishable from the ordinary
    room-light glints. Plus a colored wash (gain 0.30) on the side facing
    the burst.
  - `BirthdayShowController` — `ObservableObject`; owns the engine, the
    message choreography (`beginShow()`), the session `epoch` (so Canvas trig
    runs on small numbers) and the ball's frame for the sky layer.
  - `BirthdaySkyView` — full-screen Canvas *behind* the home content
    (`allowsHitTesting(false)`): fireworks, wandering light spots, pink/blue
    floor beams anchored under the ball, hanging wire.
  - `BirthdayMessageView` — rises via two stacked `.animation(_:value:)`
    modifiers (4 s timing-curve for position/scale, 0.6 s ease-in for opacity).
  - `DiscoBallSpin` — angular state of the ball (plain class, injected time,
    unit-tested): motor at 0.8 rad/s, grab/flick via a drag gesture,
    exponential relaxation back to default after release.
- **`N4x4/BirthdayActivation.swift`** — pure Foundation, unit-tested:
  `BirthdayEasterEgg.isTheDay(on:timeZone:)` plus the one-shot manual
  trigger (`armOneShot` / `consumeOneShot`, key `birthdayOneShotPending`).
- **`HomeScreen`** (`HomeWorkoutRedesign.swift`) — the main integration point:
  ZStack wrap + conditional ball/ring swap + gesture + lifecycle triggers.
- **`TipsView.swift`** (Guide tab) — the hidden trigger (see below).

## The hidden manual trigger (a true easter egg)

Guide tab → **Advanced** → press and hold the **last tile** ("Sleep Is Where
You Improve") for **2 seconds**. A success haptic is the only feedback. The
next arrival at the Home screen runs birthday mode for that app session;
consuming the flag clears it, so the next launch is normal again. Works in
every build configuration (it replaced the old DEBUG-only Settings toggle),
which also means it can be demoed on 1 Aug without touching the clock. Only
the last Advanced tile carries the gesture, so list scrolling is unaffected.

## Reliability (the "will it actually fire?" checklist)

All verified by `N4x4Tests/BirthdayEasterEggTests.swift` (6 tests, green):

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

## Release constraints

- Must be **live on the App Store and installed on her phone before 2 Aug**.
  Review is typically < 48 h but don't cut it fine.
- Do **not** mention the easter egg in `whats_new.txt` / App Store notes —
  it's a surprise. "Small improvements" is fine.
- The Guide trigger works in TestFlight/App Store builds too — handy for a
  quick sanity check after release, and it self-clears after one session.
