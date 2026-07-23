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
// Choreography: every time Home appears (launch or foreground) the message
// rises and a 7-rocket finale is timed to land as it parks. Long-press the
// ball for a manual finale; tap anywhere for a single firework. Ambient
// single rockets continue all day.

import SwiftUI

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

// MARK: - Firework engine

/// Particle state for the birthday fireworks. A plain reference type mutated
/// from inside the Canvas draw closure each frame (Canvas polls it; nothing
/// observes it), so it deliberately is NOT an ObservableObject.
final class FireworkEngine {
    fileprivate struct Rocket {
        var x: Double, y: Double, vx: Double, vy: Double
        var color: RGB
        var trail: [CGPoint] = []
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

    fileprivate private(set) var rockets: [Rocket] = []
    fileprivate private(set) var sparks: [Spark] = []
    fileprivate private(set) var flashes: [Flash] = []
    private var pendingLaunches: [Double] = []     // seconds until lift-off
    private var autoTimer: Double = 0
    private var lastTime: Double?
    private var bounds: CGSize = .zero

    /// One rocket. Pass a point to burst near it (tap-to-launch); with no
    /// arguments the launch column and apex are random.
    func launch(at point: CGPoint? = nil) {
        let w = Double(bounds.width), h = Double(bounds.height)
        guard w > 0, h > 0 else { return }
        let s = h / 780
        let x = point.map { Double($0.x) } ?? Double.random(in: (w * 0.15)...(w * 0.85))
        // apex band sits above the ball's top (~0.23 h) so most bursts open
        // in clear sky instead of behind the sphere
        let targetY = point.map { Double($0.y) } ?? Double.random(in: (h * 0.05)...(h * 0.22))
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

    /// Seven staggered rockets. `startingIn` lets the opening choreography
    /// time the bursts to land as the birthday message parks.
    func finale(startingIn delay: Double = 0) {
        pendingLaunches += (0..<7).map { delay + Double($0) * 0.28 }
    }

    /// Advance the simulation to `now` (seconds, monotonic within a session).
    fileprivate func step(now: Double, in size: CGSize) {
        bounds = size
        let dt = min(0.05, lastTime.map { now - $0 } ?? 0.016)
        lastTime = now
        let s = Double(size.height) / 780
        let g = 300 * s

        // ambient single rockets, all day — it's her day
        autoTimer -= dt
        if autoTimer <= 0 {
            launch()
            autoTimer = Double.random(in: 0.9...1.7)
        }

        for i in stride(from: pendingLaunches.count - 1, through: 0, by: -1) {
            pendingLaunches[i] -= dt
            if pendingLaunches[i] <= 0 {
                pendingLaunches.remove(at: i)
                launch()
            }
        }

        for i in stride(from: rockets.count - 1, through: 0, by: -1) {
            rockets[i].x += rockets[i].vx * dt
            rockets[i].y += rockets[i].vy * dt
            rockets[i].vy += g * dt
            rockets[i].trail.append(CGPoint(x: rockets[i].x, y: rockets[i].y))
            if rockets[i].trail.count > 12 { rockets[i].trail.removeFirst() }
            if rockets[i].vy > -40 * s {
                let r = rockets.remove(at: i)
                explode(x: r.x, y: r.y, color: r.color, scale: s, now: now)
            }
        }

        flashes.removeAll { now - $0.birth > Self.flashLife }

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

    private func explode(x: Double, y: Double, color: RGB, scale s: Double, now: Double) {
        guard sparks.count < 2600 else { return }   // hard cap; never runs away
        enum Burst: CaseIterable { case peony, ring, willow, crackle }
        let type = [Burst.peony, .peony, .ring, .willow, .crackle].randomElement()!
        let n = type == .ring ? 90 : Int.random(in: 130...210)
        let base = type == .willow ? bdayBlush : color

        flashes.append(Flash(x: x, y: y, color: base, birth: now))
        if flashes.count > 5 { flashes.removeFirst(flashes.count - 5) }
        let maxV = (type == .willow ? 190.0 : 250.0) * s

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

    /// Runs the opening sequence: message rises (0.8 s delay, 4 s ease-out,
    /// view-attached animations), finale timed so rockets (~1.2 s flight,
    /// 0.28 s stagger from 1.4 s) burst as the message parks around 4.8 s.
    func beginShow() {
        messageRisen = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.messageRisen = true
        }
        engine.finale(startingIn: 1.4)
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
                controller.spin.step(now: t)
                Self.drawBall(&ctx, size: size, t: t, angle: controller.spin.angle,
                              flashLights: Self.flashLights(for: controller, at: t))
            }
        }
        .frame(width: side, height: side)
        .contentShape(Circle())
        .onTapGesture { startAction() }
        .onLongPressGesture(minimumDuration: 0.5) {
            controller.engine.finale()
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
        var lights: [(dir: Vec3, color: RGB, intensity: Double)] = []
        for flash in controller.engine.flashes {
            let k = (t - flash.birth) / FireworkEngine.flashLife
            guard k >= 0, k < 1 else { continue }
            let dx = flash.x - Double(frame.midX)
            let dy = flash.y - Double(frame.midY)
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
                                     flashLights: [(dir: Vec3, color: RGB, intensity: Double)] = []) {
        let cx = Double(size.width) / 2, cy = Double(size.height) / 2
        let R = Double(min(size.width, size.height)) * 0.36
        let rot = angle                        // integrated by DiscoBallSpin
        let cone = 1 - 0.0035 * 3.0            // locked: sparkle slider at max
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
                let shimmer = 0.9 + 0.18 * sin(ph * 3 + t * 2 + h * 6.28)

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
        for glint in glints {
            let (gx, gy, s, col) = glint
            let rad = R * (0.05 + 0.09 * s)
            ctx.fill(Path(ellipseIn: CGRect(x: gx - rad, y: gy - rad, width: 2 * rad, height: 2 * rad)),
                     with: .radialGradient(
                        Gradient(stops: [.init(color: col.color(0.70 * s), location: 0),
                                         .init(color: col.color(0.25 * s), location: 0.35),
                                         .init(color: col.color(0), location: 1)]),
                        center: CGPoint(x: gx, y: gy), startRadius: 0, endRadius: rad))
            let coreR = 1.2 + s * 1.1
            ctx.fill(Path(ellipseIn: CGRect(x: gx - coreR, y: gy - coreR, width: 2 * coreR, height: 2 * coreR)),
                     with: .color(.white.opacity(min(1, s * 1.1))))
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
    }
}

// MARK: - Full-screen sky layer (fireworks, light spots, beams, wire)

/// Sits behind the home content (`allowsHitTesting(false)`), so cards and
/// buttons keep working; fireworks pass behind the ball and the cards.
struct BirthdaySkyView: View {
    @ObservedObject var controller: BirthdayShowController

    /// Wandering reflections thrown by the ball; deterministic per index.
    private static let spots: [(phi: Double, y: Double, r: Double, pink: Bool)] = {
        var result: [(phi: Double, y: Double, r: Double, pink: Bool)] = []
        for i in 0..<16 {
            let phi = bdayHash(Double(i), 1) * 2 * Double.pi
            let y = 0.12 + bdayHash(Double(i), 2) * 0.75
            let r = 5.0 + bdayHash(Double(i), 3) * 9
            result.append((phi: phi, y: y, r: r, pink: i % 2 == 0))
        }
        return result
    }()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(controller.epoch)
                controller.engine.step(now: t, in: size)
                Self.draw(&ctx, size: size, t: t,
                          engine: controller.engine,
                          ballFrame: controller.ballFrame,
                          spinAngle: controller.spin.angle)
            }
        }
        .allowsHitTesting(false)
    }

    private static func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double,
                             engine: FireworkEngine, ballFrame: CGRect,
                             spinAngle: Double) {
        let w = Double(size.width), h = Double(size.height)
        // the room reflections are thrown by the ball, so they follow its
        // actual rotation — spin it up or stop it and the spots do the same
        let rot = spinAngle

        // light spots wandering the room
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            layer.blendMode = .plusLighter
            for spot in spots {
                let ph = spot.phi + rot
                let vis = cos(ph)
                if vis <= 0 { continue }
                let col = spot.pink ? bdayPink : bdayBlue
                let x = w / 2 + sin(ph) * w * 0.55
                layer.fill(
                    Path(ellipseIn: CGRect(x: x - spot.r, y: spot.y * h - spot.r,
                                           width: 2 * spot.r, height: 2 * spot.r)),
                    with: .color(col.color(vis * 0.10)))
            }
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
        let bx = ballFrame.midX, by = ballFrame.midY
        let R = Double(min(ballFrame.width, ballFrame.height)) * 0.36

        // floor beams — same language as the chrome ring (pink left, blue right)
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 12))
            for (dx, col) in [(-0.19, bdayPink), (0.19, bdayBlue)] {
                let beamX = Double(bx) + dx * w
                let beamTop = Double(by) + R + h * 0.05
                layer.fill(
                    Path(roundedRect: CGRect(x: beamX - w * 0.055, y: beamTop,
                                             width: w * 0.11, height: h * 0.24),
                         cornerRadius: w * 0.05),
                    with: .linearGradient(
                        Gradient(colors: [col.color(0.5), col.color(0)]),
                        startPoint: CGPoint(x: beamX, y: beamTop),
                        endPoint: CGPoint(x: beamX, y: beamTop + h * 0.24)))
            }
        }

        // hanging wire, screen top to ball top
        var wire = Path()
        wire.move(to: CGPoint(x: bx, y: 0))
        wire.addLine(to: CGPoint(x: bx, y: by - R))
        ctx.stroke(wire, with: .color(Color(red: 0.15, green: 0.15, blue: 0.18)), lineWidth: 2)
    }
}

// MARK: - Birthday message

/// "Happy birthday to 🫧" — rises once from the bottom, parks near the top.
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
            (Text("Happy birthday to ").foregroundStyle(gradient) + Text("🫧"))
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .lineLimit(1)
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
