import AppKit
import AVFoundation

/// Produces and caches thumbnail images for wallpapers. Prefers the WE
/// `preview` image; falls back to a grabbed video frame.
actor ThumbnailProvider {
    static let shared = ThumbnailProvider()

    private var memoryCache: [UUID: NSImage] = [:]

    func thumbnail(for item: WallpaperItem, storeRoot: URL) async -> NSImage? {
        if let cached = memoryCache[item.id] { return cached }

        // Disk cache (PNG).
        let cacheURL = AppPaths.thumbnailsRoot.appendingPathComponent("\(item.id.uuidString).png")
        if let data = try? Data(contentsOf: cacheURL), let img = NSImage(data: data) {
            memoryCache[item.id] = img
            return img
        }

        let image = await render(item: item, storeRoot: storeRoot)
        if let image, let png = image.pngData() {
            try? png.write(to: cacheURL, options: .atomic)
            memoryCache[item.id] = image
        }
        return image
    }

    private func render(item: WallpaperItem, storeRoot: URL) async -> NSImage? {
        // 1. WE preview image (jpg/png/gif — NSImage loads the first GIF frame).
        if let previewURL = item.previewURL(storeRoot: storeRoot),
           FileManager.default.fileExists(atPath: previewURL.path),
           let img = NSImage(contentsOf: previewURL) {
            return img
        }

        // 2. Video frame grab.
        if item.kind == .video, let asset = item.mainAssetURL(storeRoot: storeRoot),
           FileManager.default.fileExists(atPath: asset.path) {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: asset))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)
            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            if let cg = try? await generator.image(at: time).image {
                return NSImage(cgImage: cg, size: .zero)
            }
        }

        // 3. Image wallpaper with no separate preview: use the asset itself.
        if item.kind == .image, let asset = item.mainAssetURL(storeRoot: storeRoot),
           FileManager.default.fileExists(atPath: asset.path),
           let img = NSImage(contentsOf: asset) {
            return img
        }

        return nil
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
