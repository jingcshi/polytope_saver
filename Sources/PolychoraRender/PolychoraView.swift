import AppKit
import MetalKit
import os
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
    private var renderedFrames = 0
    private var missedFrames = 0
    private let log = Logger(subsystem: "com.jingcshi.Polychora", category: "view")

    public var settings: PolychoraSettings {
        get { slideshow.settings }
        set {
            slideshow.settings = newValue
            renderer.theme = Theme.named(newValue.theme)
            overlay.theme = renderer.theme
            overlay.layout = newValue.overlayLayout
            overlay.showInfo = newValue.showInfo && !isPreview
            overlay.showClock = newValue.showClock && !isPreview
        }
    }

    public init?(frame: NSRect, settings: PolychoraSettings, isPreview: Bool,
                 precompiledLibrary: URL? = nil, shaderSource: @escaping () throws -> String) {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let samples = isPreview ? 1 : 4
        do {
            renderer = try Renderer(device: device, sampleCount: samples, hdr: !isPreview,
                                    precompiledLibrary: precompiledLibrary, shaderSource: shaderSource)
        } catch {
            NSLog("Polychora: renderer init failed: \(error)")
            return nil
        }
        self.isPreview = isPreview
        slideshow = Slideshow(settings: settings)
        mtkView = MTKView(frame: NSRect(origin: .zero, size: frame.size), device: device)
        overlay = OverlayView(frame: NSRect(origin: .zero, size: frame.size))
        super.init(frame: frame)

        mtkView.colorPixelFormat = renderer.colorFormat
        if renderer.hdr {
            mtkView.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
            (mtkView.layer as? CAMetalLayer)?.wantsExtendedDynamicRangeContent = true
        }
        mtkView.depthStencilPixelFormat = Renderer.depthFormat
        mtkView.sampleCount = samples
        mtkView.preferredFramesPerSecond = isPreview ? 30 : 120
        mtkView.isPaused = false
        mtkView.autoResizeDrawable = false
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

    /// Size the view to the screen its window sits on, regardless of the frame the host assigns.
    public var fitsScreen = false
    private var stopped = false
    private var lastResize = Date.distantPast
    private var unclipped = false

    /// Stop rendering for good (saver teardown).
    public func stop() {
        stopped = true
        mtkView.isPaused = true
        mtkView.delegate = nil
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let screen = window?.screen
        log.notice("""
            moved to window: frame=\(NSStringFromRect(self.frame), privacy: .public) \
            window=\(NSStringFromRect(self.window?.frame ?? .zero), privacy: .public) \
            screen=\(screen?.localizedName ?? "nil", privacy: .public) \
            \(NSStringFromRect(screen?.frame ?? .zero), privacy: .public) \
            scale=\(screen?.backingScaleFactor ?? 0) preview=\(self.isPreview)
            """)
        syncDrawable()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncDrawable()
    }

    private func unclip(_ window: NSWindow) {
        unclipped = true
        var chain: [String] = []
        var v: NSView? = self
        while let view = v {
            view.clipsToBounds = false
            view.layer?.masksToBounds = false
            chain.append("\(type(of: view))")
            v = view.superview
        }
        log.notice("unclipped \(chain.joined(separator: " < "), privacy: .public)")
    }

    /// The screen under the window's bottom-left corner. When the host gives a window the other
    /// display's size, the content is anchored there, so this is the screen actually being covered.
    private var coveredScreen: NSScreen? {
        guard let window else { return nil }
        return NSScreen.screens.first { NSPointInRect(window.frame.origin, $0.frame) } ?? window.screen
    }

    /// legacyScreenSaver sometimes hands a view (and its window) the frame of the *other* display.
    /// The window is a view-service window whose content is remoted into WallpaperAgent; the remote
    /// side resets its size, so besides retrying the resize, let the content spill past its bounds.
    private func fitToScreen() {
        guard fitsScreen, let window, let screen = coveredScreen, let host = superview,
              !window.styleMask.contains(.titled), host.bounds.width > 0, host.bounds.height > 0 else { return }
        if window.frame.size != screen.frame.size {
            if !unclipped { unclip(window) }
            if Date().timeIntervalSince(lastResize) > 1 {
                lastResize = Date()
                let before = window.frame
                window.setFrame(screen.frame, display: true)
                log.notice("""
                    window \(NSStringFromRect(before), privacy: .public) ≠ screen \(screen.localizedName, privacy: .public) \
                    \(NSStringFromRect(screen.frame), privacy: .public); after setFrame \(NSStringFromRect(window.frame), privacy: .public)
                    """)
            }
        }
        let target = host.convert(window.convertFromScreen(screen.frame), from: nil)
        if frame != target {
            log.notice("refit view \(NSStringFromRect(self.frame), privacy: .public) → \(NSStringFromRect(target), privacy: .public) on \(screen.localizedName, privacy: .public)")
            frame = target
        }
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncDrawable()
    }

    public override func layout() {
        super.layout()
        syncDrawable()
    }

    /// legacyScreenSaver creates the view at one size (often the main display's frame, or zero)
    /// and later resizes it or moves it to another screen; MTKView's own drawable tracking misses
    /// some of those transitions. Size the subviews and drawable explicitly instead.
    private func syncDrawable() {
        guard !stopped else { return }
        fitToScreen()
        for v in [mtkView, overlay] as [NSView] where v.frame != bounds { v.frame = bounds }
        let scale = coveredScreen?.backingScaleFactor ?? window?.backingScaleFactor ?? 2
        let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        // Zero-size or windowless instances (the host leaves these behind) shouldn't keep a render loop alive.
        let drawable = window != nil && size.width > 0 && size.height > 0
        if mtkView.isPaused == drawable { mtkView.isPaused = !drawable }
        guard drawable else { return }
        if mtkView.layer?.contentsScale != scale { mtkView.layer?.contentsScale = scale }
        if mtkView.drawableSize != size {
            log.notice("drawable \(Int(self.mtkView.drawableSize.width))x\(Int(self.mtkView.drawableSize.height)) → \(Int(size.width))x\(Int(size.height)) @\(scale)x")
            mtkView.drawableSize = size
        }
    }

    public func draw(in view: MTKView) {
        syncDrawable()
        let now = CACurrentMediaTime()
        let dt = lastTime.map { min(now - $0, 0.1) } ?? 0
        lastTime = now
        if !paused { slideshow.advance(by: dt) }
        let frame = slideshow.frame()
        if renderer.hdr {
            renderer.headroom = Float(coveredScreen?.maximumExtendedDynamicRangeColorComponentValue ?? 1)
        }
        if renderer.draw(frame, in: view) {
            if missedFrames > 0 || renderedFrames == 0 {
                log.info("rendering (after \(self.missedFrames) missed frames)")
                missedFrames = 0
            }
            renderedFrames += 1
        } else {
            if missedFrames % 120 == 0 {
                log.error("no drawable: bounds=\(NSStringFromRect(self.bounds), privacy: .public) drawable=\(Int(view.drawableSize.width))x\(Int(view.drawableSize.height))")
            }
            missedFrames += 1
        }
        overlay.update(frame)
    }
}
