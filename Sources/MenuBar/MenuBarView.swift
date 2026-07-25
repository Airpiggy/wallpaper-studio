import SwiftUI

/// The always-on menu-bar dropdown: status, quick-switch, pause/clear, window, quit.
struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    private var recent: [WallpaperItem] {
        Array(appState.library.items
            .filter { $0.kind.isSupported }
            .sorted { $0.addedDate > $1.addedDate }
            .prefix(8))
    }

    var body: some View {
        if let name = appState.currentWallpaperName {
            if let reason = appState.policy.pauseReason, reason != .noWallpaper {
                Text("\(name) — \(reason.message)")
            } else {
                Text(name)
            }
            Button(appState.isPaused ? "继续" : "暂停") { appState.togglePause() }
            Button("清除壁纸") { appState.clearWallpaper() }
        } else {
            Text("未应用壁纸")
        }

        Divider()

        if recent.isEmpty {
            Button("应用示例壁纸") { appState.applySampleWallpaper() }
        } else {
            Menu("快速切换") {
                ForEach(recent) { item in
                    Button(item.project.title) { appState.apply(item) }
                }
            }
        }

        Button("打开壁纸库…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "library")
        }

        Divider()
        Button("退出 Wallpaper Studio") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
