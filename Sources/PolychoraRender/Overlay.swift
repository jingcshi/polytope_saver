import AppKit
import QuartzCore
import PolytopeKit

/// Info card (bottom left) and clock (bottom right), drawn with Core Animation over the Metal view.
final class OverlayView: NSView {
    private let info = CATextLayer()
    private let clock = CATextLayer()
    private var infoKey = ""
    private var clockKey = ""
    private let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var polytope: (PolytopeKind) -> Polytope = { Polytope.make($0) }
    var theme: Theme = .ink { didSet { infoKey = ""; clockKey = "" } }
    var showInfo = true { didSet { info.isHidden = !showInfo } }
    var showClock = true { didSet { clock.isHidden = !showClock } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        for l in [info, clock] {
            l.isWrapped = false
            l.actions = ["contents": NSNull(), "opacity": NSNull(), "bounds": NSNull(), "position": NSNull()]
            layer!.addSublayer(l)
        }
        clock.alignmentMode = .right
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var unit: CGFloat { max(min(bounds.width, bounds.height), 200) / 1000 }

    private var textColor: NSColor {
        let c = theme.text
        return NSColor(srgbRed: CGFloat(linearToSRGB(c.x)), green: CGFloat(linearToSRGB(c.y)),
                       blue: CGFloat(linearToSRGB(c.z)), alpha: 1)
    }

    func update(_ frame: FrameState) {
        let scale = window?.backingScaleFactor ?? 2
        let key = "\(frame.kind.rawValue)|\(frame.projectionLabel)|\(bounds.size)|\(scale)"
        if key != infoKey {
            infoKey = key
            info.contentsScale = scale
            info.string = infoText(frame)
            let size = (info.string as! NSAttributedString).boundingRect(
                with: CGSize(width: 10000, height: 10000), options: [.usesLineFragmentOrigin]).size
            let m = 40 * unit
            info.frame = CGRect(x: m, y: m, width: ceil(size.width) + 4, height: ceil(size.height) + 4)
        }
        info.opacity = Float(frame.fade)

        let now = clockFormatter.string(from: Date())
        let ckey = "\(now)|\(bounds.size)|\(scale)"
        if ckey != clockKey {
            clockKey = ckey
            clock.contentsScale = scale
            let s = NSAttributedString(string: now, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 54 * unit, weight: .ultraLight),
                .foregroundColor: textColor.withAlphaComponent(0.75),
                .kern: 2 * unit,
            ])
            clock.string = s
            let size = s.size()
            let m = 40 * unit
            clock.frame = CGRect(x: bounds.width - m - ceil(size.width) - 4, y: m - 6 * unit,
                                 width: ceil(size.width) + 4, height: ceil(size.height) + 4)
        }
    }

    private func infoText(_ frame: FrameState) -> NSAttributedString {
        let i = frame.kind.info
        let poly = polytope(frame.kind)
        let p = (v: poly.vertices.count, e: poly.edges.count, f: poly.faces.count, c: poly.cells.count)
        let color = textColor
        func style(_ size: CGFloat, _ weight: NSFont.Weight, _ alpha: CGFloat, kern: CGFloat = 0) -> [NSAttributedString.Key: Any] {
            let para = NSMutableParagraphStyle()
            para.lineSpacing = 4 * unit
            return [.font: NSFont.systemFont(ofSize: size * unit, weight: weight),
                    .foregroundColor: color.withAlphaComponent(alpha),
                    .kern: kern * unit, .paragraphStyle: para]
        }
        let grouped = NumberFormatter()
        grouped.numberStyle = .decimal
        grouped.groupingSeparator = "\u{2009}"
        func n(_ x: Int) -> String { grouped.string(from: NSNumber(value: x)) ?? "\(x)" }

        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: i.name + "\n", attributes: style(34, .light, 0.9, kern: 0.5)))
        s.append(NSAttributedString(string: "\(i.altName)   \(i.schlafli)\n", attributes: style(15, .regular, 0.6, kern: 1)))
        s.append(NSAttributedString(string: "\n", attributes: style(6, .regular, 0)))
        let body = style(13, .regular, 0.55, kern: 0.6)
        s.append(NSAttributedString(string: "\(n(p.v)) vertices · \(n(p.e)) edges · \(n(p.f)) faces · \(n(p.c)) cells\n", attributes: body))
        s.append(NSAttributedString(string: "cells: \(i.cellType) · vertex figure: \(i.vertexFigure)\n", attributes: body))
        s.append(NSAttributedString(string: "symmetry \(i.symmetry), order \(n(i.symmetryOrder)) · dual: \(i.dual)\n", attributes: body))
        s.append(NSAttributedString(string: frame.projectionLabel, attributes: style(13, .regular, 0.4, kern: 0.6)))
        return s
    }
}

func linearToSRGB(_ x: Float) -> Float {
    x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
}