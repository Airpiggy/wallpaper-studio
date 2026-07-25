import AppKit
import WebKit

/// Renders an HTML/JS Wallpaper Engine "web" wallpaper in a `WKWebView`, with a
/// shim that provides the `window.wallpaper*` APIs and bridges user properties.
@MainActor
final class WebRenderer: NSObject, WallpaperRenderer {
    let view: NSView

    private let webView: WKWebView
    private let htmlURL: URL
    private let folderURL: URL
    private let properties: [WEProperty]
    private var currentValues: [String: JSONValue]
    private var didFinishInitialLoad = false
    /// After this long paused, fully unload the page to free WebGL/DOM memory.
    private let unloadAfterPause: TimeInterval = 300
    private var unloadWork: DispatchWorkItem?
    private var isUnloaded = false

    init(htmlURL: URL, folderURL: URL, properties: [WEProperty], initialValues: [String: JSONValue]) {
        self.htmlURL = htmlURL
        self.folderURL = folderURL
        self.properties = properties
        self.currentValues = initialValues

        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = false
        // Allow file:// wallpapers to fetch sibling assets via XHR/fetch.
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        // Inject the WE API shim at document start.
        if let shimURL = Bundle.main.url(forResource: "WEShim", withExtension: "js"),
           let shim = try? String(contentsOf: shimURL, encoding: .utf8) {
            let script = WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            config.userContentController.addUserScript(script)
        }

        webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // transparent behind content
        webView.autoresizingMask = [.width, .height]
        view = webView

        super.init()
        webView.navigationDelegate = self
    }

    func start() {
        webView.loadFileURL(htmlURL, allowingReadAccessTo: folderURL)
    }

    func pause() {
        // Ask the wallpaper to pause if it implements WE's convention.
        webView.evaluateJavaScript(
            "window.wallpaperPropertyListener && window.wallpaperPropertyListener.setPaused && window.wallpaperPropertyListener.setPaused(true);",
            completionHandler: nil
        )
        // Schedule a full unload if we stay paused long enough (memory guard).
        unloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.unload() }
        unloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + unloadAfterPause, execute: work)
    }

    func resume() {
        unloadWork?.cancel()
        unloadWork = nil
        if isUnloaded {
            isUnloaded = false
            didFinishInitialLoad = false
            webView.loadFileURL(htmlURL, allowingReadAccessTo: folderURL)
            return
        }
        webView.evaluateJavaScript(
            "window.wallpaperPropertyListener && window.wallpaperPropertyListener.setPaused && window.wallpaperPropertyListener.setPaused(false);",
            completionHandler: nil
        )
    }

    private func unload() {
        guard !isUnloaded else { return }
        isUnloaded = true
        didFinishInitialLoad = false
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    /// Push changed properties to the wallpaper (matches WE: only changed keys).
    func apply(properties values: [String: JSONValue]) {
        var changed: [String: JSONValue] = [:]
        for (k, v) in values where currentValues[k] != v {
            changed[k] = v
            currentValues[k] = v
        }
        guard !changed.isEmpty, didFinishInitialLoad else { return }
        push(values: changed)
    }

    func tearDown() {
        unloadWork?.cancel()
        unloadWork = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
        webView.removeFromSuperview()
    }

    // MARK: - Property bridge

    /// Build WE's `applyUserProperties` payload: `{ key: { value: <v> }, ... }`.
    private func push(values: [String: JSONValue]) {
        var payload: [String: [String: JSONValue]] = [:]
        for (key, value) in values {
            payload[key] = ["value": weEncoded(value, key: key)]
        }
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else { return }
        let js = "if (window.wallpaperPropertyListener && window.wallpaperPropertyListener.applyUserProperties) { window.wallpaperPropertyListener.applyUserProperties(\(json)); }"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Colors are delivered to WE web wallpapers as "r g b" normalized strings.
    private func weEncoded(_ value: JSONValue, key: String) -> JSONValue {
        if let prop = properties.first(where: { $0.key == key }), prop.kind == .color {
            if case .string = value { return value }         // already "r g b"
        }
        return value
    }
}

extension WebRenderer: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinishInitialLoad = true
        // On load, WE pushes ALL current property values.
        push(values: currentValues)
    }
}
