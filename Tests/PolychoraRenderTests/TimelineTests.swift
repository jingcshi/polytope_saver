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
