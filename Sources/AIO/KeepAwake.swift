import Foundation
import IOKit.pwr_mgt
import Observation

@Observable
final class KeepAwake {
    static let shared = KeepAwake()

    private(set) var isOn = false
    @ObservationIgnored private var assertion: IOPMAssertionID = 0
    @ObservationIgnored private var timer: Timer?

    func turnOn(for duration: TimeInterval? = nil) {
        turnOff()
        guard IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep as CFString,
                                          IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                          "AIO Keep Awake" as CFString, &assertion) == kIOReturnSuccess else { return }
        isOn = true
        if let duration {
            timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in self?.turnOff() }
        }
    }

    func turnOff() {
        timer?.invalidate()
        timer = nil
        if isOn { IOPMAssertionRelease(assertion) }
        isOn = false
    }

    func toggle() { isOn ? turnOff() : turnOn() }
}
