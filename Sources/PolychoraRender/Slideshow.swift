import Foundation
import simd
import PolytopeKit

/// Everything the renderer and overlay need for one frame.
public struct FrameState {
    public var kind: PolytopeKind
    public var rotation: Mat4
    /// 0 = flat polytope in perspective projection, 1 = stereographic.
    public var stereo: Double
    /// Global visibility for transitions, 0…1.
    public var fade: Double
    /// Camera position from the viewing distance (0) to the projection centre (1).
    public var approach: Double = 0
    /// Panorama yaw at the projection centre, radians.
    public var yaw: Double = 0
    public var stage: Stage = .view
    /// Cell highlighting: the integer part picks the highlighted Hopf ring (modulo the ring count),
    /// the fraction drives the hand-over to the next. Advances only while the polytope rotates,
    /// independent of the speed dials.
    public var highlight: Double = 0

    /// What the phase indicator shows; changes on events (spin-down done, withdraw done, morph start)
    /// rather than tracking the numbers.
    public enum Stage: Sendable { case view, flyThrough, transition }

    public var projectionLabel: String {
        switch stereo {
        case ..<0.001: return "perspective projection"
        case 0.999...: return "stereographic projection"
        default: return "perspective → stereographic"
        }
    }

    public var phaseLabel: String {
        switch stage {
        case .view: return projectionLabel
        case .flyThrough: return (stereo < 0.5 ? "perspective" : "stereographic") + " fly-through"
        case .transition: return "perspective → stereographic"
        }
    }
}

/// Per polytope: [fade in] [rotate] [fly-through?] [morph] [rotate] [fly-through?] [fade out].
/// With a fixed projection the morph is replaced by a second rotate and the last fly-through is dropped.
/// A fly-through stops the rotation, moves the camera to the projection centre, pans 360°, and
/// withdraws along the same path; rotation spins back up in the following phase.
public final class Slideshow {
    public var settings: PolychoraSettings { didSet { rebuildOrder() } }

    /// Durations with every speed at 1.
    private enum Base {
        static let hold = 36.0, morph = 5.0, fade = 3.0
        static let spin = 2.0
        static let approach = 9.0, panorama = 36.0, withdraw = 9.0
    }

    private struct Durations {
        let hold, fade, morph, spin, approach, panorama, withdraw: Double
        var fly: Double { spin + approach + panorama + withdraw }
    }

    /// Animation speed scales the still-camera phases (hold, fades, morph); pan speed the panorama; motion speed the
    /// camera travel. Spin-up/down use angular acceleration ∝ √ω, so they last ∝ ω/√ω = √(rotation speed).
    private var durations: Durations {
        let a = 1 / settings.animationSpeed, m = 1 / settings.motionSpeed
        return Durations(hold: Base.hold * a, fade: Base.fade * a, morph: Base.morph * a,
                         spin: Base.spin * max(settings.speed, 0.01).squareRoot(),
                         approach: Base.approach * m, panorama: Base.panorama / settings.panSpeed,
                         withdraw: Base.withdraw * m)
    }
    /// Seconds for the natural rotation to advance by one symmetry period at speed 1.
    public let periodSeconds = 15.0
    /// Seconds each Hopf ring (or 5-cell cell) stays highlighted.
    public let highlightSeconds = 6.0

    private(set) public var timelineTime: Double = 0
    private(set) public var rotationTime: Double = 0
    /// Seconds of rotation at full spin, regardless of the speed dials: the highlight clock, which
    /// pauses whenever the polytope stops (fly-through, including the pan).
    private(set) public var highlightTime: Double = 0
    private var order: [PolytopeKind] = []
    private var offset = 0
    private var stereoOverride: Double?
    private var cameraOverride: (approach: Double, yaw: Double)?

    public init(settings: PolychoraSettings, randomStart: Bool = true) {
        self.settings = settings
        rebuildOrder()
        if randomStart { offset = Int.random(in: 0..<order.count) }
    }

    private func rebuildOrder() {
        order = settings.polytope.map { [$0] } ?? PolytopeKind.allCases
        offset %= max(order.count, 1)
    }

    // MARK: Phases

    private enum Kind { case fadeIn, rotate, morph, fly, fadeOut }
    private struct Phase { let kind: Kind; let duration: Double; let stereo: Double }

    private func phases(_ kind: PolytopeKind) -> [Phase] {
        let d = durations, h = d.hold
        let fly = settings.flyThrough.applies(to: kind)
        let halfFade = d.fade / 2
        let first: Double = settings.projection == .stereographic ? 1 : 0
        var out = [Phase(kind: .fadeIn, duration: halfFade, stereo: first)]
        func view(_ s: Double, flyAfter: Bool) {
            out.append(Phase(kind: .rotate, duration: h, stereo: s))
            if fly && flyAfter { out.append(Phase(kind: .fly, duration: d.fly, stereo: s)) }
        }
        switch settings.projection {
        case .alternate:
            view(0, flyAfter: true)
            out.append(Phase(kind: .morph, duration: d.morph, stereo: 0))
            view(1, flyAfter: true)
        case .perspective, .stereographic:
            let s: Double = settings.projection == .stereographic ? 1 : 0
            view(s, flyAfter: true)
            view(s, flyAfter: false)
        }
        out.append(Phase(kind: .fadeOut, duration: halfFade, stereo: out.last!.stereo))
        return out
    }

    private func segmentLength(_ kind: PolytopeKind) -> Double { phases(kind).reduce(0) { $0 + $1.duration } }

    private struct Sample {
        var spin = 1.0, stereo = 0.0, fade = 1.0, approach = 0.0, yaw = 0.0
        var stage = FrameState.Stage.view
    }

    /// Stage once phase `kind` has completed, given the stage before it.
    private static func stage(after kind: Kind, from s: FrameState.Stage) -> FrameState.Stage {
        switch kind {
        case .fly: return .flyThrough
        case .morph: return .transition
        case .rotate: return .view
        case .fadeIn, .fadeOut: return s
        }
    }

    /// State at time `tau` into a polytope's segment.
    private func sample(_ kind: PolytopeKind, _ tau: Double) -> Sample {
        let dur = durations
        let list = phases(kind)
        var s = Sample()
        var start = 0.0
        var spinStart = 0.0
        var stage = FrameState.Stage.view
        for (i, ph) in list.enumerated() {
            let end = start + ph.duration
            if tau < end || i == list.count - 1 {
                let local = tau - start
                s.stereo = ph.stereo
                s.stage = ph.kind == .fly && local < dur.spin ? stage : Self.stage(after: ph.kind, from: stage)
                s.spin = rampUp((tau - spinStart) / dur.spin)
                switch ph.kind {
                case .fadeIn:
                    s.fade = smoothstep(0, ph.duration, local)
                case .rotate:
                    break
                case .morph:
                    s.stereo = smoothstep(0, ph.duration, local)
                case .fadeOut:
                    s.fade = 1 - smoothstep(0, ph.duration, local)
                    if i > 0, list[i - 1].kind == .fly { s.spin = 0 }
                case .fly:
                    let d = dur.spin, a = dur.approach, pano = dur.panorama, w = dur.withdraw
                    s.spin = rampDown(local / d)
                    if local < d {
                        break
                    } else if local < d + a {
                        s.approach = travel((local - d) / a)
                    } else if local < d + a + pano {
                        s.approach = 1
                        s.yaw = 2 * .pi * travel((local - d - a) / pano)
                    } else {
                        s.approach = 1 - travel((local - d - a - pano) / w)
                    }
                }
                return s
            }
            if ph.kind == .fly { spinStart = end }
            stage = Self.stage(after: ph.kind, from: stage)
            start = end
        }
        return s
    }

    // MARK: Timeline

    private var cycle: [PolytopeKind] { order.indices.map { order[($0 + offset) % order.count] } }

    /// Segment index into `cycle` and the segment's start on the timeline.
    private func locate(_ t: Double) -> (index: Int, start: Double) {
        let lens = cycle.map(segmentLength)
        let total = lens.reduce(0, +)
        var start = (t / total).rounded(.down) * total
        var i = 0
        while i < lens.count - 1, start + lens[i] <= t { start += lens[i]; i += 1 }
        return (i, start)
    }

    public func advance(by dt: Double) {
        let (i, start) = locate(timelineTime)
        let spin = sample(cycle[i], timelineTime - start).spin
        timelineTime += dt
        rotationTime += dt * settings.speed * spin
        highlightTime += dt * spin
    }

    public func seek(timeline: Double, rotation: Double, highlight: Double? = nil) {
        timelineTime = timeline
        rotationTime = rotation
        highlightTime = highlight ?? timeline
    }

    /// Jump to the next (+1) or previous (−1) polytope, fully faded in.
    public func skip(_ delta: Int) {
        let c = cycle
        let (i, start) = locate(timelineTime)
        let target = delta > 0 ? start + segmentLength(c[i])
                               : start - segmentLength(c[(i - 1 + c.count) % c.count])
        timelineTime = target + durations.fade / 2
    }

    /// Manual overrides for the preview app and snapshots; nil returns to the timeline.
    public func overrideStereo(_ s: Double?) { stereoOverride = s }
    public func overrideCamera(approach: Double, yaw: Double) { cameraOverride = (approach, yaw) }

    public func frame() -> FrameState {
        let c = cycle
        let (i, start) = locate(timelineTime)
        let kind = c[i]
        let s = sample(kind, timelineTime - start)

        let (natural, period) = kind.naturalRotation
        let angle = rotationTime * period / periodSeconds
        let t = rotationTime
        let drift = Rotation4.plane(0, 1, 0.031 * t) * Rotation4.plane(2, 3, 0.023 * t)
            * Rotation4.plane(0, 2, 0.017 * t) * Rotation4.plane(1, 3, 0.011 * t)
        let base = Rotation4.plane(0, 3, 0.6) * Rotation4.plane(1, 2, 0.4)
        return FrameState(kind: kind, rotation: drift * base * natural.matrix(angle),
                          stereo: stereoOverride ?? s.stereo, fade: s.fade,
                          approach: cameraOverride?.approach ?? s.approach,
                          yaw: cameraOverride?.yaw ?? s.yaw,
                          stage: stereoOverride == nil ? s.stage : .view,
                          highlight: highlightTime / highlightSeconds)
    }
}

func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(max((x - a) / (b - a), 0), 1)
    return t * t * (3 - 2 * t)
}

/// Cosine ease 0 → 1 over x ∈ [0, 1]; used for angular-velocity ramps.
func rampUp(_ x: Double) -> Double { x <= 0 ? 0 : x >= 1 ? 1 : (1 - cos(.pi * x)) / 2 }
func rampDown(_ x: Double) -> Double { 1 - rampUp(x) }

/// Position along a move whose velocity eases up to a constant, cruises, and eases down to rest.
/// `ramp` is the fraction of the duration spent accelerating (and again decelerating).
func travel(_ u: Double, ramp a: Double = 0.25) -> Double {
    let x = min(max(u, 0), 1)
    let vmax = 1 / (1 - a)
    func easeIn(_ x: Double) -> Double { vmax * (x / 2 - a / (2 * .pi) * sin(.pi * x / a)) }
    if x < a { return easeIn(x) }
    if x > 1 - a { return 1 - easeIn(1 - x) }
    return vmax * (a / 2 + x - a)
}
