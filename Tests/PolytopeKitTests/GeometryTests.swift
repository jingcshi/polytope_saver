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

    /// Adjacent cells meet at 180° minus the angle between their outward normals.
    @Test(arguments: PolytopeKind.allCases)
    func dichoralAngle(_ kind: PolytopeKind) {
        let p = Polytope.make(kind)
        let pair = p.faceCells[0]
        let normalAngle = acos(simd_dot(p.cellCentres[pair.x], p.cellCentres[pair.y])) * 180 / .pi
        #expect(abs((180 - normalAngle) - kind.info.dichoralAngle) < 1e-3)
    }

    /// Keyring framing: with a cell centroid at the projection pole, the point at the pole over a
    /// full turn of the natural rotation traces the fibre through that centroid and never meets a vertex.
    @Test(arguments: PolytopeKind.allCases)
    func keyringPoleAvoidsVertices(_ kind: PolytopeKind) {
        let p = Polytope.make(kind)
        let pole = Vec4(0, 0, 0, 1)
        let frame = Rotation4.aligning(p.cellCentres[0], to: pole)
        #expect(simd_distance(frame * p.cellCentres[0], pole) < 1e-9)
        #expect(abs(simd_determinant(frame) - 1) < 1e-9)
        let (rotation, _) = kind.naturalRotation
        var closest = Double.infinity
        for k in 0..<2000 {
            // Object-space point shown at the pole when the rendered matrix is frame · R(θ).
            let m = frame * rotation.matrix(2 * .pi * Double(k) / 2000)
            let atPole = m.inverse * pole
            for v in p.vertices { closest = min(closest, simd_distance(v, atPole)) }
        }
        #expect(closest > 0.1 * p.edgeLength)
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
