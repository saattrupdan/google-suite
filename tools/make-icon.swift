// Generates the checked-in iconset and Resources/AppIcon.icns from
// tools/google-g.png.
//
// Google's apps use a white rounded tile with the four-colour "G", so this does
// the same: the mark is 62 % of the tile, which is what the Drive/Docs icons
// measure. The tile itself is 80 % of the transparent canvas, matching the
// modern macOS icon safe area. Run it after replacing the source PNG:
//
//   swift tools/make-icon.swift && ./build.sh
//
// Source: https://ssl.gstatic.com/images/branding/product/1x/googleg_512dp.png
// The mark is Google's trademark; this icon is for a personal build, not a
// distribution.

import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("tools/google-g.png")
let iconsetDirectory = root.appendingPathComponent("tools/AppIcon.iconset", isDirectory: true)
let icnsURL = root.appendingPathComponent("Resources/AppIcon.icns")

guard let mark = NSImage(contentsOf: source) else {
    FileHandle.standardError.write("missing \(source.path) — download the Google mark first\n".data(using: .utf8)!)
    exit(1)
}

let canvasSide: CGFloat = 512
let tileFractionOfCanvas: CGFloat = 0.80
let tileSide = canvasSide * tileFractionOfCanvas
let tileOriginOnCanvas = (canvasSide - tileSide) / 2
let tileCornerRadius = tileSide * 0.2237       // iOS/macOS superellipse radius
let markFractionOfTile: CGFloat = 0.62
let markSide = tileSide * markFractionOfTile
let markOriginOnCanvas = tileOriginOnCanvas + (tileSide - markSide) / 2

func render(canvasPixels: CGFloat) -> Data? {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                        pixelsWide: Int(canvasPixels),
                                        pixelsHigh: Int(canvasPixels),
                                        bitsPerSample: 8,
                                        samplesPerPixel: 4,
                                        hasAlpha: true,
                                        isPlanar: false,
                                        colorSpaceName: .deviceRGB,
                                        bytesPerRow: 0,
                                        bitsPerPixel: 0) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.shouldAntialias = true

    let scale = canvasPixels / canvasSide
    let tileRect = NSRect(x: tileOriginOnCanvas * scale,
                          y: tileOriginOnCanvas * scale,
                          width: tileSide * scale,
                          height: tileSide * scale)
    let tile = NSBezierPath(roundedRect: tileRect,
                            xRadius: tileCornerRadius * scale,
                            yRadius: tileCornerRadius * scale)
    NSColor.white.setFill()
    tile.fill()

    let markRect = NSRect(x: markOriginOnCanvas * scale,
                          y: markOriginOnCanvas * scale,
                          width: markSide * scale,
                          height: markSide * scale)
    mark.draw(in: markRect,
              from: .zero,
              operation: .sourceOver,
              fraction: 1.0,
              respectFlipped: true,
              hints: [.interpolation: NSImageInterpolation.high.rawValue])

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])
}

func failValidation(_ message: String) -> Never {
    FileHandle.standardError.write("icon validation failed: \(message)\n".data(using: .utf8)!)
    exit(1)
}

// Read the encoded PNG back rather than validating only the in-memory bitmap.
// This catches accidental format changes and verifies the transparent safe area
// at every iconset size. One pixel of tolerance covers antialiasing at tiny sizes.
func validatePNG(at url: URL, expectedSide: Int) {
    guard let image = NSImage(contentsOf: url),
          let representation = image.representations.first as? NSBitmapImageRep,
          representation.pixelsWide == expectedSide,
          representation.pixelsHigh == expectedSide else {
        failValidation("\(url.lastPathComponent) is not \(expectedSide)x\(expectedSide)")
    }

    var minX = expectedSide
    var maxX = -1
    var minY = expectedSide
    var maxY = -1
    for y in 0..<expectedSide {
        for x in 0..<expectedSide {
            guard let color = representation.colorAt(x: x, y: y),
                  let deviceColor = color.usingColorSpace(.deviceRGB) else {
                failValidation("could not inspect \(url.lastPathComponent)")
            }
            if deviceColor.alphaComponent > 0.01 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
    }

    let scale = CGFloat(expectedSide) / canvasSide
    let expectedMin = Int(floor(tileOriginOnCanvas * scale))
    let expectedMax = Int(ceil((tileOriginOnCanvas + tileSide) * scale)) - 1
    guard minX >= expectedMin - 1, maxX <= expectedMax + 1,
          minY >= expectedMin - 1, maxY <= expectedMax + 1 else {
        failValidation("\(url.lastPathComponent) extends beyond the tile bounds")
    }
    guard abs(minX - (expectedSide - 1 - maxX)) <= 1,
          abs(minY - (expectedSide - 1 - maxY)) <= 1,
          minX > 0, minY > 0 else {
        failValidation("\(url.lastPathComponent) has asymmetric transparent padding")
    }

    let center = representation.colorAt(x: expectedSide / 2, y: expectedSide / 2)
    guard center?.usingColorSpace(.deviceRGB)?.alphaComponent ?? 0 >= 0.99 else {
        failValidation("\(url.lastPathComponent) tile center is not opaque")
    }
}

try FileManager.default.createDirectory(at: iconsetDirectory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: icnsURL.deletingLastPathComponent(), withIntermediateDirectories: true)

// The names iconutil expects; each pair is one point-size and its @2x.
let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
]
for entry in sizes {
    guard let data = render(canvasPixels: CGFloat(entry.pixels)) else {
        failValidation("render failed at \(entry.pixels)")
    }
    let pngURL = iconsetDirectory.appendingPathComponent("\(entry.name).png")
    try data.write(to: pngURL)
    validatePNG(at: pngURL, expectedSide: entry.pixels)
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", icnsURL.path, iconsetDirectory.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    failValidation("iconutil failed with status \(iconutil.terminationStatus)")
}

print("generated \(sizes.count) PNGs and \(icnsURL.path)")
print("canvas: \(Int(canvasSide))px; tile: \(tileFractionOfCanvas * 100)% (\(tileSide)px); mark: \(markFractionOfTile * 100)% of tile")
