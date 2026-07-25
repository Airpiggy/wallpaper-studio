import Foundation

/// How a wallpaper can be rendered.
enum WallpaperKind: String, Codable {
    case video
    case web
    case image              // static image / gif, or a scene.pkg reduced to its main image
    case sceneUnsupported   // WE scene.pkg whose main image couldn't be extracted
    case other              // application / unknown

    var isSupported: Bool { self == .video || self == .web || self == .image }

    var displayBadge: String {
        switch self {
        case .video: return "视频"
        case .web: return "网页"
        case .image: return "图片"
        case .sceneUnsupported: return "场景 · 暂不支持"
        case .other: return "不支持"
        }
    }
}

/// An imported wallpaper: metadata plus a pointer to its on-disk folder.
struct WallpaperItem: Codable, Identifiable, Equatable {
    let id: UUID
    var workshopID: String?
    /// Folder name inside the app's `Wallpapers/` store, OR — when `isReferenced`
    /// — an absolute path to the wallpaper folder left in place.
    var folderPath: String
    var isReferenced: Bool
    var project: WEProject
    var kind: WallpaperKind
    var unsupportedReason: String?
    /// User overrides for WE properties, keyed by property key.
    var propertyValues: [String: JSONValue]
    var addedDate: Date

    /// Absolute URL of the wallpaper's folder.
    func folderURL(storeRoot: URL) -> URL {
        isReferenced ? URL(fileURLWithPath: folderPath)
                     : storeRoot.appendingPathComponent(folderPath, isDirectory: true)
    }

    /// Absolute URL of the main asset file (`project.file`), if known.
    func mainAssetURL(storeRoot: URL) -> URL? {
        guard let file = project.file else { return nil }
        return folderURL(storeRoot: storeRoot).appendingPathComponent(file)
    }

    /// Absolute URL of the preview image, if present.
    func previewURL(storeRoot: URL) -> URL? {
        guard let preview = project.preview else { return nil }
        return folderURL(storeRoot: storeRoot).appendingPathComponent(preview)
    }

    /// Effective value for a property: user override falls back to the WE default.
    func value(for property: WEProperty) -> JSONValue {
        propertyValues[property.key] ?? property.defaultValue
    }

    /// All effective property values, ready to push to a renderer.
    var effectiveProperties: [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        for p in project.properties {
            result[p.key] = propertyValues[p.key] ?? p.defaultValue
        }
        return result
    }
}
