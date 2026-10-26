import AppKit
import ServiceManagement

@main
final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = App()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private var statusItem: NSStatusItem!
    private let awakeItem = NSMenuItem(title: "Keep Awake", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "AIO")

        let awakeMenu = NSMenu()
        for (title, hours) in [("1 h", 1.0), ("3 h", 3.0), ("Until off", 0.0)] {
            let item = NSMenuItem(title: title, action: #selector(awake(_:)), keyEquivalent: "")
            item.tag = Int(hours)
            item.target = self
            awakeMenu.addItem(item)
        }
        awakeItem.submenu = awakeMenu
        loginItem.target = self

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(awakeItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)

        Switcher.shared.start()
        Notch.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Switcher.shared.stop()
    }

    private var awakeTag = -1

    func menuNeedsUpdate(_ menu: NSMenu) {
        let on = KeepAwake.shared.isOn
        awakeItem.state = on ? .on : .off
        awakeItem.submenu?.items.forEach { $0.state = on && $0.tag == awakeTag ? .on : .off }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func awake(_ sender: NSMenuItem) {
        let ka = KeepAwake.shared
        if ka.isOn && sender.tag == awakeTag { ka.turnOff(); return }
        awakeTag = sender.tag
        ka.turnOn(for: sender.tag > 0 ? TimeInterval(sender.tag) * 3600 : nil)
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSLog("AIO: login item: \(error)")
        }
    }
}
