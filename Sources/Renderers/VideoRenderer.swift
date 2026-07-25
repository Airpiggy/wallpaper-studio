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
    private let item: AVPlayerItem

    init(url: URL, muted: Bool = true) {
        let asset = AVURLAsset(url: url)
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
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        playerView.playerLayer.player = nil
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
