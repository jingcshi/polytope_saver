import AppKit
import QuartzCore
import PolytopeKit

/// Text overlay drawn with Core Animation over the Metal view, in one of two layouts.
final class OverlayView: NSView {
    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    // Compact layout.
    private let info = CATextLayer()
    // Quadrants layout.
    private let title = CATextLayer()
    private let projection = CATextLayer()
    private let table = CATextLayer()
    // Both.
    private let clock = CATextLayer()
    private let fpsLayer = CATextLayer()

    private var infoKey = ""
    private var clockKey = ""
    private let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var polytope: (PolytopeKind) -> Polytope = { Polytope.make($0) }
    var theme: Theme = .ink { didSet { invalidate() } }
    var layout: PolychoraSettings.OverlayLayout = .quadrants { didSet { invalidate() } }
    var showInfo = true { didSet { invalidate() } }
    var showClock = true { didSet { clock.isHidden = !showClock } }
    var showFPS = false { didSet { fpsLayer.isHidden = !showFPS; fpsKey = "" } }
    /// Measured frame rate; shown under the phase indicator (top right) when `showFPS` is on.
    var fps: Double = 0
    private var fpsKey = ""

    private var infoLayers: [CATextLayer] { [info, title, projection, table] }

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        for l in infoLayers + [clock, fpsLayer] {
            l.isWrapped = false
            l.actions = ["contents": NSNull(), "opacity": NSNull(), "bounds": NSNull(), "position": NSNull()]
            layer!.addSublayer(l)
        }
        projection.alignmentMode = .right
        clock.alignmentMode = .right
        fpsLayer.alignmentMode = .right
        fpsLayer.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func invalidate() { infoKey = ""; clockKey = ""; fpsKey = "" }

    private var unit: CGFloat { max(min(bounds.width, bounds.height), 200) / 1000 }
    private var margin: CGFloat { 40 * unit }

    private func textColor(_ corner: Corner) -> NSColor {
        var c = theme.text
        if let t = theme.cardText {
            switch corner {
            case .topLeft: c = t.topLeft
            case .topRight: c = t.topRight
            case .bottomLeft: c = t.bottomLeft
            case .bottomRight: c = t.bottomRight
            }
        }
        return NSColor(srgbRed: CGFloat(linearToSRGB(c.x)), green: CGFloat(linearToSRGB(c.y)),
                       blue: CGFloat(linearToSRGB(c.z)), alpha: 1)
    }

    private func style(_ corner: Corner, _ size: CGFloat, _ weight: NSFont.Weight, _ alpha: CGFloat, kern: CGFloat = 0,
                       monospacedDigits: Bool = false, para: NSParagraphStyle? = nil) -> [NSAttributedString.Key: Any] {
        let p = (para?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        p.lineSpacing = 4 * unit
        let font = monospacedDigits ? NSFont.monospacedDigitSystemFont(ofSize: size * unit, weight: weight)
                                    : NSFont.systemFont(ofSize: size * unit, weight: weight)
        return [.font: font, .foregroundColor: textColor(corner).withAlphaComponent(alpha),
                .kern: kern * unit, .paragraphStyle: p]
    }

    private func place(_ l: CATextLayer, _ s: NSAttributedString, _ corner: Corner, dy: CGFloat = 0) {
        l.string = s
        let size = s.boundingRect(with: CGSize(width: 10000, height: 10000), options: [.usesLineFragmentOrigin]).size
        let w = ceil(size.width) + 4, h = ceil(size.height) + 4, m = margin
        let x = (corner == .topLeft || corner == .bottomLeft) ? m : bounds.width - m - w
        let y = (corner == .bottomLeft || corner == .bottomRight) ? m + dy : bounds.height - m - h + dy
        l.frame = CGRect(x: x, y: y, width: w, height: h)
    }

    func update(_ frame: FrameState) {
        let scale = window?.backingScaleFactor ?? 2
        let key = "\(frame.kind.rawValue)|\(frame.phaseLabel)|\(bounds.size)|\(scale)|\(layout)|\(showInfo)"
        if key != infoKey {
            infoKey = key
            infoLayers.forEach { $0.contentsScale = scale }
            info.isHidden = !showInfo || layout != .compact
            for l in [title, projection, table] { l.isHidden = !showInfo || layout != .quadrants }
            switch layout {
            case .compact:
                place(info, compactText(frame), .bottomLeft)
            case .quadrants:
                place(title, titleText(frame, .topLeft), .topLeft)
                place(projection, NSAttributedString(string: frame.phaseLabel,
                                                     attributes: style(.topRight, 14, .regular, 0.5, kern: 0.6)), .topRight)
                place(table, tableText(frame), .bottomLeft)
            }
        }
        infoLayers.forEach { $0.opacity = Float(frame.fade) }
        drift(scale: scale)

        let now = clockFormatter.string(from: Date())
        let ckey = "\(now)|\(bounds.size)|\(scale)|\(layout)"
        if ckey != clockKey {
            clockKey = ckey
            clock.contentsScale = scale
            let s = NSAttributedString(string: now, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 72 * unit, weight: .light),
                .foregroundColor: textColor(.bottomRight).withAlphaComponent(0.8),
                .kern: 2 * unit,
            ])
            place(clock, s, .bottomRight, dy: -6 * unit)
        }

        if showFPS {
            let text = String(format: "%.2f fps", fps)
            let fkey = "\(text)|\(bounds.size)|\(scale)|\(infoKey)"
            if fkey != fpsKey {
                fpsKey = fkey
                fpsLayer.contentsScale = scale
                let s = NSAttributedString(string: text, attributes: style(.topRight, 14, .regular, 0.5, kern: 0.6,
                                                                           monospacedDigits: true))
                // One row below the phase indicator (same height, since both are one 14-point line).
                place(fpsLayer, s, .topRight, dy: -ceil(s.size().height) - 4 * unit)
            }
        }
    }

    /// Burn-in protection: all text slides along a billiard path inside a ±12-unit box (within the
    /// 40-unit margin). Closed form from wall-clock time; offsets snap to device pixels to keep text crisp.
    private func drift(scale: CGFloat) {
        let half = 12 * unit
        let t = Date().timeIntervalSinceReferenceDate
        func bounce(_ speed: Double) -> CGFloat {
            let s = (speed * Double(unit) * t).truncatingRemainder(dividingBy: Double(4 * half))
            return CGFloat(abs(s - Double(2 * half))) - half    // triangle wave in [−half, half]
        }
        let dx = (bounce(0.13) * scale).rounded() / scale
        let dy = (bounce(0.08) * scale).rounded() / scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.sublayerTransform = CATransform3DMakeTranslation(dx, dy, 0)
        CATransaction.commit()
    }

    private func n(_ x: Int) -> String { String(x) }

    private func counts(_ kind: PolytopeKind) -> (v: Int, e: Int, f: Int, c: Int) {
        let p = polytope(kind)
        return (p.vertices.count, p.edges.count, p.faces.count, p.cells.count)
    }

    private func titleText(_ frame: FrameState, _ corner: Corner) -> NSMutableAttributedString {
        let i = frame.kind.info
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: i.name + "\n", attributes: style(corner, 40, .light, 0.9, kern: 0.5)))
        s.append(NSAttributedString(string: "\(i.altName)   \(i.schlafli)", attributes: style(corner, 18, .regular, 0.7, kern: 1)))
        return s
    }

    private func compactText(_ frame: FrameState) -> NSAttributedString {
        let i = frame.kind.info
        let p = counts(frame.kind)
        let s = titleText(frame, .bottomLeft)
        s.append(NSAttributedString(string: "\n", attributes: style(.bottomLeft, 14, .regular, 0, kern: 1)))
        s.append(NSAttributedString(string: "\n", attributes: style(.bottomLeft, 6, .regular, 0)))
        let body = style(.bottomLeft, 14, .regular, 0.8, kern: 0.6)
        s.append(NSAttributedString(string: "\(n(p.v)) vertices · \(n(p.e)) edges · \(n(p.f)) faces · \(n(p.c)) cells\n", attributes: body))
        s.append(NSAttributedString(string: "cells: \(i.cellType) · vertex figure: \(i.vertexFigure)\n", attributes: body))
        s.append(NSAttributedString(string: "symmetry \(i.symmetry), order \(n(i.symmetryOrder)) · dual: \(i.dual)\n", attributes: body))
        s.append(NSAttributedString(string: frame.phaseLabel, attributes: style(.bottomLeft, 14, .regular, 0.5, kern: 0.6)))
        return s
    }

    /// Four columns: label | value | label | value. Numeric values right-align in column 2.
    private func tableText(_ frame: FrameState) -> NSAttributedString {
        let i = frame.kind.info
        let p = counts(frame.kind)
        let angle = String(format: "%.2f°", i.dichoralAngle).replacingOccurrences(of: ".00°", with: "°")
        let rows: [(String, String, String, String)] = [
            ("vertices", n(p.v), "vertex figure", i.vertexFigure),
            ("edges", n(p.e), "dichoral angle", angle),
            ("faces", n(p.f), "polygons", i.faceType),
            ("cells", n(p.c), "polyhedra", i.cellType),
            ("symmetry", i.symmetry, "order", n(i.symmetryOrder)),
            ("3D analogue", i.analogue, "dual", i.dual),
        ]
        let label = style(.bottomLeft, 14, .regular, 0.5, kern: 0.6)
        let value = style(.bottomLeft, 14, .regular, 0.8, kern: 0.6, monospacedDigits: true)
        func width(_ s: String, _ a: [NSAttributedString.Key: Any]) -> CGFloat { NSAttributedString(string: s, attributes: a).size().width }
        let w0 = rows.map { width($0.0, label) }.max()!
        let w1 = rows.map { width($0.1, value) }.max()!
        let w2 = rows.map { width($0.2, label) }.max()!
        let c1 = ceil(w0 + 18 * unit + w1), c2 = ceil(c1 + 32 * unit), c3 = ceil(c2 + w2 + 18 * unit)

        let para = NSMutableParagraphStyle()
        para.tabStops = [NSTextTab(textAlignment: .right, location: c1),
                         NSTextTab(textAlignment: .left, location: c2),
                         NSTextTab(textAlignment: .left, location: c3)]
        let labelP = style(.bottomLeft, 14, .regular, 0.5, kern: 0.6, para: para)
        let valueP = style(.bottomLeft, 14, .regular, 0.8, kern: 0.6, monospacedDigits: true, para: para)

        let s = NSMutableAttributedString()
        for (k, r) in rows.enumerated() {
            s.append(NSAttributedString(string: r.0 + "\t", attributes: labelP))
            s.append(NSAttributedString(string: r.1 + "\t", attributes: valueP))
            s.append(NSAttributedString(string: r.2 + "\t", attributes: labelP))
            s.append(NSAttributedString(string: r.3 + (k < rows.count - 1 ? "\n" : ""), attributes: valueP))
        }
        return s
    }
}

extension Renderer {
    /// Composite the overlay onto a snapshot (points == pixels / scale).
    public func compositeOverlay(_ frame: FrameState, settings: PolychoraSettings, onto image: CGImage,
                                 scale: CGFloat = 2) -> CGImage? {
        let w = image.width, h = image.height
        let overlay = OverlayView(frame: NSRect(x: 0, y: 0, width: CGFloat(w) / scale, height: CGFloat(h) / scale))
        overlay.polytope = { [unowned self] in self.polytope($0) }
        overlay.theme = Theme.named(settings.theme)
        overlay.layout = settings.overlayLayout
        overlay.showInfo = settings.showInfo
        overlay.showClock = settings.showClock
        overlay.showFPS = settings.showFPS
        overlay.update(frame)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        overlay.layer!.render(in: ctx)
        return ctx.makeImage()
    }
}

func linearToSRGB(_ x: Float) -> Float {
    x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
}
