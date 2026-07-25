// BirthdayEasterEgg.swift
//
// Annual 2 August easter egg: on the home screen the chrome START ring becomes
// a spinning mirror ball with fireworks behind it and a birthday message that
// rises once and parks above the ball. Cosmetic only — the ball remains the
// START control and the workout screen is untouched. The whole feature lives
// in this file plus a conditional in `HomeScreen` and a DEBUG-only preview
// toggle in Settings, so it is trivial to remove.
//
// The look was locked via an HTML motion mockup (2026-07-23) and ports 1:1:
//   • glints use the physical model — a facet flashes only while its true
//     mirror reflection of the view ray lines up with one of ten fixed "room
//     lights" (no random twinkle, no star shapes)
//   • sparkle cone factor 3.0, spin 0.8 rad/s
//   • the brand amber becomes pink #FF3E96 for the day; fireworks weighted
//     toward pink with blue/white as contrast
//   • the message rises once over 4 s (0.8 s delay) and stays parked
//
// Choreography: every arrival at Home (launch or foreground, at most once per
// `BirthdayEasterEgg.showCooldown`) rises the message and times a 7-rocket
// finale to land as it parks. Long-press the ball for a manual finale; tap
// anywhere for a single firework. Ambient single rockets continue all day.
//
// 4.13 additions: haptics (a thud per shell, a flourish on the finale, a
// rumble that tracks the spin), a pendulum sway with the wire anchored to the
// swung ball, burst smoke / double-breaks / low comets, room light that
// spills onto the cards, and motion smear so a hard flick doesn't strobe.

import SwiftUI
import UIKit
import CoreHaptics
import UserNotifications

// Activation logic (date check, preview key) lives in BirthdayActivation.swift
// — pure Foundation, unit-tested in BirthdayEasterEggTests.

// MARK: - Palette (0–1 components so Canvas math can lerp them)

private struct RGB {
    var r: Double, g: Double, b: Double
    func color(_ opacity: Double = 1) -> Color {
        Color(red: r, green: g, blue: b, opacity: opacity)
    }
}

private let bdayPink  = RGB(r: 1.00, g: 0.243, b: 0.588)   // #FF3E96 — her color
private let bdayBlush = RGB(r: 1.00, g: 0.667, b: 0.824)
private let bdayBlue  = RGB(r: 0.18, g: 0.52,  b: 1.00)    // Palette.electricBlue
private let bdayIce   = RGB(r: 0.62, g: 0.788, b: 1.00)
private let bdayWhite = RGB(r: 1.00, g: 1.00,  b: 1.00)
private let bdayWarm  = RGB(r: 1.00, g: 0.957, b: 0.878)   // warm-white glint

// MARK: - Small math helpers (mirror the mockup exactly)

private func bdayHash(_ a: Double, _ b: Double) -> Double {
    let s = sin(a * 127.1 + b * 311.7) * 43758.5453
    return s - s.rounded(.down)
}

private struct Vec3 {
    var x: Double, y: Double, z: Double
    func normalized() -> Vec3 {
        let l = (x * x + y * y + z * z).squareRoot()
        return Vec3(x: x / l, y: y / l, z: z / l)
    }
    func dot(_ o: Vec3) -> Double { x * o.x + y * o.y + z * o.z }
}

// MARK: - Spin dynamics

/// Angular state of the mirror ball. A motor normally turns it at
/// `defaultOmega`; a horizontal drag grabs the surface (the ball follows the
/// finger, so holding still stops it) and releasing throws it with the
/// finger's velocity. Once free, motor-plus-friction torque relaxes it back
/// to the house speed over a few seconds. Injected time, no SwiftUI —
/// unit-tested in BirthdayEasterEggTests.
final class DiscoBallSpin {
    static let defaultOmega = 0.8          // rad/s — the locked mockup speed
    static let maxOmega = 10.0             // flick cap (~1.6 rev/s)
    /// Motor/friction time constant. A stopped or thrown ball is visibly
    /// back to normal within ~3τ ≈ 12 s.
    static let relaxationTau = 4.0

    private(set) var angle = 0.0
    private(set) var omega = DiscoBallSpin.defaultOmega
    private(set) var isGrabbed = false
    private var lastTime: Double?
    private var lastDragX: Double?
    private var lastDragTime: Double?

    /// Advance to `now` (the Canvas session clock). While grabbed the finger
    /// owns the angle and this only keeps the clock current.
    func step(now: Double) {
        let dt = min(0.05, max(0, lastTime.map { now - $0 } ?? 0.016))
        lastTime = now
        guard !isGrabbed else { return }
        omega += (Self.defaultOmega - omega) * (1 - exp(-dt / Self.relaxationTau))
        angle += omega * dt
    }

    /// `x` in the ball view's local space; `time` on the same session clock;
    /// `radius` the sphere radius in points (dx/radius = surface radians).
    func dragChanged(x: Double, time: Double, radius: Double) {
        guard radius > 0 else { return }
        if !isGrabbed {
            isGrabbed = true
            lastDragX = nil
            lastDragTime = nil
            omega = 0                       // caught — surface now follows the finger
        }
        if let px = lastDragX, let pt = lastDragTime, time > pt {
            let dAngle = (x - px) / radius
            angle += dAngle
            // smoothed finger velocity, so a still hold releases to a stop
            omega = omega * 0.65 + (dAngle / (time - pt)) * 0.35
        }
        lastDragX = x
        lastDragTime = time
    }

    func dragEnded(velocityX: Double, radius: Double) {
        isGrabbed = false
        guard radius > 0 else { return }
        omega = max(-Self.maxOmega, min(Self.maxOmega, velocityX / radius))
    }
}

// MARK: - Pendulum sway

/// The ball hangs from a wire, so it swings. Two components summed: an ambient
/// sway that never quite stops (two detuned sines, so it doesn't read as a
/// metronome) and a damped oscillator that takes an impulse when a flick
/// releases. Output is in points of horizontal travel — the caller offsets the
/// sphere and re-anchors the wire to it. Injected time, no SwiftUI:
/// unit-tested in BirthdayEasterEggTests.
final class DiscoBallSwing {
    /// ~3.6 s period. A real mirror ball on a short chain is nearer 2 s; slower
    /// reads as heavier at phone scale.
    static let omega0 = 1.75
    /// Decay rate of the flick impulse, 1/s (e-fold 4 s, settled in ~12 s —
    /// deliberately matched to `DiscoBallSpin.relaxationTau` so the sway and
    /// the spin calm down together).
    static let dampingRate = 0.25
    static let ambientAmplitude = 2.0        // pt
    static let maxKickVelocity = 18.0        // pt/s ⇒ ≈10 pt of swing

    private(set) var offsetX = 0.0
    private var kick = 0.0                   // damped oscillator position, pt
    private var kickVelocity = 0.0
    private var lastTime: Double?

    func step(now: Double) {
        let dt = min(0.05, max(0, lastTime.map { now - $0 } ?? 0.016))
        lastTime = now
        // semi-implicit Euler on ẍ = -ω₀²x - 2λẋ
        kickVelocity += (-Self.omega0 * Self.omega0 * kick
                         - 2 * Self.dampingRate * kickVelocity) * dt
        kick += kickVelocity * dt
        let a = Self.ambientAmplitude
        offsetX = a * (0.65 * sin(Self.omega0 * now)
                       + 0.35 * sin(Self.omega0 * 0.83 * now + 1.7)) + kick
    }

    /// A horizontal flick both spins the ball and shoves it. `velocityX` is the
    /// gesture velocity in points/s; only a small fraction becomes swing (most
    /// of it goes into rotation).
    func kick(velocityX: Double) {
        let v = max(-Self.maxKickVelocity,
                    min(Self.maxKickVelocity, velocityX * 0.012))
        kickVelocity += v
    }

    /// A pendulum's centre traces an arc, so the ball lifts slightly at the
    /// extremes. Sub-pixel at these amplitudes, but it costs nothing and keeps
    /// the wire length honest.
    func verticalRise(pendulumLength length: Double) -> Double {
        guard length > 1 else { return 0 }
        return (offsetX * offsetX) / (2 * length)
    }
}

// MARK: - Haptics

/// Touch for the show: a soft thud when a shell opens, a scripted flourish as
/// the message parks, and a rumble that rises with the ball's spin. CoreHaptics
/// where the hardware has it (the transient UIKit generators can't rumble),
/// UIKit taps as the fallback. One instance per `BirthdayShowController`.
///
/// Deliberately NOT gated on the user's `hapticsEnabled` setting: that flag
/// governs interval cues during a workout, and the rest of the app's UI
/// feedback (the Guide's own easter-egg confirmation) ignores it too.
final class BirthdayHaptics {
    private var engine: CHHapticEngine?
    private var engineUnavailable = false
    private var spinPlayer: CHHapticAdvancedPatternPlayer?
    private var spinRunning = false
    private var lastBurstAt = -1.0
    private var lastSpinUpdateAt = -1.0
    private let softTap = UIImpactFeedbackGenerator(style: .soft)

    init() { softTap.prepare() }

    // MARK: shells

    /// `strength` 0…1, set by the shell's size and whether a finale is running,
    /// so an ambient shell is a whisper and a finale peony thuds. `t` is the
    /// controller's session clock, used only to stop two shells stacking.
    func burst(strength: Double, at t: Double) {
        guard t - lastBurstAt > 0.12 else { return }
        lastBurstAt = t
        let s = max(0.08, min(1, strength))
        let events = [
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(s)),
                CHHapticEventParameter(parameterID: .hapticSharpness,
                                       value: Float(0.25 + 0.35 * s)),
            ], relativeTime: 0),
            // the low tail is what makes it a distant boom rather than a tick
            CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(s * 0.55)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.05),
            ], relativeTime: 0.02, duration: 0.11 + 0.09 * s),
        ]
        if play(events) { return }
        softTap.impactOccurred(intensity: s)
    }

    /// Timed to the moment the message parks: three rising thumps into a
    /// half-second swell. Falls back to a success notification tap.
    func finaleFlourish() {
        var events: [CHHapticEvent] = []
        for (i, intensity) in [0.55, 0.75, 1.0].enumerated() {
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity)),
                CHHapticEventParameter(parameterID: .hapticSharpness,
                                       value: Float(0.35 + 0.2 * Double(i))),
            ], relativeTime: Double(i) * 0.13))
        }
        events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1),
        ], relativeTime: 0.42, duration: 0.5))
        if play(events) { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: spin

    /// Called every frame while the ball is on screen. A looping continuous
    /// player whose intensity and sharpness track |ω|, so the ball feels like
    /// it is turning under the finger and grinding down after a flick. Silent
    /// at house speed, or there would be a rumble in the pocket all day.
    /// No fallback: the UIKit generators would have to machine-gun taps at
    /// 18 Hz to fake it, which reads as a rattle, not a spin.
    func spin(omega: Double, grabbed: Bool, at t: Double) {
        let speed = abs(omega)
        let active = grabbed ? speed > 0.3 : speed > 1.3
        guard active else { stopSpin(); return }
        guard let player = spinRumblePlayer() else { return }

        if !spinRunning {
            // only claim it's running if it actually started, or a throw here
            // would latch the flag and silence the rumble for the session
            guard (try? player.start(atTime: CHHapticTimeImmediate)) != nil else { return }
            spinRunning = true
        }
        // ~20 Hz is plenty for a smooth ramp and keeps the engine off the
        // Canvas's frame budget
        guard t - lastSpinUpdateAt > 0.05 else { return }
        lastSpinUpdateAt = t
        let k = min(1, max(0, (speed - 0.8) / (DiscoBallSpin.maxOmega - 0.8)))
        try? player.sendParameters([
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                     value: Float(0.22 + 0.6 * k), relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl,
                                     value: Float(0.08 + 0.55 * k), relativeTime: 0),
        ], atTime: CHHapticTimeImmediate)
    }

    func stopSpin() {
        guard spinRunning else { return }
        spinRunning = false
        try? spinPlayer?.stop(atTime: CHHapticTimeImmediate)
    }

    // MARK: engine plumbing

    private func startedEngine() -> CHHapticEngine? {
        guard !engineUnavailable else { return nil }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            engineUnavailable = true
            return nil
        }
        if engine == nil {
            guard let created = try? CHHapticEngine() else {
                engineUnavailable = true
                return nil
            }
            created.playsHapticsOnly = true
            // The engine is stopped for us on interruption (a call, the app
            // backgrounding). Drop the cached player so the next frame builds a
            // fresh one instead of pushing parameters into a dead engine.
            created.stoppedHandler = { [weak self] _ in
                self?.spinPlayer = nil
                self?.spinRunning = false
            }
            created.resetHandler = { [weak self] in
                self?.spinPlayer = nil
                self?.spinRunning = false
                try? self?.engine?.start()
            }
            engine = created
        }
        guard let engine, (try? engine.start()) != nil else { return nil }
        return engine
    }

    private func play(_ events: [CHHapticEvent]) -> Bool {
        guard let engine = startedEngine(),
              let pattern = try? CHHapticPattern(events: events, parameters: []),
              let player = try? engine.makePlayer(with: pattern),
              (try? player.start(atTime: CHHapticTimeImmediate)) != nil
        else { return false }
        return true
    }

    /// A 1 s continuous event on loop, driven entirely by dynamic parameters.
    private func spinRumblePlayer() -> CHHapticAdvancedPatternPlayer? {
        if let spinPlayer { return spinPlayer }
        guard let engine = startedEngine() else { return nil }
        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2),
        ], relativeTime: 0, duration: 1.0)
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let player = try? engine.makeAdvancedPlayer(with: pattern)
        else { return nil }
        player.loopEnabled = true
        spinPlayer = player
        return player
    }
}

// MARK: - Firework engine

/// Particle state for the birthday fireworks. A plain reference type mutated
/// from inside the Canvas draw closure each frame (Canvas polls it; nothing
/// observes it), so it deliberately is NOT an ObservableObject.
final class FireworkEngine {
    fileprivate struct Rocket {
        var x: Double, y: Double, vx: Double, vy: Double
        var color: RGB
        var trail: [CGPoint] = []
        /// A comet never breaks: it arcs across, sheds sparks and falls past
        /// the cards, so the sky isn't only ever busy at the top.
        var isComet = false
        var shedTimer = 0.0
    }
    fileprivate struct Spark {
        var x: Double, y: Double, vx: Double, vy: Double
        var age: Double, life: Double, drag: Double, size: Double
        var twinkle: Double            // 0 = steady; else flicker frequency
        var color: RGB
    }

    /// A burst as a light source, so the ball can reflect it (screen position
    /// in the sky canvas's space, which is also the ballFrame's space).
    fileprivate struct Flash {
        var x: Double, y: Double
        var color: RGB
        var birth: Double              // engine time of the explosion
    }
    static let flashLife = 1.3         // seconds a burst stays "lit"

    /// The drifting smoke a shell leaves behind. Real fireworks leave the sky
    /// dirty; without it every burst vanishes without trace.
    fileprivate struct Smoke {
        var x: Double, y: Double
        var birth: Double
        var radius: Double
        var color: RGB
    }
    static let smokeLife = 2.8

    fileprivate private(set) var rockets: [Rocket] = []
    fileprivate private(set) var sparks: [Spark] = []
    fileprivate private(set) var flashes: [Flash] = []
    fileprivate private(set) var smoke: [Smoke] = []
    private var pendingLaunches: [Double] = []     // seconds until lift-off
    /// Scheduled secondary breaks (engine time, position, colour, scale).
    private var pendingBreaks: [(t: Double, x: Double, y: Double, color: RGB, scale: Double)] = []
    private var autoTimer: Double = 0
    private var lastTime: Double?
    private var bounds: CGSize = .zero
    /// Engine time the current finale's last shell should have burst by.
    /// Bursts inside the window are felt at full strength; ambient ones are
    /// deliberately much softer (one lands every ~1.2 s, all day).
    private var finaleWindowEnd = -1.0

    /// Called on every explosion with a 0…1 strength. Wired to the haptics by
    /// `BirthdayShowController`; kept as a plain closure so the engine stays
    /// free of UIKit and testable.
    var onBurst: ((Double) -> Void)?

    // Test surface (BirthdayEasterEggTests) — the particle structs stay
    // fileprivate, so expose only counts and positions.
    var rocketCount: Int { rockets.count }
    var sparkCount: Int { sparks.count }
    var smokeCount: Int { smoke.count }
    var flashCount: Int { flashes.count }
    var pendingLaunchCount: Int { pendingLaunches.count }
    var rocketPositions: [CGPoint] { rockets.map { CGPoint(x: $0.x, y: $0.y) } }

    /// One rocket. Pass a point to burst near it (tap-to-launch); with no
    /// arguments the launch column and apex are random.
    func launch(at point: CGPoint? = nil) {
        let w = Double(bounds.width), h = Double(bounds.height)
        guard w > 0, h > 0 else { return }
        let s = h / 780
        let x = point.map { Double($0.x) } ?? Double.random(in: (w * 0.15)...(w * 0.85))
        // apex band sits above the ball's top (~0.23 h) so most bursts open in
        // clear sky; one in five is a low shell that breaks down among the
        // cards, which is what gives the sky depth (it lights the ball from
        // below too)
        let randomTarget = Double.random(in: 0...1) < 0.2
            ? Double.random(in: (h * 0.35)...(h * 0.55))
            : Double.random(in: (h * 0.05)...(h * 0.22))
        let targetY = point.map { Double($0.y) } ?? randomTarget
        let clampedTarget = min(h * 0.8, max(h * 0.05, targetY))
        rockets.append(Rocket(
            x: x, y: h + 8,
            vx: Double.random(in: -14...14) * s,
            vy: -(2 * 300 * s * (h + 8 - clampedTarget)).squareRoot(),
            // weighted: mostly pink, blue/white kept as occasional contrast
            color: [bdayPink, bdayPink, bdayPink, bdayBlush, bdayBlush, bdayIce, bdayWhite]
                .randomElement()!
        ))
    }

    /// A shell that fails to break: it crosses the sky, arcs over and falls
    /// past the cards trailing gold. Rare, and never more than one at a time.
    func launchComet() {
        let w = Double(bounds.width), h = Double(bounds.height)
        guard w > 0, h > 0 else { return }
        guard !rockets.contains(where: { $0.isComet }) else { return }
        let s = h / 780
        let fromLeft = Bool.random()
        rockets.append(Rocket(
            x: fromLeft ? -10 : w + 10,
            y: h + 8,
            vx: (fromLeft ? 1 : -1) * Double.random(in: 90...150) * s,
            vy: -(2 * 300 * s * (h * 0.75)).squareRoot(),
            color: RGB(r: 1, g: 0.86, b: 0.67),
            isComet: true
        ))
    }

    /// Seven staggered rockets. `startingIn` lets the opening choreography
    /// time the bursts to land as the birthday message parks.
    func finale(startingIn delay: Double = 0) {
        pendingLaunches += (0..<7).map { delay + Double($0) * 0.28 }
        // last lift-off + ~1.3 s of flight, measured from wherever the clock is
        let now = lastTime ?? 0
        finaleWindowEnd = max(finaleWindowEnd, now + delay + 6 * 0.28 + 1.6)
    }

    /// Advance the simulation to `now` (seconds, monotonic within a session).
    /// `dt` is clamped at BOTH ends: the clock does run backwards in the field
    /// (a local-midnight zone change, an NTP correction, or the documented
    /// "set the phone's date to 2 August" test), and a negative step would age
    /// sparks in reverse and run the sky backwards for a frame.
    func step(now: Double, in size: CGSize) {
        bounds = size
        let dt = min(0.05, max(0, lastTime.map { now - $0 } ?? 0.016))
        lastTime = now
        let s = Double(size.height) / 780
        let g = 300 * s

        // ambient single rockets, all day — it's her day
        autoTimer -= dt
        if autoTimer <= 0 {
            if Double.random(in: 0...1) < 0.06 { launchComet() } else { launch() }
            autoTimer = Double.random(in: 0.9...1.7)
        }

        for i in stride(from: pendingLaunches.count - 1, through: 0, by: -1) {
            pendingLaunches[i] -= dt
            if pendingLaunches[i] <= 0 {
                pendingLaunches.remove(at: i)
                launch()
            }
        }

        for i in stride(from: pendingBreaks.count - 1, through: 0, by: -1) {
            guard now >= pendingBreaks[i].t else { continue }
            let b = pendingBreaks.remove(at: i)
            explode(x: b.x, y: b.y, color: b.color, scale: b.scale, now: now,
                    allowSecondary: false)
        }

        for i in stride(from: rockets.count - 1, through: 0, by: -1) {
            rockets[i].x += rockets[i].vx * dt
            rockets[i].y += rockets[i].vy * dt
            rockets[i].vy += g * dt
            rockets[i].trail.append(CGPoint(x: rockets[i].x, y: rockets[i].y))
            if rockets[i].trail.count > 12 { rockets[i].trail.removeFirst() }

            if rockets[i].isComet {
                // sheds a slow ember every ~40 ms, dies off the bottom
                rockets[i].shedTimer -= dt
                if rockets[i].shedTimer <= 0, sparks.count < Self.sparkCap {
                    rockets[i].shedTimer = 0.04
                    sparks.append(Spark(
                        x: rockets[i].x, y: rockets[i].y,
                        vx: rockets[i].vx * 0.12 + Double.random(in: -8...8) * s,
                        vy: Double.random(in: -6...14) * s,
                        age: 0, life: Double.random(in: 0.6...1.2),
                        drag: 1.1, size: Double.random(in: 1.2...2.0) * s,
                        twinkle: Double.random(in: 0...1) < 0.3
                            ? Double.random(in: 14...24) : 0,
                        color: Double.random(in: 0...1) < 0.25 ? bdayWhite : rockets[i].color))
                }
                if rockets[i].y > Double(size.height) + 40 {
                    rockets.remove(at: i)
                }
                continue
            }

            if rockets[i].vy > -40 * s {
                let r = rockets.remove(at: i)
                explode(x: r.x, y: r.y, color: r.color, scale: s, now: now)
            }
        }

        flashes.removeAll { now - $0.birth > Self.flashLife }
        smoke.removeAll { now - $0.birth > Self.smokeLife }

        for i in stride(from: sparks.count - 1, through: 0, by: -1) {
            sparks[i].age += dt
            if sparks[i].age >= sparks[i].life {
                sparks.remove(at: i)
                continue
            }
            let k = exp(-sparks[i].drag * dt)
            sparks[i].vx *= k
            sparks[i].vy = sparks[i].vy * k + g * dt
            sparks[i].x += sparks[i].vx * dt
            sparks[i].y += sparks[i].vy * dt
        }
    }

    /// Hard ceiling on live sparks. Enforced against the WHOLE burst, not just
    /// the count before it: the old `count < cap` guard admitted a burst that
    /// then appended up to 210 more, so the real ceiling was 2809 (caught by
    /// testSparkCapHoldsUnderAContinuousShow with three overlapping finales).
    /// A burst that doesn't fit is skipped whole rather than half-drawn.
    static let sparkCap = 2600

    private func explode(x: Double, y: Double, color: RGB, scale s: Double,
                         now: Double, allowSecondary: Bool = true) {
        enum Burst: CaseIterable { case peony, ring, willow, crackle }
        let type = [Burst.peony, .peony, .ring, .willow, .crackle].randomElement()!
        let n = type == .ring ? 90 : Int.random(in: 130...210)
        guard sparks.count + n <= Self.sparkCap else { return }
        let base = type == .willow ? bdayBlush : color

        flashes.append(Flash(x: x, y: y, color: base, birth: now))
        if flashes.count > 5 { flashes.removeFirst(flashes.count - 5) }
        let maxV = (type == .willow ? 190.0 : 250.0) * s

        // dirty sky: a soft puff that grows and drifts up as it thins
        smoke.append(Smoke(x: x, y: y, birth: now, radius: maxV * 0.12, color: base))
        if smoke.count > 8 { smoke.removeFirst(smoke.count - 8) }

        // a peony sometimes has a second, smaller break just off-centre
        if allowSecondary, type == .peony, Double.random(in: 0...1) < 0.3 {
            pendingBreaks.append((
                t: now + Double.random(in: 0.35...0.55),
                x: x + Double.random(in: -50...50) * s,
                y: y + Double.random(in: -30...30) * s,
                color: color, scale: s * 0.7))
        }

        // felt, not just seen. Bigger shells hit harder; a secondary break and
        // anything outside a finale is deliberately soft, since one ambient
        // shell lands every ~1.2 s for the whole day.
        let typeWeight: Double = {
            switch type {
            case .peony:   return 1.0
            case .crackle: return 0.85
            case .ring:    return 0.7
            case .willow:  return 0.6
            }
        }()
        let sizeWeight = 0.7 + 0.3 * (Double(n) / 210)
        let occasion = (now <= finaleWindowEnd && allowSecondary) ? 1.0 : 0.5
        onBurst?(min(1, 0.62 * typeWeight * sizeWeight * occasion
                        * (allowSecondary ? 1.0 : 0.6)))

        for i in 0..<n {
            let a = (Double(i) / Double(n)) * 2 * .pi + Double.random(in: -0.03...0.03)
            let v = type == .ring
                ? maxV * Double.random(in: 0.92...1.0)
                : maxV * Double.random(in: 0...1).squareRoot()
            sparks.append(Spark(
                x: x, y: y, vx: cos(a) * v, vy: sin(a) * v,
                age: 0,
                life: type == .willow ? Double.random(in: 2.2...3.0)
                                      : Double.random(in: 1.1...2.0),
                drag: type == .willow ? 0.5 : 1.6,
                size: Double.random(in: 1.4...2.4) * s,
                twinkle: type == .crackle ? Double.random(in: 18...30) : 0,
                color: Double.random(in: 0...1) < 0.15 ? bdayWhite : base
            ))
        }
    }
}

// MARK: - Show controller

/// Owns the engine, the message choreography and the ball's frame (so the
/// full-screen sky layer can anchor beams/wire to wherever layout put the
/// ball). One instance per `HomeScreen`.
final class BirthdayShowController: ObservableObject {
    let engine = FireworkEngine()
    let spin = DiscoBallSpin()
    let swing = DiscoBallSwing()
    let haptics = BirthdayHaptics()
    /// Session-local time origin so Canvas trig runs on small numbers.
    let epoch = Date()
    @Published var messageRisen = false
    /// Ball slot frame in the "birthdayHome" coordinate space. The sky canvas
    /// reads it every frame, but it must ALSO be @Published: the layout shifts
    /// after launch (the VO₂ card loads in async from HealthKit) and the
    /// parked message has to follow the ball, not its first reported frame.
    /// Updates only on real layout changes, so the extra invalidation is
    /// negligible.
    @Published var ballFrame: CGRect = .zero

    /// Distance from the wire's anchor (screen top) to the ball's centre —
    /// the pendulum's length, used for the tiny rise at the ends of the arc.
    var pendulumLength: Double {
        ballFrame == .zero ? 400 : max(1, Double(ballFrame.midY))
    }

    /// When the last full choreography started, for the arrival cooldown.
    private var lastShowAt: Date?

    init() {
        engine.onBurst = { [weak self] strength in
            guard let self else { return }
            self.haptics.burst(strength: strength,
                               at: Date().timeIntervalSince(self.epoch))
        }
    }

    /// Runs the opening sequence: message rises (0.8 s delay, 4 s ease-out,
    /// view-attached animations), finale timed so rockets (~1.2 s flight,
    /// 0.28 s stagger from 1.4 s) burst as the message parks around 4.8 s,
    /// with the haptic flourish landing on the park.
    ///
    /// Re-arriving at Home within `BirthdayEasterEgg.showCooldown` is a no-op:
    /// the message stays parked and the ambient show carries on, so twenty app
    /// switches on the day don't mean twenty finales. `force` skips the
    /// cooldown for the Guide's manual trigger, which is someone explicitly
    /// asking to see the show right now.
    func beginShow(force: Bool = false) {
        guard force || BirthdayEasterEgg.shouldRestartShow(lastShownAt: lastShowAt) else { return }
        lastShowAt = Date()
        messageRisen = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.messageRisen = true
        }
        engine.finale(startingIn: 1.4)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.7) { [weak self] in
            self?.haptics.finaleFlourish()
        }
    }

    /// Called when Home goes away or the scene leaves the foreground: the spin
    /// rumble is a looping haptic player and must not be left running.
    func suspend() {
        haptics.stopSpin()
    }
}

// MARK: - The disco ball (replaces StartRingButton on the day)

/// The mirror ball in the ring's 340pt slot. Tap = START (same contract as
/// `StartRingButton`); long-press = manual finale; horizontal drag grabs the
/// ball — flick to spin it up, hold to stop it, and the motor eases it back
/// to house speed after release (DiscoBallSpin).
struct DiscoBallStartButton: View {
    var side: CGFloat = 340
    let controller: BirthdayShowController
    let startAction: () -> Void

    /// Sphere radius in points — must match drawBall's `R` for the 340 slot.
    private var ballRadius: Double { Double(side) * 0.36 }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(controller.epoch)
                // The spin and the sway are integrated once per frame in
                // BirthdaySkyView — the full-screen layer that is always on
                // screen — so this canvas only reads them. Stepping here left
                // the sky's light spots reading whatever angle they happened to
                // see, and tied the physics to the ball's own draw pass.
                Self.drawBall(&ctx, size: size, t: t, angle: controller.spin.angle,
                              omega: controller.spin.omega,
                              swayX: controller.swing.offsetX,
                              rise: controller.swing.verticalRise(
                                        pendulumLength: controller.pendulumLength),
                              flashLights: Self.flashLights(for: controller, at: t))
            }
        }
        .frame(width: side, height: side)
        .contentShape(Circle())
        .onTapGesture { startAction() }
        // 0.7 s, not 0.5: a deliberate slow press meant for START was firing
        // the finale and never starting the workout.
        .onLongPressGesture(minimumDuration: 0.7) {
            controller.engine.finale()
            // the first shell is ~1.3 s of flight away — acknowledge the press
            controller.haptics.burst(strength: 0.3,
                                     at: Date().timeIntervalSince(controller.epoch))
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    controller.spin.dragChanged(
                        x: value.location.x,
                        time: value.time.timeIntervalSince(controller.epoch),
                        radius: ballRadius)
                }
                .onEnded { value in
                    controller.spin.dragEnded(velocityX: value.velocity.width,
                                              radius: ballRadius)
                    // a flick shoves the ball as well as spinning it
                    controller.swing.kick(velocityX: value.velocity.width)
                }
        )
        .accessibilityLabel("Start workout")
        .accessibilityHint("Long press for fireworks")
        .accessibilityAddTraits(.isButton)
    }

    // Fixed "room lights". A facet glints only while its mirror reflection of
    // the view ray lines up with one — flashes sweep in arcs as the ball
    // turns, which is the real mechanism (random twinkle reads as cartoon).
    private static let roomLights: [(dir: Vec3, color: RGB)] = [
        (Vec3(x: -0.60, y: 0.50, z: 0.60), bdayWarm),
        (Vec3(x: 0.55, y: 0.60, z: 0.55), bdayWarm),
        (Vec3(x: -0.20, y: 0.15, z: 0.95), bdayWarm),
        (Vec3(x: 0.30, y: -0.35, z: 0.90), bdayWarm),
        (Vec3(x: -0.35, y: -0.30, z: 0.85), bdayWarm),
        (Vec3(x: 0.05, y: 0.90, z: 0.40), bdayWarm),
        (Vec3(x: 0.85, y: 0.10, z: 0.50), RGB(r: 0.784, g: 0.863, b: 1.0)),  // faint cool
        (Vec3(x: -0.85, y: 0.05, z: 0.50), RGB(r: 1.0, g: 0.745, b: 0.863)), // faint pink
        (Vec3(x: 0.70, y: 0.30, z: -0.10), bdayWarm),                        // rim catchers
        (Vec3(x: -0.65, y: -0.15, z: -0.15), bdayWarm),
    ].map { (dir: $0.0.normalized(), color: $0.1) }

    /// Firework bursts as live light sources for the ball. Direction runs
    /// from the ball's centre to the burst (both in the sky canvas's space,
    /// same space as ballFrame), pushed forward (+z) so the reflection sits
    /// inside the rim facing the burst — the same half-vector model as the
    /// room lights. Intensity fades over the flash's life.
    private static func flashLights(for controller: BirthdayShowController, at t: Double)
        -> [(dir: Vec3, color: RGB, intensity: Double)] {
        let frame = controller.ballFrame
        guard frame != .zero else { return [] }
        let cx = Double(frame.midX) + controller.swing.offsetX
        let cy = Double(frame.midY)
        var lights: [(dir: Vec3, color: RGB, intensity: Double)] = []
        for flash in controller.engine.flashes {
            let k = (t - flash.birth) / FireworkEngine.flashLife
            guard k >= 0, k < 1 else { continue }
            let dx = flash.x - cx
            let dy = flash.y - cy
            let planar = max(1, (dx * dx + dy * dy).squareRoot())
            lights.append((dir: Vec3(x: dx, y: -dy, z: 0.45 * planar).normalized(),
                           color: flash.color,
                           intensity: pow(1 - k, 1.2)))
        }
        return lights
    }

    private static let keyLight = Vec3(x: -0.45, y: 0.55, z: 0.75).normalized()
    private static let halfVec: Vec3 = {
        let l = keyLight
        return Vec3(x: l.x, y: l.y, z: l.z + 1).normalized()
    }()
    private static let sidePink = Vec3(x: -0.85, y: -0.05, z: 0.5).normalized()
    private static let sideBlue = Vec3(x: 0.85, y: -0.05, z: 0.5).normalized()

    fileprivate static func drawBall(_ ctx: inout GraphicsContext, size: CGSize,
                                     t: Double, angle: Double,
                                     omega: Double = DiscoBallSpin.defaultOmega,
                                     swayX: Double = 0, rise: Double = 0,
                                     flashLights: [(dir: Vec3, color: RGB, intensity: Double)] = []) {
        // The 340 pt slot leaves ~47 pt of margin around the sphere, so the
        // sway never clips.
        let cx = Double(size.width) / 2 + swayX
        let cy = Double(size.height) / 2 - rise
        let R = Double(min(size.width, size.height)) * 0.36
        let rot = angle                        // integrated by DiscoBallSpin
        // Motion smear: at the 10 rad/s flick cap the facet grid strobes and
        // the glints stutter. Fading facet contrast, widening the glint cone
        // and streaking the blooms tangentially reads as blur instead of
        // jitter. Zero at house speed, full by ~6.6 rad/s.
        let smear = min(1, max(0, (abs(omega) - 1.6) / 5.0))
        // locked at max, widened by smear. Kept to ×2 deliberately: the cone
        // sets how many facets flash at once, and each flash costs bloom fills
        // that are then multiplied by the smear copies below — exactly during
        // the flick that has to stay smooth.
        let cone = 1 - 0.0035 * 3.0 * (1 + 2 * smear)
        let center = CGPoint(x: cx, y: cy)
        let ballRect = CGRect(x: cx - R, y: cy - R, width: 2 * R, height: 2 * R)

        // dark sphere base
        ctx.fill(Path(ellipseIn: ballRect), with: .radialGradient(
            Gradient(colors: [Color(red: 0.23, green: 0.23, blue: 0.26),
                              Color(red: 0.05, green: 0.05, blue: 0.06)]),
            center: CGPoint(x: cx - R * 0.35, y: cy - R * 0.4),
            startRadius: R * 0.1, endRadius: R * 1.5))

        var glints: [(x: Double, y: Double, s: Double, color: RGB)] = []
        let bands = 16

        for b in 0..<bands {
            let th = -Double.pi / 2 + (Double(b) + 0.5) * .pi / Double(bands)
            let dth = Double.pi / Double(bands)
            let count = max(4, Int((cos(th) * 36).rounded()))
            let dph = 2 * Double.pi / Double(count)
            for k in 0..<count {
                let ph = Double(k) * dph + rot
                let n = Vec3(x: cos(th) * sin(ph), y: sin(th), z: cos(th) * cos(ph))
                if n.z <= 0.02 { continue }

                let h = bdayHash(Double(b), Double(k))
                let h2 = bdayHash(Double(k + 7), Double(b + 13))
                let diff = max(0, n.dot(keyLight))
                let tintA = pow(max(0, n.dot(sidePink)), 2)
                let tintB = pow(max(0, n.dot(sideBlue)), 2)
                let spec = pow(max(0, n.dot(halfVec)), 42) * (0.7 + 0.6 * h)
                    * (1 - 0.55 * smear)
                let shimmer = 0.9 + 0.18 * (1 - 0.7 * smear)
                    * sin(ph * 3 + t * 2 + h * 6.28)

                // true mirror reflection of the view ray (0,0,1) around n
                let refl = Vec3(x: 2 * n.z * n.x, y: 2 * n.z * n.y, z: 2 * n.z * n.z - 1)
                var flash = 0.0
                var flashColor = bdayWarm
                var burstFlash = 0.0
                var burstColor = bdayPink
                if h2 > 0.12 {                 // some facets are dull mirrors
                    for light in roomLights {
                        let a = refl.dot(light.dir)
                        if a > cone {
                            let s = ((a - cone) / (1 - cone)) * (0.6 + 0.7 * h2)
                            if s > flash { flash = min(1, s); flashColor = light.color }
                        }
                    }
                    // firework bursts reflect too — an extended source, so a
                    // much wider cone. Tracked separately from the room
                    // lights: lifting toward white hid them among the
                    // ordinary glints, so burst facets take the burst COLOUR.
                    for light in flashLights {
                        let a = refl.dot(light.dir)
                        let burstCone = 0.90
                        if a > burstCone {
                            let s = ((a - burstCone) / (1 - burstCone))
                                * light.intensity * (0.6 + 0.6 * h2)
                            if s > burstFlash { burstFlash = min(1, s); burstColor = light.color }
                        }
                    }
                }

                let v = (0.133 + 0.588 * diff) * shimmer
                var r = v + bdayPink.r * tintA * 0.35 + bdayBlue.r * tintB * 0.35
                var g = v + bdayPink.g * tintA * 0.35 + bdayBlue.g * tintB * 0.35
                var bl = v + bdayPink.b * tintA * 0.35 + bdayBlue.b * tintB * 0.35
                // colored wash on the side of the ball facing a burst
                for light in flashLights {
                    let d = max(0, n.dot(light.dir))
                    let wash = d * d * 0.30 * light.intensity
                    r += light.color.r * wash
                    g += light.color.g * wash
                    bl += light.color.b * wash
                }
                // lerp toward white so bright tiles keep their shading
                let lift = max(spec > 0.4 ? spec : 0, flash)
                if lift > 0 {
                    r += (1 - r) * lift; g += (1 - g) * lift; bl += (1 - bl) * lift
                }
                // burst reflections lerp toward the burst colour half-lifted
                // to white — bright enough to read as a glint, coloured
                // enough to unmistakably be the firework
                if burstFlash > 0 {
                    let cr = burstColor.r + (1 - burstColor.r) * 0.5
                    let cg = burstColor.g + (1 - burstColor.g) * 0.5
                    let cb = burstColor.b + (1 - burstColor.b) * 0.5
                    r += (cr - r) * burstFlash
                    g += (cg - g) * burstFlash
                    bl += (cb - bl) * burstFlash
                }

                // facet quad, inset for grout gaps
                var path = Path()
                let corners: [(Double, Double)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
                for (ci, corner) in corners.enumerated() {
                    let tt = th + corner.0 * dth * 0.42
                    let pp = ph + corner.1 * dph * 0.42
                    let px = cx + R * cos(tt) * sin(pp)
                    let py = cy - R * sin(tt)
                    if ci == 0 { path.move(to: CGPoint(x: px, y: py)) }
                    else { path.addLine(to: CGPoint(x: px, y: py)) }
                }
                path.closeSubpath()
                ctx.fill(path, with: .color(Color(red: min(1, r), green: min(1, g), blue: min(1, bl))))

                if spec > 0.75 {
                    glints.append((cx + R * n.x, cy - R * n.y, min(1, spec), bdayWarm))
                }
                if flash > 0.2 {
                    glints.append((cx + R * n.x, cy - R * n.y, flash, flashColor))
                }
                if burstFlash > 0.15 {
                    glints.append((cx + R * n.x, cy - R * n.y, burstFlash, burstColor))
                }
            }
        }

        // curvature shading + static key-light bloom
        ctx.fill(Path(ellipseIn: ballRect), with: .radialGradient(
            Gradient(stops: [.init(color: .black.opacity(0), location: 0.45),
                             .init(color: .black.opacity(0.55), location: 1)]),
            center: center, startRadius: 0, endRadius: R))

        ctx.blendMode = .plusLighter
        let bloomCenter = CGPoint(x: cx - R * 0.38, y: cy - R * 0.42)
        ctx.fill(Path(ellipseIn: ballRect), with: .radialGradient(
            Gradient(colors: [.white.opacity(0.30), .white.opacity(0)]),
            center: bloomCenter, startRadius: 0, endRadius: R * 0.55))

        // glints as points of light: hot core + soft bloom, faint streak only
        // on the very brightest (camera veiling glare) — no drawn star shapes
        // A spinning ball's facets travel horizontally, so the smear is drawn
        // as copies displaced along x at a divided alpha — a real motion blur
        // in the only direction the surface actually moves.
        let smearSteps: [Double] = smear > 0.05 ? [-1, 0, 1] : [0]
        let smearSpan = R * 0.16 * smear
        let smearAlpha = 1.0 / Double(smearSteps.count)
        for glint in glints {
            let (gx, gy, s, col) = glint
            let rad = R * (0.05 + 0.09 * s)
            for step in smearSteps {
                let x = gx + step * smearSpan
                ctx.fill(Path(ellipseIn: CGRect(x: x - rad, y: gy - rad,
                                                width: 2 * rad, height: 2 * rad)),
                         with: .radialGradient(
                            Gradient(stops: [.init(color: col.color(0.70 * s * smearAlpha), location: 0),
                                             .init(color: col.color(0.25 * s * smearAlpha), location: 0.35),
                                             .init(color: col.color(0), location: 1)]),
                            center: CGPoint(x: x, y: gy), startRadius: 0, endRadius: rad))
            }
            // the hot core survives the smear but stretches into a short dash
            let coreR = 1.2 + s * 1.1
            let coreHalfWidth = coreR + smearSpan * 0.5
            ctx.fill(Path(roundedRect: CGRect(x: gx - coreHalfWidth, y: gy - coreR,
                                              width: 2 * coreHalfWidth, height: 2 * coreR),
                          cornerRadius: coreR),
                     with: .color(.white.opacity(min(1, s * 1.1) * (1 - 0.35 * smear))))
            if s > 0.75 {
                let len = R * 0.9 * (s - 0.75)
                ctx.fill(Path(CGRect(x: gx - len, y: gy - 0.7, width: 2 * len, height: 1.4)),
                         with: .linearGradient(
                            Gradient(stops: [.init(color: .white.opacity(0), location: 0),
                                             .init(color: .white.opacity(0.28 * s), location: 0.5),
                                             .init(color: .white.opacity(0), location: 1)]),
                            startPoint: CGPoint(x: gx - len, y: gy),
                            endPoint: CGPoint(x: gx + len, y: gy)))
                let vlen = len * 0.55
                ctx.fill(Path(CGRect(x: gx - 0.7, y: gy - vlen, width: 1.4, height: 2 * vlen)),
                         with: .linearGradient(
                            Gradient(stops: [.init(color: .white.opacity(0), location: 0),
                                             .init(color: .white.opacity(0.22 * s), location: 0.5),
                                             .init(color: .white.opacity(0), location: 1)]),
                            startPoint: CGPoint(x: gx, y: gy - vlen),
                            endPoint: CGPoint(x: gx, y: gy + vlen)))
            }
        }
        ctx.blendMode = .normal

        // The cap and eyelet the wire hangs from. Without them the wire simply
        // vanishes into the sphere and the ball reads as pinned to the screen.
        let capW = R * 0.22, capH = R * 0.13
        let capRect = CGRect(x: cx - capW / 2, y: cy - R - capH * 0.5,
                             width: capW, height: capH)
        ctx.fill(Path(roundedRect: capRect, cornerRadius: capH * 0.35),
                 with: .linearGradient(
                    Gradient(colors: [Color(red: 0.52, green: 0.53, blue: 0.58),
                                      Color(red: 0.16, green: 0.16, blue: 0.19)]),
                    startPoint: CGPoint(x: capRect.minX, y: capRect.minY),
                    endPoint: CGPoint(x: capRect.maxX, y: capRect.maxY)))
        let ringR = R * 0.05
        ctx.stroke(Path(ellipseIn: CGRect(x: cx - ringR, y: capRect.minY - ringR * 1.4,
                                          width: 2 * ringR, height: 2 * ringR)),
                   with: .color(Color(red: 0.42, green: 0.43, blue: 0.47)),
                   lineWidth: max(1, R * 0.018))
    }
}

// MARK: - Full-screen sky layer (fireworks, light spots, beams, wire)

/// Wandering reflections thrown by the ball; deterministic per index. Shared by
/// the sky layer (behind the cards) and the spill layer (in front of them), so
/// a single spot appears to travel across the whole room.
private let bdayRoomSpots: [(phi: Double, y: Double, r: Double, pink: Bool)] = {
    var result: [(phi: Double, y: Double, r: Double, pink: Bool)] = []
    for i in 0..<16 {
        let phi = bdayHash(Double(i), 1) * 2 * Double.pi
        let y = 0.12 + bdayHash(Double(i), 2) * 0.75
        let r = 5.0 + bdayHash(Double(i), 3) * 9
        result.append((phi: phi, y: y, r: r, pink: i % 2 == 0))
    }
    return result
}()

/// Total live burst light, 0…n — used to make the room react to the fireworks
/// rather than only the ball.
private func bdayBurstGlow(_ engine: FireworkEngine, at t: Double) -> Double {
    var glow = 0.0
    for flash in engine.flashes {
        let k = (t - flash.birth) / FireworkEngine.flashLife
        guard k >= 0, k < 1 else { continue }
        glow += pow(1 - k, 1.6)
    }
    return min(1.6, glow)
}

/// Sits behind the home content (`allowsHitTesting(false)`), so cards and
/// buttons keep working; fireworks pass behind the ball and the cards.
struct BirthdaySkyView: View {
    @ObservedObject var controller: BirthdayShowController

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(controller.epoch)
                // This layer owns the clock: it is always full-screen and
                // always present on the day, so the spin, the sway and the
                // particles all advance here exactly once per frame. The ball's
                // own canvas only reads the results.
                controller.spin.step(now: t)
                controller.swing.step(now: t)
                controller.engine.step(now: t, in: size)
                controller.haptics.spin(omega: controller.spin.omega,
                                        grabbed: controller.spin.isGrabbed, at: t)
                Self.draw(&ctx, size: size, t: t,
                          engine: controller.engine,
                          ballFrame: controller.ballFrame,
                          spinAngle: controller.spin.angle,
                          swayX: controller.swing.offsetX,
                          rise: controller.swing.verticalRise(
                                    pendulumLength: controller.pendulumLength))
            }
        }
        .allowsHitTesting(false)
        .onDisappear { controller.suspend() }
    }

    private static func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double,
                             engine: FireworkEngine, ballFrame: CGRect,
                             spinAngle: Double, swayX: Double, rise: Double) {
        let w = Double(size.width), h = Double(size.height)
        // the room reflections are thrown by the ball, so they follow its
        // actual rotation — spin it up or stop it and the spots do the same
        let rot = spinAngle
        let burstGlow = bdayBurstGlow(engine, at: t)

        // light spots wandering the room. Dimmer than they used to be because
        // BirthdayLightSpillView now draws the same spots *in front of* the
        // cards; the two together are what make one spot cross the whole room.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            layer.blendMode = .plusLighter
            for spot in bdayRoomSpots {
                let ph = spot.phi + rot
                let vis = cos(ph)
                if vis <= 0 { continue }
                let col = spot.pink ? bdayPink : bdayBlue
                let x = w / 2 + sin(ph) * w * 0.55
                layer.fill(
                    Path(ellipseIn: CGRect(x: x - spot.r, y: spot.y * h - spot.r,
                                           width: 2 * spot.r, height: 2 * spot.r)),
                    with: .color(col.color(vis * 0.07)))
            }
        }

        // burst smoke: soft, non-additive, drifting up as it thins. Drawn
        // before the sparks so fresh sparks read through their own smoke.
        for puff in engine.smoke {
            let age = (t - puff.birth) / FireworkEngine.smokeLife
            guard age >= 0, age < 1 else { continue }
            let r = puff.radius * (1 + 3.5 * age)
            let y = puff.y - age * 26
            let alpha = 0.16 * (1 - age) * (1 - age)
            ctx.fill(Path(ellipseIn: CGRect(x: puff.x - r, y: y - r,
                                            width: 2 * r, height: 2 * r)),
                     with: .radialGradient(
                        Gradient(colors: [puff.color.color(alpha),
                                          puff.color.color(0)]),
                        center: CGPoint(x: puff.x, y: y),
                        startRadius: 0, endRadius: r))
        }

        // fireworks (behind ball by layer order: sky < home content)
        ctx.blendMode = .plusLighter
        for rocket in engine.rockets {
            if rocket.trail.count > 1 {
                var path = Path()
                path.move(to: rocket.trail[0])
                for p in rocket.trail.dropFirst() { path.addLine(to: p) }
                ctx.stroke(path, with: .color(Color(red: 1, green: 0.86, blue: 0.67).opacity(0.35)),
                           lineWidth: 1.6)
            }
            let hr = 1.8
            ctx.fill(Path(ellipseIn: CGRect(x: rocket.x - hr, y: rocket.y - hr,
                                            width: 2 * hr, height: 2 * hr)),
                     with: .color(Color(red: 1, green: 0.86, blue: 0.67).opacity(0.9)))
        }
        for spark in engine.sparks {
            var a = pow(1 - spark.age / spark.life, 1.4)
            if spark.twinkle > 0 {
                a *= 0.55 + 0.45 * sin(t * spark.twinkle + spark.x)
            }
            // short motion streak instead of the mockup's persistent trail
            var streak = Path()
            streak.move(to: CGPoint(x: spark.x - spark.vx * 0.06, y: spark.y - spark.vy * 0.06))
            streak.addLine(to: CGPoint(x: spark.x, y: spark.y))
            ctx.stroke(streak, with: .color(spark.color.color(a * 0.5)), lineWidth: spark.size)
            ctx.fill(Path(ellipseIn: CGRect(x: spark.x - spark.size, y: spark.y - spark.size,
                                            width: 2 * spark.size, height: 2 * spark.size)),
                     with: .color(spark.color.color(a)))
        }
        ctx.blendMode = .normal

        guard ballFrame != .zero else { return }
        // the wire hangs from a fixed anchor; the ball itself swings under it
        let anchorX = Double(ballFrame.midX)
        let bx = anchorX + swayX
        let by = Double(ballFrame.midY) - rise
        let R = Double(min(ballFrame.width, ballFrame.height)) * 0.36

        // floor beams — same language as the chrome ring (pink left, blue
        // right). They brighten with the live bursts: a shell that lights the
        // ball has to light the room too, or the ball reads as the only real
        // object on screen.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 12))
            for (dx, col) in [(-0.19, bdayPink), (0.19, bdayBlue)] {
                let beamX = anchorX + dx * w
                let beamTop = by + R + h * 0.05
                let peak = min(0.85, 0.5 + 0.28 * burstGlow)
                layer.fill(
                    Path(roundedRect: CGRect(x: beamX - w * 0.055, y: beamTop,
                                             width: w * 0.11, height: h * 0.24),
                         cornerRadius: w * 0.05),
                    with: .linearGradient(
                        Gradient(colors: [col.color(peak), col.color(0)]),
                        startPoint: CGPoint(x: beamX, y: beamTop),
                        endPoint: CGPoint(x: beamX, y: beamTop + h * 0.24)))
            }
        }

        // hanging wire, screen top to the swung ball's cap — it tilts with the
        // sway, which is most of what sells the ball as hanging
        var wire = Path()
        wire.move(to: CGPoint(x: anchorX, y: 0))
        wire.addLine(to: CGPoint(x: bx, y: by - R))
        ctx.stroke(wire, with: .color(Color(red: 0.15, green: 0.15, blue: 0.18)), lineWidth: 2)
    }
}

// MARK: - Light spill layer (in front of the cards)

/// The room's light landing ON the home content: the ball's reflections cross
/// the cards, and the ball itself blooms onto whatever sits next to it. Sits
/// above `homeContent` and below the message, never intercepts touches.
///
/// This is the other half of `BirthdaySkyView`'s spots — without it the
/// reflections vanish the moment they reach a card, which is what made the
/// cards read as cut out of the scene.
struct BirthdayLightSpillView: View {
    @ObservedObject var controller: BirthdayShowController

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(controller.epoch)
                Self.draw(&ctx, size: size, t: t,
                          engine: controller.engine,
                          ballFrame: controller.ballFrame,
                          spinAngle: controller.spin.angle,
                          swayX: controller.swing.offsetX)
            }
        }
        .allowsHitTesting(false)
    }

    private static func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double,
                             engine: FireworkEngine, ballFrame: CGRect,
                             spinAngle: Double, swayX: Double) {
        let w = Double(size.width), h = Double(size.height)
        let burstGlow = bdayBurstGlow(engine, at: t)
        let bx = Double(ballFrame.midX) + swayX
        let by = Double(ballFrame.midY)
        let R = Double(min(ballFrame.width, ballFrame.height)) * 0.36
        // Nothing this layer draws may land on the ball: it is all light the
        // ball itself is throwing.
        let sphere = ballFrame == .zero
            ? nil
            : Path(ellipseIn: CGRect(x: bx - R, y: by - R, width: 2 * R, height: 2 * R))

        ctx.drawLayer { layer in
            if let sphere { layer.clip(to: sphere, options: .inverse) }
            layer.addFilter(.blur(radius: 9))
            layer.blendMode = .plusLighter
            for spot in bdayRoomSpots {
                let ph = spot.phi + spinAngle
                let vis = cos(ph)
                if vis <= 0 { continue }
                let col = spot.pink ? bdayPink : bdayBlue
                let x = w / 2 + sin(ph) * w * 0.55
                let r = spot.r * 1.15
                layer.fill(
                    Path(ellipseIn: CGRect(x: x - r, y: spot.y * h - r,
                                           width: 2 * r, height: 2 * r)),
                    with: .color(col.color(vis * 0.06)))
            }
        }

        guard let sphere else { return }

        // The ball's own bloom onto the neighbouring cards, pumped by bursts.
        // Clipped OUT of the sphere for the same reason: laying it over the ball
        // washed the facets pale (seen on the simulator during the first run of
        // this code — the sphere lost its dark base entirely).
        let spillR = R * 2.1
        let peak = 0.05 + 0.07 * burstGlow
        ctx.drawLayer { layer in
            layer.clip(to: sphere, options: .inverse)
            layer.blendMode = .plusLighter
            layer.fill(Path(ellipseIn: CGRect(x: bx - spillR, y: by - spillR,
                                              width: 2 * spillR, height: 2 * spillR)),
                       with: .radialGradient(
                        Gradient(stops: [.init(color: bdayBlush.color(peak), location: 0),
                                         .init(color: bdayPink.color(peak * 0.55), location: 0.5),
                                         .init(color: bdayPink.color(0), location: 1)]),
                        center: CGPoint(x: bx, y: by),
                        startRadius: R * 0.95, endRadius: spillR))
        }
    }
}

// MARK: - Birthday message

/// "Happy Birthday 🫧!" — rises once from the bottom, parks near the top.
/// Rendered above the home content; never intercepts touches.
struct BirthdayMessageView: View {
    @ObservedObject var controller: BirthdayShowController

    private var gradient: LinearGradient {
        LinearGradient(colors: [bdayBlush.color(), bdayPink.color(), bdayBlue.color()],
                       startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        GeometryReader { geo in
            let risen = controller.messageRisen
            (Text("Happy Birthday ").foregroundStyle(gradient) + Text("🫧")
                + Text("!").foregroundStyle(gradient))
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .lineLimit(1)
                // 28 pt heavy rounded doesn't fit 320 pt of SE width; without
                // this it truncates to "Happy Birth…" on exactly the screen
                // that matters most.
                .minimumScaleFactor(0.7)
                .shadow(color: bdayPink.color(0.5), radius: 14)
                .scaleEffect(risen ? 1 : 0.3)
                .position(x: geo.size.width / 2,
                          y: risen ? parkedY(in: geo.size) : geo.size.height * 0.9)
                .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 4).delay(0.8), value: risen)
                .opacity(risen ? 1 : 0)
                .animation(.easeIn(duration: 0.6).delay(0.8), value: risen)
        }
        .allowsHitTesting(false)
    }

    /// Parks just above the sphere's top edge. The ball is R = 0.36 × the
    /// slot's short side, centred in the slot, so the slot's minY is well
    /// above the visible ball — compute from the sphere, not the frame.
    /// 48 pt of clearance leaves ~30 pt of daylight under the descenders and
    /// the glow (device-checked 2026-07-23: 30 pt read as overlapping).
    /// Clamped so it can't ride up under the streak header; falls back to a
    /// fixed height until layout has reported the frame.
    private func parkedY(in size: CGSize) -> CGFloat {
        let frame = controller.ballFrame
        guard frame != .zero else { return size.height * 0.16 }
        let r = min(frame.width, frame.height) * 0.36
        return max(frame.midY - r - 48, size.height * 0.10)
    }
}

// MARK: - Morning nudges (UserNotifications half of BirthdayActivation)

extension BirthdayEasterEgg {
    /// Two yearly repeating 06:00 notifications: 2 August for everyone, and the
    /// user's own birthday once HealthKit has told us when that is. The show
    /// only runs on the Home screen, so without a nudge a phone that stays in a
    /// pocket all day means the egg never happens at all.
    ///
    /// Never requests permission — call sites must already have it (per
    /// AGENTS.md, from inside `refreshNotificationPermissionState`'s completion).
    /// Re-registering the same identifier replaces the pending request, so this
    /// is safe to call on every foreground.
    static func scheduleMorningNudges(userBirthday: (month: Int, day: Int)? =
                                        cachedUserBirthday()) {
        let center = UNUserNotificationCenter.current()

        let hers = UNMutableNotificationContent()
        hers.title = "Hey, 🫧 - Open N4x4"
        hers.sound = .default
        center.add(UNNotificationRequest(
            identifier: hersNudgeIdentifier,
            content: hers,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: nudgeComponents(month: herMonth, day: herDay),
                repeats: true))) { error in
            if let error { print("Birthday nudge (2 Aug) failed: \(error.localizedDescription)") }
        }

        guard let own = userBirthday else { return }
        guard needsOwnNudge(month: own.month, day: own.day) else {
            // their birthday IS 2 August — one notification, not two
            center.removePendingNotificationRequests(withIdentifiers: [usersNudgeIdentifier])
            return
        }
        let theirs = UNMutableNotificationContent()
        theirs.title = "Happy Birthday! 🎉"
        theirs.body = "Open N4x4 - there's something for you today."
        theirs.sound = .default
        center.add(UNNotificationRequest(
            identifier: usersNudgeIdentifier,
            content: theirs,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: nudgeComponents(month: own.month, day: own.day),
                repeats: true))) { error in
            if let error { print("Birthday nudge (user) failed: \(error.localizedDescription)") }
        }
    }
}

// MARK: - Ball frame preference

struct BirthdayBallFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        // Only the ball sets this preference; every other subtree contributes
        // the .zero default. Keep the real frame instead of letting a later
        // sibling's default overwrite it (device-checked 2026-07-23: blind
        // assignment left ballFrame at .zero — no parked message tracking,
        // no wire/beams, no burst reflections).
        let next = nextValue()
        if next != .zero { value = next }
    }
}
