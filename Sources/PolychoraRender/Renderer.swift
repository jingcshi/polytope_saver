import Metal
import MetalKit
import simd
import PolytopeKit

/// Layout mirrors `Uniforms` in Polychora.metal.
struct Uniforms {
    var rot4: simd_float4x4
    var viewProj: simd_float4x4
    var cameraPos: SIMD4<Float>
    var proj: SIMD4<Float>
    var radii: SIMD4<Float>
    var fog: SIMD4<Float>
    var bgTop: SIMD4<Float>
    var bgBottom: SIMD4<Float>
    var edgeColor: SIMD4<Float>
    var vertexColor: SIMD4<Float>
    var faceColor: SIMD4<Float>
    var lightDir: SIMD4<Float>
    var palA: SIMD4<Float>
    var palB: SIMD4<Float>
    var palC: SIMD4<Float>
    var palD: SIMD4<Float>
    var style: SIMD4<Float>
    var viewport: SIMD4<Float>
    var pole: SIMD4<Float>
    var glow: SIMD4<Float>
    var glowShape: SIMD4<Float>
    var rimLight: SIMD4<Float>
    var highlight: SIMD4<Float>
    var hdr: SIMD4<Float>
}

/// Layout mirrors `Instance` in Polychora.metal.
struct Instance {
    var a: SIMD4<Float>
    var b: SIMD4<Float> = .zero
    var c: SIMD4<Float> = .zero
    var info: SIMD4<Float> = .zero
}

public final class Renderer {
    public static let depthFormat = MTLPixelFormat.depth32Float
    /// EDR output is float16 in extended-linear sRGB (same primaries as before, values may exceed 1);
    /// SDR output (snapshots) is 8-bit sRGB.
    public let hdr: Bool
    public var colorFormat: MTLPixelFormat { hdr ? .rgba16Float : .bgra8Unorm_srgb }
    /// Current EDR headroom of the target display (1 = SDR).
    public var headroom: Float = 1

    public enum Transition {
        /// Edges, vertices and faces burn away along 4D noise attached to the polytope.
        case dissolve
        /// Deprecated: plain cross-fade of the whole frame to the background. Kept for comparison.
        case fade
    }
    public var transition: Transition = .dissolve
    public var coloring: PolychoraSettings.Coloring = .signature

    public let device: MTLDevice
    public let sampleCount: Int
    public var theme: Theme = .ink

    private let queue: MTLCommandQueue
    private let shaderSource: () throws -> String
    private var pipelines: Pipelines?
    private let depthWrite: MTLDepthStencilState
    private let depthRead: MTLDepthStencilState
    private let depthOff: MTLDepthStencilState

    private let tube: Mesh
    private let sphere: Mesh
    private let grid: Mesh
    private var models: [PolytopeKind: Model] = [:]

    private struct Pipelines {
        let background, fade, edge, vertex, face: MTLRenderPipelineState
    }

    private struct Mesh {
        let vertices: MTLBuffer
        let indices: MTLBuffer
        let indexCount: Int
    }

    private struct Model {
        let polytope: Polytope
        let edges: MTLBuffer
        let vertices: MTLBuffer
        let faces: MTLBuffer
        let faceCount: Int
        let edgeRadius: Float
        /// Keyring framing: takes a cell centroid to the projection pole (0,0,0,1), so the pole sits on
        /// that centroid's Hopf fibre and every vertex ring stays bounded in the stereographic view.
        let framing: Mat4
    }

    public init(device: MTLDevice, sampleCount: Int, hdr: Bool = false, precompiledLibrary: URL? = nil,
                shaderSource: @escaping () throws -> String) throws {
        self.hdr = hdr
        self.precompiledLibrary = precompiledLibrary
        self.device = device
        self.sampleCount = sampleCount
        self.shaderSource = shaderSource
        queue = device.makeCommandQueue()!

        func depthState(_ compare: MTLCompareFunction, write: Bool) -> MTLDepthStencilState {
            let d = MTLDepthStencilDescriptor()
            d.depthCompareFunction = compare
            d.isDepthWriteEnabled = write
            return device.makeDepthStencilState(descriptor: d)!
        }
        depthWrite = depthState(.less, write: true)
        depthRead = depthState(.less, write: false)
        depthOff = depthState(.always, write: false)

        func mesh<V: BitwiseCopyable>(_ m: (vertices: [V], indices: [UInt32])) -> Mesh {
            Mesh(vertices: device.makeBuffer(bytes: m.vertices, length: MemoryLayout<V>.stride * m.vertices.count)!,
                 indices: device.makeBuffer(bytes: m.indices, length: 4 * m.indices.count)!,
                 indexCount: m.indices.count)
        }
        tube = mesh(Meshes.tube(segments: 32, sides: 10))
        sphere = mesh(Meshes.sphere(subdivisions: 2))
        grid = mesh(Meshes.triangleGrid(level: 8))

        try reloadShaders()
    }

    /// Shipped builds use a precompiled metallib; development compiles from source for hot reload.
    public var precompiledLibrary: URL?

    /// Recompile shaders; on failure the previous pipelines stay active.
    public func reloadShaders() throws {
        let library: MTLLibrary
        if let url = precompiledLibrary, let lib = try? device.makeLibrary(URL: url) {
            library = lib
        } else {
            let options = MTLCompileOptions()
            options.mathMode = .fast
            library = try device.makeLibrary(source: try shaderSource(), options: options)
        }

        func pipeline(_ vs: String, _ fs: String, blend: Bool, depth: Bool = true,
                      alphaToCoverage: Bool = false) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vs)
            d.fragmentFunction = library.makeFunction(name: fs)
            d.rasterSampleCount = sampleCount
            d.isAlphaToCoverageEnabled = alphaToCoverage && sampleCount > 1
            d.colorAttachments[0].pixelFormat = colorFormat
            d.depthAttachmentPixelFormat = Self.depthFormat
            if blend {
                let c = d.colorAttachments[0]!
                c.isBlendingEnabled = true
                c.sourceRGBBlendFactor = .one
                c.sourceAlphaBlendFactor = .one
                c.destinationRGBBlendFactor = .oneMinusSourceAlpha
                c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try device.makeRenderPipelineState(descriptor: d)
        }
        pipelines = Pipelines(
            background: try pipeline("background_vs", "background_fs", blend: false),
            fade: try pipeline("background_vs", "fade_fs", blend: true),
            edge: try pipeline("edge_vs", "opaque_fs", blend: false, alphaToCoverage: true),
            vertex: try pipeline("vertex_vs", "opaque_fs", blend: false, alphaToCoverage: true),
            face: try pipeline("face_vs", "face_fs", blend: true))
    }

    private func model(_ kind: PolytopeKind) -> Model {
        if let m = models[kind] { return m }
        let p = Polytope.make(kind)
        func f4(_ v: Vec4) -> SIMD4<Float> { SIMD4<Float>(v) }
        let rings = Float(max(p.ringCount, 1)), cellRings = Float(max(p.cellRingCount, 1))
        let singleRing = p.ringCount <= 1

        let edges = p.edges.map { e -> Instance in
            let r = p.vertexRing[e.x]
            let onRing = !singleRing && r == p.vertexRing[e.y]
            return Instance(a: f4(p.vertices[e.x]), b: f4(p.vertices[e.y]),
                            info: [onRing ? Float(r) / rings : -1, 0, 0, 0])
        }
        let verts = p.vertices.map { Instance(a: f4($0), info: [-1, 0, 0, 0]) }
        var tris: [Instance] = []
        for (fi, face) in p.faces.enumerated() {
            let cr = p.cellRing[p.faceCells[fi].x]
            let ring: Float = p.cellRingCount > 1 && cr == p.cellRing[p.faceCells[fi].y] ? Float(cr) / cellRings : -1
            for k in 1..<(face.count - 1) {
                tris.append(Instance(a: f4(p.vertices[face[0]]), b: f4(p.vertices[face[k]]),
                                     c: f4(p.vertices[face[k + 1]]), info: [ring, Float(fi), 0, 0]))
            }
        }
        func buffer(_ a: [Instance]) -> MTLBuffer {
            device.makeBuffer(bytes: a, length: MemoryLayout<Instance>.stride * a.count)!
        }
        let m = Model(polytope: p, edges: buffer(edges), vertices: buffer(verts), faces: buffer(tris),
                      faceCount: tris.count, edgeRadius: Float(0.016 * pow(p.edgeLength, 0.4)),
                      framing: Rotation4.aligning(p.cellCentres[0], to: Vec4(0, 0, 0, 1)))
        models[kind] = m
        return m
    }

    public func polytope(_ kind: PolytopeKind) -> Polytope { model(kind).polytope }

    /// Build geometry ahead of time so the first frame of each polytope doesn't stall.
    public func preload(_ kinds: [PolytopeKind]) { kinds.forEach { _ = model($0) } }

    private func uniforms(_ frame: FrameState, model m: Model, size: CGSize) -> Uniforms {
        let s = Float(frame.stereo)
        let d = 2.2 - 1.2 * s
        let camDistance = 4.6 + 0.6 * s
        let eye = SIMD3<Float>(0, 0, camDistance * Float(1 - frame.approach))
        let yaw = Float(frame.yaw)
        let forward = SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
        let aspect = Float(size.width / max(size.height, 1))
        let fovY: Float = 38 * .pi / 180
        let viewProj = perspective(fovY: fovY, aspect: aspect, near: 0.01, far: 100)
            * lookAt(eye: eye, target: eye + forward, up: [0, 1, 0])
        let t = theme
        let r = m.framing * frame.rotation
        let signature = coloring == .signature
        let colors = signature ? t.signatureColors(frame.kind) : (edge: t.edge, vertex: t.vertex, face: t.face)
        func c(_ v: SIMD3<Float>) -> SIMD4<Float> { SIMD4<Float>(v, 1) }
        // EDR: highlights roll off towards min(theme peak, display headroom); the highlight gain only
        // applies to the extent the display has headroom, so SDR output is unchanged.
        let ceiling = max(1, min(t.peak, headroom))
        let hdrActive = min(max(headroom - 1, 0), 1)
        return Uniforms(
            rot4: simd_float4x4(columns: (SIMD4<Float>(r.columns.0), SIMD4<Float>(r.columns.1),
                                          SIMD4<Float>(r.columns.2), SIMD4<Float>(r.columns.3))),
            viewProj: viewProj,
            cameraPos: c(eye),
            proj: [d, s, d, 0.02],
            radii: [m.edgeRadius, m.edgeRadius * 1.4, Float(frame.fade), 0],
            fog: [t.fogDensity, 0.15, 0.9, signature ? t.faceAlpha * t.signature.faceAlphaScale : t.faceAlpha],
            bgTop: c(t.backgroundTop), bgBottom: c(t.backgroundBottom),
            edgeColor: c(colors.edge), vertexColor: c(colors.vertex), faceColor: c(colors.face),
            lightDir: SIMD4<Float>(t.lightDir, 0),
            palA: c(t.palette.a), palB: c(t.palette.b), palC: c(t.palette.c), palD: c(t.palette.d),
            style: [signature ? 0 : t.ringMix, t.fresnelPower, t.specular, transition == .dissolve ? 1 : 0],
            viewport: [Float(size.width), Float(size.height), 1 / tan(fovY / 2), 0],
            pole: [2.5, 3, 9, 0],
            glow: t.glowUniforms.0, glowShape: t.glowUniforms.1,
            rimLight: SIMD4<Float>(t.rim, 0),
            highlight: SIMD4<Float>(t.highlight, t.highlightGain),
            hdr: [ceiling, hdrActive, 0, 0])
    }

    public func encode(_ frame: FrameState, pass: MTLRenderPassDescriptor, size: CGSize,
                       commandBuffer: MTLCommandBuffer) {
        guard let p = pipelines, let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let m = model(frame.kind)
        var u = uniforms(frame, model: m, size: size)
        let uSize = MemoryLayout<Uniforms>.stride

        enc.setVertexBytes(&u, length: uSize, index: 2)
        enc.setFragmentBytes(&u, length: uSize, index: 0)

        enc.setDepthStencilState(depthOff)
        enc.setRenderPipelineState(p.background)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        func draw(_ mesh: Mesh, _ inst: MTLBuffer, count: Int) {
            enc.setVertexBuffer(mesh.vertices, offset: 0, index: 0)
            enc.setVertexBuffer(inst, offset: 0, index: 1)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: mesh.indexCount, indexType: .uint32,
                                      indexBuffer: mesh.indices, indexBufferOffset: 0, instanceCount: count)
        }
        enc.setDepthStencilState(depthWrite)
        enc.setRenderPipelineState(p.edge)
        draw(tube, m.edges, count: m.polytope.edges.count)
        enc.setRenderPipelineState(p.vertex)
        draw(sphere, m.vertices, count: m.polytope.vertices.count)

        enc.setDepthStencilState(depthRead)
        enc.setCullMode(.none)
        enc.setRenderPipelineState(p.face)
        draw(grid, m.faces, count: m.faceCount)

        if transition == .fade, frame.fade < 0.999 {
            enc.setDepthStencilState(depthOff)
            enc.setRenderPipelineState(p.fade)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        enc.endEncoding()
    }

    /// Returns false if no drawable was available.
    @discardableResult
    public func draw(_ frame: FrameState, in view: MTKView) -> Bool {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let cb = queue.makeCommandBuffer() else { return false }
        let target = drawable.texture
        encode(frame, pass: pass, size: CGSize(width: target.width, height: target.height), commandBuffer: cb)
        cb.present(drawable)
        cb.commit()
        return true
    }

    /// Render one frame offscreen and return it as an sRGB image.
    public func snapshot(_ frame: FrameState, width: Int, height: Int) -> CGImage? {
        func texture(_ format: MTLPixelFormat, samples: Int, usage: MTLTextureUsage, storage: MTLStorageMode) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
            d.textureType = samples > 1 ? .type2DMultisample : .type2D
            d.sampleCount = samples
            d.usage = usage
            d.storageMode = storage
            return device.makeTexture(descriptor: d)!
        }
        precondition(!hdr, "snapshots read back 8-bit sRGB; use an SDR renderer")
        let resolve = texture(colorFormat, samples: 1, usage: [.renderTarget, .shaderRead], storage: .shared)
        let pass = MTLRenderPassDescriptor()
        if sampleCount > 1 {
            pass.colorAttachments[0].texture = texture(colorFormat, samples: sampleCount, usage: .renderTarget, storage: .private)
            pass.colorAttachments[0].resolveTexture = resolve
            pass.colorAttachments[0].storeAction = .multisampleResolve
        } else {
            pass.colorAttachments[0].texture = resolve
            pass.colorAttachments[0].storeAction = .store
        }
        pass.colorAttachments[0].loadAction = .clear
        pass.depthAttachment.texture = texture(Self.depthFormat, samples: sampleCount, usage: .renderTarget, storage: .private)
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1

        guard let cb = queue.makeCommandBuffer() else { return nil }
        encode(frame, pass: pass, size: CGSize(width: width, height: height), commandBuffer: cb)
        cb.commit()
        cb.waitUntilCompleted()

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        resolve.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                                                | CGImageAlphaInfo.premultipliedFirst.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

// MARK: Matrices (right-handed view, Metal clip depth 0…1)

func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
    let y = 1 / tan(fovY / 2), x = y / aspect, z = far / (near - far)
    return simd_float4x4(columns: ([x, 0, 0, 0], [0, y, 0, 0], [0, 0, z, -1], [0, 0, z * near, 0]))
}

func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
    let f = simd_normalize(target - eye)
    let s = simd_normalize(simd_cross(f, up))
    let u = simd_cross(s, f)
    return simd_float4x4(columns: (
        [s.x, u.x, -f.x, 0], [s.y, u.y, -f.y, 0], [s.z, u.z, -f.z, 0],
        [-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1]))
}
