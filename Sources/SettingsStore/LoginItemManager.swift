import Foundation
import ServiceManagement

/// Wraps `SMAppService` for launch-at-login. Requires the app to live in a
/// stable location (e.g. /Applications) to remain registered.
enum LoginItemManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            NSLog("LoginItem toggle failed: \(error.localizedDescription)")
            return false
        }
    }
}
