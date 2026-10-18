import AppKit
import os
import PaperSaverKit

// The appex must live inside an app bundle; this app carries it. Launching it makes Polychora the
// screensaver on every display and space (via PaperSaver, which writes the wallpaper store and
// restarts WallpaperAgent), then opens the Screen Saver settings.
// `--register-only` (used by `make install`) skips activation.

let log = Logger(subsystem: "com.jingcshi.Polychora", category: "host")
let settingsURL = URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension")!

if !CommandLine.arguments.contains("--register-only") {
    do {
        try await PaperSaver().setScreensaverEverywhere(module: "Polychora")
        log.notice("activated Polychora everywhere")
    } catch {
        log.error("activation failed: \(String(describing: error), privacy: .public)")
    }
}
NSWorkspace.shared.open(settingsURL)
