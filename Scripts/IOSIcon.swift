import AppKit
// Flatten the matching Mac icon onto an opaque RGB background for iOS.
let root = CommandLine.arguments[1]
let size = 1024
import ImageIO
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.035, green: 0.16, blue: 0.26, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
let icon = NSImage(contentsOfFile: root + "/Resources/NearGuard.iconset/icon_512x512@2x.png")!
var rect = CGRect(x: 0, y: 0, width: size, height: size)
let image = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
context.draw(image, in: rect)
context.flush()
let path = root + "/iOS/NearGuardPhone/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("PNG write failed") }
print("Wrote opaque 1024px iOS icon: \(path)")
