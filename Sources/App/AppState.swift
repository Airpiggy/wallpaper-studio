import AppKit
import Combine
import UniformTypeIdentifiers

/// Central app-wide state. Owns the desktop controller, library, settings, and
/// the playback-policy controller, and exposes high-level actions to the UI.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let desktop = DesktopWindowController()
    let library = WallpaperLibrary()
    let settings = AppSettings()
    let policy: PlaybackPolicyController
    private var screenTracker: ScreenTracker!

    @Published var lastError: String?
    /// Bumped whenever display configuration or per-display assignment changes,
    /// so the display-strip UI refreshes.
    @Published var displaysVersion = 0
    /// The display currently selected in the strip (independent mode target).
    @Published var selectedDisplayUUID: String?

    private var cancellables: Set<AnyCancellable> = []

    /// The item shown on the main screen (for menu/status display).
    var currentItemID: UUID? {
        guard let main = NSScreen.main, let uuid = DesktopWindowController.displayUUID(for: main) else {
            return desktop.assignments.values.first?.id
        }
        return desktop.assignments[uuid]?.id
    }
    var currentWallpaperName: String? {
        currentItemID.flatMap { id in desktop.assignments.values.first { $0.id == id }?.project.title }
    }
    var isPaused: Bool { policy.pauseReason == .userPaused }

    /// True if `id` is the wallpaper on any connected display.
    func isApplied(_ id: UUID) -> Bool {
        desktop.assignments.values.contains { $0.id == id }
    }

    private init() {
        policy = PlaybackPolicyController(desktop: desktop, settings: settings)
        desktop.storeRoot = library.storeRoot

        // Re-publish nested changes so views refresh.
        for obj in [library.objectWillChange, settings.objectWillChange, policy.objectWillChange] {
            obj.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }
    }

    // MARK: - Lifecycle

    func onLaunch() {
        NSApp.setActivationPolicy(settings.hideDockIcon ? .accessory : .regular)
        screenTracker = ScreenTracker { [weak self] in self?.handleScreenChange() }
        screenTracker.start()
        policy.start()
        restoreAssignments()
    }

    func onTerminate() {
        policy.stop()
        screenTracker?.stop()
        desktop.tearDown()
    }

    /// Rebuild desktop windows from persisted per-display assignments.
    private func restoreAssignments() {
        desktop.muteVideo = settings.muteVideo
        desktop.videoMemoryCacheLimitMB = settings.videoMemoryCacheLimitMB
        var map: [String: WallpaperItem] = [:]
        for (uuid, idString) in settings.assignments {
            guard let id = UUID(uuidString: idString), let item = library.item(id: id) else { continue }
            map[uuid] = item
        }
        desktop.restore(assignments: map)
        // Extend the current wallpaper onto any display connected now but not in
        // the persisted map (e.g. booted with a new external display attached).
        handleScreenChange()
    }

    /// React to a display connect/disconnect/rearrange: reconcile existing
    /// windows, then auto-apply the current wallpaper to displays that need it.
    func handleScreenChange() {
        desktop.reconcile()

        let connected = NSScreen.screens.compactMap(DesktopWindowController.displayUUID)
        var assignmentIDs: [String: UUID] = [:]
        for (uuid, idString) in settings.assignments {
            if let id = UUID(uuidString: idString) { assignmentIDs[uuid] = id }
        }
        let targetID = currentItemID
        let needing = Self.displaysNeedingAssignment(
            connected: connected, assignments: assignmentIDs,
            currentItemID: targetID, sameOnAllDisplays: settings.sameOnAllDisplays
        )
        if let id = targetID, let item = library.item(id: id) {
            for uuid in needing {
                desktop.setWallpaper(item, to: .display(uuid))
                settings.assign(itemID: id, to: uuid)
            }
        }
        policy.hasWallpaper = desktop.hasWallpaper
        displaysVersion &+= 1
    }

    /// Pure decision: which connected displays should receive the current
    /// wallpaper. Sync mode → any display not already showing it; independent
    /// mode → only displays with no assignment at all (fall back to main's).
    static func displaysNeedingAssignment(
        connected: [String],
        assignments: [String: UUID],
        currentItemID: UUID?,
        sameOnAllDisplays: Bool
    ) -> [String] {
        guard let current = currentItemID else { return [] }
        if sameOnAllDisplays {
            return connected.filter { assignments[$0] != current }
        } else {
            return connected.filter { assignments[$0] == nil }
        }
    }

    // MARK: - Apply

    func apply(_ item: WallpaperItem, to target: DisplayTarget = .all) {
        guard item.kind.isSupported else {
            lastError = item.unsupportedReason ?? "该壁纸暂不支持"
            return
        }
        // The target drives the mode: applying to all → sync; to one → independent.
        switch target {
        case .all: settings.sameOnAllDisplays = true
        case .display: settings.sameOnAllDisplays = false
        }
        if let error = desktop.setWallpaper(item, to: target) {
            lastError = error
            return
        }
        // Persist assignment(s).
        let uuids: [String]
        switch target {
        case .all: uuids = NSScreen.screens.compactMap(DesktopWindowController.displayUUID)
        case .display(let u): uuids = [u]
        }
        settings.assignToAll(itemID: item.id, displayUUIDs: uuids)
        policy.userPaused = false
        policy.hasWallpaper = desktop.hasWallpaper
        displaysVersion &+= 1
        lastError = nil
    }

    /// Apply honoring the current mode + strip selection (used by double-click /
    /// the Apply button). Sync → all displays; independent → selected (or main).
    func applyToCurrentTarget(_ item: WallpaperItem) {
        if settings.sameOnAllDisplays {
            apply(item, to: .all)
        } else if let uuid = selectedDisplayUUID
            ?? NSScreen.main.flatMap(DesktopWindowController.displayUUID) {
            apply(item, to: .display(uuid))
        } else {
            apply(item, to: .all)
        }
    }

    /// Switch between sync and independent display modes.
    func setSameOnAllDisplays(_ sync: Bool) {
        guard sync != settings.sameOnAllDisplays else { return }
        if sync {
            // Unify the selected (or main) display's wallpaper across all displays.
            let uuid = selectedDisplayUUID ?? NSScreen.main.flatMap(DesktopWindowController.displayUUID)
            let item = (uuid.flatMap { desktop.assignments[$0] } ?? currentItemID.flatMap(library.item(id:)))
                .flatMap { library.item(id: $0.id) }
            settings.sameOnAllDisplays = true
            selectedDisplayUUID = nil
            if let item { apply(item, to: .all) } else { displaysVersion &+= 1 }
        } else {
            settings.sameOnAllDisplays = false
            selectedDisplayUUID = NSScreen.main.flatMap(DesktopWindowController.displayUUID)
            displaysVersion &+= 1
        }
    }

    /// Per-display info for the strip UI.
    struct DisplayInfo: Identifiable {
        let id: String            // display UUID
        let name: String
        let aspect: CGFloat       // width / height
        let assignedItem: WallpaperItem?
        let isMain: Bool
    }

    var displayInfos: [AppState.DisplayInfo] {
        let mainUUID = NSScreen.main.flatMap(DesktopWindowController.displayUUID)
        return NSScreen.screens
            .sorted { $0.frame.minX < $1.frame.minX }
            .compactMap { screen -> AppState.DisplayInfo? in
                guard let uuid = DesktopWindowController.displayUUID(for: screen) else { return nil }
                let snapshot = desktop.assignments[uuid]
                let item = snapshot.flatMap { library.item(id: $0.id) } ?? snapshot
                let aspect = screen.frame.height > 0 ? screen.frame.width / screen.frame.height : 16.0 / 9.0
                return AppState.DisplayInfo(
                    id: uuid, name: screen.localizedName, aspect: aspect,
                    assignedItem: item, isMain: uuid == mainUUID
                )
            }
    }

    func applyPropertyValues(_ values: [String: JSONValue], for itemID: UUID) {
        library.updatePropertyValues(values, for: itemID)
        guard let item = library.item(id: itemID) else { return }
        // Re-apply to any display currently showing this item.
        for (uuid, assigned) in desktop.assignments where assigned.id == itemID {
            desktop.setWallpaper(item, to: .display(uuid))
        }
    }

    /// Debug/sample: apply the bundled sample video via a transient item.
    func applySampleWallpaper() {
        guard let url = Bundle.main.url(
            forResource: "sample", withExtension: "mp4", subdirectory: "Fixtures/SampleVideo"
        ) ?? Bundle.main.url(forResource: "sample", withExtension: "mp4") else {
            lastError = "找不到示例视频"
            return
        }
        let project = WEProject(title: "示例视频", type: "video", file: "sample.mp4",
                                preview: nil, descriptionText: nil, tags: [], properties: [])
        let item = WallpaperItem(
            id: UUID(), workshopID: nil, folderPath: url.deletingLastPathComponent().path,
            isReferenced: true, project: project, kind: .video, unsupportedReason: nil,
            propertyValues: [:], addedDate: Date()
        )
        apply(item)
    }

    func clearWallpaper() {
        desktop.clear()
        settings.clearAssignments()
        policy.hasWallpaper = false
    }

    func togglePause() {
        policy.userPaused.toggle()
    }

    // MARK: - Import

    func importWallpapers(copyIntoStore: Bool = true) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "导入"
        panel.message = "选择壁纸文件夹、整个 431960 创意工坊目录，或直接选图片文件"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { await library.importFrom(urls: urls, copyIntoStore: copyIntoStore) }
    }

    // MARK: - Settings actions

    func setHideDockIcon(_ hide: Bool) {
        settings.hideDockIcon = hide
        NSApp.setActivationPolicy(hide ? .accessory : .regular)
        if !hide { NSApp.activate(ignoringOtherApps: true) }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        LoginItemManager.setEnabled(enabled)
    }

    /// Change the video memory-cache threshold and rebuild live video wallpapers
    /// so the new setting takes effect immediately.
    func setVideoMemoryCacheLimit(_ limitMB: Int) {
        guard limitMB != settings.videoMemoryCacheLimitMB else { return }
        settings.videoMemoryCacheLimitMB = limitMB
        desktop.videoMemoryCacheLimitMB = limitMB
        desktop.rebuildRenderers()
    }

    // MARK: - Debug hooks

    func debugImportAndApplyBundledWeb() {
        guard let fixtures = Bundle.main.resourceURL?.appendingPathComponent("Fixtures/SampleWeb") else {
            lastError = "找不到内置网页壁纸 fixture"; return
        }
        Task {
            await library.importFrom(urls: [fixtures], copyIntoStore: true)
            if let webItem = library.items.first(where: { $0.kind == .web }) {
                apply(webItem)
                NSLog("WPS_TESTWEB applied: \(webItem.project.title), error=\(lastError ?? "none")")
            }
        }
    }
}
