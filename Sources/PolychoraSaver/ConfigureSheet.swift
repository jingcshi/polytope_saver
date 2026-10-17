import AppKit
import PolychoraRender
import PolytopeKit

/// Options sheet shown from System Settings → Screen Saver → Options.
final class ConfigureSheet: NSObject {
    let window: NSWindow
    private let onSave: (PolychoraSettings) -> Void
    private var settings: PolychoraSettings

    private let polytope = NSPopUpButton()
    private let projection = NSPopUpButton()
    private let theme = NSPopUpButton()
    private let layout = NSPopUpButton()
    private let speed = NSSlider(value: 1, minValue: 0.25, maxValue: 3, target: nil, action: nil)
    private let hold = NSSlider(value: 30, minValue: 10, maxValue: 120, target: nil, action: nil)
    private let info = NSButton(checkboxWithTitle: "Show info card", target: nil, action: nil)
    private let clock = NSButton(checkboxWithTitle: "Show clock", target: nil, action: nil)

    init(settings: PolychoraSettings, onSave: @escaping (PolychoraSettings) -> Void) {
        self.settings = settings
        self.onSave = onSave
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 330),
                          styleMask: [.titled], backing: .buffered, defer: false)
        super.init()

        polytope.addItem(withTitle: "Cycle all six")
        PolytopeKind.allCases.forEach { polytope.addItem(withTitle: $0.info.name) }
        polytope.selectItem(at: settings.polytope.map { $0.rawValue + 1 } ?? 0)
        PolychoraSettings.Projection.allCases.forEach { projection.addItem(withTitle: $0.label) }
        projection.selectItem(at: settings.projection.rawValue)
        Theme.all.forEach { theme.addItem(withTitle: $0.name) }
        theme.selectItem(withTitle: settings.theme)
        PolychoraSettings.OverlayLayout.allCases.forEach { layout.addItem(withTitle: $0.label) }
        layout.selectItem(at: settings.overlayLayout.rawValue)
        speed.doubleValue = settings.speed
        hold.doubleValue = settings.holdSeconds
        info.state = settings.showInfo ? .on : .off
        clock.state = settings.showClock ? .on : .off

        func row(_ label: String, _ control: NSView) -> [NSView] {
            [NSTextField(labelWithString: label), control]
        }
        let grid = NSGridView(views: [
            row("Polytope:", polytope), row("Projection:", projection), row("Theme:", theme), row("Info layout:", layout),
            row("Rotation speed:", speed), row("Seconds per view:", hold),
            [NSGridCell.emptyContentView, info], [NSGridCell.emptyContentView, clock],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 10

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
        cancel.keyEquivalent = "\u{1b}"
        let ok = NSButton(title: "OK", target: self, action: #selector(okPressed))
        ok.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancel, ok])
        let stack = NSStackView(views: [grid, buttons])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 20
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window.contentView = stack
    }

    private func close() {
        if let parent = window.sheetParent { parent.endSheet(window) } else { window.close() }
    }

    @objc private func cancelPressed() { close() }

    @objc private func okPressed() {
        let p = polytope.indexOfSelectedItem
        settings.polytope = p == 0 ? nil : PolytopeKind(rawValue: p - 1)
        settings.projection = .init(rawValue: projection.indexOfSelectedItem) ?? .alternate
        settings.theme = theme.titleOfSelectedItem ?? Theme.ink.name
        settings.speed = speed.doubleValue
        settings.holdSeconds = hold.doubleValue.rounded()
        settings.overlayLayout = .init(rawValue: layout.indexOfSelectedItem) ?? .compact
        settings.showInfo = info.state == .on
        settings.showClock = clock.state == .on
        onSave(settings)
        close()
    }
}
