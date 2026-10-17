import simd

/// Colours are linear RGB.
public struct Theme: Sendable {
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

    public static let ink = Theme(
        name: "Ink",
        backgroundTop: [0.022, 0.028, 0.048], backgroundBottom: [0.003, 0.005, 0.010],
        edge: [0.78, 0.72, 0.60], vertex: [0.92, 0.86, 0.72], face: [0.32, 0.46, 0.66],
        text: [0.70, 0.68, 0.62],
        palette: ([0.50, 0.48, 0.46], [0.28, 0.24, 0.22], [1, 1, 1], [0.00, 0.33, 0.67]),
        ringMix: 0.6, faceAlpha: 0.10, fresnelPower: 2.5, specular: 0.35, fogDensity: 0.05)

    public static let porcelain = Theme(
        name: "Porcelain",
        backgroundTop: [0.80, 0.79, 0.76], backgroundBottom: [0.60, 0.60, 0.58],
        edge: [0.09, 0.10, 0.12], vertex: [0.07, 0.07, 0.08], face: [0.50, 0.58, 0.68],
        text: [0.12, 0.12, 0.13],
        palette: ([0.40, 0.38, 0.36], [0.22, 0.18, 0.16], [1, 1, 1], [0.05, 0.38, 0.72]),
        ringMix: 0.35, faceAlpha: 0.16, fresnelPower: 2.0, specular: 0.2, fogDensity: 0.03)

    public static let brass = Theme(
        name: "Brass",
        backgroundTop: [0.014, 0.011, 0.008], backgroundBottom: [0.001, 0.001, 0.001],
        edge: [0.72, 0.50, 0.22], vertex: [0.86, 0.64, 0.30], face: [0.30, 0.27, 0.24],
        text: [0.62, 0.52, 0.36],
        palette: ([0.5, 0.5, 0.5], [0.0, 0.0, 0.0], [1, 1, 1], [0, 0, 0]),
        ringMix: 0.0, faceAlpha: 0.07, fresnelPower: 3.0, specular: 0.8, fogDensity: 0.05)

    public static let all: [Theme] = [.ink, .porcelain, .brass]

    public static func named(_ name: String) -> Theme {
        all.first { $0.name == name } ?? .ink
    }
}
