import Foundation
import IOKit.ps

/// Monitors power source and low-power mode. Calls `onChange` whenever the
/// battery state that affects playback policy changes.
@MainActor
final class PowerMonitor {
    /// True when running on battery (not plugged in).
    private(set) var onBattery = false
    /// 0–100, or nil if no battery (desktop Mac).
    private(set) var batteryPercent: Int?
    var isLowPowerMode: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    var onChange: (() -> Void)?

    private var runLoopSource: CFRunLoopSource?

    func start() {
        refresh()

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(ctx).takeUnretainedValue()
            Task { @MainActor in monitor.refresh(); monitor.onChange?() }
        }, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(lowPowerChanged),
            name: .NSProcessInfoPowerStateDidChange, object: nil
        )
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        runLoopSource = nil
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func lowPowerChanged() {
        onChange?()
    }

    private func refresh() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            onBattery = false
            batteryPercent = nil
            return
        }

        var foundBattery = false
        var percent: Int?
        var charging = true
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            if let type = desc[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType {
                foundBattery = true
                if let cur = desc[kIOPSCurrentCapacityKey] as? Int,
                   let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
                    percent = Int(Double(cur) / Double(max) * 100)
                }
                if let state = desc[kIOPSPowerSourceStateKey] as? String {
                    charging = (state == kIOPSACPowerValue)
                }
            }
        }
        onBattery = foundBattery && !charging
        batteryPercent = percent
    }
}
