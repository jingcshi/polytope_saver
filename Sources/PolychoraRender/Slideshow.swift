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

    public var projectionLabel: String {
        switch stereo {
        case ..<0.001: return "perspective projection"
        case 0.999...: return "stereographic projection"
        default: return "perspective → stereographic"
        }
    }
}

/// Timeline: per polytope, [hold] [morph] [hold] [cross-fade], then the next polytope.
public final class Slideshow {
    public var settings: PolychoraSettings { didSet { rebuildOrder() } }

    public let morphSeconds = 8.0
    public let fadeSeconds = 3.0
    /// Seconds for the natural rotation to advance by one symmetry period at speed 1.
    public let periodSeconds = 10.0

    private(set) public var timelineTime: Double = 0
    private(set) public var rotationTime: Double = 0
    private var order: [PolytopeKind] = []
    private var offset = 0
    private var stereoOverride: Double?

    public init(settings: PolychoraSettings, randomStart: Bool = true) {
        self.settings = settings
        rebuildOrder()
        if randomStart { offset = Int.random(in: 0..<order.count) }
    }

    private func rebuildOrder() {
        order = settings.polytope.map { [$0] } ?? PolytopeKind.allCases
        offset %= max(order.count, 1)
    }

    private var segmentLength: Double {
        let h = settings.holdSeconds
        return settings.projection == .alternate ? 2 * h + morphSeconds + fadeSeconds : 2 * h + fadeSeconds
    }

    public func advance(by dt: Double) {
        timelineTime += dt
        rotationTime += dt * settings.speed
    }

    public func seek(timeline: Double, rotation: Double) {
        timelineTime = timeline
        rotationTime = rotation
    }

    /// Jump to the start of the next (+1) or previous (−1) polytope.
    public func skip(_ delta: Int) {
        let current = (timelineTime / segmentLength).rounded(.down)
        timelineTime = (current + Double(delta)) * segmentLength + fadeSeconds / 2
    }

    /// Manually pin the projection (preview app); nil returns to the timeline.
    public func overrideStereo(_ s: Double?) { stereoOverride = s }

    public func frame() -> FrameState {
        let len = segmentLength
        let index = Int((timelineTime / len).rounded(.down))
        let kind = order[((index + offset) % order.count + order.count) % order.count]
        let tau = timelineTime - Double(index) * len

        let half = fadeSeconds / 2
        let fade = smoothstep(0, half, tau) * (1 - smoothstep(len - half, len, tau))

        let stereo: Double
        switch settings.projection {
        case .perspective: stereo = 0
        case .stereographic: stereo = 1
        case .alternate:
            let h = settings.holdSeconds
            stereo = smoothstep(half + h, half + h + morphSeconds, tau)
        }

        let (natural, period) = kind.naturalRotation
        let angle = rotationTime * period / periodSeconds
        let t = rotationTime
        let drift = Rotation4.plane(0, 1, 0.031 * t) * Rotation4.plane(2, 3, 0.023 * t)
            * Rotation4.plane(0, 2, 0.017 * t) * Rotation4.plane(1, 3, 0.011 * t)
        let base = Rotation4.plane(0, 3, 0.6) * Rotation4.plane(1, 2, 0.4)
        return FrameState(kind: kind, rotation: drift * base * natural.matrix(angle),
                          stereo: stereoOverride ?? stereo, fade: fade)
    }
}

func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(max((x - a) / (b - a), 0), 1)
    return t * t * (3 - 2 * t)
}
