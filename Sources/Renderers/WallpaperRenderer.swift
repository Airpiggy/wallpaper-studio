import AppKit

/// A renderer produces the visual content for one wallpaper on one screen.
/// Concrete implementations: `VideoRenderer` (AVPlayer), `WebRenderer` (WKWebView),
/// and — in a future milestone — a scene renderer for WE `scene.pkg` wallpapers.
@MainActor
protocol WallpaperRenderer: AnyObject {
    /// The view to embed in a `WallpaperWindow`. Should be layer-backed and
    /// resize to fill its superview.
    var view: NSView { get }

    /// Begin playback / loading.
    func start()

    /// Pause playback to save power (must be cheap and reversible).
    func pause()

    /// Resume from a paused state.
    func resume()

    /// Apply user-customizable properties (WE `general.properties`). Renderers
    /// that don't support properties can no-op.
    func apply(properties: [String: JSONValue])

    /// Release all resources. The renderer is unusable afterward.
    func tearDown()
}

extension WallpaperRenderer {
    func apply(properties: [String: JSONValue]) {}
}
