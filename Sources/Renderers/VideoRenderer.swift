import AppKit
import AVFoundation

/// Renders a looping video wallpaper with `AVQueuePlayer` + `AVPlayerLooper`
/// for gapless looping, drawn into an `AVPlayerLayer`.
@MainActor
final class VideoRenderer: WallpaperRenderer {
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
    private var didFallBackToDisk = false

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
    }

    /// If memory-backed playback ever fails (e.g. a future OS changes resource
    /// loader behavior), rebuild the pipeline straight off disk exactly once.
    private func observeFailures() {
        guard memoryAsset != nil else { return }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fallBackToDisk() }
        }
    }

    private func fallBackToDisk() {
        guard !didFallBackToDisk, memoryAsset != nil else { return }
        didFallBackToDisk = true
        NSLog("VideoRenderer: memory-backed playback failed, falling back to disk for \(url.lastPathComponent)")

        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        memoryAsset = nil

        item = AVPlayerItem(asset: AVURLAsset(url: url))
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.play()
    }

    func start() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func resume() {
        player.play()
    }

    func setMuted(_ muted: Bool) {
        player.isMuted = muted
    }

    func tearDown() {
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
            self.failureObserver = nil
        }
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        playerView.playerLayer.player = nil
        // Drop the mapping; the registry holds it weakly, so this frees it once
        // no other display is showing the same wallpaper.
        memoryAsset = nil
    }
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
