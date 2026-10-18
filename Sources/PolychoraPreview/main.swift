import AppKit
import ImageIO
import UniformTypeIdentifiers
import PolychoraRender
import PolytopeKit

// Development harness: windowed preview with shader hot-reload, or a headless snapshot.
//
//   PolychoraPreview
//   PolychoraPreview --snapshot out.png [--kind 120] [--stereo 1] [--time 12] [--theme Ink] [--size 1600x1000] [--overlay quadrants|compact]
//                    [--approach 0…1] [--yaw degrees]

let shaderURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Shaders/Polychora.metal")
let loadShader = { try String(contentsOf: shaderURL, encoding: .utf8) }

let kindNames: [String: PolytopeKind] = ["5": .cell5, "8": .cell8, "16": .cell16, "24": .cell24, "120": .cell120, "600": .cell600]

func argument(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
    return a[i + 1]
}

if let out = argument("--snapshot") {
    var settings = PolychoraSettings()
    settings.polytope = kindNames[argument("--kind") ?? "120"] ?? .cell120
    settings.theme = argument("--theme") ?? Theme.ink.name
    let dims = (argument("--size") ?? "1600x1000").split(separator: "x").compactMap { Int($0) }
    let time = Double(argument("--time") ?? "5") ?? 5

    let device = MTLCreateSystemDefaultDevice()!
    let renderer = try Renderer(device: device, sampleCount: 4, shaderSource: loadShader)
    renderer.theme = Theme.named(settings.theme)
    let show = Slideshow(settings: settings, randomStart: false)
    show.seek(timeline: 10, rotation: time)
    show.overrideStereo(Double(argument("--stereo") ?? "0") ?? 0)
    show.overrideCamera(approach: Double(argument("--approach") ?? "0") ?? 0,
                        yaw: (Double(argument("--yaw") ?? "0") ?? 0) * .pi / 180)

    var snapshot = renderer.snapshot(show.frame(), width: dims[0], height: dims[1])
    if let layout = argument("--overlay"), let shot = snapshot {
        settings.overlayLayout = layout == "compact" ? .compact : .quadrants
        snapshot = renderer.compositeOverlay(show.frame(), settings: settings, onto: shot)
    }
    guard let image = snapshot,
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("snapshot failed") }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var view: PolychoraView!
    var shaderDate: Date?

    func applicationDidFinishLaunching(_ note: Notification) {
        let defaults = UserDefaults.standard
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        view = PolychoraView(frame: frame, settings: .load(from: defaults), isPreview: false, shaderSource: loadShader)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "Polychora preview"
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        shaderDate = modificationDate()
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.checkShader() }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.handle(e) == true ? nil : e
        }
        printHelp()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    private func modificationDate() -> Date? {
        try? FileManager.default.attributesOfItem(atPath: shaderURL.path)[.modificationDate] as? Date
    }

    private func checkShader() {
        let d = modificationDate()
        guard d != shaderDate else { return }
        shaderDate = d
        reload()
    }

    private func reload() {
        do { try view.renderer.reloadShaders(); print("shaders reloaded") }
        catch { print("shader error:\n\(error)") }
    }

    private func update(_ change: (inout PolychoraSettings) -> Void) {
        var s = view.settings
        change(&s)
        view.settings = s
        s.save(to: .standard)
        print("polytope=\(s.polytope.map { "\($0)" } ?? "all") projection=\(s.projection.label) theme=\(s.theme) speed=\(s.speed) layout=\(s.overlayLayout.label) fly=\(s.flyThrough.label)")
    }

    private func handle(_ e: NSEvent) -> Bool {
        switch e.keyCode {
        case 124: view.slideshow.skip(1); return true
        case 123: view.slideshow.skip(-1); return true
        default: break
        }
        guard let ch = e.charactersIgnoringModifiers?.lowercased() else { return false }
        let kinds = PolytopeKind.allCases
        switch ch {
        case "1", "2", "3", "4", "5", "6": update { $0.polytope = kinds[Int(ch)! - 1] }
        case "0": update { $0.polytope = nil }
        case "p": update { $0.projection = .init(rawValue: ($0.projection.rawValue + 1) % 3)! }
        case "t":
            update { s in
                let names = Theme.all.map(\.name)
                s.theme = names[((names.firstIndex(of: s.theme) ?? 0) + 1) % names.count]
            }
        case "i": update { $0.showInfo.toggle() }
        case "v": update { $0.flyThrough = .init(rawValue: ($0.flyThrough.rawValue + 1) % 3)! }
        case "l": update { $0.overlayLayout = .init(rawValue: ($0.overlayLayout.rawValue + 1) % 2)! }
        case "c": update { $0.showClock.toggle() }
        case "=", "+": update { $0.speed = min($0.speed * 1.25, 8) }
        case "-": update { $0.speed = max($0.speed / 1.25, 0.1) }
        case " ": view.paused.toggle()
        case "r": reload()
        case "f": window.toggleFullScreen(nil)
        case "h": printHelp()
        default: return false
        }
        return true
    }

    private func printHelp() {
        print("""
        keys: ←/→ prev/next · 1-6 pick polytope · 0 cycle all · p projection mode · t theme
              i info · l info layout · v fly-through · c clock · +/- speed · space pause · r reload shaders · f fullscreen · h help
        shader: \(shaderURL.path) (auto-reloads on save)
        """)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
