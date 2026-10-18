import AppKit
import os
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

        content?.fitsScreen = !isPreview
        Self.live.add(self)
        log.notice("init frame=\(NSStringFromRect(frame), privacy: .public) preview=\(isPreview) live=\(Self.live.count)")

        // legacyScreenSaver never tears down old instances or delivers stopAnimation reliably
        // (Sonoma → Tahoe, still present on 27). Exiting the host after the saver stops is the
        // known workaround; Tahoe+ sends willstop slightly early, hence the delay.
        if !isPreview {
            let center = DistributedNotificationCenter.default()
            center.addObserver(self, selector: #selector(willStop), name: .init("com.apple.screensaver.willstop"), object: nil)
            center.addObserver(self, selector: #selector(didStart), name: .init("com.apple.screensaver.didstart"), object: nil)
            NSWorkspace.shared.notificationCenter.addObserver(
                self, selector: #selector(willStop), name: NSWorkspace.willSleepNotification, object: nil)
        }
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    private static let live = NSHashTable<PolychoraSaverView>.weakObjects()
    private static var lastStart = Date.distantPast
    private let created = Date()
    private let log = Logger(subsystem: "com.jingcshi.Polychora", category: "saver")

    @objc private func didStart(_ note: Notification) { Self.lastStart = Date() }

    /// Exit the host only if no newer session has begun in this process meanwhile: with rapid
    /// re-activation the next session's instance can already be alive when the exit fires.
    @objc private func willStop(_ note: Notification) {
        // A late willstop from the previous session can reach an instance that was just created.
        if Date().timeIntervalSince(created) < 1 {
            log.notice("ignore willstop: instance only \(Date().timeIntervalSince(self.created))s old")
            return
        }
        content?.stop()
        let stoppedAt = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [log] in
            let newer = Self.live.allObjects.contains { $0.created > stoppedAt && !$0.isPreview && $0.window != nil }
            if newer || Self.lastStart > stoppedAt {
                log.notice("skip exit: newer session (instance=\(newer), didstart=\(Self.lastStart > stoppedAt))")
                return
            }
            log.notice("exit after willstop")
            exit(0)
        }
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
