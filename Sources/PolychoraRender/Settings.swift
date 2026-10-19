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
        /// Deprecated. Single info card bottom left, clock bottom right.
        case compact
        /// Title, projection, geometry table and clock in the four corners.
        case quadrants

        public var label: String { self == .compact ? "Compact" : "Quadrants" }
    }

    public enum FlyThrough: Int, CaseIterable, Sendable {
        case off, large, all

        public var label: String {
            switch self {
            case .off: return "Off"
            case .large: return "120- and 600-cell"
            case .all: return "All polytopes"
            }
        }

        public func applies(to kind: PolytopeKind) -> Bool {
            switch self {
            case .off: return false
            case .large: return kind == .cell120 || kind == .cell600
            case .all: return true
            }
        }
    }

    public enum Coloring: Int, CaseIterable, Sendable {
        /// One hue per polytope, rendered in the theme's lightness and chroma.
        case signature
        /// Theme base colours with Hopf-ring tinting.
        case rings

        public var label: String { self == .signature ? "Signature" : "Hopf rings" }
    }

    /// Raw values are the stored defaults (none was added later); `allCases` is the menu order.
    public enum Surfaces: Int, CaseIterable, Sendable {
        /// Frame only.
        case none = 2
        /// Glass faces (bubbles in stereographic projection).
        case faces = 0
        /// Solid cells, acrylic morphing into jelly; one Hopf ring at a time.
        case cells = 1

        public var label: String {
            switch self {
            case .none: return "None"
            case .faces: return "Faces"
            case .cells: return "Cells"
            }
        }
    }

    public enum FrameColors: Int, CaseIterable, Sendable {
        /// The theme's metal.
        case steel
        /// The polytope's signature hue, in the theme's metal finish.
        case signature

        public var label: String { self == .steel ? "Steel" : "Signature" }
    }

    /// nil cycles through all six.
    /// Not loaded from defaults: the options sheet always cycles; a single polytope is preview-app only.
    public var polytope: PolytopeKind?
    public var projection: Projection = .alternate
    public var speed: Double = 1
    public var theme: String = Theme.ink.name
    public var showInfo = true
    public var showClock = true
    public var showFPS = false
    /// Not loaded from defaults: compact is deprecated and only reachable from the preview app.
    public var overlayLayout: OverlayLayout = .quadrants
    public var flyThrough: FlyThrough = .large
    /// Not loaded from defaults: the options sheet no longer offers it, so the app uses one fixed
    /// scheme (Hopf rings remain reachable from the preview app).
    public var coloring: Coloring = .signature
    public var surfaces: Surfaces = .faces
    public var frameColors: FrameColors = .steel
    /// Still-camera animation (rotation hold, fades, morph): durations scale by 1 / animationSpeed.
    public var animationSpeed: Double = 1
    /// The 360° panorama at the projection centre: its duration scales by 1 / panSpeed.
    public var panSpeed: Double = 1
    /// Camera travel (fly-through approach and withdraw): durations scale by 1 / motionSpeed.
    public var motionSpeed: Double = 1

    /// Range of the speed multipliers; the options sheet maps them onto log2-scaled sliders.
    public static let speedRange: ClosedRange<Double> = 0.25...4

    public init() {}

    private enum Key {
        static let polytope = "polytope", projection = "projection", speed = "speed", theme = "theme"
        static let showInfo = "showInfo", showClock = "showClock", showFPS = "showFPS", layout = "overlayLayout"
        static let fly = "flyThrough", animation = "animationSpeed", motion = "motionSpeed", coloring = "coloring"
        static let surfaces = "surfaces", pan = "panSpeed", frameColors = "frameColors"
    }

    public static func load(from d: UserDefaults) -> PolychoraSettings {
        var s = PolychoraSettings()
        if let p = d.object(forKey: Key.projection) as? Int, let m = Projection(rawValue: p) { s.projection = m }
        if let v = d.object(forKey: Key.speed) as? Double { s.speed = v }
        if let v = d.string(forKey: Key.theme) { s.theme = v }
        if let v = d.object(forKey: Key.showInfo) as? Bool { s.showInfo = v }
        if let v = d.object(forKey: Key.showClock) as? Bool { s.showClock = v }
        if let v = d.object(forKey: Key.showFPS) as? Bool { s.showFPS = v }
        if let v = d.object(forKey: Key.animation) as? Double { s.animationSpeed = v }
        if let v = d.object(forKey: Key.motion) as? Double { s.motionSpeed = v }
        if let v = d.object(forKey: Key.pan) as? Double { s.panSpeed = v }
        if let v = d.object(forKey: Key.fly) as? Int, let f = FlyThrough(rawValue: v) { s.flyThrough = f }
        if let v = d.object(forKey: Key.surfaces) as? Int, let f = Surfaces(rawValue: v) { s.surfaces = f }
        if let v = d.object(forKey: Key.frameColors) as? Int, let f = FrameColors(rawValue: v) { s.frameColors = f }
        return s
    }

    public func save(to d: UserDefaults) {
        d.set(polytope?.rawValue ?? -1, forKey: Key.polytope)
        d.set(projection.rawValue, forKey: Key.projection)
        d.set(speed, forKey: Key.speed)
        d.set(theme, forKey: Key.theme)
        d.set(showInfo, forKey: Key.showInfo)
        d.set(showClock, forKey: Key.showClock)
        d.set(showFPS, forKey: Key.showFPS)
        d.set(animationSpeed, forKey: Key.animation)
        d.set(motionSpeed, forKey: Key.motion)
        d.set(panSpeed, forKey: Key.pan)
        d.set(coloring.rawValue, forKey: Key.coloring)
        d.set(overlayLayout.rawValue, forKey: Key.layout)
        d.set(flyThrough.rawValue, forKey: Key.fly)
        d.set(surfaces.rawValue, forKey: Key.surfaces)
        d.set(frameColors.rawValue, forKey: Key.frameColors)
        d.synchronize()
    }
}
