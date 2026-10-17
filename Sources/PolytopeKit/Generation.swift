import simd

private let tolerance = 1e-6
private let phi = (1 + 5.0.squareRoot()) / 2

extension Polytope {
    public static func make(_ kind: PolytopeKind) -> Polytope {
        let vertices = Self.vertices(kind)
        let edges = Self.edges(vertices)
        let cells: [[Int]]
        if kind.isSimplicial {
            cells = Self.tetrahedra(vertexCount: vertices.count, edges: edges)
        } else {
            cells = Self.dualDirections(kind).map { Self.facet(vertices, direction: $0) }
        }
        let cellCentres = cells.map { c in simd_normalize(c.reduce(Vec4.zero) { $0 + vertices[$1] }) }
        let (faces, faceCells) = Self.faces(vertices, cells: cells)
        let (rotation, period) = kind.naturalRotation
        let step = rotation.matrix(period)
        return Polytope(kind: kind, vertices: vertices, edges: edges, faces: faces, faceCells: faceCells,
                        cells: cells, cellCentres: cellCentres,
                        vertexRing: Self.orbits(vertices, step: step),
                        cellRing: Self.orbits(cellCentres, step: step))
    }

    // MARK: Vertex sets

    static func vertices(_ kind: PolytopeKind) -> [Vec4] {
        switch kind {
        case .cell5:
            return (0..<5).map { k in
                let a = 2 * Double.pi * Double(k) / 5
                return Vec4(cos(a), sin(a), cos(2 * a), sin(2 * a)) / 2.0.squareRoot()
            }
        case .cell8: return halves()
        case .cell16: return units()
        case .cell24: return units() + halves()
        case .cell600: return units() + halves() + snubs()
        case .cell120:
            let p = Polytope.make(.cell600)
            return p.cellCentres
        }
    }

    /// Cell-centre directions of the non-simplicial polytopes (the dual's vertices).
    static func dualDirections(_ kind: PolytopeKind) -> [Vec4] {
        switch kind {
        case .cell8: return units()
        case .cell24: return signedPermutations(Vec4(1, 1, 0, 0)).map { $0 / 2.0.squareRoot() }
        case .cell120: return vertices(.cell600)
        default: fatalError("simplicial polytopes derive cells from cliques")
        }
    }

    private static func units() -> [Vec4] {
        (0..<4).flatMap { i -> [Vec4] in
            var v = Vec4.zero; v[i] = 1
            return [v, -v]
        }
    }

    private static func halves() -> [Vec4] {
        (0..<16).map { m in
            Vec4((0..<4).map { (m >> $0) & 1 == 0 ? 0.5 : -0.5 })
        }
    }

    /// Even permutations of ½(±φ, ±1, ±1/φ, 0).
    private static func snubs() -> [Vec4] {
        let base = [phi, 1, 1 / phi, 0]
        var out: [Vec4] = []
        for perm in permutations([0, 1, 2, 3]) where isEven(perm) {
            for signs in 0..<8 {
                var v = Vec4.zero
                for (slot, src) in perm.enumerated() {
                    var x = base[src]
                    if src < 3, (signs >> src) & 1 == 1 { x = -x }
                    v[slot] = x / 2
                }
                out.append(v)
            }
        }
        return out
    }

    private static func signedPermutations(_ v: Vec4) -> [Vec4] {
        var seen = Set<[Int]>()
        var out: [Vec4] = []
        for perm in permutations([0, 1, 2, 3]) {
            for signs in 0..<16 {
                var w = Vec4.zero
                for i in 0..<4 { w[i] = v[perm[i]] * ((signs >> i) & 1 == 0 ? 1 : -1) }
                let key = (0..<4).map { Int((w[$0] * 1e6).rounded()) }
                if seen.insert(key).inserted { out.append(w) }
            }
        }
        return out
    }

    private static func permutations(_ a: [Int]) -> [[Int]] {
        if a.count <= 1 { return [a] }
        return a.indices.flatMap { i -> [[Int]] in
            var rest = a; let head = rest.remove(at: i)
            return permutations(rest).map { [head] + $0 }
        }
    }

    private static func isEven(_ p: [Int]) -> Bool {
        var inversions = 0
        for i in p.indices { for j in (i + 1)..<p.count where p[i] > p[j] { inversions += 1 } }
        return inversions % 2 == 0
    }

    // MARK: Combinatorics

    static func edges(_ v: [Vec4]) -> [SIMD2<Int>] {
        var best = Double.infinity
        for i in v.indices { for j in (i + 1)..<v.count { best = min(best, simd_distance(v[i], v[j])) } }
        var out: [SIMD2<Int>] = []
        for i in v.indices {
            for j in (i + 1)..<v.count where abs(simd_distance(v[i], v[j]) - best) < tolerance {
                out.append([i, j])
            }
        }
        return out
    }

    static func tetrahedra(vertexCount n: Int, edges: [SIMD2<Int>]) -> [[Int]] {
        var adj = Array(repeating: Set<Int>(), count: n)
        for e in edges { adj[e.x].insert(e.y); adj[e.y].insert(e.x) }
        var out: [[Int]] = []
        for e in edges {
            let (i, j) = (e.x, e.y)
            let common = adj[i].intersection(adj[j]).filter { $0 > j }.sorted()
            for (a, k) in common.enumerated() {
                for l in common[(a + 1)...] where adj[k].contains(l) { out.append([i, j, k, l]) }
            }
        }
        return out
    }

    /// Vertices maximising ⟨v, d⟩: the facet with outward normal d.
    static func facet(_ v: [Vec4], direction d: Vec4) -> [Int] {
        let dots = v.map { simd_dot($0, d) }
        let top = dots.max()!
        return v.indices.filter { dots[$0] > top - tolerance }
    }

    /// Faces are the ≥3-vertex intersections of adjacent cells.
    static func faces(_ v: [Vec4], cells: [[Int]]) -> ([[Int]], [SIMD2<Int>]) {
        var cellsOfVertex = Array(repeating: [Int](), count: v.count)
        for (c, cell) in cells.enumerated() { for i in cell { cellsOfVertex[i].append(c) } }
        var faces: [[Int]] = []
        var faceCells: [SIMD2<Int>] = []
        for (c, cell) in cells.enumerated() {
            var shared: [Int: [Int]] = [:]
            for i in cell { for d in cellsOfVertex[i] where d > c { shared[d, default: []].append(i) } }
            for (d, common) in shared.sorted(by: { $0.key < $1.key }) where common.count >= 3 {
                faces.append(cyclicOrder(common, v))
                faceCells.append([c, d])
            }
        }
        return (faces, faceCells)
    }

    private static func cyclicOrder(_ idx: [Int], _ v: [Vec4]) -> [Int] {
        let m = idx.reduce(Vec4.zero) { $0 + v[$1] } / Double(idx.count)
        let e1 = simd_normalize(v[idx[0]] - m)
        var e2 = Vec4.zero
        for i in idx.dropFirst() {
            let r = v[i] - m
            let perp = r - simd_dot(r, e1) * e1
            if simd_length(perp) > 1e-4 { e2 = simd_normalize(perp); break }
        }
        return idx.sorted {
            let a = v[$0] - m, b = v[$1] - m
            return atan2(simd_dot(a, e2), simd_dot(a, e1)) < atan2(simd_dot(b, e2), simd_dot(b, e1))
        }
    }

    /// Orbit index of each point under repeated application of `step`.
    static func orbits(_ points: [Vec4], step: Mat4) -> [Int] {
        func key(_ p: Vec4) -> [Int] { (0..<4).map { Int((p[$0] * 1e5).rounded()) } }
        var index: [[Int]: Int] = [:]
        for (i, p) in points.enumerated() { index[key(p)] = i }
        var ring = Array(repeating: -1, count: points.count)
        var next = 0
        for start in points.indices where ring[start] < 0 {
            var i = start
            while ring[i] < 0 {
                ring[i] = next
                guard let j = index[key(step * points[i])] else { break }
                i = j
            }
            next += 1
        }
        return ring
    }
}
