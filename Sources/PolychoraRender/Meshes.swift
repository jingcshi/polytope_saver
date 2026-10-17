import simd

/// Parameter-space templates, instanced once per edge / vertex / face triangle.
enum Meshes {
    /// (t along edge, angle around tube).
    static func tube(segments: Int, sides: Int) -> (vertices: [SIMD2<Float>], indices: [UInt32]) {
        var v: [SIMD2<Float>] = []
        for s in 0...segments {
            for k in 0..<sides {
                v.append([Float(s) / Float(segments), 2 * .pi * Float(k) / Float(sides)])
            }
        }
        var idx: [UInt32] = []
        for s in 0..<segments {
            for k in 0..<sides {
                let a = UInt32(s * sides + k), b = UInt32(s * sides + (k + 1) % sides)
                let c = a + UInt32(sides), d = b + UInt32(sides)
                idx += [a, c, b, b, c, d]
            }
        }
        return (v, idx)
    }

    /// Unit icosphere; positions double as normals.
    static func sphere(subdivisions: Int) -> (vertices: [SIMD3<Float>], indices: [UInt32]) {
        let t = (1 + Float(5).squareRoot()) / 2
        var v: [SIMD3<Float>] = [
            [-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0],
            [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
            [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1],
        ].map { simd_normalize($0) }
        var f: [SIMD3<UInt32>] = [
            [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
            [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
            [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
            [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
        ]
        for _ in 0..<subdivisions {
            var cache: [UInt64: UInt32] = [:]
            func mid(_ a: UInt32, _ b: UInt32) -> UInt32 {
                let key = UInt64(min(a, b)) << 32 | UInt64(max(a, b))
                if let m = cache[key] { return m }
                v.append(simd_normalize(v[Int(a)] + v[Int(b)]))
                let m = UInt32(v.count - 1)
                cache[key] = m
                return m
            }
            f = f.flatMap { tri -> [SIMD3<UInt32>] in
                let ab = mid(tri.x, tri.y), bc = mid(tri.y, tri.z), ca = mid(tri.z, tri.x)
                return [[tri.x, ab, ca], [tri.y, bc, ab], [tri.z, ca, bc], [ab, bc, ca]]
            }
        }
        return (v, f.flatMap { [$0.x, $0.y, $0.z] })
    }

    /// Barycentric grid (u, v) with u + v ≤ 1.
    static func triangleGrid(level n: Int) -> (vertices: [SIMD2<Float>], indices: [UInt32]) {
        var v: [SIMD2<Float>] = []
        var index: [[UInt32]] = []
        for i in 0...n {
            var row: [UInt32] = []
            for j in 0...(n - i) {
                row.append(UInt32(v.count))
                v.append([Float(i) / Float(n), Float(j) / Float(n)])
            }
            index.append(row)
        }
        var idx: [UInt32] = []
        for i in 0..<n {
            for j in 0..<(n - i) {
                idx += [index[i][j], index[i + 1][j], index[i][j + 1]]
                if j + 1 < n - i { idx += [index[i + 1][j], index[i + 1][j + 1], index[i][j + 1]] }
            }
        }
        return (v, idx)
    }
}
