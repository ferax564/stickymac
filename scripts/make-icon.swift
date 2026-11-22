import AppKit

// Draws a stack of three tilted sticky notes and writes a .iconset.
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let ctx = NSGraphicsContext.current!.cgContext

    func note(_ angle: CGFloat, _ top: NSColor, _ bottom: NSColor, lines: Bool) {
        ctx.saveGState()
        ctx.translateBy(x: s / 2, y: s / 2)
        ctx.rotate(by: angle * .pi / 180)
        let side = s * 0.62
        let r = CGRect(x: -side / 2, y: -side / 2, width: side, height: side)
        let path = NSBezierPath(roundedRect: r, xRadius: s * 0.07, yRadius: s * 0.07)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = s * 0.04
        shadow.shadowOffset = NSSize(width: 0, height: -s * 0.015)
        shadow.set()
        top.setFill(); path.fill()
        NSShadow().set()
        NSGradient(starting: top, ending: bottom)!.draw(in: path, angle: -90)
        // header band
        let band = NSBezierPath(roundedRect: CGRect(x: r.minX, y: r.maxY - side * 0.17, width: side, height: side * 0.17),
                                xRadius: s * 0.07, yRadius: s * 0.07)
        NSColor.black.withAlphaComponent(0.06).setFill(); band.fill()
        if lines {
            NSColor.black.withAlphaComponent(0.28).setFill()
            for (i, w) in [0.62, 0.74, 0.48].enumerated() {
                let y = r.maxY - side * (0.36 + CGFloat(i) * 0.16)
                NSBezierPath(roundedRect: CGRect(x: r.minX + side * 0.14, y: y, width: side * w, height: side * 0.055),
                             xRadius: side * 0.03, yRadius: side * 0.03).fill()
            }
        }
        ctx.restoreGState()
    }
    let c = { (h: UInt32) in NSColor(red: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: 1) }
    note(14, c(0xC4E4FF), c(0x98CEFF), lines: false)
    note(-10, c(0xFFC6D9), c(0xFFA3C2), lines: false)
    note(2, c(0xFFF6A8), c(0xFFE76B), lines: true)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
