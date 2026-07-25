import Foundation

/// Maps a `WallpaperItem` to a concrete renderer. This is the single seam where
/// a future `SceneRenderer` (WE `scene.pkg`) would plug in — the import pipeline
/// already carries scene items through to here.
enum RendererFactory {
    enum FailureReason: Error {
        case unsupportedKind(String)
        case missingAsset

        var message: String {
            switch self {
            case .unsupportedKind(let s): return s
            case .missingAsset: return "找不到壁纸的主资源文件"
            }
        }
    }

    @MainActor
    static func makeRenderer(
        for item: WallpaperItem,
        storeRoot: URL,
        muted: Bool = true
    ) -> Result<WallpaperRenderer, FailureReason> {
        switch item.kind {
        case .video:
            guard let url = item.mainAssetURL(storeRoot: storeRoot),
                  FileManager.default.fileExists(atPath: url.path) else {
                return .failure(.missingAsset)
            }
            return .success(VideoRenderer(url: url, muted: muted))

        case .web:
            guard let url = item.mainAssetURL(storeRoot: storeRoot),
                  FileManager.default.fileExists(atPath: url.path) else {
                return .failure(.missingAsset)
            }
            let renderer = WebRenderer(
                htmlURL: url,
                folderURL: item.folderURL(storeRoot: storeRoot),
                properties: item.project.properties,
                initialValues: item.effectiveProperties
            )
            return .success(renderer)

        case .image:
            guard let url = item.mainAssetURL(storeRoot: storeRoot),
                  FileManager.default.fileExists(atPath: url.path) else {
                return .failure(.missingAsset)
            }
            return .success(ImageRenderer(url: url))

        case .sceneUnsupported:
            return .failure(.unsupportedKind("场景类型（scene.pkg）暂不支持"))
        case .other:
            return .failure(.unsupportedKind(item.unsupportedReason ?? "不支持的壁纸类型"))
        }
    }
}
