import os

/// Unified-log handles for the app. Logged at `.notice` and above so entries
/// persist to disk — diagnosing the sleep/wake stall found three days of
/// nothing under this process, which is why these exist. Retrieve with:
///
///     log show --predicate 'subsystem == "com.wallpaperstudio.app"' --last 1d
enum WallpaperLog {
    static let policy = Logger(subsystem: "com.wallpaperstudio.app", category: "policy")
    static let video = Logger(subsystem: "com.wallpaperstudio.app", category: "video")
    static let desktop = Logger(subsystem: "com.wallpaperstudio.app", category: "desktop")
}
