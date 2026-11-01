import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
        NSColor(red: 0.863, green: 0.910, blue: 0.953, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 210, yRadius: 210).fill()
        NSColor(red: 0.137, green: 0.235, blue: 0.353, alpha: 1).setStroke()
        let rotate = NSAffineTransform(); rotate.translateX(by: 512, yBy: 512); rotate.rotate(byDegrees: 40); rotate.translateX(by: -512, yBy: -512); rotate.concat()
        for x in [260.0, 440.0] {
            let path = NSBezierPath(roundedRect: NSRect(x: x, y: 390, width: 320, height: 244), xRadius: 122, yRadius: 122)
            path.lineWidth = 57; path.stroke()
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name))
    }
}
