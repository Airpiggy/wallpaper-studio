import AppKit

// One-off: compose a 1024×1024 macOS app icon from the user's image.png.
// Scales the source up slightly (crops the fuzzy cutout edge) and re-clips to a
// fresh rounded square at the standard macOS content size.
//
// Usage: swift Tools/make-icon.swift <source.png> <out-1024.png>

let args = CommandLine.arguments
let srcPath = args.count > 1 ? args[1] : "image.png"
let outPath = args.count > 2 ? args[2] : "AppIcon-1024.png"

guard let src = NSImage(contentsOfFile: srcPath),
      let srcTiff = src.tiffRepresentation,
      let srcRep = NSBitmapImageRep(data: srcTiff) else {
    FileHandle.standardError.write(Data("cannot load \(srcPath)\n".utf8))
    exit(1)
}
let srcCG = srcRep.cgImage!

let canvas = 1024
let contentBox = 824.0            // ~82% — macOS content size
let inset = (Double(canvas) - contentBox) / 2.0
let overscan = 1.06               // scale source up ~6% to drop the fuzzy edge
let radius = 185.0                // continuous-ish corner radius

let colorSpace = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(
    data: nil, width: canvas, height: canvas,
    bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
ctx.interpolationQuality = .high
ctx.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

// Rounded-rect clip at the content box.
let box = CGRect(x: inset, y: inset, width: contentBox, height: contentBox)
let path = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.addPath(path)
ctx.clip()

// Draw the source overscanned and centered so its edges fall outside the clip.
let drawSize = contentBox * overscan
let drawOrigin = (Double(canvas) - drawSize) / 2.0
ctx.draw(srcCG, in: CGRect(x: drawOrigin, y: drawOrigin, width: drawSize, height: drawSize))

guard let out = ctx.makeImage() else { exit(1) }
let outRep = NSBitmapImageRep(cgImage: out)
guard let png = outRep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
