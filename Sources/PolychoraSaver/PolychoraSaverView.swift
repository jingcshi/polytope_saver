import AppKit
import ScreenSaver
import PolychoraRender

/// Principal class of Polychora.saver. The ObjC name must be unique inside legacyScreenSaver.
@objc(PolychoraSaverView)
final class PolychoraSaverView: ScreenSaverView {
    static let moduleName = "com.jingcshi.Polychora"

    private var content: PolychoraView?
    private var sheet: ConfigureSheet?

    private var defaults: UserDefaults {
        ScreenSaverDefaults(forModuleWithName: Self.moduleName) ?? .standard
    }

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1 / 60
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

        // legacyScreenSaver never tears down old instances or delivers stopAnimation reliably
        // (Sonoma → Tahoe, still present on 27). Exiting the host after the saver stops is the
        // known workaround; Tahoe+ sends willstop slightly early, hence the delay.
        if !isPreview {
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(willStop), name: .init("com.apple.screensaver.willstop"), object: nil)
            NSWorkspace.shared.notificationCenter.addObserver(
                self, selector: #selector(willStop), name: NSWorkspace.willSleepNotification, object: nil)
        }
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    @objc private func willStop(_ note: Notification) {
        content?.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) }
    }

    // Rendering is driven by the MTKView's own display link, not the host's timer.
    override func animateOneFrame() {}

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        let s = ConfigureSheet(settings: .load(from: defaults)) { [weak self] settings in
            guard let self else { return }
            settings.save(to: self.defaults)
            self.content?.settings = settings
        }
        sheet = s
        return s.window
    }
}
