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
    var metal: SIMD4<Float>
    var metalTint: SIMD4<Float>
    var glass: SIMD4<Float>
    var cellColor: SIMD4<Float>
    var cells: SIMD4<Float>
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
    public var surfaces: PolychoraSettings.Surfaces = .faces
    public var frameColors: PolychoraSettings.FrameColors = .steel

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
    private var models: [PolytopeKind: Model] = [:]

    private struct Pipelines {
        let background, fade, edge, vertex, face, cell, composite: MTLRenderPipelineState
    }

    /// Weighted blended order-independent transparency (McGuire & Bavoil 2013) for faces and cells.
    /// The accumulation targets are memoryless: they live in tile memory for the duration of the pass.
    static let accumFormat = MTLPixelFormat.rgba16Float
    static let revealFormat = MTLPixelFormat.r16Float

    /// Single-sample targets of the transparent pass: OIT accumulators and the frame's depth,
    /// resolved from the multisampled pass so the tubes still hide the glass behind them.
    private struct TransparentTargets { let accum, reveal, depth: MTLTexture }
    private var transparentTargets: TransparentTargets?

    private func transparentTargets(width: Int, height: Int) -> TransparentTargets {
        if let t = transparentTargets, t.depth.width == width, t.depth.height == height { return t }
        func make(_ format: MTLPixelFormat, _ storage: MTLStorageMode) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
            d.usage = .renderTarget
            d.storageMode = storage
            return device.makeTexture(descriptor: d)!
        }
        let t = TransparentTargets(accum: make(Self.accumFormat, .memoryless), reveal: make(Self.revealFormat, .memoryless),
                                   depth: make(Self.depthFormat, .private))
        transparentTargets = t
        return t
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
        let grid: Mesh
        /// Every cell's faces at full size (the shader scales them by `kCellScale`); info.x is the highlight
        /// group (Hopf ring, or the cell itself without rings), info.y the cell index.
        let cellTris: MTLBuffer
        /// `cellTris` is sorted by highlight group; each group's instance range.
        let groupRanges: [Range<Int>]
        var highlightGroups: Int { groupRanges.count }
        let cellGrid: Mesh
        /// Unrotated 4D centroid of each cell (not normalised).
        let cellCentroids: MTLBuffer
        /// Unrotated 4D centroid of each face (not normalised), indexed by the face triangles' info.y.
        let faceCentroids: MTLBuffer
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

        tube = Self.mesh(device, Meshes.tube(segments: 32, sides: 10))
        sphere = Self.mesh(device, Meshes.sphere(subdivisions: 2))

        try reloadShaders()
    }

    private static func mesh<V: BitwiseCopyable>(_ device: MTLDevice, _ m: (vertices: [V], indices: [UInt32])) -> Mesh {
        Mesh(vertices: device.makeBuffer(bytes: m.vertices, length: MemoryLayout<V>.stride * m.vertices.count)!,
             indices: device.makeBuffer(bytes: m.indices, length: 4 * m.indices.count)!,
             indexCount: m.indices.count)
    }

    /// Face tessellation, shared by polytopes with the same level.
    private var grids: [Int: Mesh] = [:]
    private func grid(level: Int) -> Mesh {
        if let g = grids[level] { return g }
        let g = Self.mesh(device, Meshes.triangleGrid(level: level))
        grids[level] = g
        return g
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

        // Opaque pipelines run in the multisampled pass (colour only). Transparent ones run in the
        // single-sample pass, which always carries the two OIT attachments; only faces / cells write them.
        func pipeline(_ vs: String, _ fs: String, blend: Bool, alphaToCoverage: Bool = false,
                      transparent: Bool = false, accumulate: Bool = false) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vs)
            d.fragmentFunction = library.makeFunction(name: fs)
            d.rasterSampleCount = transparent ? 1 : sampleCount
            d.isAlphaToCoverageEnabled = alphaToCoverage && sampleCount > 1
            d.colorAttachments[0].pixelFormat = colorFormat
            if transparent {
                d.colorAttachments[1].pixelFormat = Self.accumFormat
                d.colorAttachments[2].pixelFormat = Self.revealFormat
            }
            d.depthAttachmentPixelFormat = Self.depthFormat
            if blend {
                let c = d.colorAttachments[0]!
                c.isBlendingEnabled = true
                c.sourceRGBBlendFactor = .one
                c.sourceAlphaBlendFactor = .one
                c.destinationRGBBlendFactor = .oneMinusSourceAlpha
                c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            if accumulate {
                d.colorAttachments[0].writeMask = []
                let a = d.colorAttachments[1]!    // Σ w·(premultiplied colour, α)
                a.isBlendingEnabled = true
                a.sourceRGBBlendFactor = .one; a.sourceAlphaBlendFactor = .one
                a.destinationRGBBlendFactor = .one; a.destinationAlphaBlendFactor = .one
                let r = d.colorAttachments[2]!    // Π (1 − α)
                r.isBlendingEnabled = true
                r.sourceRGBBlendFactor = .zero; r.sourceAlphaBlendFactor = .zero
                r.destinationRGBBlendFactor = .oneMinusSourceColor; r.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            } else if transparent {
                d.colorAttachments[1].writeMask = []
                d.colorAttachments[2].writeMask = []
            }
            return try device.makeRenderPipelineState(descriptor: d)
        }
        pipelines = Pipelines(
            background: try pipeline("background_vs", "background_fs", blend: false),
            fade: try pipeline("background_vs", "fade_fs", blend: true, transparent: true),
            edge: try pipeline("edge_vs", "opaque_fs", blend: false, alphaToCoverage: true),
            vertex: try pipeline("vertex_vs", "opaque_fs", blend: false, alphaToCoverage: true),
            face: try pipeline("face_vs", "face_fs", blend: false, transparent: true, accumulate: true),
            cell: try pipeline("cell_vs", "cell_fs", blend: false, transparent: true, accumulate: true),
            composite: try pipeline("background_vs", "oit_composite_fs", blend: true, transparent: true))
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
            // Fan triangle (a, b, c): bc is always on the polygon border; ab only for the first
            // triangle (flag 1), ac only for the last (flag 2).
            for k in 1..<(face.count - 1) {
                let border = (k == 1 ? 1 : 0) + (k == face.count - 2 ? 2 : 0)
                tris.append(Instance(a: f4(p.vertices[face[0]]), b: f4(p.vertices[face[k]]),
                                     c: f4(p.vertices[face[k + 1]]), info: [ring, Float(fi), Float(border), 0]))
            }
        }
        let centroids = p.cells.map { c in c.reduce(Vec4.zero) { $0 + p.vertices[$1] } / Double(c.count) }
        let byRing = p.cellRingCount > 1
        let groupCount = byRing ? p.cellRingCount : p.cells.count
        var groups = [[Instance]](repeating: [], count: groupCount)
        for (fi, face) in p.faces.enumerated() {
            for cell in [p.faceCells[fi].x, p.faceCells[fi].y] {
                let group = byRing ? p.cellRing[cell] : cell
                for k in 1..<(face.count - 1) {
                    groups[group].append(Instance(a: f4(p.vertices[face[0]]), b: f4(p.vertices[face[k]]),
                                                  c: f4(p.vertices[face[k + 1]]), info: [Float(group), Float(cell), 0, 0]))
                }
            }
        }
        let cellTris = groups.flatMap { $0 }
        var groupRanges: [Range<Int>] = []
        for g in groups { let start = groupRanges.last?.upperBound ?? 0; groupRanges.append(start..<(start + g.count)) }
        func buffer<T>(_ a: [T]) -> MTLBuffer {
            device.makeBuffer(bytes: a, length: MemoryLayout<T>.stride * a.count)!
        }
        // Same grid spacing on S³ for every polytope (≈ 0.04 of the unit radius), so large
        // stereographic bubbles keep a smooth silhouette.
        func gridLevel(_ length: Double) -> Int { min(max(Int((length / 0.04).rounded(.up)), 8), 48) }
        let m = Model(polytope: p, edges: buffer(edges), vertices: buffer(verts), faces: buffer(tris),
                      faceCount: tris.count,
                      grid: grid(level: gridLevel(p.edgeLength)),
                      cellTris: buffer(cellTris), groupRanges: groupRanges,
                      // Budget of the earlier 70% cells, measured at a steady 120 fps on the 600-cell.
                      cellGrid: grid(level: gridLevel(p.edgeLength * 0.7)),
                      cellCentroids: buffer(centroids.map { SIMD4<Float>($0) }),
                      faceCentroids: buffer(p.faces.map { f in
                          SIMD4<Float>(f.reduce(Vec4.zero) { $0 + p.vertices[$1] } / Double(f.count))
                      }),
                      edgeRadius: Float(0.012 * pow(p.edgeLength, 0.4)),
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
        let face = signature ? t.signatureColors(frame.kind).face : t.face
        // Joints take the tube colour too, so the frame stays one casting.
        let metal = frameColors == .signature ? t.signatureColors(frame.kind).edge : t.edge
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
            radii: [m.edgeRadius, m.edgeRadius, Float(frame.fade), 0],
            fog: [t.fogDensity, 0.15, 0.9, signature ? t.faceAlpha * t.signature.faceAlphaScale : t.faceAlpha],
            bgTop: c(t.backgroundTop), bgBottom: c(t.backgroundBottom),
            edgeColor: c(metal), vertexColor: c(metal), faceColor: c(face),
            lightDir: SIMD4<Float>(t.lightDir, 0),
            palA: c(t.palette.a), palB: c(t.palette.b), palC: c(t.palette.c), palD: c(t.palette.d),
            style: [signature ? 0 : t.ringMix, t.fresnelPower, t.specular, transition == .dissolve ? 1 : 0],
            viewport: [Float(size.width), Float(size.height), 1 / tan(fovY / 2), 0],
            pole: [2.5, 3, 9, 0],
            glow: t.glowUniforms.0, glowShape: t.glowUniforms.1,
            rimLight: SIMD4<Float>(t.rim, 0),
            highlight: SIMD4<Float>(t.highlight, t.highlightGain),
            hdr: [ceiling, hdrActive, 0, 0],
            metal: [t.metal.sharpness, t.metal.reflection, t.metal.softbox, t.metal.diffuse],
            metalTint: [t.metal.tint, 0, 0, 0],
            glass: [t.glass.glassAlpha, t.glass.bubbleAlpha, t.glass.seam, 0],
            cellColor: t.cellColor(frame.kind),
            // Phase wrapped per group cycle to keep float precision over long sessions.
            cells: [Float(frame.highlight.truncatingRemainder(dividingBy: Double(m.highlightGroups))),
                    Float(m.highlightGroups), Float(Slideshow.highlightHandoverStart), 0])
    }

    public func encode(_ frame: FrameState, pass: MTLRenderPassDescriptor, size: CGSize,
                       commandBuffer: MTLCommandBuffer) {
        guard let p = pipelines, let target = pass.colorAttachments[0].texture else { return }
        let t = transparentTargets(width: target.width, height: target.height)
        let m = model(frame.kind)
        var u = uniforms(frame, model: m, size: size)
        let uSize = MemoryLayout<Uniforms>.stride

        // Pass 1, multisampled: background and frame. Colour resolves into the output as configured by
        // the caller; depth resolves (or, single-sampled, is stored) into `t.depth` for pass 2.
        if sampleCount > 1 {
            pass.depthAttachment.resolveTexture = t.depth
            pass.depthAttachment.depthResolveFilter = .sample0
            pass.depthAttachment.storeAction = .multisampleResolve
        } else {
            pass.depthAttachment.texture = t.depth
            pass.depthAttachment.storeAction = .store
        }
        func draw(_ enc: MTLRenderCommandEncoder, _ mesh: Mesh, _ inst: MTLBuffer, count: Int) {
            enc.setVertexBuffer(mesh.vertices, offset: 0, index: 0)
            enc.setVertexBuffer(inst, offset: 0, index: 1)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: mesh.indexCount, indexType: .uint32,
                                      indexBuffer: mesh.indices, indexBufferOffset: 0, instanceCount: count)
        }

        guard let opaque = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        opaque.setVertexBytes(&u, length: uSize, index: 2)
        opaque.setFragmentBytes(&u, length: uSize, index: 0)
        opaque.setDepthStencilState(depthOff)
        opaque.setRenderPipelineState(p.background)
        opaque.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        opaque.setDepthStencilState(depthWrite)
        opaque.setRenderPipelineState(p.edge)
        draw(opaque, tube, m.edges, count: m.polytope.edges.count)
        opaque.setRenderPipelineState(p.vertex)
        draw(opaque, sphere, m.vertices, count: m.polytope.vertices.count)
        opaque.endEncoding()

        // Pass 2, single-sampled: faces / cells into the OIT accumulators over the resolved frame. The
        // bubbles' soft Fresnel edges need no multisampling, and blending once per pixel rather than per
        // sample is most of their cost.
        let second = MTLRenderPassDescriptor()
        second.colorAttachments[0].texture = pass.colorAttachments[0].resolveTexture ?? target
        second.colorAttachments[0].loadAction = .load
        second.colorAttachments[0].storeAction = .store
        for (i, tex, clear) in [(1, t.accum, MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)),
                                (2, t.reveal, MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1))] {
            let a = second.colorAttachments[i]!
            a.texture = tex
            a.loadAction = .clear
            a.storeAction = .dontCare
            a.clearColor = clear
        }
        second.depthAttachment.texture = t.depth
        second.depthAttachment.loadAction = .load
        second.depthAttachment.storeAction = .dontCare
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: second) else { return }
        enc.setVertexBytes(&u, length: uSize, index: 2)
        enc.setFragmentBytes(&u, length: uSize, index: 0)

        enc.setDepthStencilState(depthRead)
        enc.setCullMode(.none)
        switch surfaces {
        case .none:
            break
        case .faces:
            enc.setRenderPipelineState(p.face)
            enc.setVertexBuffer(m.faceCentroids, offset: 0, index: 3)
            draw(enc, m.grid, m.faces, count: m.faceCount)
        case .cells:
            enc.setRenderPipelineState(p.cell)
            enc.setVertexBuffer(m.cellCentroids, offset: 0, index: 3)
            enc.setVertexBuffer(m.cellGrid.vertices, offset: 0, index: 0)
            enc.setVertexBuffer(m.cellTris, offset: 0, index: 1)
            // Only the highlighted ring is drawn, plus the next one during the hand-over (as in cell_vs).
            let n = m.highlightGroups
            let phase = frame.highlight.truncatingRemainder(dividingBy: Double(n))
            let current = Int(phase)
            let handover = smoothstep(Slideshow.highlightHandoverStart, 1.0, phase - Double(current))
            for g in handover > 0 ? [current, (current + 1) % n] : [current] {
                let r = m.groupRanges[g]
                enc.drawIndexedPrimitives(type: .triangle, indexCount: m.cellGrid.indexCount, indexType: .uint32,
                                          indexBuffer: m.cellGrid.indices, indexBufferOffset: 0,
                                          instanceCount: r.count, baseVertex: 0, baseInstance: r.lowerBound)
            }
        }

        enc.setDepthStencilState(depthOff)
        enc.setRenderPipelineState(p.composite)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        if transition == .fade, frame.fade < 0.999 {
            enc.setDepthStencilState(depthOff)
            enc.setRenderPipelineState(p.fade)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        enc.endEncoding()
    }

    /// Presents at least `interval` seconds after the previous frame, so reduced frame rates hold
    /// each frame for the same number of refreshes. Returns false if no drawable was available.
    @discardableResult
    public func draw(_ frame: FrameState, in view: MTKView, interval: Double = 0) -> Bool {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let cb = queue.makeCommandBuffer() else { return false }
        let target = drawable.texture
        encode(frame, pass: pass, size: CGSize(width: target.width, height: target.height), commandBuffer: cb)
        if interval > 0 {
            cb.present(drawable, afterMinimumDuration: interval)
        } else {
            cb.present(drawable)
        }
        cb.commit()
        return true
    }

    /// GPU milliseconds for each of `frames` offscreen renders, the rotation advancing between them
    /// (development benchmark: compares rendering modes at a given drawable size).
    public func gpuTimes(_ show: Slideshow, width: Int, height: Int, frames: Int) -> [Double] {
        let (pass, _) = offscreenPass(width: width, height: height)
        var times: [Double] = []
        for _ in 0..<frames {
            show.advance(by: 1.0 / 120)
            guard let cb = queue.makeCommandBuffer() else { break }
            encode(show.frame(), pass: pass, size: CGSize(width: width, height: height), commandBuffer: cb)
            cb.commit()
            cb.waitUntilCompleted()
            times.append((cb.gpuEndTime - cb.gpuStartTime) * 1000)
        }
        return times
    }

    /// Render one frame offscreen and return it as an sRGB image.
    public func snapshot(_ frame: FrameState, width: Int, height: Int) -> CGImage? {
        precondition(!hdr, "snapshots read back 8-bit sRGB; use an SDR renderer")
        let (pass, resolve) = offscreenPass(width: width, height: height)
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

    /// Offscreen pass (multisampled when sampleCount > 1) and its single-sample resolve texture.
    private func offscreenPass(width: Int, height: Int) -> (MTLRenderPassDescriptor, MTLTexture) {
        func texture(_ format: MTLPixelFormat, samples: Int, usage: MTLTextureUsage, storage: MTLStorageMode) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
            d.textureType = samples > 1 ? .type2DMultisample : .type2D
            d.sampleCount = samples
            d.usage = usage
            d.storageMode = storage
            return device.makeTexture(descriptor: d)!
        }
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
        return (pass, resolve)
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
