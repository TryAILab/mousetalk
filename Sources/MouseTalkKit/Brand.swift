import AppKit

public enum MouseTalkBrand {
    public static let name = "鼠语 MouseTalk"

    /// One vector mark for the settings header, menu bar and exported app icon.
    public static func image(size: CGFloat = 80, template: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSGraphicsContext.current?.shouldAntialias = true
            let transform = AffineTransform(scale: size / 100)
            let ink = template ? NSColor.black : NSColor(calibratedRed: 0.11, green: 0.34, blue: 0.31, alpha: 1)
            func draw(_ path: NSBezierPath, color: NSColor, stroke: Bool = false) {
                path.transform(using: transform)
                color.set()
                if stroke { path.stroke() } else { path.fill() }
            }
            if !template {
                draw(NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 100, height: 100), xRadius: 24, yRadius: 24),
                     color: NSColor(calibratedRed: 0.90, green: 0.96, blue: 0.92, alpha: 1))
            }
            // Round ears + an elongated mouse body, joined into one silhouette.
            for x in [CGFloat(15), CGFloat(60)] {
                draw(NSBezierPath(ovalIn: NSRect(x: x, y: 61, width: 25, height: 25)), color: ink)
            }
            let face = NSBezierPath()
            face.move(to: NSPoint(x: 50, y: 79))
            face.curve(to: NSPoint(x: 23, y: 53), controlPoint1: NSPoint(x: 32, y: 79), controlPoint2: NSPoint(x: 23, y: 67))
            face.curve(to: NSPoint(x: 50, y: 16), controlPoint1: NSPoint(x: 23, y: 29), controlPoint2: NSPoint(x: 34, y: 16))
            face.curve(to: NSPoint(x: 77, y: 53), controlPoint1: NSPoint(x: 66, y: 16), controlPoint2: NSPoint(x: 77, y: 29))
            face.curve(to: NSPoint(x: 50, y: 79), controlPoint1: NSPoint(x: 77, y: 67), controlPoint2: NSPoint(x: 68, y: 79))
            face.close()
            draw(face, color: ink)
            // Knockouts keep the small menu-bar version legible on light and dark menus.
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = template ? .destinationOut : .sourceOver
            let accent = template ? NSColor.black : NSColor(calibratedRed: 0.90, green: 0.96, blue: 0.92, alpha: 1)
            draw(NSBezierPath(roundedRect: NSRect(x: 46, y: 50, width: 8, height: 17), xRadius: 4, yRadius: 4), color: accent)
            for x in [CGFloat(34), CGFloat(61)] {
                draw(NSBezierPath(ovalIn: NSRect(x: x, y: 45, width: 5, height: 5)), color: accent)
            }
            let seam = NSBezierPath(rect: NSRect(x: 49, y: 69, width: 2, height: 10))
            draw(seam, color: accent)
            NSGraphicsContext.restoreGraphicsState()
            // A small voice wave at the right edge.
            if !template {
                for (x, height) in [(CGFloat(81), CGFloat(9)), (87, 18), (93, 11)] {
                    draw(NSBezierPath(roundedRect: NSRect(x: x, y: 35 - height / 2, width: 3, height: height), xRadius: 1.5, yRadius: 1.5), color: ink)
                }
            }
            return true
        }
        image.isTemplate = template
        return image
    }

    public static func exportPNG(to url: URL, pixels: Int) throws {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image(size: CGFloat(pixels)).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }
}
