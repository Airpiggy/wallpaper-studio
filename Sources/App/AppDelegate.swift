import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.shared.onLaunch()

        // Debug hooks for headless verification.
        let env = ProcessInfo.processInfo.environment
        if env["WPS_AUTOAPPLY"] == "1" {
            AppState.shared.applySampleWallpaper()
        }
        if env["WPS_TESTWEB"] == "1" {
            AppState.shared.debugImportAndApplyBundledWeb()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in the menu bar after the library window is closed —
        // the wallpaper should stay up.
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.onTerminate()
    }
}
