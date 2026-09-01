import AppKit

/// Why playback is currently paused (nil = playing).
enum PauseReason: Equatable {
    case userPaused
    case fullscreenApp
    case lowBattery
    case displayAsleep
    case noWallpaper

    var message: String {
        switch self {
        case .userPaused: return "已手动暂停"
        case .fullscreenApp: return "已暂停 — 全屏应用"
        case .lowBattery: return "已暂停 — 电量低"
        case .displayAsleep: return "已暂停 — 显示器休眠"
        case .noWallpaper: return "未应用壁纸"
        }
    }
}

/// Aggregates power / fullscreen / sleep / user signals into a single play-or-pause
/// decision and drives the desktop controller accordingly. Also holds a
/// `ProcessInfo` activity token while playing to keep App Nap from freezing us.
@MainActor
final class PlaybackPolicyController: ObservableObject {
    @Published private(set) var pauseReason: PauseReason?

    var userPaused = false { didSet { evaluate() } }
    /// Set by AppState: is any wallpaper currently applied?
    var hasWallpaper = false { didSet { evaluate() } }

    private let desktop: DesktopWindowController
    private let settings: AppSettings
    private let power = PowerMonitor()
    private let fullscreen = FullscreenDetector()
    private var displayAsleep = false
    private var activityToken: NSObjectProtocol?

    init(desktop: DesktopWindowController, settings: AppSettings) {
        self.desktop = desktop
        self.settings = settings
    }

    func start() {
        power.onChange = { [weak self] in self?.evaluate() }
        fullscreen.onChange = { [weak self] in self?.evaluate() }
        power.start()
        fullscreen.start()

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(screensSlept), name: NSWorkspace.screensDidSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(screensWoke), name: NSWorkspace.screensDidWakeNotification, object: nil)
        // System wake is a separate notification from screen wake. Observing
        // only the latter risks staying pinned to .displayAsleep forever if it
        // is missed during a run of dark wakes.
        nc.addObserver(self, selector: #selector(systemWoke), name: NSWorkspace.didWakeNotification, object: nil)
        evaluate()
    }

    func stop() {
        power.stop()
        fullscreen.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        endActivity()
    }

    /// Re-evaluate when settings toggles change.
    func settingsChanged() { evaluate() }

    @objc private func screensSlept() {
        WallpaperLog.policy.notice("screens slept")
        displayAsleep = true
        evaluate()
    }

    @objc private func screensWoke() {
        WallpaperLog.policy.notice("screens woke")
        displayAsleep = false
        evaluate()
    }

    @objc private func systemWoke() {
        WallpaperLog.policy.notice("system woke")
        displayAsleep = false
        evaluate()
        // Screen state can still be settling right after wake; re-check once it has.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.evaluate()
        }
    }

    // MARK: - Decision

    private func computeReason() -> PauseReason? {
        guard hasWallpaper else { return .noWallpaper }
        if userPaused { return .userPaused }
        if displayAsleep { return .displayAsleep }
        if settings.pauseOnFullscreen && fullscreen.isFullscreenActive { return .fullscreenApp }
        if settings.pauseOnBattery && power.onBattery {
            let low = power.isLowPowerMode || (power.batteryPercent ?? 100) <= settings.batteryThreshold
            if low { return .lowBattery }
        }
        return nil
    }

    private func evaluate() {
        let reason = computeReason()
        let shouldPlay = (reason == nil)

        if shouldPlay {
            desktop.resumeAll()
            beginActivity()
        } else {
            desktop.pauseAll()
            endActivity()
        }
        if reason != pauseReason {
            WallpaperLog.policy.notice(
                "pause reason: \(String(describing: self.pauseReason), privacy: .public) -> \(String(describing: reason), privacy: .public)"
            )
            pauseReason = reason
        }
    }

    // MARK: - App Nap

    private func beginActivity() {
        guard activityToken == nil else { return }
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: "Rendering live wallpaper"
        )
    }

    private func endActivity() {
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }
}
