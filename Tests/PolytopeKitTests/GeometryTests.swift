import Testing
import simd
@testable import PolytopeKit

private let expected: [PolytopeKind: (v: Int, e: Int, f: Int, c: Int, faceSize: Int, cellSize: Int)] = [
    .cell5: (5, 10, 10, 5, 3, 4),
    .cell8: (16, 32, 24, 8, 4, 8),
    .cell16: (8, 24, 32, 16, 3, 4),
    .cell24: (24, 96, 96, 24, 3, 6),
    .cell120: (600, 1200, 720, 120, 5, 20),
    .cell600: (120, 720, 1200, 600, 3, 4),
]

@Suite struct GeometryTests {
    @Test(arguments: PolytopeKind.allCases)
    func counts(_ kind: PolytopeKind) {
        let p = Polytope.make(kind)
        let x = expected[kind]!
        #expect(p.vertices.count == x.v)
        #expect(p.edges.count == x.e)
        #expect(p.faces.count == x.f)
        #expect(p.cells.count == x.c)
        #expect(p.faces.allSatisfy { $0.count == x.faceSize })
        #expect(p.cells.allSatisfy { $0.count == x.cellSize })
        #expect(p.vertices.count - p.edges.count + p.faces.count - p.cells.count == 0)
    }

    @Test(arguments: PolytopeKind.allCases)
    func onUnitSphere(_ kind: PolytopeKind) {
        let p = Polytope.make(kind)
        #expect(p.vertices.allSatisfy { abs(simd_length($0) - 1) < 1e-9 })
    }

    @Test(arguments: PolytopeKind.allCases)
    func facesAreCyclic(_ kind: PolytopeKind) {
        let p = Polytope.make(kind)
        let l = p.edgeLength
        for f in p.faces {
            for k in f.indices {
                let d = simd_distance(p.vertices[f[k]], p.vertices[f[(k + 1) % f.count]])
                #expect(abs(d - l) < 1e-9)
            }
        }
    }

    /// The natural rotation by one period is a symmetry, and its orbits partition evenly.
    @Test(arguments: PolytopeKind.allCases)
    func naturalRotationIsSymmetry(_ kind: PolytopeKind) {
        let p = Polytope.make(kind)
        let (rotation, period) = kind.naturalRotation
        let m = rotation.matrix(period)
        for v in p.vertices {
            let w = m * v
            #expect(p.vertices.contains { simd_distance($0, w) < 1e-9 })
        }
        let sizes = Dictionary(grouping: p.vertexRing, by: { $0 }).values.map(\.count)
        #expect(Set(sizes).count == 1)
        let cellSizes = Dictionary(grouping: p.cellRing, by: { $0 }).values.map(\.count)
        #expect(Set(cellSizes).count == 1)
    }
}
