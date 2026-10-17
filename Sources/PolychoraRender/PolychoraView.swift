import AppKit
import MetalKit
import PolytopeKit

/// Host-agnostic content view: Metal scene plus overlay. Used by the saver and the preview app.
public final class PolychoraView: NSView, MTKViewDelegate {
    public let renderer: Renderer
    public let slideshow: Slideshow
    public var paused = false

    private let mtkView: MTKView
    private let overlay: OverlayView
    private let isPreview: Bool
    private var lastTime: CFTimeInterval?

    public var settings: PolychoraSettings {
        get { slideshow.settings }
        set {
            slideshow.settings = newValue
            renderer.theme = Theme.named(newValue.theme)
            overlay.theme = renderer.theme
            overlay.showInfo = newValue.showInfo && !isPreview
            overlay.showClock = newValue.showClock && !isPreview
        }
    }

    public init?(frame: NSRect, settings: PolychoraSettings, isPreview: Bool,
                 precompiledLibrary: URL? = nil, shaderSource: @escaping () throws -> String) {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let samples = isPreview ? 1 : 4
        do {
            renderer = try Renderer(device: device, sampleCount: samples, precompiledLibrary: precompiledLibrary,
                                    shaderSource: shaderSource)
        } catch {
            NSLog("Polychora: renderer init failed: \(error)")
            return nil
        }
        self.isPreview = isPreview
        slideshow = Slideshow(settings: settings)
        mtkView = MTKView(frame: NSRect(origin: .zero, size: frame.size), device: device)
        overlay = OverlayView(frame: NSRect(origin: .zero, size: frame.size))
        super.init(frame: frame)

        mtkView.colorPixelFormat = Renderer.colorFormat
        mtkView.depthStencilPixelFormat = Renderer.depthFormat
        mtkView.sampleCount = samples
        mtkView.preferredFramesPerSecond = isPreview ? 30 : 120
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.delegate = self
        for v in [mtkView, overlay] as [NSView] {
            v.autoresizingMask = [.width, .height]
            addSubview(v)
        }
        overlay.polytope = { [unowned self] in self.renderer.polytope($0) }
        self.settings = settings
        renderer.preload([slideshow.frame().kind])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Stop rendering for good (saver teardown).
    public func stop() {
        mtkView.isPaused = true
        mtkView.delegate = nil
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = lastTime.map { min(now - $0, 0.1) } ?? 0
        lastTime = now
        if !paused { slideshow.advance(by: dt) }
        let frame = slideshow.frame()
        renderer.draw(frame, in: view)
        overlay.update(frame)
    }
}
