import AppKit
import SwiftUI

@MainActor @Observable
final class Notch {
    static let shared = Notch()
    enum Tab { case home, shelf }
    enum Mode { case idle, wings, expanded }
    struct HUD: Equatable { var icon: String; var level: Float }

    static let panelSize = CGSize(width: 560, height: 260)
    static let expandedSize = CGSize(width: 500, height: 230)

    var expanded = false { didSet { if expanded && !oldValue { Agenda.shared.reload(); Hub.shared.refresh() } } }
    var tab = Tab.home
    var hud: HUD?
    var chargeFlash = false
    var notchSize = CGSize(width: 185, height: 32)
    var dropTargeted = false {
        didSet {
            guard dropTargeted else { mouseChanged(); return }
            collapseTask?.cancel()
            collapseTask = nil
            tab = .shelf
            expanded = true
        }
    }

    @ObservationIgnored private var panel: NSPanel!
    @ObservationIgnored private var screenFrame: CGRect?
    @ObservationIgnored private var midX: CGFloat = 0
    @ObservationIgnored private(set) var displayID = CGMainDisplayID()
    @ObservationIgnored private var collapseTask: Task<Void, Never>?
    @ObservationIgnored private var hudTask: Task<Void, Never>?
    @ObservationIgnored private var chargeTask: Task<Void, Never>?

    var isVisible: Bool { screenFrame != nil }

    var mode: Mode {
        if expanded { return .expanded }
        return hud != nil || chargeFlash || NowPlaying.shared.isPlaying ? .wings : .idle
    }

    var wing: CGFloat { hud != nil ? 76 : notchSize.height + 14 }

    /// Total size (including the top flares), flare radius, bottom corner radius.
    var shape: (size: CGSize, top: CGFloat, bottom: CGFloat) {
        switch mode {
        case .idle: (notchSize, 0, 8)
        case .wings: (CGSize(width: notchSize.width + 2 * wing + 12, height: notchSize.height), 6, 10)
        case .expanded: (Self.expandedSize, 12, 26)
        }
    }

    func start() {
        UserDefaults.standard.register(defaults: ["hudEnabled": true])

        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        let host = NotchHostingView(rootView: NotchView())
        host.sizingOptions = []
        panel.contentView = host
        layout()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Notch.shared.layout() }
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp]) { _ in
            MainActor.assumeIsolated { Notch.shared.mouseChanged() }
        }
        EventTap.shared.add { type, event in
            MainActor.assumeIsolated { MediaKeys.handle(type, event) }
        }

        Battery.shared.start()
        Agenda.shared.start()
        Hub.shared.start()
        NowPlaying.shared.start()
    }

    func layout() {
        guard let s = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil }),
              let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea else {
            screenFrame = nil
            panel.orderOut(nil)
            return
        }
        let w = s.frame.width - l.width - r.width
        notchSize = CGSize(width: w, height: s.safeAreaInsets.top)
        midX = s.frame.minX + l.width + w / 2
        screenFrame = s.frame
        displayID = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
        let p = Self.panelSize
        panel.setFrame(CGRect(x: midX - p.width / 2, y: s.frame.maxY - p.height, width: p.width, height: p.height), display: true)
        panel.orderFrontRegardless()
    }

    private var hitRect: CGRect {
        guard let f = screenFrame else { return .null }
        let s = shape.size
        return CGRect(x: midX - s.width / 2, y: f.maxY - s.height, width: s.width, height: s.height + 1)
    }

    func mouseChanged() {
        let inside = hitRect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        let dragging = NSEvent.pressedMouseButtons & 1 != 0
        if inside {
            collapseTask?.cancel()
            collapseTask = nil
            if !expanded && !dragging { expanded = true }
        } else if expanded && !dragging && !dropTargeted && collapseTask == nil {
            collapseTask = later(0.3) { [self] in
                collapseTask = nil
                expanded = false
            }
        }
    }

    func showHUD(_ icon: String, _ level: Float) {
        hud = HUD(icon: icon, level: level)
        hudTask?.cancel()
        hudTask = later(1.5) { [self] in hud = nil }
    }

    func flashCharge() {
        chargeFlash = true
        chargeTask?.cancel()
        chargeTask = later(2.5) { [self] in chargeFlash = false }
    }

    private func later(_ seconds: Double, _ f: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { f() }
        }
    }
}

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class NotchHostingView: NSHostingView<NotchView> {
    private lazy var tracker = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited], owner: self)

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if !trackingAreas.contains(tracker) { addTrackingArea(tracker) }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        Notch.shared.mouseChanged()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        Notch.shared.mouseChanged()
    }
}
