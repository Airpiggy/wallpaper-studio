import Foundation

/// Scans folders for Wallpaper Engine wallpapers, classifies them, and imports
/// them into the app's store (copy by default, or reference in place).
struct ImportService {
    struct Result {
        var imported: [WallpaperItem]
        var skipped: [String]   // human-readable reasons for anything skipped
    }

    private static let fm = FileManager.default

    /// Recursively find every directory that directly contains a `project.json`.
    /// A single wallpaper folder or a whole `431960/` content dir both work.
    static func findWallpaperFolders(in root: URL) -> [URL] {
        var results: [URL] = []
        // Is the root itself a wallpaper folder?
        if fm.fileExists(atPath: root.appendingPathComponent("project.json").path) {
            results.append(root)
        }
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return results }

        for case let url as URL in enumerator {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }
            if fm.fileExists(atPath: url.appendingPathComponent("project.json").path) {
                results.append(url)
            }
        }
        return results
    }

    /// Import the wallpapers found under each source URL.
    /// `existingIDs` (workshop IDs) lets callers avoid duplicate imports.
    static func importWallpapers(
        from sources: [URL],
        copyIntoStore: Bool,
        existingWorkshopIDs: Set<String>
    ) -> Result {
        AppPaths.ensureDirectories()
        var imported: [WallpaperItem] = []
        var skipped: [String] = []
        var seenWorkshop = existingWorkshopIDs

        for source in sources {
            // A bare image file selected directly → synthesize a wallpaper folder.
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: source.path, isDirectory: &isDir), !isDir.boolValue {
                if isImageExtension(source.lastPathComponent), let item = makeBareImageItem(source: source) {
                    imported.append(item)
                } else {
                    skipped.append("\(source.lastPathComponent)：不是壁纸文件夹或受支持的图片")
                }
                continue
            }

            for folder in findWallpaperFolders(in: source) {
                let projectURL = folder.appendingPathComponent("project.json")
                guard let data = try? Data(contentsOf: projectURL),
                      let project = WEProject.parse(data: data) else {
                    skipped.append("\(folder.lastPathComponent)：project.json 无法解析")
                    continue
                }

                let workshopID = workshopID(from: folder)
                if let wid = workshopID, seenWorkshop.contains(wid) {
                    skipped.append("\(project.title)：已导入，跳过")
                    continue
                }

                var (kind, reason) = classify(project: project, folder: folder)
                var mutableProject = project   // extraction may rewrite `file`

                let id = UUID()
                var folderPath: String
                var isReferenced: Bool
                if copyIntoStore {
                    let destName = workshopID ?? id.uuidString
                    let dest = AppPaths.wallpapersRoot.appendingPathComponent(destName, isDirectory: true)
                    do {
                        if fm.fileExists(atPath: dest.path) {
                            try fm.removeItem(at: dest)
                        }
                        try fm.copyItem(at: folder, to: dest)
                    } catch {
                        skipped.append("\(project.title)：复制失败（\(error.localizedDescription)）")
                        continue
                    }
                    folderPath = destName
                    isReferenced = false
                } else {
                    folderPath = folder.path
                    isReferenced = true
                }

                // Scene wallpaper: try to reduce it to a static main image so the
                // image pipeline can render it. On failure it stays unsupported.
                if kind == .sceneUnsupported {
                    let resolvedFolder = isReferenced
                        ? URL(fileURLWithPath: folderPath)
                        : AppPaths.wallpapersRoot.appendingPathComponent(folderPath, isDirectory: true)
                    if let extracted = try? ScenePkgExtractor.extract(folder: resolvedFolder) {
                        mutableProject.file = extracted
                        kind = .image
                        reason = nil
                    } else {
                        reason = "场景提取失败（未能解出主图）"
                    }
                }

                imported.append(WallpaperItem(
                    id: id,
                    workshopID: workshopID,
                    folderPath: folderPath,
                    isReferenced: isReferenced,
                    project: mutableProject,
                    kind: kind,
                    unsupportedReason: reason,
                    propertyValues: [:],
                    addedDate: Date()
                ))
                if let wid = workshopID { seenWorkshop.insert(wid) }
            }
        }

        return Result(imported: imported, skipped: skipped)
    }

    // MARK: - Classification

    static func classify(project: WEProject, folder: URL) -> (WallpaperKind, String?) {
        switch project.type {
        case "video":
            if let file = project.file {
                let ext = (file as NSString).pathExtension.lowercased()
                if ext == "webm" {
                    return (.video, "webm/VP9 视频 AVPlayer 无法播放（可在设置中用 ffmpeg 转码）")
                }
            }
            return (.video, nil)
        case "web":
            return (.web, nil)
        case "image":
            return (.image, nil)
        case "scene":
            // A scene may be just an image behind the scenes; the extractor
            // (V2-M2) upgrades these to `.image` when it can pull a main image.
            return (.sceneUnsupported, "场景类型（scene.pkg）——可尝试提取为静态图片")
        default:
            // Extension fallback: many local/third-party items have an empty or
            // unknown type but point `file` straight at an image.
            if let file = project.file, isImageExtension(file) {
                return (.image, nil)
            }
            return (.other, "未知或不支持的壁纸类型：\(project.type.isEmpty ? "空" : project.type)")
        }
    }

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "tiff"]

    static func isImageExtension(_ file: String) -> Bool {
        imageExtensions.contains((file as NSString).pathExtension.lowercased())
    }

    /// Copy a bare image into a new store folder and synthesize a wallpaper +
    /// a WE-format `project.json` so re-scans stay uniform.
    private static func makeBareImageItem(source: URL) -> WallpaperItem? {
        let id = UUID()
        let dest = AppPaths.wallpapersRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        let fileName = source.lastPathComponent
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: dest.appendingPathComponent(fileName))
        } catch { return nil }

        let title = source.deletingPathExtension().lastPathComponent
        let jsonDict: [String: String] = ["title": title, "type": "image", "file": fileName, "preview": fileName]
        if let data = try? JSONSerialization.data(withJSONObject: jsonDict, options: [.prettyPrinted]) {
            try? data.write(to: dest.appendingPathComponent("project.json"))
        }
        let project = WEProject(title: title, type: "image", file: fileName,
                                preview: fileName, descriptionText: nil, tags: [], properties: [])
        return WallpaperItem(
            id: id, workshopID: nil, folderPath: id.uuidString, isReferenced: false,
            project: project, kind: .image, unsupportedReason: nil,
            propertyValues: [:], addedDate: Date()
        )
    }

    /// WE workshop layout puts wallpapers under `.../content/431960/<id>/`.
    /// Use the numeric folder name as the workshop id when it looks like one.
    static func workshopID(from folder: URL) -> String? {
        let name = folder.lastPathComponent
        if !name.isEmpty, name.allSatisfy(\.isNumber) { return name }
        return nil
    }
}
