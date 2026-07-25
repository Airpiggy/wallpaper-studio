import AppKit

/// Watches for display configuration changes and asks the desktop controller to
/// reconcile. Debounced, because `didChangeScreenParameters` fires in bursts.
@MainActor
final class ScreenTracker {
    private let onReconcile: () -> Void
    private var debounce: DispatchWorkItem?

    init(onReconcile: @escaping () -> Void) {
        self.onReconcile = onReconcile
    }

    func start() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func screensChanged() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onReconcile() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
