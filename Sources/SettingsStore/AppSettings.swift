import Foundation
import Combine

/// Global user preferences, persisted in `UserDefaults`, plus the per-display
/// wallpaper assignment map. Assignments are keyed by stable display UUID.
@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard
    private enum Key {
        static let assignments = "assignments"          // [displayUUID: itemID-uuid-string]
        static let sameOnAllDisplays = "sameOnAllDisplays"
        static let pauseOnFullscreen = "pauseOnFullscreen"
        static let pauseOnBattery = "pauseOnBattery"
        static let batteryThreshold = "batteryThreshold"
        static let pauseWhenOccluded = "pauseWhenOccluded"
        static let hideDockIcon = "hideDockIcon"
        static let muteVideo = "muteVideo"
        static let videoMemoryCacheLimitMB = "videoMemoryCacheLimitMB"
        static let didDisableVideoMemoryCache = "didDisableVideoMemoryCacheV2"
    }

    @Published var assignments: [String: String] {
        didSet { defaults.set(assignments, forKey: Key.assignments) }
    }
    @Published var sameOnAllDisplays: Bool {
        didSet { defaults.set(sameOnAllDisplays, forKey: Key.sameOnAllDisplays) }
    }
    @Published var pauseOnFullscreen: Bool {
        didSet { defaults.set(pauseOnFullscreen, forKey: Key.pauseOnFullscreen) }
    }
    @Published var pauseOnBattery: Bool {
        didSet { defaults.set(pauseOnBattery, forKey: Key.pauseOnBattery) }
    }
    @Published var batteryThreshold: Int {
        didSet { defaults.set(batteryThreshold, forKey: Key.batteryThreshold) }
    }
    @Published var pauseWhenOccluded: Bool {
        didSet { defaults.set(pauseWhenOccluded, forKey: Key.pauseWhenOccluded) }
    }
    @Published var hideDockIcon: Bool {
        didSet { defaults.set(hideDockIcon, forKey: Key.hideDockIcon) }
    }
    @Published var muteVideo: Bool {
        didSet { defaults.set(muteVideo, forKey: Key.muteVideo) }
    }
    /// Videos up to this size are played from a memory mapping instead of being
    /// re-read from disk on every loop. 0 disables the memory path.
    ///
    /// Off by default: shipped on in v0.4.0, it turned out to wedge playback
    /// every minute or so on high-bitrate video (see `MemoryVideoAsset`).
    @Published var videoMemoryCacheLimitMB: Int {
        didSet { defaults.set(videoMemoryCacheLimitMB, forKey: Key.videoMemoryCacheLimitMB) }
    }

    init() {
        defaults.register(defaults: [
            Key.sameOnAllDisplays: true,
            Key.pauseOnFullscreen: true,
            Key.pauseOnBattery: true,
            Key.batteryThreshold: 20,
            Key.pauseWhenOccluded: true,
            Key.hideDockIcon: false,
            Key.muteVideo: true,
            Key.videoMemoryCacheLimitMB: 0,
        ])
        assignments = defaults.dictionary(forKey: Key.assignments) as? [String: String] ?? [:]
        sameOnAllDisplays = defaults.bool(forKey: Key.sameOnAllDisplays)
        pauseOnFullscreen = defaults.bool(forKey: Key.pauseOnFullscreen)
        pauseOnBattery = defaults.bool(forKey: Key.pauseOnBattery)
        batteryThreshold = defaults.integer(forKey: Key.batteryThreshold)
        pauseWhenOccluded = defaults.bool(forKey: Key.pauseWhenOccluded)
        hideDockIcon = defaults.bool(forKey: Key.hideDockIcon)
        muteVideo = defaults.bool(forKey: Key.muteVideo)
        videoMemoryCacheLimitMB = defaults.integer(forKey: Key.videoMemoryCacheLimitMB)

        // v0.4.0 and v0.4.1 defaulted this on, and the stored value is that
        // default rather than a choice anyone made. Clear it once so existing
        // installs stop freezing; a deliberate re-enable afterwards sticks.
        if !defaults.bool(forKey: Key.didDisableVideoMemoryCache) {
            defaults.set(true, forKey: Key.didDisableVideoMemoryCache)
            if videoMemoryCacheLimitMB != 0 { videoMemoryCacheLimitMB = 0 }
        }
    }

    // MARK: - Assignment helpers

    func itemID(for displayUUID: String) -> UUID? {
        assignments[displayUUID].flatMap(UUID.init)
    }

    func assign(itemID: UUID, to displayUUID: String) {
        assignments[displayUUID] = itemID.uuidString
    }

    func assignToAll(itemID: UUID, displayUUIDs: [String]) {
        for uuid in displayUUIDs { assignments[uuid] = itemID.uuidString }
    }

    func clearAssignments() {
        assignments = [:]
    }
}
