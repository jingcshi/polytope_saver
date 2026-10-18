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

    /// The rotation in the plane of unit vectors `a` and `b` that takes `a` to `b`:
    /// R = I − (a+b)(a+b)ᵀ / (1 + a·b) + 2·b·aᵀ.
    public static func aligning(_ a: Vec4, to b: Vec4) -> Mat4 {
        func outer(_ u: Vec4, _ v: Vec4) -> Mat4 { Mat4(columns: (u * v[0], u * v[1], u * v[2], u * v[3])) }
        let c = simd_dot(a, b)
        if c > 1 - 1e-12 { return Mat4(diagonal: Vec4(repeating: 1)) }
        if c < -1 + 1e-12 {
            // Antipodal: half-turn in a plane containing a.
            let axis = abs(a[0]) < 0.9 ? Vec4(1, 0, 0, 0) : Vec4(0, 1, 0, 0)
            let n = simd_normalize(axis - simd_dot(axis, a) * a)
            return Mat4(diagonal: Vec4(repeating: 1)) - 2 * outer(a, a) - 2 * outer(n, n)
        }
        let s = a + b
        return Mat4(diagonal: Vec4(repeating: 1)) - outer(s, s) * (1 / (1 + c)) + 2 * outer(b, a)
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
