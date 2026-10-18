import Testing
@testable import PolychoraRender
import PolytopeKit

@Suite struct TimelineTests {
    @Test func travelIsMonotoneAndContinuous() {
        #expect(abs(travel(0)) < 1e-12)
        #expect(abs(travel(1) - 1) < 1e-12)
        var previous = 0.0
        for k in 1...1000 {
            let x = travel(Double(k) / 1000)
            #expect(x >= previous)
            #expect(x - previous < 0.002)
            previous = x
        }
    }

    /// Rotation stops for the whole camera move and the camera returns to rest.
    @Test func flyThroughFreezesRotation() {
        var s = PolychoraSettings()
        s.polytope = .cell120
        s.projection = .perspective
        s.flyThrough = .large
        let show = Slideshow(settings: s, randomStart: false)
        // fade-in 1.5 + hold 36 + spin-down 2 → approach starts at 39.5 s; fly-through ends at 39.5 + 9 + 36 + 9 = 93.5 s.
        show.seek(timeline: 39.6, rotation: 0)
        let r0 = show.rotationTime
        var maxApproach = 0.0, maxYaw = 0.0
        for _ in 0..<(538 * 6) {
            show.advance(by: 1.0 / 60)
            let f = show.frame()
            maxApproach = max(maxApproach, f.approach)
            maxYaw = max(maxYaw, f.yaw)
        }
        #expect(show.rotationTime == r0)
        #expect(abs(maxApproach - 1) < 1e-9)
        #expect(abs(maxYaw - 2 * .pi) < 1e-3)
        show.advance(by: 1)
        #expect(show.frame().approach == 0)
        show.advance(by: 1)
        #expect(show.rotationTime > r0)
    }

    /// Motion speed stretches only approach/withdraw, animation speed the hold and pan,
    /// rotation speed the spin-down (∝ √speed).
    @Test func speedDialsScaleTheirOwnPhases() {
        func approachWindow(animation: Double = 1, motion: Double = 1, rotation: Double = 1) -> (start: Double, end: Double) {
            var s = PolychoraSettings()
            s.polytope = .cell600
            s.projection = .perspective
            s.animationSpeed = animation
            s.motionSpeed = motion
            s.speed = rotation
            let show = Slideshow(settings: s, randomStart: false)
            var start = Double.nan, end = Double.nan
            for k in 0..<20000 {
                let t = Double(k) * 0.01
                show.seek(timeline: t, rotation: 0)
                let a = show.frame().approach
                if a > 0, start.isNaN { start = t }
                if a > 0 { end = t } else if !start.isNaN { break }
            }
            return (start, end)
        }
        // fade-in 1.5/a + hold 36/a, spin-down 2·√r; camera moves for 9/m + 36/a + 9/m.
        let base = approachWindow()
        #expect(abs(base.start - 39.5) < 0.02)
        #expect(abs((base.end - base.start) - 54) < 0.05)
        let slowMotion = approachWindow(motion: 0.5)
        #expect(abs(slowMotion.start - 39.5) < 0.02)
        #expect(abs((slowMotion.end - slowMotion.start) - 72) < 0.05)
        let fastAnimation = approachWindow(animation: 2)
        #expect(abs(fastAnimation.start - 20.75) < 0.02)
        #expect(abs((fastAnimation.end - fastAnimation.start) - 36) < 0.05)
        let fastRotation = approachWindow(rotation: 4)
        #expect(abs(fastRotation.start - 41.5) < 0.02)
    }

    @Test func noFlyThroughForSmallPolytopesInLargeMode() {
        var s = PolychoraSettings()
        s.polytope = .cell8
        s.flyThrough = .large
        let show = Slideshow(settings: s, randomStart: false)
        for k in 0..<2000 {
            show.seek(timeline: Double(k) * 0.05, rotation: 0)
            #expect(show.frame().approach == 0)
        }
    }
}
