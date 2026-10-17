import Foundation
import PolytopeKit

public struct PolychoraSettings: Sendable {
    public enum Projection: Int, CaseIterable, Sendable {
        case alternate, perspective, stereographic

        public var label: String {
            switch self {
            case .alternate: return "Alternate"
            case .perspective: return "Perspective"
            case .stereographic: return "Stereographic"
            }
        }
    }

    public enum OverlayLayout: Int, CaseIterable, Sendable {
        /// Single info card bottom left, clock bottom right.
        case compact
        /// Title, projection, geometry table and clock in the four corners.
        case quadrants

        public var label: String { self == .compact ? "Compact" : "Quadrants" }
    }

    /// nil cycles through all six.
    public var polytope: PolytopeKind?
    public var projection: Projection = .alternate
    public var speed: Double = 1
    public var theme: String = Theme.ink.name
    public var showInfo = true
    public var showClock = true
    public var overlayLayout: OverlayLayout = .compact
    /// Seconds spent in each projection before morphing / moving on.
    public var holdSeconds: Double = 30

    public init() {}

    private enum Key {
        static let polytope = "polytope", projection = "projection", speed = "speed", theme = "theme"
        static let showInfo = "showInfo", showClock = "showClock", hold = "holdSeconds", layout = "overlayLayout"
    }

    public static func load(from d: UserDefaults) -> PolychoraSettings {
        var s = PolychoraSettings()
        if let p = d.object(forKey: Key.polytope) as? Int { s.polytope = PolytopeKind(rawValue: p) }
        if let p = d.object(forKey: Key.projection) as? Int, let m = Projection(rawValue: p) { s.projection = m }
        if let v = d.object(forKey: Key.speed) as? Double { s.speed = v }
        if let v = d.string(forKey: Key.theme) { s.theme = v }
        if let v = d.object(forKey: Key.showInfo) as? Bool { s.showInfo = v }
        if let v = d.object(forKey: Key.showClock) as? Bool { s.showClock = v }
        if let v = d.object(forKey: Key.hold) as? Double { s.holdSeconds = v }
        if let v = d.object(forKey: Key.layout) as? Int, let l = OverlayLayout(rawValue: v) { s.overlayLayout = l }
        return s
    }

    public func save(to d: UserDefaults) {
        d.set(polytope?.rawValue ?? -1, forKey: Key.polytope)
        d.set(projection.rawValue, forKey: Key.projection)
        d.set(speed, forKey: Key.speed)
        d.set(theme, forKey: Key.theme)
        d.set(showInfo, forKey: Key.showInfo)
        d.set(showClock, forKey: Key.showClock)
        d.set(holdSeconds, forKey: Key.hold)
        d.set(overlayLayout.rawValue, forKey: Key.layout)
        d.synchronize()
    }
}
