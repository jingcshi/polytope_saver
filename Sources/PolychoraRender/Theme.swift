import Foundation
import simd
import PolytopeKit

extension PolytopeKind {
    /// Signature hue, OKLCH degrees: red 5-cell, blue tesseract, yellow 16-cell, magenta 24-cell,
    /// cyan 120-cell, green 600-cell.
    public var signatureHue: Float {
        switch self {
        case .cell5: return 29
        case .cell8: return 264
        case .cell16: return 100
        case .cell24: return 330
        case .cell120: return 200
        case .cell600: return 145
        }
    }
}

/// OKLCH (Björn Ottosson's Oklab in polar form) to linear sRGB, clamped to the gamut.
/// Equal L reads as equal lightness across hues, unlike HSV.
func oklch(_ L: Float, _ C: Float, _ hDegrees: Float) -> SIMD3<Float> {
    let h = hDegrees * .pi / 180
    let a = C * cos(h), b = C * sin(h)
    let l = pow(L + 0.3963377774 * a + 0.2158037573 * b, 3)
    let m = pow(L - 0.1055613458 * a - 0.0638541728 * b, 3)
    let s = pow(L - 0.0894841775 * a - 1.2914855480 * b, 3)
    let rgb = SIMD3<Float>(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                           -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                           -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    return simd_clamp(rgb, .zero, .one)
}

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
    /// What "highlighting" means in this theme; used for the dissolve front. May exceed 1 on EDR.
    public var highlight: SIMD3<Float> = [1, 1, 1]
    /// EDR multiplier for specular highlights and the dissolve front (applies only with headroom).
    public var highlightGain: Float = 1
    /// Brightest value highlights may reach, as a multiple of SDR white (also capped by the display).
    public var peak: Float = 1
    /// How this theme renders the polytopes' signature hues (OKLCH lightness and chroma).
    public var signature = Signature(edgeL: 0.8, edgeC: 0.07, vertexL: 0.86, vertexC: 0.06,
                                     faceL: 0.62, faceC: 0.04, faceAlphaScale: 0.85)
    /// Framework material; `edge` is the metal's base colour.
    public var metal = Metal(sharpness: 60, reflection: 0.8, softbox: 0.35, diffuse: 0.7, tint: 0.2)

    /// Cast metal: specular exponent, strength of the environment reflection (theme gradient, glow and an
    /// overhead softbox of strength `softbox`), diffuse weight, and how far reflections take the base
    /// colour (0 steel, 1 brass).
    public struct Metal: Sendable {
        public var sharpness, reflection, softbox, diffuse, tint: Float
    }
    /// Info card text colours where the background differs by corner; nil uses `text` everywhere.
    public var cardText: CardText?

    public struct CardText: Sendable {
        public var topLeft, topRight, bottomLeft, bottomRight: SIMD3<Float>
    }

    /// Per-theme lightness / chroma for the signature palette; the hue comes from the polytope.
    public struct Signature: Sendable {
        public var edgeL, edgeC, vertexL, vertexC, faceL, faceC: Float
        public var faceAlphaScale: Float
    }

    /// Edge, vertex and face colours (linear sRGB) for a polytope in this theme's signature palette.
    public func signatureColors(_ kind: PolytopeKind) -> (edge: SIMD3<Float>, vertex: SIMD3<Float>, face: SIMD3<Float>) {
        let h = kind.signatureHue, s = signature
        return (oklch(s.edgeL, s.edgeC, h), oklch(s.vertexL, s.vertexC, h), oklch(s.faceL, s.faceC, h))
    }

    public static let ink = Theme(
        name: "Ink",
        backgroundTop: [0.022, 0.028, 0.048], backgroundBottom: [0.003, 0.005, 0.010],
        edge: [0.40, 0.41, 0.43], vertex: [0.92, 0.86, 0.72], face: [0.32, 0.46, 0.66],
        text: [0.70, 0.68, 0.62],
        palette: ([0.50, 0.48, 0.46], [0.28, 0.24, 0.22], [1, 1, 1], [0.00, 0.33, 0.67]),
        ringMix: 0.6, faceAlpha: 0.10, fresnelPower: 2.5, specular: 0.35, fogDensity: 0.05,
        glow: .horizon(color: [0.016, 0.024, 0.046], y: 0.25, width: 0.18),
        highlight: [0.62, 0.82, 1.0], highlightGain: 2.2, peak: 3.0,    // cool filament
        signature: .init(edgeL: 0.80, edgeC: 0.075, vertexL: 0.86, vertexC: 0.06,
                         faceL: 0.62, faceC: 0.05, faceAlphaScale: 0.85),
        metal: .init(sharpness: 80, reflection: 0.9, softbox: 0.30, diffuse: 0.6, tint: 0.15))

    /// Late afternoon: halfway (in sRGB) between a clear day sky and dusk, with a warm horizon.
    public static let sky = Theme(
        name: "Sky",
        backgroundTop: [0.119, 0.235, 0.461], backgroundBottom: [0.451, 0.511, 0.625],
        edge: [0.03, 0.035, 0.045], vertex: [0.04, 0.05, 0.09], face: [0.92, 0.93, 1.00],
        text: [0.04, 0.07, 0.13],
        palette: ([0.40, 0.42, 0.48], [0.20, 0.18, 0.16], [1, 1, 1], [0.55, 0.85, 0.15]),
        ringMix: 0.3, faceAlpha: 0.16, fresnelPower: 2.0, specular: 0.3, fogDensity: 0.03,
        lightDir: [-0.3, 0.85, 0.45],
        glow: .horizon(color: [0.258, 0.163, 0.088], y: 0.25, width: 0.18),
        highlight: [1.0, 0.62, 0.38], highlightGain: 1.6, peak: 2.0,     // sunset peach
        signature: .init(edgeL: 0.40, edgeC: 0.095, vertexL: 0.36, vertexC: 0.08,
                         faceL: 0.88, faceC: 0.04, faceAlphaScale: 0.9),
        metal: .init(sharpness: 90, reflection: 0.06, softbox: 4.0, diffuse: 0.5, tint: 0),
        cardText: .init(topLeft: [0.86, 0.87, 0.90], topRight: [0.86, 0.87, 0.90],
                        bottomLeft: [0.04, 0.07, 0.13], bottomRight: [0.04, 0.07, 0.13]))

    public static let porcelain = Theme(
        name: "Porcelain",
        backgroundTop: [0.80, 0.79, 0.76], backgroundBottom: [0.60, 0.60, 0.58],
        edge: [0.05, 0.055, 0.06], vertex: [0.07, 0.07, 0.08], face: [0.50, 0.58, 0.68],
        text: [0.12, 0.12, 0.13],
        palette: ([0.40, 0.38, 0.36], [0.22, 0.18, 0.16], [1, 1, 1], [0.05, 0.38, 0.72]),
        ringMix: 0.35, faceAlpha: 0.16, fresnelPower: 2.0, specular: 0.2, fogDensity: 0.03,
        lightDir: [-0.2, 0.6, -0.35],
        glow: .backlight(color: [0.16, 0.11, 0.05], center: [0.5, 0.52], radius: 0.42),
        rim: [0.26, 0.20, 0.12],
        highlight: [0.60, 0.40, 0.12],     // gold seams (kintsugi); no EDR boost, the look stays as is
        signature: .init(edgeL: 0.42, edgeC: 0.115, vertexL: 0.37, vertexC: 0.095,
                         faceL: 0.72, faceC: 0.06, faceAlphaScale: 0.85),
        metal: .init(sharpness: 80, reflection: 0.06, softbox: 4.0, diffuse: 0.5, tint: 0))

    public static let brass = Theme(
        name: "Brass",
        backgroundTop: [0.014, 0.011, 0.008], backgroundBottom: [0.001, 0.001, 0.001],
        edge: [0.72, 0.50, 0.22], vertex: [0.86, 0.64, 0.30], face: [0.30, 0.27, 0.24],
        text: [0.62, 0.52, 0.36],
        palette: ([0.5, 0.5, 0.5], [0.0, 0.0, 0.0], [1, 1, 1], [0, 0, 0]),
        ringMix: 0.0, faceAlpha: 0.07, fresnelPower: 3.0, specular: 0.8, fogDensity: 0.05,
        lightDir: [-0.3, 0.55, -0.4],
        glow: .backlight(color: [0.038, 0.021, 0.007], center: [0.5, 0.50], radius: 0.40),
        rim: [0.30, 0.19, 0.08],
        highlight: [1.48, 0.96, 0.46], highlightGain: 2.5, peak: 3.5,    // ember (the original dissolve glow)
        signature: .init(edgeL: 0.74, edgeC: 0.12, vertexL: 0.80, vertexC: 0.10,
                         faceL: 0.50, faceC: 0.06, faceAlphaScale: 0.9),
        metal: .init(sharpness: 50, reflection: 0.7, softbox: 0.25, diffuse: 0.45, tint: 0.9))

    /// Two light (Porcelain, Sky at dusk is mid-toned), two dark.
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
