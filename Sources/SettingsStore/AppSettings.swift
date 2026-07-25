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

    init() {
        defaults.register(defaults: [
            Key.sameOnAllDisplays: true,
            Key.pauseOnFullscreen: true,
            Key.pauseOnBattery: true,
            Key.batteryThreshold: 20,
            Key.pauseWhenOccluded: true,
            Key.hideDockIcon: false,
            Key.muteVideo: true,
        ])
        assignments = defaults.dictionary(forKey: Key.assignments) as? [String: String] ?? [:]
        sameOnAllDisplays = defaults.bool(forKey: Key.sameOnAllDisplays)
        pauseOnFullscreen = defaults.bool(forKey: Key.pauseOnFullscreen)
        pauseOnBattery = defaults.bool(forKey: Key.pauseOnBattery)
        batteryThreshold = defaults.integer(forKey: Key.batteryThreshold)
        pauseWhenOccluded = defaults.bool(forKey: Key.pauseWhenOccluded)
        hideDockIcon = defaults.bool(forKey: Key.hideDockIcon)
        muteVideo = defaults.bool(forKey: Key.muteVideo)
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
