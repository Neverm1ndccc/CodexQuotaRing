import AppKit

public struct RingSpec: Equatable {
    public let kind: WindowKind
    public let radius: CGFloat
    public let fraction: Double
}
@MainActor public enum RingIconRenderer {
    public static func layout(_ windows: [QuotaWindow]) -> [RingSpec] {
        let ordered = WindowKind.allCases.compactMap { kind in windows.first { $0.kind == kind } }
        return ordered.enumerated().map { index, window in
            RingSpec(kind: window.kind, radius: ordered.count == 1 || index == 0 ? 8 : 4.6, fraction: window.remaining / 100)
        }
    }
    public static func color(_ window: QuotaWindow, stale: Bool = false, monochrome: Bool = false) -> NSColor {
        if stale { return .secondaryLabelColor }
        if window.remaining < 10 { return .systemRed }
        if window.remaining <= 30 { return .systemOrange }
        return monochrome ? .labelColor : (window.kind == .fiveHour ? .systemBlue : .systemGreen)
    }
    public static func render(windows: [QuotaWindow], state: QuotaState, monochrome: Bool = false, restricted: Bool = false) -> NSImage {
        let size = NSSize(width: 20, height: 20)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let rings = layout(windows)
            context.setLineWidth(2); context.setLineCap(.butt)
            if rings.isEmpty {
                context.setStrokeColor(NSColor.secondaryLabelColor.cgColor)
                context.strokeEllipse(in: CGRect(x: 3, y: 3, width: 14, height: 14))
                context.setStrokeColor(NSColor.secondaryLabelColor.cgColor)
                context.setFillColor(NSColor.secondaryLabelColor.cgColor)
                context.setLineWidth(1.4)
                if state == .loading {
                    for x in [6.5, 10.0, 13.5] { context.fillEllipse(in: CGRect(x:x-0.7,y:9.3,width:1.4,height:1.4)) }
                } else if state == .unauthenticated {
                    context.addArc(center: CGPoint(x:10,y:11),radius:2,startAngle:0,endAngle:.pi,clockwise:false)
                    context.strokePath(); context.fill(CGRect(x:7,y:6.5,width:6,height:4.5))
                } else if state == .error || state == .cliUnavailable {
                    context.move(to:CGPoint(x:10,y:13));context.addLine(to:CGPoint(x:10,y:9));context.strokePath()
                    context.fillEllipse(in:CGRect(x:9.2,y:6,width:1.6,height:1.6))
                } else {
                    context.move(to:CGPoint(x:7,y:10));context.addLine(to:CGPoint(x:13,y:10));context.strokePath()
                }
            }
            for ring in rings {
                context.setStrokeColor(NSColor.labelColor.withAlphaComponent(0.18).cgColor)
                context.strokeEllipse(in: CGRect(x: 10 - ring.radius, y: 10 - ring.radius, width: 2 * ring.radius, height: 2 * ring.radius))
                guard ring.fraction > 0, let window = windows.first(where: { $0.kind == ring.kind }) else { continue }
                context.setStrokeColor(color(window, stale: state != .ready || restricted, monochrome: monochrome).cgColor)
                context.addArc(center: CGPoint(x: 10, y: 10), radius: ring.radius, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * ring.fraction, clockwise: true)
                context.strokePath()
            }
            if restricted { context.setFillColor(NSColor.systemRed.cgColor); context.fillEllipse(in: CGRect(x: 8.5, y: 8.5, width: 3, height: 3)) }
            return true
        }
        image.isTemplate = false
        return image
    }
}
