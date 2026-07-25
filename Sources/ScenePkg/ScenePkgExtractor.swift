import AppKit

/// Extracts a single static "main image" from a WE `scene.pkg`, discarding all
/// particle/shader animation. Writes the result next to the wallpaper so the
/// existing image pipeline can render it. Purely a reduction — not a renderer.
enum ScenePkgExtractor {
    static let extractedBaseName = "_ws_extracted"

    enum ExtractError: LocalizedError {
        case noPkg
        case noDecodableTexture

        var errorDescription: String? {
            switch self {
            case .noPkg: return "文件夹中没有 scene.pkg / gifscene.pkg"
            case .noDecodableTexture: return "未能从场景中解出可用的主图"
            }
        }
    }

    /// Extract into `folder`; returns the written file name (relative). Throws on
    /// failure. Safe to call off the main thread.
    @discardableResult
    static func extract(folder: URL) throws -> String {
        guard let pkgURL = findPkg(in: folder) else { throw ExtractError.noPkg }
        let archive = try PKGReader.read(url: pkgURL)

        // Try candidate textures in priority order until one decodes.
        for entry in candidateTexEntries(archive) {
            guard let texData = archive.data(for: entry),
                  let decoded = try? TEXReader.decode(data: texData),
                  let (filename, bytes) = encode(decoded) else { continue }
            let outURL = folder.appendingPathComponent(filename)
            try bytes.write(to: outURL, options: .atomic)
            return filename
        }
        throw ExtractError.noDecodableTexture
    }

    // MARK: - PKG location

    static func findPkg(in folder: URL) -> URL? {
        for name in ["scene.pkg", "gifscene.pkg"] {
            let url = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    // MARK: - Main-image selection

    /// Ordered candidate list: the scene.json background chain first (Plan A),
    /// then all textures largest-first, non-GIF preferred (Plan B). Deduped.
    private static func candidateTexEntries(_ archive: PKGArchive) -> [PKGEntry] {
        var ordered: [PKGEntry] = []
        var seen = Set<String>()
        func add(_ e: PKGEntry) {
            if seen.insert(e.path).inserted { ordered.append(e) }
        }

        if let planA = backgroundTexFromScene(archive) { add(planA) }

        let scored = archive.entries(withExtension: "tex").compactMap { entry -> (PKGEntry, Int)? in
            guard let data = archive.data(for: entry),
                  let info = try? TEXReader.headerOnly(data: data) else { return nil }
            let area = max(info.imgWidth * info.imgHeight, 0)
            let score = area - (info.isGif ? 1_000_000_000 : 0) // deprioritize GIF sheets
            return (entry, score)
        }
        .sorted { $0.1 > $1.1 }
        for (entry, _) in scored { add(entry) }

        return ordered
    }

    /// Plan A: walk scene.json objects → image json → material json → first
    /// texture. Returns the first resolvable `materials/<name>.tex`. Best-effort.
    private static func backgroundTexFromScene(_ archive: PKGArchive) -> PKGEntry? {
        guard let sceneData = archive.data(named: "scene.json"),
              let scene = try? JSONDecoder().decode(JSONValue.self, from: sceneData),
              let objects = scene.objectValue?["objects"]?.arrayValue else { return nil }

        for object in objects {
            guard let obj = object.objectValue else { continue }
            // Image objects reference a model json via "image".
            guard let imagePath = obj["image"]?.stringValue,
                  imagePath.hasSuffix(".json"),
                  let modelData = archive.data(named: imagePath),
                  let model = try? JSONDecoder().decode(JSONValue.self, from: modelData),
                  let materialPath = model.objectValue?["material"]?.stringValue,
                  let materialData = archive.data(named: materialPath),
                  let material = try? JSONDecoder().decode(JSONValue.self, from: materialData)
            else { continue }

            guard let passes = material.objectValue?["passes"]?.arrayValue,
                  let firstPass = passes.first?.objectValue,
                  let textures = firstPass["textures"]?.arrayValue,
                  let texName = textures.first?.stringValue, !texName.isEmpty
            else { continue }

            // Texture name → pkg entry (try a few reasonable path shapes).
            for candidate in [
                "materials/\(texName).tex",
                "\(texName).tex",
                texName.hasSuffix(".tex") ? texName : "\(texName).tex",
            ] {
                if let entry = archive.entry(named: candidate) { return entry }
            }
        }
        return nil
    }

    // MARK: - Encoding

    /// Turn a decoded TEX into (filename, bytes) ready to write.
    private static func encode(_ decoded: TEXDecoded) -> (String, Data)? {
        switch decoded {
        case .fileBytes(let data, let fmt):
            let ext = sniffExtension(data) ?? defaultExtension(fmt)
            return ("\(extractedBaseName).\(ext)", data)
        case .rawRGBA(let pixels, let width, let height):
            guard let png = pngData(rgba: pixels, width: width, height: height) else { return nil }
            return ("\(extractedBaseName).png", png)
        }
    }

    private static func sniffExtension(_ data: Data) -> String? {
        let b = [UInt8](data.prefix(4))
        if b.count >= 4 {
            if b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 { return "png" }
            if b[0] == 0xFF, b[1] == 0xD8 { return "jpg" }
            if b[0] == 0x47, b[1] == 0x49, b[2] == 0x46 { return "gif" }
            if b[0] == 0x42, b[1] == 0x4D { return "bmp" }
        }
        return nil
    }

    private static func defaultExtension(_ fmt: FreeImageFormat) -> String {
        switch fmt {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .gif: return "gif"
        case .bmp: return "bmp"
        default: return "png"
        }
    }

    private static func pngData(rgba: [UInt8], width: Int, height: Int) -> Data? {
        guard width > 0, height > 0, rgba.count >= width * height * 4 else { return nil }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        guard let cg = CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo,
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }
}
