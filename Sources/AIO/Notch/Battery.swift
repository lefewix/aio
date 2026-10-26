import Foundation
import IOKit.ps
import Observation

@MainActor @Observable
final class Battery {
    static let shared = Battery()

    var present = false
    var percent = 100
    var charging = false
    var plugged = false

    var symbol: String {
        if charging { return "battery.100percent.bolt" }
        return "battery.\([0, 25, 50, 75, 100].min { abs($0 - percent) < abs($1 - percent) }!)percent"
    }

    func start() {
        update(flash: false)
        guard let src = IOPSNotificationCreateRunLoopSource({ _ in
            MainActor.assumeIsolated { Battery.shared.update(flash: true) }
        }, nil)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
    }

    private func update(flash: Bool) {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        guard let d = list.lazy.compactMap({ IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }).first,
              let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { return }
        let wasPlugged = plugged
        present = true
        percent = cur * 100 / max
        charging = d[kIOPSIsChargingKey] as? Bool ?? false
        plugged = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        if flash && plugged && !wasPlugged { Notch.shared.flashCharge() }
    }
}
