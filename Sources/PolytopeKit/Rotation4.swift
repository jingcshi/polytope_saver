import simd

public typealias Vec4 = SIMD4<Double>
public typealias Mat4 = simd_double4x4

public enum Rotation4 {
    /// Rotation by `angle` in the plane spanned by coordinate axes `i` and `j`.
    public static func plane(_ i: Int, _ j: Int, _ angle: Double) -> Mat4 {
        var m = Mat4(diagonal: Vec4(repeating: 1))
        let c = cos(angle), s = sin(angle)
        m[i][i] = c; m[j][j] = c
        m[i][j] = s; m[j][i] = -s
        return m
    }

    /// Left multiplication p ↦ q·p by a unit quaternion q = (w, x, y, z).
    /// Always an isoclinic rotation of R⁴.
    public static func leftMultiplication(_ q: Vec4) -> Mat4 {
        let (a, b, c, d) = (q[0], q[1], q[2], q[3])
        return Mat4(rows: [
            Vec4(a, -b, -c, -d),
            Vec4(b, a, -d, c),
            Vec4(c, d, a, -b),
            Vec4(d, -c, b, a),
        ])
    }

    /// exp(θu) for a unit pure quaternion u.
    public static func quaternionExp(axis u: SIMD3<Double>, angle: Double) -> Vec4 {
        let n = simd_normalize(u)
        return Vec4(cos(angle), n.x * sin(angle), n.y * sin(angle), n.z * sin(angle))
    }
}

/// A one-parameter rotation group adapted to a polytope's symmetry.
public enum NaturalRotation: Sendable {
    /// Left multiplication by exp(θ·axis): isoclinic, orbits are Hopf circles.
    case leftIsoclinic(axis: SIMD3<Double>)
    /// Double rotation by (θ, 2θ) in the xy and zw planes.
    case petrie

    public func matrix(_ angle: Double) -> Mat4 {
        switch self {
        case .leftIsoclinic(let axis):
            return Rotation4.leftMultiplication(Rotation4.quaternionExp(axis: axis, angle: angle))
        case .petrie:
            return Rotation4.plane(0, 1, angle) * Rotation4.plane(2, 3, 2 * angle)
        }
    }
}
