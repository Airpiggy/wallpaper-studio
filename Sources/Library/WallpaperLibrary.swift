import AppKit

/// Observable collection of imported wallpapers, backed by `LibraryStore`.
@MainActor
final class WallpaperLibrary: ObservableObject {
    @Published private(set) var items: [WallpaperItem] = []
    @Published var lastImportSummary: String?

    let storeRoot = AppPaths.wallpapersRoot

    init() {
        items = LibraryStore.load()
    }

    // MARK: - Import

    /// Import from user-selected folders on a background task, then merge.
    func importFrom(urls: [URL], copyIntoStore: Bool) async {
        let existing = Set(items.compactMap(\.workshopID))
        let result = await Task.detached(priority: .userInitiated) {
            ImportService.importWallpapers(
                from: urls,
                copyIntoStore: copyIntoStore,
                existingWorkshopIDs: existing
            )
        }.value

        items.append(contentsOf: result.imported)
        persist()

        var summary = "导入 \(result.imported.count) 个壁纸"
        if !result.skipped.isEmpty {
            summary += "，跳过 \(result.skipped.count) 个"
        }
        lastImportSummary = summary
    }

    // MARK: - Mutation

    func delete(_ item: WallpaperItem) {
        // Remove copied folder + cached thumbnail from disk.
        if !item.isReferenced {
            try? FileManager.default.removeItem(at: item.folderURL(storeRoot: storeRoot))
        }
        let thumb = AppPaths.thumbnailsRoot.appendingPathComponent("\(item.id.uuidString).png")
        try? FileManager.default.removeItem(at: thumb)

        items.removeAll { $0.id == item.id }
        persist()
    }

    func updatePropertyValues(_ values: [String: JSONValue], for itemID: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[idx].propertyValues = values
        persist()
    }

    func item(id: UUID) -> WallpaperItem? {
        items.first { $0.id == id }
    }

    func rename(_ item: WallpaperItem, to newTitle: String) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items[idx].project.title = trimmed
        persist()
    }

    /// Convert a webm item to mp4 via ffmpeg. Returns an error message on failure.
    func convertWebmToMP4(_ item: WallpaperItem) async -> String? {
        guard let src = item.mainAssetURL(storeRoot: storeRoot) else { return "找不到源文件" }
        do {
            let outURL = try await ConversionService.convertToMP4(sourceURL: src)
            guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return nil }
            items[idx].project.file = outURL.lastPathComponent
            items[idx].unsupportedReason = nil
            // Invalidate cached thumbnail so it regenerates from the new mp4.
            let thumb = AppPaths.thumbnailsRoot.appendingPathComponent("\(item.id.uuidString).png")
            try? FileManager.default.removeItem(at: thumb)
            persist()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Extract a static main image from a scene.pkg wallpaper and upgrade the
    /// item to `.image`. Returns an error message on failure.
    func extractSceneImage(_ item: WallpaperItem) async -> String? {
        let folder = item.folderURL(storeRoot: storeRoot)
        let result: Result<String, Error> = await Task.detached(priority: .userInitiated) {
            do { return .success(try ScenePkgExtractor.extract(folder: folder)) }
            catch { return .failure(error) }
        }.value

        switch result {
        case .failure(let error):
            return error.localizedDescription
        case .success(let filename):
            guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return nil }
            items[idx].project.file = filename
            items[idx].kind = .image
            items[idx].unsupportedReason = nil
            let thumb = AppPaths.thumbnailsRoot.appendingPathComponent("\(item.id.uuidString).png")
            try? FileManager.default.removeItem(at: thumb)
            persist()
            return nil
        }
    }

    private func persist() {
        LibraryStore.save(items)
    }
}
