import AppKit

/// Offline visual diagnostic. Values are labeled test fixtures, never production data.
@main struct RenderRings {
    @MainActor static func main() throws {
        let samples: [(String, [QuotaWindow], QuotaState)] = [
            ("Dual 72 / 43", [.init(kind:.fiveHour, remaining:72), .init(kind:.weekly, remaining:43)], .ready),
            ("Weekly 50", [.init(kind:.weekly, remaining:50)], .ready),
            ("5-hour 25", [.init(kind:.fiveHour, remaining:25)], .ready),
            ("0 / 100", [.init(kind:.fiveHour, remaining:0), .init(kind:.weekly, remaining:100)], .ready),
            ("No data", [], .noQuotaData),
            ("Stale", [.init(kind:.fiveHour, remaining:72), .init(kind:.weekly, remaining:43)], .stale)
        ]
        let canvas = NSImage(size:NSSize(width:600,height:290),flipped:false) { _ in
            for side in 0..<2 {
                let appearance=NSAppearance(named:side == 0 ? .aqua : .darkAqua)!
                appearance.performAsCurrentDrawingAppearance {
                    (side == 0 ? NSColor.white : NSColor(calibratedWhite:0.12,alpha:1)).setFill()
                    NSRect(x:side*300,y:0,width:300,height:290).fill()
                    let attrs: [NSAttributedString.Key: Any] = [.font:NSFont.systemFont(ofSize:11),.foregroundColor:NSColor.labelColor]
                    (side == 0 ? "LIGHT · TEST FIXTURES" : "DARK · TEST FIXTURES").draw(at:NSPoint(x:side*300+20,y:265),withAttributes:attrs)
                    for (index,sample) in samples.enumerated() {
                        let x=CGFloat(side*300+(index%3)*100+50), y=CGFloat(210-(index/3)*120)
                        let icon=RingIconRenderer.render(windows:sample.1,state:sample.2)
                        icon.draw(in:NSRect(x:x-30,y:y-20,width:60,height:60))
                        icon.draw(in:NSRect(x:x-10,y:y-50,width:20,height:20))
                        (sample.0 as NSString).draw(at:NSPoint(x:x-40,y:y-70),withAttributes:attrs)
                    }
                }
            }
            return true
        }
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1200,pixelsHigh:580,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        bitmap.size=NSSize(width:600,height:290)
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
        canvas.draw(in:NSRect(x:0,y:0,width:600,height:290))
        NSGraphicsContext.restoreGraphicsState()
        let path=CommandLine.arguments.dropFirst().first ?? "ring-preview.png"
        try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:path))
        print("Rendered test fixture rings: \(path)")
    }
}
