import AppKit
import os
import PolychoraRender
import ScreenSaver
import ScreenSaverPrivate

// Class names are referenced from Resources/Appex/Info.plist as `PolychoraAppex.<Class>`.

private let log = Logger(subsystem: "com.jingcshi.Polychora", category: "appex")
private let moduleName = "com.jingcshi.Polychora"

private var defaults: UserDefaults {
    ScreenSaverDefaults(forModuleWithName: moduleName) ?? .standard
}

final class SaverExtension: ScreenSaverExtension {
    override init() {
        log.notice("extension init pid=\(ProcessInfo.processInfo.processIdentifier)")
        super.init()
    }
}

final class SaverViewController: ScreenSaverViewController {
    private var saverView: SaverView?

    override func loadView(forFrame frame: NSRect, isPreview: Bool) {
        log.notice("loadView(forFrame: \(NSStringFromRect(frame), privacy: .public), isPreview: \(isPreview))")
        install(frame: frame, isPreview: isPreview)
    }

    override func loadView() {
        log.notice("loadView()")
        install(frame: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080), isPreview: false)
    }

    private func install(frame: NSRect, isPreview: Bool) {
        let v = SaverView(frame: frame, isPreview: isPreview)
        saverView = v
        view = v ?? NSView(frame: frame)
    }
}

final class SaverConfigurationViewController: ScreenSaverConfigurationViewController {
    private var sheet: ConfigureSheet?

    override func loadView() {
        let s = ConfigureSheet(settings: .load(from: defaults)) { settings in settings.save(to: defaults) }
        s.onDismiss = { [weak self] in self?.configureSheetDidEnd() }
        sheet = s
        view = s.view
        preferredContentSize = s.view.fittingSize
    }
}

/// Runs in its own sandboxed process per session, so none of legacyScreenSaver's workarounds apply.
final class SaverView: ScreenSaverView {
    private var content: PolychoraView?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        let bundle = Bundle(for: Self.self)
        content = PolychoraView(
            frame: bounds, settings: .load(from: defaults), isPreview: isPreview,
            precompiledLibrary: bundle.url(forResource: "Polychora", withExtension: "metallib"),
            shaderSource: {
                guard let url = bundle.url(forResource: "Polychora", withExtension: "metal") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                return try String(contentsOf: url, encoding: .utf8)
            })
        if let content {
            content.autoresizingMask = [.width, .height]
            addSubview(content)
        }
        log.notice("view init frame=\(NSStringFromRect(frame), privacy: .public) preview=\(isPreview) content=\(self.content != nil)")
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        log.notice("""
            moved to window: frame=\(NSStringFromRect(self.frame), privacy: .public) \
            window=\(NSStringFromRect(self.window?.frame ?? .zero), privacy: .public) \
            screen=\(self.window?.screen?.localizedName ?? "nil", privacy: .public)
            """)
    }

    override func stopAnimation() {
        log.notice("stopAnimation")
        content?.stop()
        super.stopAnimation()
    }

    // Rendering is driven by the MTKView's display link.
    override func animateOneFrame() {}
}
