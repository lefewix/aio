import AppKit

final class EventTap {
    static let shared = EventTap()
    typealias Handler = (CGEventType, CGEvent) -> Bool

    private var handlers: [Handler] = []
    private var tap: CFMachPort?

    func add(_ handler: @escaping Handler) {
        handlers.append(handler)
        if tap == nil { start() }
    }

    private func start() {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, CGEventType(rawValue: 14)!]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: mask, callback: { _, type, event, _ in
            EventTap.shared.handle(type, event)
        }, userInfo: nil)
        guard let tap else { NSLog("AIO: event tap failed (Accessibility?)"); return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        for h in handlers where h(type, event) { return nil }
        return Unmanaged.passUnretained(event)
    }
}
