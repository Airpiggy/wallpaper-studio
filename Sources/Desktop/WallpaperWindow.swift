import AppKit

/// A borderless, non-interactive window pinned to the desktop layer (behind
/// desktop icons) that hosts a wallpaper renderer's view for a single screen.
final class WallpaperWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Sit at the desktop-picture layer, below the desktop-icon layer, so the
        // wallpaper renders behind icons while icons stay clickable.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        // Never steal focus / key status from real apps.
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Install a renderer's view as the full-bleed content of this window.
    func setContentView(_ view: NSView) {
        view.frame = contentLayoutRect
        view.autoresizingMask = [.width, .height]
        contentView = view
    }
}
