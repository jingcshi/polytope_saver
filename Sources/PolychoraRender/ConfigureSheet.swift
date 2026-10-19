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

    private let projection = NSPopUpButton()
    private let theme = NSPopUpButton()
    private let fly = NSPopUpButton()
    private let surfaces = NSPopUpButton()
    private let frameColors = NSPopUpButton()
    private let animation = ConfigureSheet.speedSlider()
    private let pan = ConfigureSheet.speedSlider()
    private let motion = ConfigureSheet.speedSlider()
    private let rotation = ConfigureSheet.speedSlider()
    private let targetFPS = ConfigureSheet.fpsSlider()
    private let fpsReadout = ConfigureSheet.caption("")
    private let info = NSButton(checkboxWithTitle: "Show info card", target: nil, action: nil)
    private let clock = NSButton(checkboxWithTitle: "Show clock", target: nil, action: nil)
    private let fps = NSButton(checkboxWithTitle: "Show frame rate", target: nil, action: nil)

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

    /// Discrete slider over `PolychoraSettings.targetFPSSteps`, one tick per value.
    private static func fpsSlider() -> NSSlider {
        let steps = PolychoraSettings.targetFPSSteps
        let s = NSSlider(value: 0, minValue: 0, maxValue: Double(steps.count - 1), target: nil, action: nil)
        s.numberOfTickMarks = steps.count
        s.allowsTickMarkValuesOnly = true
        s.tickMarkPosition = .below
        s.widthAnchor.constraint(equalToConstant: sliderWidth).isActive = true
        return s
    }

    private static func caption(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        l.textColor = .secondaryLabelColor
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    /// Slider with captions under it: the first and last at its ends, the rest evenly spread between.
    private static func captioned(_ slider: NSSlider, _ captions: [NSTextField] = ["Slow", "Fast"].map(caption)) -> NSView {
        let box = NSView()
        slider.translatesAutoresizingMaskIntoConstraints = false
        ([slider] + captions).forEach(box.addSubview)
        let first = captions.first!, last = captions.last!
        var constraints = [
            slider.topAnchor.constraint(equalTo: box.topAnchor),
            slider.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            first.leadingAnchor.constraint(equalTo: slider.leadingAnchor),
            last.trailingAnchor.constraint(equalTo: slider.trailingAnchor),
            first.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ]
        constraints += captions.map { $0.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 1) }
        // Inner captions centre on evenly spaced points spanning the track inset by the knob's half-width.
        let inset: CGFloat = 10, n = CGFloat(captions.count - 1)
        for (i, c) in captions.enumerated().dropFirst().dropLast() {
            let f = CGFloat(i) / n
            constraints.append(NSLayoutConstraint(item: c, attribute: .centerX, relatedBy: .equal, toItem: box,
                                                  attribute: .trailing, multiplier: f, constant: inset * (1 - 2 * f)))
        }
        NSLayoutConstraint.activate(constraints)
        return box
    }

    public init(settings: PolychoraSettings, onSave: @escaping (PolychoraSettings) -> Void) {
        self.settings = settings
        self.onSave = onSave
        let stack = NSStackView()
        view = stack
        super.init()

        PolychoraSettings.Projection.allCases.forEach { projection.addItem(withTitle: $0.label) }
        projection.selectItem(at: settings.projection.rawValue)
        Theme.all.forEach { theme.addItem(withTitle: $0.name) }
        theme.selectItem(withTitle: settings.theme)
        PolychoraSettings.FlyThrough.allCases.forEach { fly.addItem(withTitle: $0.label) }
        fly.selectItem(at: settings.flyThrough.rawValue)
        PolychoraSettings.Surfaces.allCases.forEach { surfaces.addItem(withTitle: $0.label) }
        surfaces.selectItem(at: PolychoraSettings.Surfaces.allCases.firstIndex(of: settings.surfaces) ?? 1)
        PolychoraSettings.FrameColors.allCases.forEach { frameColors.addItem(withTitle: $0.label) }
        frameColors.selectItem(at: settings.frameColors.rawValue)
        for p in [projection, fly, theme, surfaces, frameColors] {
            p.widthAnchor.constraint(equalToConstant: Self.popupWidth).isActive = true
        }
        animation.doubleValue = log2(settings.animationSpeed)
        pan.doubleValue = log2(settings.panSpeed)
        motion.doubleValue = log2(settings.motionSpeed)
        rotation.doubleValue = log2(settings.speed)
        targetFPS.doubleValue = Double(PolychoraSettings.targetFPSSteps.firstIndex(of: settings.targetFPS)
                                       ?? PolychoraSettings.targetFPSSteps.firstIndex(of: 60)!)
        targetFPS.target = self
        targetFPS.action = #selector(targetFPSChanged)
        fpsReadout.textColor = .labelColor
        targetFPSChanged()
        info.state = settings.showInfo ? .on : .off
        clock.state = settings.showClock ? .on : .off
        fps.state = settings.showFPS ? .on : .off

        var rows: [[NSView]] = [
            ("Projection:", projection), ("Fly-through:", fly), ("Theme:", theme),
            ("Surfaces:", surfaces), ("Frame colors:", frameColors),
        ].map { [NSTextField(labelWithString: $0.0), $0.1] }
        var sliderLabels: [(NSTextField, NSSlider)] = []
        for (title, slider) in [("Animation speed:", animation), ("Pan speed:", pan), ("Motion speed:", motion), ("Rotation speed:", rotation)] {
            let label = NSTextField(labelWithString: title)
            sliderLabels.append((label, slider))
            rows.append([label, Self.captioned(slider)])
        }
        let fpsLabel = NSTextField(labelWithString: "Target frame rate:")
        sliderLabels.append((fpsLabel, targetFPS))
        let steps = PolychoraSettings.targetFPSSteps
        rows.append([fpsLabel, Self.captioned(targetFPS, [Self.caption("\(steps.first!)"), fpsReadout,
                                                          Self.caption("\(steps.last!)")])])
        let tip = """
            Frames per second to aim for. A display only shows whole divisors of its refresh rate, so other \
            values fall back to the next lower one (90 on a 120 Hz display runs at 60). Check your display's \
            refresh rate and your Mac's graphics performance before choosing above 60: higher rates draw more \
            power and heat.
            """
        fpsLabel.toolTip = tip
        targetFPS.toolTip = tip
        rows += [info, clock, fps].map { [NSGridCell.emptyContentView, $0] }

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

    @objc private func targetFPSChanged() {
        fpsReadout.stringValue = "\(PolychoraSettings.targetFPSSteps[targetFPS.integerValue]) fps"
    }

    @objc private func okPressed() {
        settings.projection = .init(rawValue: projection.indexOfSelectedItem) ?? .alternate
        settings.theme = theme.titleOfSelectedItem ?? Theme.ink.name
        settings.animationSpeed = Self.speed(of: animation)
        settings.panSpeed = Self.speed(of: pan)
        settings.motionSpeed = Self.speed(of: motion)
        settings.speed = Self.speed(of: rotation)
        settings.targetFPS = PolychoraSettings.targetFPSSteps[targetFPS.integerValue]
        settings.flyThrough = .init(rawValue: fly.indexOfSelectedItem) ?? .large
        let s = surfaces.indexOfSelectedItem, cases = PolychoraSettings.Surfaces.allCases
        settings.surfaces = cases.indices.contains(s) ? cases[s] : .faces
        settings.frameColors = .init(rawValue: frameColors.indexOfSelectedItem) ?? .steel
        settings.showInfo = info.state == .on
        settings.showClock = clock.state == .on
        settings.showFPS = fps.state == .on
        onSave(settings)
        close()
    }
}
