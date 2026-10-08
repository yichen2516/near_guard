import AppKit
let root = CommandLine.arguments[1]
let fm = FileManager.default
let set = root + "/NearGuard.iconset"
try fm.createDirectory(atPath: set, withIntermediateDirectories: true)
func render(_ pixels: Int) -> Data {
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let s = CGFloat(pixels) / 1024
    NSColor(calibratedRed: 0.035, green: 0.16, blue: 0.26, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 48*s, y: 48*s, width: 928*s, height: 928*s), xRadius: 206*s, yRadius: 206*s).fill()
    let shield = NSBezierPath()
    shield.move(to: NSPoint(x: 512*s, y: 832*s)); shield.line(to: NSPoint(x: 788*s, y: 728*s))
    shield.line(to: NSPoint(x: 766*s, y: 443*s)); shield.curve(to: NSPoint(x: 512*s, y: 205*s), controlPoint1: NSPoint(x: 740*s, y: 340*s), controlPoint2: NSPoint(x: 620*s, y: 246*s))
    shield.curve(to: NSPoint(x: 258*s, y: 443*s), controlPoint1: NSPoint(x: 404*s, y: 246*s), controlPoint2: NSPoint(x: 284*s, y: 340*s))
    shield.line(to: NSPoint(x: 236*s, y: 728*s)); shield.close()
    NSColor(calibratedRed: 0.13, green: 0.73, blue: 0.85, alpha: 1).setFill(); shield.fill()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 360*s, y: 439*s, width: 67*s, height: 120*s), xRadius: 20*s, yRadius: 20*s).fill()
    NSBezierPath(roundedRect: NSRect(x: 478*s, y: 439*s, width: 67*s, height: 206*s), xRadius: 20*s, yRadius: 20*s).fill()
    NSBezierPath(roundedRect: NSRect(x: 596*s, y: 439*s, width: 67*s, height: 292*s), xRadius: 20*s, yRadius: 20*s).fill()
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}
for size in [16,32,128,256,512] {
    try render(size).write(to: URL(fileURLWithPath: set + "/icon_\(size)x\(size).png"))
    try render(size*2).write(to: URL(fileURLWithPath: set + "/icon_\(size)x\(size)@2x.png"))
}
