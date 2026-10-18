import simd

/// Colours are linear RGB.
public struct Theme: Sendable {
    /// Light added to the background gradient.
    public enum Glow: Sendable {
        case none
        /// Horizontal band centred at `y` (0 bottom … 1 top), Gaussian half-width `width`.
        case horizon(color: SIMD3<Float>, y: Float, width: Float)
        /// Soft halo behind the object, as in a museum case lit from behind.
        /// `center` in uv (0…1), `radius` in units of screen height. The halo is added to the
        /// background, so `color`'s magnitude is its strength.
        case backlight(color: SIMD3<Float>, center: SIMD2<Float>, radius: Float)
    }

    public var name: String
    public var backgroundTop: SIMD3<Float>
    public var backgroundBottom: SIMD3<Float>
    public var edge: SIMD3<Float>
    public var vertex: SIMD3<Float>
    public var face: SIMD3<Float>
    public var text: SIMD3<Float>
    /// Cosine palette a + b·cos(2π(c·t + d)) for ring colouring.
    public var palette: (a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>, d: SIMD3<Float>)
    /// 0: element base colours only, 1: ring palette only.
    public var ringMix: Float
    public var faceAlpha: Float
    public var fresnelPower: Float
    public var specular: Float
    public var fogDensity: Float
    /// Key light direction (towards the light), world space; the camera looks down −z.
    public var lightDir: SIMD3<Float> = [-0.45, 0.75, 0.5]
    public var glow: Glow = .none
    /// Rim light colour × strength, added at grazing angles (light from behind the object).
    public var rim: SIMD3<Float> = .zero

    public static let ink = Theme(
        name: "Ink",
        backgroundTop: [0.022, 0.028, 0.048], backgroundBottom: [0.003, 0.005, 0.010],
        edge: [0.78, 0.72, 0.60], vertex: [0.92, 0.86, 0.72], face: [0.32, 0.46, 0.66],
        text: [0.70, 0.68, 0.62],
        palette: ([0.50, 0.48, 0.46], [0.28, 0.24, 0.22], [1, 1, 1], [0.00, 0.33, 0.67]),
        ringMix: 0.6, faceAlpha: 0.10, fresnelPower: 2.5, specular: 0.35, fogDensity: 0.05,
        glow: .horizon(color: [0.016, 0.024, 0.046], y: 0.25, width: 0.18))

    public static let sky = Theme(
        name: "Sky",
        backgroundTop: [0.16, 0.36, 0.68], backgroundBottom: [0.58, 0.74, 0.88],
        edge: [0.05, 0.08, 0.14], vertex: [0.03, 0.05, 0.10], face: [0.92, 0.95, 1.00],
        text: [0.04, 0.07, 0.13],
        palette: ([0.40, 0.42, 0.48], [0.20, 0.18, 0.16], [1, 1, 1], [0.55, 0.85, 0.15]),
        ringMix: 0.3, faceAlpha: 0.18, fresnelPower: 2.0, specular: 0.3, fogDensity: 0.03,
        lightDir: [-0.3, 0.85, 0.45],
        glow: .horizon(color: [0.22, 0.20, 0.16], y: 0.25, width: 0.18))

    public static let porcelain = Theme(
        name: "Porcelain",
        backgroundTop: [0.80, 0.79, 0.76], backgroundBottom: [0.60, 0.60, 0.58],
        edge: [0.09, 0.10, 0.12], vertex: [0.07, 0.07, 0.08], face: [0.50, 0.58, 0.68],
        text: [0.12, 0.12, 0.13],
        palette: ([0.40, 0.38, 0.36], [0.22, 0.18, 0.16], [1, 1, 1], [0.05, 0.38, 0.72]),
        ringMix: 0.35, faceAlpha: 0.16, fresnelPower: 2.0, specular: 0.2, fogDensity: 0.03,
        lightDir: [-0.2, 0.6, -0.35],
        glow: .backlight(color: [0.16, 0.11, 0.05], center: [0.5, 0.52], radius: 0.42),
        rim: [0.55, 0.42, 0.26])

    public static let brass = Theme(
        name: "Brass",
        backgroundTop: [0.014, 0.011, 0.008], backgroundBottom: [0.001, 0.001, 0.001],
        edge: [0.72, 0.50, 0.22], vertex: [0.86, 0.64, 0.30], face: [0.30, 0.27, 0.24],
        text: [0.62, 0.52, 0.36],
        palette: ([0.5, 0.5, 0.5], [0.0, 0.0, 0.0], [1, 1, 1], [0, 0, 0]),
        ringMix: 0.0, faceAlpha: 0.07, fresnelPower: 3.0, specular: 0.8, fogDensity: 0.05,
        lightDir: [-0.3, 0.55, -0.4],
        glow: .backlight(color: [0.049, 0.027, 0.009], center: [0.5, 0.50], radius: 0.40),
        rim: [0.70, 0.45, 0.18])

    /// Two light, two dark.
    public static let all: [Theme] = [.ink, .sky, .porcelain, .brass]

    public static func named(_ name: String) -> Theme {
        all.first { $0.name == name } ?? .ink
    }

    /// Shader packing: (rgb, mode) and (centre x, centre y, width/radius, 0); mode 0 none, 1 horizon, 2 backlight.
    var glowUniforms: (SIMD4<Float>, SIMD4<Float>) {
        switch glow {
        case .none: return (.zero, .zero)
        case let .horizon(c, y, w): return (SIMD4(c, 1), [0.5, y, w, 0])
        case let .backlight(c, p, r): return (SIMD4(c, 2), [p.x, p.y, r, 0])
        }
    }
}
