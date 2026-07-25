import AppKit

/// Detects whether another app currently occupies a display fullscreen, so the
/// wallpaper can pause. Uses a dual signal: NSWorkspace space/activation
/// notifications trigger a `CGWindowListCopyWindowInfo` scan that looks for a
/// non-self window covering a full display. (Window bounds/PID are available
/// without Screen Recording permission; only window *names* are gated.)
@MainActor
final class FullscreenDetector {
    private(set) var isFullscreenActive = false
    var onChange: (() -> Void)?

    private var debounce: DispatchWorkItem?
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
        ] {
            nc.addObserver(self, selector: #selector(scheduleScan), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(scheduleScan),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        scan()
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func scheduleScan() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func scan() {
        let active = detectFullscreen()
        if active != isFullscreenActive {
            isFullscreenActive = active
            onChange?()
        }
    }

    /// True if a non-self, on-screen, layer-0 window matches a display's full size.
    private func detectFullscreen() -> Bool {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly], kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        // Full pixel sizes of all displays.
        let screenSizes = NSScreen.screens.map { screen -> CGSize in
            let scale = screen.backingScaleFactor
            return CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale)
        }
        // Also compare in points (CGWindow bounds are in points).
        let pointSizes = NSScreen.screens.map { $0.frame.size }

        for info in infoList {
            let layer = info[kCGWindowLayer as String] as? Int ?? -1
            guard layer == 0 else { continue }
            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? -1
            guard pid != ownPID else { continue }
            guard let b = info[kCGWindowBounds as String] as? [String: Any],
                  let w = b["Width"] as? CGFloat, let h = b["Height"] as? CGFloat else { continue }

            for size in pointSizes where matches(w: w, h: h, to: size) { return true }
            for size in screenSizes where matches(w: w, h: h, to: size) { return true }
        }
        return false
    }

    private func matches(w: CGFloat, h: CGFloat, to size: CGSize) -> Bool {
        abs(w - size.width) < 3 && abs(h - size.height) < 3
    }
}
