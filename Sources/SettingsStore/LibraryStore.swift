import Foundation

/// Well-known on-disk locations for the app's data.
enum AppPaths {
    /// `~/Library/Application Support/Wallpaper Studio/`
    static var supportRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Wallpaper Studio", isDirectory: true)
    }

    static var wallpapersRoot: URL { supportRoot.appendingPathComponent("Wallpapers", isDirectory: true) }
    static var thumbnailsRoot: URL { supportRoot.appendingPathComponent("thumbnails", isDirectory: true) }
    static var libraryFile: URL { supportRoot.appendingPathComponent("library.json") }

    /// Create the directory tree if needed.
    static func ensureDirectories() {
        for dir in [supportRoot, wallpapersRoot, thumbnailsRoot] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}

/// Reads/writes the persisted wallpaper library (`library.json`) with atomic,
/// versioned writes.
struct LibraryStore {
    private struct Payload: Codable {
        var schemaVersion: Int
        var items: [WallpaperItem]
    }

    private static let currentSchema = 1

    static func load() -> [WallpaperItem] {
        guard let data = try? Data(contentsOf: AppPaths.libraryFile),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return []
        }
        return payload.items
    }

    static func save(_ items: [WallpaperItem]) {
        AppPaths.ensureDirectories()
        let payload = Payload(schemaVersion: currentSchema, items: items)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: AppPaths.libraryFile, options: .atomic)
    }
}
