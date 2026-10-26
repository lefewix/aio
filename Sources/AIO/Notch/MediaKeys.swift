import AppKit
import AudioToolbox
import CoreAudio

@MainActor
enum MediaKeys {
    private static var lastBrightness = Date.distantPast

    /// Volume up/down/mute and brightness up/down. Returns true to swallow the event.
    static func handle(_ type: CGEventType, _ cg: CGEvent) -> Bool {
        guard Notch.shared.isVisible, UserDefaults.standard.bool(forKey: "hudEnabled") else { return false }
        let key: Int, down: Bool
        if type.rawValue == 14 {
            guard let e = NSEvent(cgEvent: cg), e.subtype.rawValue == 8 else { return false }
            key = (e.data1 & 0xFFFF0000) >> 16
            down = (e.data1 & 0xFF00) >> 8 == 0xA
        } else if type == .keyDown || type == .keyUp {
            // Apple keyboards can also send brightness as plain key codes 144/145.
            let code = cg.getIntegerValueField(.keyboardEventKeycode)
            guard code == 144 || code == 145 else { return false }
            key = code == 144 ? 2 : 3
            down = type == .keyDown
        } else {
            return false
        }
        let step: Float = CGEventSource.flagsState(.combinedSessionState).isSuperset(of: [.maskAlternate, .maskShift]) ? 1 / 64 : 1 / 16

        switch key {
        case 0, 1, 7:
            guard let dev = Volume.device(), Volume.settable(dev) else { return false }
            if down { volume(dev, key, step) }
            return true
        case 2, 3:
            guard let level = Brightness.get(Notch.shared.displayID) else { return false }
            if down && Date().timeIntervalSince(lastBrightness) > 0.02 {
                lastBrightness = Date()
                let v = stepped(level, key == 2, step)
                Brightness.set(Notch.shared.displayID, v)
                Notch.shared.showHUD(v < 0.5 ? "sun.min.fill" : "sun.max.fill", v)
            }
            return true
        default:
            return false
        }
    }

    private static func volume(_ dev: AudioObjectID, _ key: Int, _ step: Float) {
        var v = Volume.get(dev, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(0))
        var muted = Volume.get(dev, kAudioDevicePropertyMute, UInt32(0)) != 0
        if key == 7 {
            muted.toggle()
        } else {
            muted = false
            v = stepped(v, key == 0, step)
            Volume.set(dev, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, v)
        }
        Volume.set(dev, kAudioDevicePropertyMute, UInt32(muted ? 1 : 0))
        let icon = muted || v == 0 ? "speaker.slash.fill"
            : v < 0.34 ? "speaker.wave.1.fill" : v < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        Notch.shared.showHUD(icon, muted ? 0 : v)
    }

    private static func stepped(_ v: Float, _ up: Bool, _ step: Float) -> Float {
        min(1, max(0, ((v / step).rounded() + (up ? 1 : -1)) * step))
    }
}

enum Volume {
    static func device() -> AudioObjectID? {
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id)
        return err == noErr && id != 0 ? id : nil
    }

    static func settable(_ dev: AudioObjectID) -> Bool {
        var a = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var ok: DarwinBoolean = false
        return AudioObjectIsPropertySettable(dev, &a, &ok) == noErr && ok.boolValue
    }

    static func get<T: BitwiseCopyable>(_ dev: AudioObjectID, _ sel: AudioObjectPropertySelector, _ fallback: T) -> T {
        var v = fallback
        var a = address(sel)
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr ? v : fallback
    }

    static func set<T: BitwiseCopyable>(_ dev: AudioObjectID, _ sel: AudioObjectPropertySelector, _ value: T) {
        var v = value
        var a = address(sel)
        AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<T>.size), &v)
    }

    private static func address(_ sel: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }
}

/// Private DisplayServices.framework, loaded at runtime.
@MainActor
enum Brightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let lib = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getFn = lib.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetFn.self) }
    private static let setFn = lib.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetFn.self) }

    static func get(_ display: CGDirectDisplayID) -> Float? {
        guard let getFn, setFn != nil else { return nil }
        var v: Float = 0
        return getFn(display, &v) == 0 ? v : nil
    }

    static func set(_ display: CGDirectDisplayID, _ value: Float) {
        _ = setFn?(display, value)
    }
}
