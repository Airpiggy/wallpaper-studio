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
        screenTracker = ScreenTracker { [weak self] in self?.desktop.reconcile() }
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
        var map: [String: WallpaperItem] = [:]
        for (uuid, idString) in settings.assignments {
            guard let id = UUID(uuidString: idString), let item = library.item(id: id) else { continue }
            map[uuid] = item
        }
        desktop.restore(assignments: map)
        policy.hasWallpaper = desktop.hasWallpaper
    }

    // MARK: - Apply

    func apply(_ item: WallpaperItem, to target: DisplayTarget = .all) {
        guard item.kind.isSupported else {
            lastError = item.unsupportedReason ?? "该壁纸暂不支持"
            return
        }
        let effectiveTarget: DisplayTarget = settings.sameOnAllDisplays ? .all : target
        if let error = desktop.setWallpaper(item, to: effectiveTarget) {
            lastError = error
            return
        }
        // Persist assignment(s).
        let uuids: [String]
        switch effectiveTarget {
        case .all: uuids = NSScreen.screens.compactMap(DesktopWindowController.displayUUID)
        case .display(let u): uuids = [u]
        }
        settings.assignToAll(itemID: item.id, displayUUIDs: uuids)
        policy.userPaused = false
        policy.hasWallpaper = desktop.hasWallpaper
        lastError = nil
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
