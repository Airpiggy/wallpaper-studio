import AppKit
import AVFoundation

/// Renders a looping video wallpaper with `AVQueuePlayer` + `AVPlayerLooper`
/// for gapless looping, drawn into an `AVPlayerLayer`.
///
/// Playback is supervised by a watchdog. Sleeping the Mac can leave the
/// AVFoundation pipeline wedged — it stops advancing without ever reporting an
/// error, so `play()` alone will not revive it and the desktop keeps showing a
/// frozen frame. The watchdog notices the lack of progress and escalates through
/// `RecoveryAction` until playback resumes.
@MainActor
final class VideoRenderer: WallpaperRenderer {

    /// What to do about a wedged player, in escalating order of disruption.
    enum RecoveryAction: Equatable {
        /// Nudge the existing pipeline: seek where we already are, play again.
        case kick
        /// Throw the pipeline away and build a new one. `fromDisk` abandons the
        /// memory-mapped source, ruling out the custom resource loader.
        case rebuild(fromDisk: Bool)
        /// Nothing left to try; stop churning and leave a log entry.
        case giveUp
    }

    let view: NSView

    private let playerView: PlayerLayerView
    private let player: AVQueuePlayer
    private var looper: AVPlayerLooper?
    private var item: AVPlayerItem
    private let url: URL
    private let muted: Bool

    /// Strong reference to the memory-backed source, if in use. The resource
    /// loader holds its delegate weakly, so this must outlive the asset.
    private var memoryAsset: MemoryVideoAsset?
    private var failureObserver: NSObjectProtocol?
    private var wakeObservers: [NSObjectProtocol] = []

    // MARK: Watchdog state

    /// Fires only while playback actually advances, so a stale timestamp means
    /// the pipeline is wedged. Sampling `currentTime` directly would alias: a
    /// looping clip can land on the same position every time it is polled.
    private var heartbeatObserver: Any?
    private var lastHeartbeat = Date()
    private var watchdog: Timer?
    /// Whether the policy layer currently wants this playing. The watchdog must
    /// never fire while we are deliberately paused.
    private var wantsPlayback = false
    private var recoveryAttempt = 0
    private var healthyChecks = 0
    private var pendingWakeCheck: DispatchWorkItem?

    private static let heartbeatInterval: TimeInterval = 1
    private static let watchdogInterval: TimeInterval = 5
    /// No progress for this long while playback is wanted means wedged. Well
    /// clear of the heartbeat interval so ordinary scheduling jitter is not read
    /// as a stall.
    static let stallTolerance: TimeInterval = 8
    /// Consecutive healthy checks before the ladder resets — 60s of real
    /// playback, so a recovered player starts from `kick` again next time.
    static let healthyChecksToReset = 12

    /// - Parameter memoryCacheLimitBytes: play files up to this size from a
    ///   memory mapping instead of streaming them off disk on every loop.
    ///   Pass 0 to always use the disk-backed path.
    init(url: URL, muted: Bool = true, memoryCacheLimitBytes: Int64 = 0) {
        self.url = url
        self.muted = muted

        let asset: AVAsset
        if let memory = MemoryVideoAssetRegistry.shared.asset(for: url, maxBytes: memoryCacheLimitBytes) {
            memoryAsset = memory
            asset = memory.makeAsset()
        } else {
            asset = AVURLAsset(url: url)
        }

        item = AVPlayerItem(asset: asset)
        player = AVQueuePlayer()
        player.isMuted = muted
        // A wallpaper must never keep the display awake.
        player.preventsDisplaySleepDuringVideoPlayback = false
        // Avoid audio-session side effects; wallpapers are silent by default.
        player.automaticallyWaitsToMinimizeStalling = false

        looper = AVPlayerLooper(player: player, templateItem: item)

        playerView = PlayerLayerView(player: player)
        view = playerView

        observeFailures()
        observeHeartbeat()
        observeWake()
    }

    // MARK: - Playback

    func start() {
        wantsPlayback = true
        beat()
        player.play()
        startWatchdog()
    }

    func pause() {
        wantsPlayback = false
        stopWatchdog()
        player.pause()
    }

    func resume() {
        wantsPlayback = true
        beat()
        player.play()
        startWatchdog()
    }

    func setMuted(_ muted: Bool) {
        player.isMuted = muted
    }

    func tearDown() {
        wantsPlayback = false
        stopWatchdog()
        pendingWakeCheck?.cancel()
        pendingWakeCheck = nil

        if let heartbeatObserver {
            player.removeTimeObserver(heartbeatObserver)
            self.heartbeatObserver = nil
        }
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
            self.failureObserver = nil
        }
        for observer in wakeObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        wakeObservers.removeAll()

        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        playerView.playerLayer.player = nil
        // Drop the mapping; the registry holds it weakly, so this frees it once
        // no other display is showing the same wallpaper.
        memoryAsset = nil
    }

    // MARK: - Watchdog

    /// Mark playback as having just made progress.
    private func beat() {
        lastHeartbeat = Date()
    }

    private func observeHeartbeat() {
        let interval = CMTime(seconds: Self.heartbeatInterval, preferredTimescale: 600)
        heartbeatObserver = player.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.lastHeartbeat = Date()
                self?.noteHealthyProgress()
            }
        }
    }

    private func startWatchdog() {
        guard watchdog == nil else { return }
        let timer = Timer(timeInterval: Self.watchdogInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForStall() }
        }
        // .common so the check keeps running while menus are being tracked.
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func stopWatchdog() {
        watchdog?.invalidate()
        watchdog = nil
    }

    /// True when playback is wanted but has not advanced within `tolerance`.
    static func isStalled(
        lastHeartbeat: Date, now: Date, wantsPlayback: Bool,
        tolerance: TimeInterval = VideoRenderer.stallTolerance
    ) -> Bool {
        guard wantsPlayback else { return false }
        return now.timeIntervalSince(lastHeartbeat) > tolerance
    }

    /// The escalation ladder. `usingMemory` gates the disk-rebuild rung: with no
    /// memory-mapped source there is no different source left to try.
    static func recoveryAction(forAttempt attempt: Int, usingMemory: Bool) -> RecoveryAction {
        switch attempt {
        case 0: return .kick
        case 1: return .rebuild(fromDisk: false)
        case 2: return usingMemory ? .rebuild(fromDisk: true) : .giveUp
        default: return .giveUp
        }
    }

    private func noteHealthyProgress() {
        guard recoveryAttempt > 0 else { return }
        healthyChecks += 1
        if healthyChecks >= Self.healthyChecksToReset {
            WallpaperLog.video.notice(
                "playback healthy again, resetting recovery ladder for \(self.url.lastPathComponent, privacy: .public)"
            )
            recoveryAttempt = 0
            healthyChecks = 0
        }
    }

    private func checkForStall() {
        guard Self.isStalled(
            lastHeartbeat: lastHeartbeat, now: Date(), wantsPlayback: wantsPlayback
        ) else { return }

        let action = Self.recoveryAction(
            forAttempt: recoveryAttempt, usingMemory: memoryAsset != nil
        )
        let stalledFor = Date().timeIntervalSince(lastHeartbeat)
        let position = player.currentTime().seconds
        WallpaperLog.video.error(
            """
            playback stalled \(stalledFor, format: .fixed(precision: 1))s for \
            \(self.url.lastPathComponent, privacy: .public) — attempt \
            \(self.recoveryAttempt), action \(String(describing: action), privacy: .public), \
            position \(position, format: .fixed(precision: 2))s, rate \(self.player.rate), \
            timeControl \(self.player.timeControlStatus.rawValue), \
            itemStatus \(self.item.status.rawValue)
            """
        )

        recoveryAttempt += 1
        healthyChecks = 0

        switch action {
        case .kick:
            beat()
            player.seek(to: player.currentTime())
            player.play()
        case .rebuild(let fromDisk):
            rebuildPipeline(fromDisk: fromDisk)
        case .giveUp:
            // Stop checking: further rebuilds would only churn. A later
            // start()/resume() from the policy layer restarts supervision.
            stopWatchdog()
            WallpaperLog.video.fault(
                "giving up on \(self.url.lastPathComponent, privacy: .public); re-apply the wallpaper to retry"
            )
        }
    }

    /// Replace the player's item and looper with a fresh pipeline.
    /// - Parameter fromDisk: abandon the memory-mapped source and read the file
    ///   directly, ruling out the custom resource loader as the cause.
    private func rebuildPipeline(fromDisk: Bool) {
        if fromDisk, memoryAsset != nil {
            WallpaperLog.video.notice(
                "abandoning memory-backed playback for \(self.url.lastPathComponent, privacy: .public)"
            )
            memoryAsset = nil
        }

        looper?.disableLooping()
        looper = nil
        player.removeAllItems()

        let asset: AVAsset = memoryAsset?.makeAsset() ?? AVURLAsset(url: url)
        item = AVPlayerItem(asset: asset)
        looper = AVPlayerLooper(player: player, templateItem: item)

        beat()
        player.play()
        if wantsPlayback { startWatchdog() }
    }

    // MARK: - Failure and wake signals

    /// A hard playback failure is a faster signal than the watchdog's timeout,
    /// so jump straight to rebuilding.
    private func observeFailures() {
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self else { return }
                // The notification is posted for every player in the process;
                // only act on our own item, or two displays showing the same
                // wallpaper would tear each other down.
                guard let failed = note.object as? AVPlayerItem, failed === self.item else { return }
                WallpaperLog.video.error(
                    "item failed to play to end for \(self.url.lastPathComponent, privacy: .public)"
                )
                self.recoveryAttempt = max(self.recoveryAttempt, 1)
                self.rebuildPipeline(fromDisk: false)
            }
        }
    }

    /// Waking is when the pipeline is most likely to come back wedged, so check
    /// promptly instead of waiting out the next watchdog tick.
    private func observeWake() {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            let observer = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleWakeCheck() }
            }
            wakeObservers.append(observer)
        }
    }

    private func scheduleWakeCheck() {
        guard wantsPlayback else { return }
        pendingWakeCheck?.cancel()
        // Give the pipeline a moment to come back on its own before judging it.
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.checkForStall() }
        }
        pendingWakeCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stallTolerance + 2, execute: work)
    }

    // MARK: - Test hooks

    var lastHeartbeatForTesting: Date { lastHeartbeat }
    var recoveryAttemptForTesting: Int { recoveryAttempt }
    var isSupervisingForTesting: Bool { watchdog != nil }
    var usesMemoryAssetForTesting: Bool { memoryAsset != nil }

    func rebuildForTesting(fromDisk: Bool) { rebuildPipeline(fromDisk: fromDisk) }

    /// Reproduce the wedged state seen after sleep: the player stops advancing
    /// while the policy layer still believes it is playing. Pausing the player
    /// directly (rather than via `pause()`) leaves `wantsPlayback` set, which is
    /// exactly the condition the watchdog exists to catch.
    func simulateStallForTesting() {
        player.pause()
        lastHeartbeat = Date(timeIntervalSinceNow: -(Self.stallTolerance + 1))
    }

    func checkForStallForTesting() { checkForStall() }
}

/// A layer-backed NSView whose backing layer is an `AVPlayerLayer`.
private final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()

    init(player: AVPlayer) {
        super.init(frame: .zero)
        wantsLayer = true
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = NSColor.black.cgColor
        layer = playerLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
