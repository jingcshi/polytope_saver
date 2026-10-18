import simd

public enum PolytopeKind: Int, CaseIterable, Codable, Sendable {
    case cell5, cell8, cell16, cell24, cell120, cell600
}

public struct PolytopeInfo: Sendable {
    public let name: String
    public let altName: String
    public let schlafli: String
    public let cellType: String
    public let faceType: String
    public let vertexFigure: String
    public let symmetry: String
    public let symmetryOrder: Int
    /// 3D analogue of the polytope. 24-cell is unique to 4D.
    public let analogue: String
    /// Interior angle between adjacent cells, in degrees.
    public let dichoralAngle: Double
    public let dual: String
}

extension PolytopeKind {
    public var info: PolytopeInfo {
        switch self {
        case .cell5:
            return PolytopeInfo(name: "5-cell", altName: "pentachoron", schlafli: "{3,3,3}",
                                cellType: "tetrahedra", faceType: "triangles", vertexFigure: "tetrahedron",
                                symmetry: "A₄", symmetryOrder: 120, analogue: "tetrahedron", dichoralAngle: 75.5225, dual: "self-dual")
        case .cell8:
            return PolytopeInfo(name: "8-cell", altName: "tesseract", schlafli: "{4,3,3}",
                                cellType: "cubes", faceType: "squares", vertexFigure: "tetrahedron",
                                symmetry: "B₄", symmetryOrder: 384, analogue: "cube", dichoralAngle: 90, dual: "16-cell")
        case .cell16:
            return PolytopeInfo(name: "16-cell", altName: "hexadecachoron", schlafli: "{3,3,4}",
                                cellType: "tetrahedra", faceType: "triangles", vertexFigure: "octahedron",
                                symmetry: "B₄", symmetryOrder: 384, analogue: "octahedron", dichoralAngle: 120, dual: "8-cell")
        case .cell24:
            return PolytopeInfo(name: "24-cell", altName: "icositetrachoron", schlafli: "{3,4,3}",
                                cellType: "octahedra", faceType: "triangles", vertexFigure: "cube",
                                symmetry: "F₄", symmetryOrder: 1152, analogue: "none", dichoralAngle: 120, dual: "self-dual")
        case .cell120:
            return PolytopeInfo(name: "120-cell", altName: "hecatonicosachoron", schlafli: "{5,3,3}",
                                cellType: "dodecahedra", faceType: "pentagons", vertexFigure: "tetrahedron",
                                symmetry: "H₄", symmetryOrder: 14400, analogue: "dodecahedron", dichoralAngle: 144, dual: "600-cell")
        case .cell600:
            return PolytopeInfo(name: "600-cell", altName: "hexacosichoron", schlafli: "{3,3,5}",
                                cellType: "tetrahedra", faceType: "triangles", vertexFigure: "icosahedron",
                                symmetry: "H₄", symmetryOrder: 14400, analogue: "icosahedron", dichoralAngle: 164.4775, dual: "120-cell")
        }
    }

    var isSimplicial: Bool { self == .cell5 || self == .cell16 || self == .cell600 }

    /// Rotation whose orbits follow the polytope's rings, and the smallest angle
    /// at which it maps the polytope onto itself.
    public var naturalRotation: (rotation: NaturalRotation, period: Double) {
        let phi = (1 + 5.0.squareRoot()) / 2
        switch self {
        case .cell5: return (.petrie, 2 * .pi / 5)
        case .cell8, .cell16: return (.leftIsoclinic(axis: [1, 0, 0]), .pi / 2)
        case .cell24: return (.leftIsoclinic(axis: [1, 1, 1]), .pi / 3)
        case .cell120, .cell600: return (.leftIsoclinic(axis: [1, 1 / phi, 0]), .pi / 5)
        }
    }
}

/// A regular 4-polytope inscribed in the unit 3-sphere.
public struct Polytope: Sendable {
    public let kind: PolytopeKind
    public let vertices: [Vec4]
    public let edges: [SIMD2<Int>]
    /// Vertex indices of each face, in cyclic order.
    public let faces: [[Int]]
    /// The two cells sharing each face.
    public let faceCells: [SIMD2<Int>]
    public let cells: [[Int]]
    /// Unit direction of each cell's centre.
    public let cellCentres: [Vec4]
    /// Orbit index of each vertex / cell under the natural rotation's period step.
    public let vertexRing: [Int]
    public let cellRing: [Int]

    public var edgeLength: Double { simd_distance(vertices[edges[0].x], vertices[edges[0].y]) }
    public var ringCount: Int { (vertexRing.max() ?? -1) + 1 }
    public var cellRingCount: Int { (cellRing.max() ?? -1) + 1 }
}
