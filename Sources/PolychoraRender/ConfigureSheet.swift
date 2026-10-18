import AppKit
import PolytopeKit

/// Options sheet shown from System Settings → Screen Saver → Options.
/// The legacy saver presents `window`; the appex embeds `view` in its configuration controller.
/// Every control has a fixed width, so `view.fittingSize` is the sheet's exact size.
public final class ConfigureSheet: NSObject {
    public let view: NSView
    public lazy var window: NSWindow = {
        let w = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        w.contentView = view
        return w
    }()
    /// Called on OK/Cancel instead of ending the sheet on its parent window.
    public var onDismiss: (() -> Void)?
    private let onSave: (PolychoraSettings) -> Void
    private var settings: PolychoraSettings

    private static let popupWidth: CGFloat = 200, sliderWidth: CGFloat = 240, buttonWidth: CGFloat = 96

    private let polytope = NSPopUpButton()
    private let projection = NSPopUpButton()
    private let theme = NSPopUpButton()
    private let layout = NSPopUpButton()
    private let fly = NSPopUpButton()
    private let animation = ConfigureSheet.speedSlider()
    private let motion = ConfigureSheet.speedSlider()
    private let rotation = ConfigureSheet.speedSlider()
    private let info = NSButton(checkboxWithTitle: "Show info card", target: nil, action: nil)
    private let clock = NSButton(checkboxWithTitle: "Show clock", target: nil, action: nil)

    /// Continuous slider over log2(speed), slow on the left; tick marks at both ends as in Apple's Flurry.
    private static func speedSlider() -> NSSlider {
        let r = PolychoraSettings.speedRange
        let s = NSSlider(value: 0, minValue: log2(r.lowerBound), maxValue: log2(r.upperBound), target: nil, action: nil)
        s.numberOfTickMarks = 2
        s.tickMarkPosition = .below
        s.widthAnchor.constraint(equalToConstant: sliderWidth).isActive = true
        return s
    }

    private static func speed(of slider: NSSlider) -> Double { pow(2, slider.doubleValue) }

    /// Slider with "Slow" / "Fast" captions under its ends.
    private static func captioned(_ slider: NSSlider) -> NSView {
        func caption(_ text: String) -> NSTextField {
            let l = NSTextField(labelWithString: text)
            l.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            l.textColor = .secondaryLabelColor
            l.translatesAutoresizingMaskIntoConstraints = false
            return l
        }
        let box = NSView()
        let slow = caption("Slow"), fast = caption("Fast")
        slider.translatesAutoresizingMaskIntoConstraints = false
        [slider, slow, fast].forEach(box.addSubview)
        NSLayoutConstraint.activate([
            slider.topAnchor.constraint(equalTo: box.topAnchor),
            slider.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            slow.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 1),
            fast.topAnchor.constraint(equalTo: slow.topAnchor),
            slow.leadingAnchor.constraint(equalTo: slider.leadingAnchor),
            fast.trailingAnchor.constraint(equalTo: slider.trailingAnchor),
            slow.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        return box
    }

    public init(settings: PolychoraSettings, onSave: @escaping (PolychoraSettings) -> Void) {
        self.settings = settings
        self.onSave = onSave
        let stack = NSStackView()
        view = stack
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
        PolychoraSettings.FlyThrough.allCases.forEach { fly.addItem(withTitle: $0.label) }
        fly.selectItem(at: settings.flyThrough.rawValue)
        for p in [polytope, projection, fly, theme, layout] {
            p.widthAnchor.constraint(equalToConstant: Self.popupWidth).isActive = true
        }
        animation.doubleValue = log2(settings.animationSpeed)
        motion.doubleValue = log2(settings.motionSpeed)
        rotation.doubleValue = log2(settings.speed)
        info.state = settings.showInfo ? .on : .off
        clock.state = settings.showClock ? .on : .off

        var rows: [[NSView]] = [
            ("Polytope:", polytope), ("Projection:", projection), ("Fly-through:", fly),
            ("Theme:", theme), ("Info layout:", layout),
        ].map { [NSTextField(labelWithString: $0.0), $0.1] }
        var sliderLabels: [(NSTextField, NSSlider)] = []
        for (title, slider) in [("Animation speed:", animation), ("Motion speed:", motion), ("Rotation speed:", rotation)] {
            let label = NSTextField(labelWithString: title)
            sliderLabels.append((label, slider))
            rows.append([label, Self.captioned(slider)])
        }
        rows += [[NSGridCell.emptyContentView, info], [NSGridCell.emptyContentView, clock]]

        let grid = NSGridView(views: rows)
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.rowSpacing = 10
        grid.columnSpacing = 8
        for (label, slider) in sliderLabels {
            guard let cell = grid.cell(for: label) else { continue }
            cell.yPlacement = .none
            cell.customPlacementConstraints = [label.centerYAnchor.constraint(equalTo: slider.centerYAnchor)]
        }

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
        cancel.keyEquivalent = "\u{1b}"
        let ok = NSButton(title: "OK", target: self, action: #selector(okPressed))
        ok.keyEquivalent = "\r"
        for b in [cancel, ok] { b.widthAnchor.constraint(equalToConstant: Self.buttonWidth).isActive = true }
        let buttons = NSStackView()
        buttons.setViews([cancel, ok], in: .trailing)

        stack.setViews([grid, buttons], in: .leading)
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 20
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        // NSStackView underestimates the grid's natural width; pin it so fittingSize is exact.
        stack.widthAnchor.constraint(equalToConstant: grid.fittingSize.width + 48).isActive = true
        stack.frame.size = stack.fittingSize
    }

    private func close() {
        if let onDismiss {
            onDismiss()
        } else if let w = view.window, let parent = w.sheetParent {
            parent.endSheet(w)
        } else {
            view.window?.close()
        }
    }

    @objc private func cancelPressed() { close() }

    @objc private func okPressed() {
        let p = polytope.indexOfSelectedItem
        settings.polytope = p == 0 ? nil : PolytopeKind(rawValue: p - 1)
        settings.projection = .init(rawValue: projection.indexOfSelectedItem) ?? .alternate
        settings.theme = theme.titleOfSelectedItem ?? Theme.ink.name
        settings.animationSpeed = Self.speed(of: animation)
        settings.motionSpeed = Self.speed(of: motion)
        settings.speed = Self.speed(of: rotation)
        settings.flyThrough = .init(rawValue: fly.indexOfSelectedItem) ?? .all
        settings.overlayLayout = .init(rawValue: layout.indexOfSelectedItem) ?? .compact
        settings.showInfo = info.state == .on
        settings.showClock = clock.state == .on
        onSave(settings)
        close()
    }
}
