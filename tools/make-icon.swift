// Generates Resources/AppIcon.icns from tools/google-g.png.
//
// Google's apps use a white rounded tile with the four-colour "G", so this does
// the same: the mark sits at ~62 % of the tile, which is what the Drive/Docs
// icons measure. Run it after replacing the source PNG:
//
//   swift tools/make-icon.swift && ./build.sh
//
// Source: https://ssl.gstatic.com/images/branding/product/1x/googleg_512dp.png
// The mark is Google's trademark; this icon is for a personal build, not a
// distribution.

import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("tools/google-g.png")
let outDir = root.appendingPathComponent("tools/AppIcon.iconset", isDirectory: true)
let icns = root.appendingPathComponent("Resources/AppIcon.icns")

guard let mark = NSImage(contentsOf: source) else {
    FileHandle.standardError.write("missing \(source.path) — download the Google mark first\n".data(using: .utf8)!)
    exit(1)
}

let tileSide: CGFloat = 512
let corner: CGFloat = tileSide * 0.2237            // iOS/macOS superellipse radius
let markSide = tileSide * 0.62

func render(_ side: CGFloat) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let scale = side / tileSide
    let tile = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: side, height: side),
                            xRadius: corner * scale, yRadius: corner * scale)
    NSColor.white.setFill()
    tile.fill()

    let origin = (side - markSide * scale) / 2
    mark.draw(in: NSRect(x: origin, y: origin, width: markSide * scale, height: markSide * scale),
              from: .zero, operation: .sourceOver, fraction: 1.0,
              respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: icns.deletingLastPathComponent(), withIntermediateDirectories: true)

// The names iconutil expects; each pair is one point-size and its @2x.
let sizes: [(name: String, px: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
]
for entry in sizes {
    guard let data = render(entry.px) else { print("render failed at \(entry.px)"); exit(1) }
    try data.write(to: outDir.appendingPathComponent("\(entry.name).png"))
}
FileHandle.standardError.write("iconset written, run: iconutil -c icns -o Resources/AppIcon.icns tools/AppIcon.iconset\n".data(using: .utf8)!)
