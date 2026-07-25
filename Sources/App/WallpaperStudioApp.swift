import SwiftUI

@main
struct WallpaperStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        Window("Wallpaper Studio", id: "library") {
            LibraryView()
                .environmentObject(appState)
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra("Wallpaper Studio", systemImage: "photo.on.rectangle.angled") {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            GeneralSettingsView()
                .environmentObject(appState)
        }
    }
}
