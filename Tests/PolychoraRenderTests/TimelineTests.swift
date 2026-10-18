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
        // fade-in 1.5 + rotate 30 + spin-down 3 → approach starts at 34.5 s; fly-through ends at 66.5 s.
        show.seek(timeline: 34.6, rotation: 0)
        let r0 = show.rotationTime
        var maxApproach = 0.0, maxYaw = 0.0
        for _ in 0..<(31 * 60) {
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

    /// Doubling the fly-through length stretches only the camera move; the view before it is unchanged.
    @Test func flyPaceIsIndependentOfViewPace() {
        func approachWindow(fly: Double) -> (start: Double, end: Double) {
            var s = PolychoraSettings()
            s.polytope = .cell600
            s.projection = .perspective
            s.flySeconds = fly
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
        let base = approachWindow(fly: 35), long = approachWindow(fly: 70)
        // fade-in 1.5 + rotate 30, then spin-down 3·f; the camera moves for 32·f.
        #expect(abs(base.start - 34.5) < 0.02)
        #expect(abs(long.start - 37.5) < 0.02)
        #expect(abs((base.end - base.start) - 32) < 0.05)
        #expect(abs((long.end - long.start) - 64) < 0.05)
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
