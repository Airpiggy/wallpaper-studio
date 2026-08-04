import AppKit

/// Which screen(s) an action targets.
enum DisplayTarget {
    case all
    case display(String) // display UUID string
}

/// Owns per-screen wallpaper windows and their renderers, driven by a map of
/// display-UUID → assigned wallpaper. `reconcile()` makes the live windows match
/// the assignments and the currently connected screens, so wallpapers survive
/// display hot-plug, resolution changes, and app relaunch.
@MainActor
final class DesktopWindowController {
    private struct Entry {
        let window: WallpaperWindow
        let renderer: WallpaperRenderer
        let itemID: UUID
    }

    /// Resolved wallpaper per display UUID.
    private(set) var assignments: [String: WallpaperItem] = [:]
    private var entries: [String: Entry] = [:]
    private var isPaused = false

    /// Root of the wallpaper store, for resolving item asset paths.
    var storeRoot: URL = AppPaths.wallpapersRoot
    /// Whether video wallpapers are muted (mirrors the user setting).
    var muteVideo = true
    /// Play videos up to this size from memory instead of re-reading them from
    /// disk on every loop (mirrors the user setting; 0 disables).
    var videoMemoryCacheLimitMB = 200

    // MARK: - Public API

    /// Assign an item to the given display(s) and reconcile. Returns an error
    /// message if the item can't be rendered.
    @discardableResult
    func setWallpaper(_ item: WallpaperItem, to target: DisplayTarget) -> String? {
        if case .failure(let reason) = RendererFactory.makeRenderer(for: item, storeRoot: storeRoot) {
            return reason.message
        }
        for uuid in displayUUIDs(for: target) {
            assignments[uuid] = item
        }
        reconcile()
        return nil
    }

    /// Restore a full set of display→item assignments (e.g. on launch).
    func restore(assignments map: [String: WallpaperItem]) {
        assignments = map
        reconcile()
    }

    /// Tear down and recreate every live renderer, keeping assignments — used
    /// when a setting that only applies at renderer construction changes.
    func rebuildRenderers() {
        for (uuid, entry) in entries {
            entry.renderer.tearDown()
            entry.window.contentView = nil
            entries.removeValue(forKey: uuid)
        }
        reconcile()
    }

    /// Remove all wallpapers.
    func clear() {
        assignments.removeAll()
        reconcile()
    }

    func pauseAll() {
        isPaused = true
        entries.values.forEach { $0.renderer.pause() }
    }

    func resumeAll() {
        isPaused = false
        entries.values.forEach { $0.renderer.resume() }
    }

    func tearDown() {
        for entry in entries.values {
            entry.renderer.tearDown()
            entry.window.orderOut(nil)
            entry.window.contentView = nil
        }
        entries.removeAll()
    }

    var hasWallpaper: Bool { !entries.isEmpty }

    /// Make live windows match `assignments` and the connected screens.
    func reconcile() {
        let active = activeScreensByUUID()

        // Remove windows for displays that are gone or no longer assigned.
        for (uuid, entry) in entries where active[uuid] == nil || assignments[uuid] == nil {
            entry.renderer.tearDown()
            entry.window.orderOut(nil)
            entry.window.contentView = nil
            entries.removeValue(forKey: uuid)
        }

        // Create/update windows for each assigned, connected display.
        for (uuid, item) in assignments {
            guard let screen = active[uuid] else { continue }
            if let existing = entries[uuid], existing.itemID == item.id {
                existing.window.setFrame(screen.frame, display: true)
                continue
            }
            guard case .success(let renderer) = RendererFactory.makeRenderer(
                for: item, storeRoot: storeRoot, muted: muteVideo,
                videoMemoryCacheLimitMB: videoMemoryCacheLimitMB
            ) else { continue }
            renderer.apply(properties: item.effectiveProperties)

            let window = entries[uuid]?.window ?? WallpaperWindow(screen: screen)
            entries[uuid]?.renderer.tearDown()
            window.setFrame(screen.frame, display: true)
            window.setContentView(renderer.view)
            window.orderFrontRegardless()

            renderer.start()
            if isPaused { renderer.pause() }
            entries[uuid] = Entry(window: window, renderer: renderer, itemID: item.id)
        }
    }

    // MARK: - Screen helpers

    private func displayUUIDs(for target: DisplayTarget) -> [String] {
        switch target {
        case .all:
            return NSScreen.screens.compactMap(Self.displayUUID)
        case .display(let uuid):
            return [uuid]
        }
    }

    /// Connected screens keyed by UUID, collapsing mirror sets to one entry.
    private func activeScreensByUUID() -> [String: NSScreen] {
        var result: [String: NSScreen] = [:]
        for screen in NSScreen.screens {
            guard let uuid = Self.displayUUID(for: screen) else { continue }
            result[uuid] = screen
        }
        return result
    }

    /// Stable UUID string for a screen, derived from its `CGDirectDisplayID`.
    static func displayUUID(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?
            .takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, cfUUID) as String
    }
}
