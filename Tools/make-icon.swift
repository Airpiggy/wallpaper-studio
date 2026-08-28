import AppKit

// Compose macOS app icon artwork from the user's image.png.
//
//   swift Tools/make-icon.swift <source.png> Resources/AppIcon.icon/Assets/artwork.png
//
// Produces the single layer of AppIcon.icon. It fills the whole canvas with opaque artwork and draws no corners
// of its own: macOS 26 applies the squircle mask itself, and an icon that leaves
// its own transparent margin gets parked on a grey backing plate instead.
// The source is a rounded square on transparency, so filling the canvas means
// cropping inside those corners — and inside far enough that the source's own
// glass rim goes with them, or it survives as an inset outline that reads as
// exactly the border we are trying to be rid of. The crop is the largest centred
// square that is opaque to its corners, pulled in by `rimTrim` to clear the rim.

let args = Array(CommandLine.arguments.dropFirst())
let srcPath = args.count > 0 ? args[0] : "image.png"
let outPath = args.count > 1 ? args[1] : "Resources/AppIcon.icon/Assets/artwork.png"

guard let src = NSImage(contentsOfFile: srcPath),
      let srcTiff = src.tiffRepresentation,
      let srcRep = NSBitmapImageRep(data: srcTiff),
      let srcCG = srcRep.cgImage else {
    FileHandle.standardError.write(Data("cannot load \(srcPath)\n".utf8))
    exit(1)
}

let canvas = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()

// MARK: - Full-bleed (Tahoe / Liquid Glass) artwork

/// Alpha map of the source, bottom-up to match Core Graphics' coordinate space.
func sourceAlpha() -> (buf: [UInt8], w: Int, h: Int) {
    let w = srcCG.width, h = srcCG.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    buf.withUnsafeMutableBytes { raw in
        let ctx = CGContext(
            data: raw.baseAddress, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.draw(srcCG, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return (buf, w, h)
}

func makeFullBleed() -> CGImage {
    let (buf, w, h) = sourceAlpha()
    func opaque(_ x: Int, _ y: Int) -> Bool { buf[(y * w + x) * 4 + 3] > 250 }

    // Opaque bounding box, and its centre — the source art sits slightly high in
    // its canvas, so centring on the image would shift the crop.
    var minX = w, maxX = 0, minY = h, maxY = 0
    for y in 0..<h {
        for x in 0..<w where opaque(x, y) {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard minX <= maxX else {
        FileHandle.standardError.write(Data("source has no opaque pixels\n".utf8))
        exit(1)
    }
    let cx = Double(minX + maxX) / 2.0, cy = Double(minY + maxY) / 2.0

    // Largest centred square that is opaque all the way to its corners.
    func allOpaque(half: Double) -> Bool {
        let x0 = Int(cx - half), x1 = Int(cx + half)
        let y0 = Int(cy - half), y1 = Int(cy + half)
        guard x0 >= 0, y0 >= 0, x1 < w, y1 < h else { return false }
        for y in y0...y1 { for x in x0...x1 where !opaque(x, y) { return false } }
        return true
    }
    var lo = 0.0, hi = Double(max(w, h))
    for _ in 0..<24 {
        let mid = (lo + hi) / 2
        if allOpaque(half: mid) { lo = mid } else { hi = mid }
    }
    let rimTrim = 0.94                  // pull inside the source's glass rim
    let cropSide = lo * 2 * rimTrim

    // Opaque canvas — no alpha channel at all, so nothing can read as a margin.
    let ctx = CGContext(
        data: nil, width: canvas, height: canvas,
        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    ctx.interpolationQuality = .high

    // Scale the source so that a centred `cropSide`-wide region of it exactly
    // fills the canvas, keeping the opaque centre on the canvas centre.
    let scale = Double(canvas) / cropSide
    ctx.draw(srcCG, in: CGRect(
        x: Double(canvas) / 2.0 - cx * scale,
        y: Double(canvas) / 2.0 - cy * scale,
        width: Double(w) * scale, height: Double(h) * scale
    ))

    let image = ctx.makeImage()!
    print("full-bleed: cropped to \(String(format: "%.1f%%", cropSide / Double(w) * 100)) of source")
    return image
}

// MARK: - Write

let image = makeFullBleed()
let outRep = NSBitmapImageRep(cgImage: image)
guard let png = outRep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
