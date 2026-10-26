import AppKit

struct SwitchWindow: Identifiable {
    let id: CGWindowID
    let pid: pid_t
    let ax: AXUIElement
    let app: NSRunningApplication
    let title: String
    let minimized: Bool
}

final class WindowStore {
    private(set) var mru: [CGWindowID] = []
    private var observers: [pid_t: AXObserver] = [:]
    private let queue = DispatchQueue(label: "aio.windows")
    // queue-only: windows found by brute force, and CG ids we already brute-forced for.
    private var bruteCache: [pid_t: [CGWindowID: AXUIElement]] = [:]
    private var bruteTried: [pid_t: Set<CGWindowID>] = [:]

    func start() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.3)
        mru = cgWindows(onScreen: true).map(\.id)
        NSWorkspace.shared.runningApplications.forEach(observe)
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.observe(app) }
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let pid = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier else { return }
            observers[pid] = nil
            queue.async { self.bruteCache[pid] = nil; self.bruteTried[pid] = nil }
        }
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            observe(app)
            let focused: AXUIElement? = AXUIElementCreateApplication(app.processIdentifier).value(kAXFocusedWindowAttribute)
            if let id = focused?.windowID { bump(id) }
        }
        snapshot { _ in } // warm the brute-force cache
    }

    func bump(_ id: CGWindowID) {
        mru.removeAll { $0 == id }
        mru.insert(id, at: 0)
    }

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard observers[pid] == nil, pid != getpid(), app.activationPolicy != .prohibited else { return }
        var obs: AXObserver?
        guard AXObserverCreate(pid, { obs, el, note, refcon in
            Switcher.shared.store.axEvent(obs, el, note as String, refcon)
        }, &obs) == .success, let obs else { return }
        let el = AXUIElementCreateApplication(pid)
        let r = AXObserverAddNotification(obs, el, kAXFocusedWindowChangedNotification as CFString, nil)
        guard r == .success || r == .notificationAlreadyRegistered else { return } // not AX-ready; retried on next activation
        AXObserverAddNotification(obs, el, kAXWindowCreatedNotification as CFString, nil)
        AXObserverAddNotification(obs, el, kAXWindowMiniaturizedNotification as CFString, nil)
        (el.value(kAXWindowsAttribute) as [AXUIElement]?)?.forEach { watchDestroy(obs, $0) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observers[pid] = obs
    }

    // The destroyed element can't be asked for its id anymore, so carry it in refcon.
    private func watchDestroy(_ obs: AXObserver, _ win: AXUIElement) {
        guard let id = win.windowID else { return }
        AXObserverAddNotification(obs, win, kAXUIElementDestroyedNotification as CFString, UnsafeMutableRawPointer(bitPattern: UInt(id)))
    }

    fileprivate func axEvent(_ obs: AXObserver, _ el: AXUIElement, _ note: String, _ refcon: UnsafeMutableRawPointer?) {
        switch note {
        case kAXFocusedWindowChangedNotification:
            var pid: pid_t = 0
            AXUIElementGetPid(el, &pid)
            if let id = el.windowID, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { bump(id) }
        case kAXWindowCreatedNotification:
            watchDestroy(obs, el)
        case kAXWindowMiniaturizedNotification:
            if let id = el.windowID { mru.removeAll { $0 == id }; mru.append(id) }
        case kAXUIElementDestroyedNotification:
            if let refcon { let id = CGWindowID(UInt(bitPattern: refcon)); mru.removeAll { $0 == id } }
        default: break
        }
    }

    private func cgWindows(onScreen: Bool) -> [(id: CGWindowID, pid: pid_t)] {
        let opts: CGWindowListOption = onScreen ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll, .excludeDesktopElements]
        let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] ?? []
        let me = getpid()
        return info.compactMap { d in
            guard let id = d[kCGWindowNumber as String] as? CGWindowID,
                  let pid = d[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  d[kCGWindowLayer as String] as? Int == 0,
                  let b = d[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b), r.width >= 100, r.height >= 50 else { return nil }
            return (id, pid)
        }
    }

    // Builds the MRU-ordered list off the main thread, delivers on main.
    func snapshot(_ done: @escaping ([SwitchWindow]) -> Void) {
        let frontPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        queue.async { [self] in
            let cg = cgWindows(onScreen: false)
            let pidOf = Dictionary(cg.map { ($0.id, $0.pid) }, uniquingKeysWith: { a, _ in a })
            var wins: [SwitchWindow] = []
            var frontWin: CGWindowID?
            for pid in Set(cg.map(\.pid)) {
                guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy != .prohibited else { continue }
                let axApp = AXUIElementCreateApplication(pid)
                var found: [CGWindowID: AXUIElement] = [:]
                for w in axApp.value(kAXWindowsAttribute) as [AXUIElement]? ?? [] {
                    if let id = w.windowID { found[id] = w }
                }
                let missing = Set(cg.filter { $0.pid == pid && found[$0.id] == nil }.map(\.id))
                if !missing.subtracting(bruteTried[pid] ?? []).isEmpty {
                    bruteTried[pid, default: []].formUnion(missing)
                    for w in bruteForceWindows(pid) { if let id = w.windowID { bruteCache[pid, default: [:]][id] = w } }
                }
                for (id, w) in bruteCache[pid] ?? [:] where found[id] == nil { found[id] = w }
                for (id, w) in found where pidOf[id] != nil && w.isRealWindow {
                    let title: String = w.value(kAXTitleAttribute) ?? ""
                    wins.append(SwitchWindow(id: id, pid: pid, ax: w, app: app, title: title.isEmpty ? app.localizedName ?? "" : title,
                                             minimized: w.value(kAXMinimizedAttribute) ?? false))
                }
                if pid == frontPid { frontWin = (axApp.value(kAXFocusedWindowAttribute) as AXUIElement?)?.windowID }
            }
            DispatchQueue.main.async { [self] in
                if let frontWin { bump(frontWin) }
                let ids = Set(wins.map(\.id))
                mru.removeAll { !ids.contains($0) }
                for c in cg where ids.contains(c.id) && !mru.contains(c.id) { mru.append(c.id) }
                let rank = Dictionary(uniqueKeysWithValues: mru.enumerated().map { ($1, $0) })
                done(wins.sorted { rank[$0.id, default: .max] < rank[$1.id, default: .max] })
            }
        }
    }
}
