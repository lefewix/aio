import ApplicationServices
import Darwin

// Private APIs, all resolved with dlsym so a missing symbol degrades instead of crashing.
private let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

private func sym<T>(_ name: String, _ type: T.Type) -> T? {
    guard let p = dlsym(skyLight, name) ?? dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil } // -2 = RTLD_DEFAULT
    return unsafeBitCast(p, to: type)
}

struct PSN { var high: UInt32 = 0; var low: UInt32 = 0 }

let CGSSetSymbolicHotKeyEnabled = sym("CGSSetSymbolicHotKeyEnabled", (@convention(c) (UInt32, Bool) -> Int32).self)
let AXGetWindow = sym("_AXUIElementGetWindow", (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self)
let AXCreateWithRemoteToken = sym("_AXUIElementCreateWithRemoteToken", (@convention(c) (CFData) -> Unmanaged<AXUIElement>?).self)
let GetProcessForPID = sym("GetProcessForPID", (@convention(c) (pid_t, UnsafeMutableRawPointer) -> Int32).self)
let SLPSSetFrontProcessWithOptions = sym("_SLPSSetFrontProcessWithOptions", (@convention(c) (UnsafeMutableRawPointer, CGWindowID, UInt32) -> Int32).self)
let SLPSPostEventRecordTo = sym("SLPSPostEventRecordTo", (@convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt8>) -> Int32).self)

// Symbolic hotkeys 1 = Cmd+Tab, 2 = Cmd+Shift+Tab.
func setNativeSwitcher(_ on: Bool) {
    _ = CGSSetSymbolicHotKeyEnabled?(1, on)
    _ = CGSSetSymbolicHotKeyEnabled?(2, on)
}

extension AXUIElement {
    func value<T>(_ attr: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attr as CFString, &v) == .success else { return nil }
        return v as? T
    }

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        guard let AXGetWindow, AXGetWindow(self, &id) == .success, id != 0 else { return nil }
        return id
    }

    var isRealWindow: Bool {
        let sub: String? = value(kAXSubroleAttribute)
        return sub == kAXStandardWindowSubrole || sub == kAXDialogSubrole
    }
}

// AltTab's trick: AX only returns windows on the current Space, but every AX element of a
// process can be minted from a remote token (pid, 0, 'coco', element id). Walk the ids.
func bruteForceWindows(_ pid: pid_t) -> [AXUIElement] {
    guard let AXCreateWithRemoteToken else { return [] }
    var token = Data(count: 20)
    token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
    token.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
    token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })
    let deadline = Date().addingTimeInterval(0.1)
    var found: [AXUIElement] = []
    for id: UInt64 in 0..<1000 {
        if Date() > deadline { break }
        token.replaceSubrange(12..<20, with: withUnsafeBytes(of: id) { Data($0) })
        if let el = AXCreateWithRemoteToken(token as CFData)?.takeRetainedValue(), el.isRealWindow {
            found.append(el)
        }
    }
    return found
}

// AltTab/Hammerspoon: bring one specific window forward and make it key, across Spaces.
func forceFront(pid: pid_t, wid: CGWindowID) -> Bool {
    guard let GetProcessForPID, let SLPSSetFrontProcessWithOptions, let SLPSPostEventRecordTo else { return false }
    var psn = PSN()
    guard GetProcessForPID(pid, &psn) == 0 else { return false }
    _ = SLPSSetFrontProcessWithOptions(&psn, wid, 0x200) // userGenerated
    var bytes = [UInt8](repeating: 0, count: 0xf8)
    bytes[0x04] = 0xf8
    bytes[0x3a] = 0x10
    withUnsafeBytes(of: wid) { bytes.replaceSubrange(0x3c..<0x40, with: $0) }
    for i in 0x20..<0x30 { bytes[i] = 0xff }
    bytes[0x08] = 0x01
    _ = SLPSPostEventRecordTo(&psn, &bytes)
    bytes[0x08] = 0x02
    _ = SLPSPostEventRecordTo(&psn, &bytes)
    return true
}
