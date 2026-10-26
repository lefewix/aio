import AppKit

final class Switcher {
    static let shared = Switcher()
    let store = WindowStore()
    private let panel = SwitcherPanel()
    private var active = false
    private var commitWhenReady = false
    private var generation = 0
    private var model: SwitcherModel { panel.model }

    func start() {
        guard AXIsProcessTrusted() else {
            // Without Accessibility there is no event tap, so keep the native switcher until granted.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.start() }
            return
        }
        setNativeSwitcher(true) // undo a crashed previous run before taking over
        setNativeSwitcher(false)
        atexit { setNativeSwitcher(true) }
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig) { s in
                setNativeSwitcher(true)
                signal(s, SIG_DFL)
                raise(s)
            }
        }
        store.start()
        EventTap.shared.add { [unowned self] type, event in handle(type, event) }
    }

    func stop() { setNativeSwitcher(true) }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let flags = event.flags
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if !active {
            guard type == .keyDown, key == 48, flags.contains(.maskCommand),
                  flags.isDisjoint(with: [.maskControl, .maskAlternate]) else { return false }
            open(back: flags.contains(.maskShift))
            return true
        }
        switch type {
        case .flagsChanged:
            if !flags.contains(.maskCommand) { commit() }
            return false // let modifier state reach the app so Cmd doesn't stick
        case .keyDown:
            // Missed the Cmd release (tap timeout): never keep eating keys.
            if !flags.contains(.maskCommand) { commit(); return false }
            switch key {
            case 48: move(flags.contains(.maskShift) ? -1 : 1)
            case 123: move(-1)
            case 124: move(1)
            case 126: move(-model.cols)
            case 125: move(model.cols)
            case 53: cancel()
            case 36, 76: commit()
            default: break
            }
            return true
        case .keyUp: return true
        default: return false
        }
    }

    private func open(back: Bool) {
        active = true
        commitWhenReady = false
        generation += 1
        let gen = generation
        model.windows = []
        model.sel = back ? -1 : 1
        store.snapshot { [self] wins in
            guard gen == generation, active || commitWhenReady else { return }
            guard !wins.isEmpty else { active = false; commitWhenReady = false; return }
            model.windows = wins
            model.sel = (model.sel % wins.count + wins.count) % wins.count
            if commitWhenReady { commitWhenReady = false; focus(wins[model.sel]) }
            else if panel.wantsShow { panel.show() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [self] in
            guard gen == generation, active else { return }
            panel.wantsShow = true
            if !model.windows.isEmpty { panel.show() }
        }
    }

    private func move(_ d: Int) {
        let n = model.windows.count
        model.sel = n == 0 ? model.sel + d : ((model.sel + d) % n + n) % n
    }

    func commit() {
        guard active else { return }
        active = false
        panel.hide()
        if model.windows.isEmpty { commitWhenReady = true; return }
        focus(model.windows[model.sel])
    }

    private func cancel() {
        active = false
        generation += 1
        panel.hide()
    }

    private func focus(_ w: SwitchWindow) {
        if w.minimized { AXUIElementSetAttributeValue(w.ax, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
        if w.app.isHidden { w.app.unhide() }
        AXUIElementPerformAction(w.ax, kAXRaiseAction as CFString)
        w.app.activate()
        store.bump(w.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let focused: AXUIElement? = AXUIElementCreateApplication(w.pid).value(kAXFocusedWindowAttribute)
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier != w.pid || focused?.windowID != w.id else { return }
            if forceFront(pid: w.pid, wid: w.id) { AXUIElementPerformAction(w.ax, kAXRaiseAction as CFString) }
        }
    }
}
