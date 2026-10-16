// Draws the app icon: scripts/draw-icon.swift <out.png>
// Then: scripts/make-icon.sh <out.png> → Resources/AppIcon.icns
//
// Three stacked windows (every window, not one per app) on a dark slate tile, the front
// one selected with the switcher's purple ring and the macOS traffic lights.
// Follows the macOS icon grid: 1024 canvas, 824 body, ~185 corner radius, soft shadow.
import AppKit

let canvas: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255, alpha: alpha
    )
}

let slateTop = rgb(0x1E293B), slateBottom = rgb(0x0F172A)
let purple = rgb(0xAF52DE)
let trafficLights = [rgb(0xFF5F57), rgb(0xFEBC2E), rgb(0x28C840)]

let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: true) { _ in
    // Tile with a soft drop shadow.
    let tile = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: 12) // in this flipped canvas, positive y points down
    shadow.shadowBlurRadius = 28
    shadow.set()
    slateBottom.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSGradient(starting: slateTop, ending: slateBottom)!.draw(in: body, angle: 90)
    // Faint top sheen for depth.
    NSGradient(colors: [.white.withAlphaComponent(0.07), .clear])!
        .draw(in: CGRect(x: body.minX, y: body.minY, width: body.width, height: body.height * 0.45), angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    // Window cards, back to front, offset diagonally.
    let size = CGSize(width: 500, height: 360)
    let step: CGFloat = 76
    let origin = CGPoint(x: 512 - (size.width + 2 * step) / 2, y: 512 - (size.height + 2 * step) / 2 + 6)
    let radius: CGFloat = 38
    let titleHeight: CGFloat = 62

    func card(at index: Int) -> CGRect {
        CGRect(x: origin.x + CGFloat(index) * step, y: origin.y + CGFloat(index) * step, width: size.width, height: size.height)
    }

    // Back cards: muted slate, so the front one carries the colour.
    for (index, fill, bar) in [(0, rgb(0x3B4A60), rgb(0x48586F)), (1, rgb(0x5D6E87), rgb(0x6B7C95))] {
        let rect = card(at: index)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        fill.setFill()
        path.fill()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        bar.setFill()
        CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: titleHeight).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    // Front card: selection ring, light window, traffic lights, a hint of content.
    let front = card(at: 2)
    let ring = NSBezierPath(roundedRect: front.insetBy(dx: -16, dy: -16), xRadius: radius + 16, yRadius: radius + 16)
    ring.lineWidth = 14
    purple.setStroke()
    ring.stroke()

    let frontPath = NSBezierPath(roundedRect: front, xRadius: radius, yRadius: radius)
    NSGraphicsContext.saveGraphicsState()
    let cardShadow = NSShadow()
    cardShadow.shadowColor = .black.withAlphaComponent(0.3)
    cardShadow.shadowOffset = NSSize(width: 0, height: 6)
    cardShadow.shadowBlurRadius = 18
    cardShadow.set()
    rgb(0xF8FAFC).setFill()
    frontPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    frontPath.addClip()
    rgb(0xE2E8F0).setFill()
    CGRect(x: front.minX, y: front.minY, width: front.width, height: titleHeight).fill()
    // Content: two soft bars, like a preview of a document.
    rgb(0xCBD5E1).setFill()
    NSBezierPath(roundedRect: CGRect(x: front.minX + 40, y: front.minY + titleHeight + 46, width: 300, height: 30), xRadius: 15, yRadius: 15).fill()
    NSBezierPath(roundedRect: CGRect(x: front.minX + 40, y: front.minY + titleHeight + 100, width: 400, height: 30), xRadius: 15, yRadius: 15).fill()
    NSBezierPath(roundedRect: CGRect(x: front.minX + 40, y: front.minY + titleHeight + 154, width: 220, height: 30), xRadius: 15, yRadius: 15).fill()
    NSGraphicsContext.restoreGraphicsState()

    let dot: CGFloat = 26
    for (i, color) in trafficLights.enumerated() {
        let rect = CGRect(x: front.minX + 30 + CGFloat(i) * (dot + 14), y: front.minY + (titleHeight - dot) / 2, width: dot, height: dot)
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
    }
    return true
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = image.size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
NSGraphicsContext.restoreGraphicsState()
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
