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
        ScreenSaverStarts.observe()
        super.init()
    }
}

/// Time of the last `com.apple.screensaver.didstart`; observed from extension load onwards.
enum ScreenSaverStarts {
    private static var last: Date?
    private static var observing = false

    static func observe() {
        guard !observing else { return }
        observing = true
        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screensaver.didstart"), object: nil, queue: .main) { _ in last = Date() }
    }

    static var recent: Bool { last.map { Date().timeIntervalSince($0) < 3 } ?? false }
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

    private var stopped = false

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        ScreenSaverStarts.observe()
        wantsLayer = true
        log.notice("view init frame=\(NSStringFromRect(frame), privacy: .public)")
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    /// The framework never reports previews (only `loadView()` is called, with the main screen's frame,
    /// and System Settings' thumbnail also gets a screen-sized WallpaperAgent window). A real session,
    /// including the Preview button, is announced by `com.apple.screensaver.didstart` ~0.1–0.2 s before
    /// the view attaches; the thumbnail is not. Content is created once the mode is known, because MSAA
    /// is fixed at renderer creation.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        log.notice("""
            moved to window: frame=\(NSStringFromRect(self.frame), privacy: .public) \
            window=\(NSStringFromRect(self.window?.frame ?? .zero), privacy: .public) \
            screen=\(self.window?.screen?.localizedName ?? "nil", privacy: .public)
            """)
        guard window != nil, content == nil, !stopped else { return }
        if ScreenSaverStarts.recent {
            install(preview: false, reason: "didstart")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.window != nil, self.content == nil, !self.stopped else { return }
            // A process launched by the start itself may have missed the notification;
            // the thumbnail is only ever shown with System Settings in front.
            let settingsFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences"
            if ScreenSaverStarts.recent {
                self.install(preview: false, reason: "didstart (late)")
            } else {
                self.install(preview: settingsFront, reason: settingsFront ? "no didstart, Settings in front" : "no didstart")
            }
        }
    }

    private func install(preview: Bool, reason: String) {
        log.notice("mode: \(preview ? "preview" : "full", privacy: .public) (\(reason, privacy: .public))")
        let bundle = Bundle(for: Self.self)
        content = PolychoraView(
            frame: bounds, settings: .load(from: defaults), isPreview: preview,
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
    }

    override func stopAnimation() {
        log.notice("stopAnimation")
        stopped = true
        content?.stop()
        super.stopAnimation()
    }

    // Rendering is driven by the MTKView's display link.
    override func animateOneFrame() {}
}
