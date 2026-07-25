import AppKit

/// Renders a static image (or animated GIF) wallpaper, aspect-filled to the
/// screen. Used both for genuine image wallpapers and for scene.pkg wallpapers
/// reduced to their extracted main image.
@MainActor
final class ImageRenderer: WallpaperRenderer {
    let view: NSView
    private let container: ImageContainerView

    init(url: URL) {
        let image = NSImage(contentsOf: url)
        container = ImageContainerView(image: image)
        view = container
    }

    func start() {
        container.imageView.animates = true
    }

    func pause() {
        // Stop GIF timers while hidden by fullscreen / power policy.
        container.imageView.animates = false
    }

    func resume() {
        container.imageView.animates = true
    }

    func tearDown() {
        container.imageView.animates = false
        container.imageView.image = nil
    }
}

/// A black, layer-backed container that aspect-fills an inner NSImageView.
private final class ImageContainerView: NSView {
    let imageView = NSImageView()
    private let image: NSImage?

    init(image: NSImage?) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true

        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently  // we compute the frame ourselves
        imageView.animates = true
        imageView.wantsLayer = true
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func layout() {
        super.layout()
        guard let size = image?.size, size.width > 0, size.height > 0 else {
            imageView.frame = bounds
            return
        }
        // Aspect-fill: scale so the image covers `bounds`, then center (overflow clipped).
        let scale = max(bounds.width / size.width, bounds.height / size.height)
        let w = size.width * scale
        let h = size.height * scale
        imageView.frame = NSRect(
            x: (bounds.width - w) / 2,
            y: (bounds.height - h) / 2,
            width: w, height: h
        )
    }
}
