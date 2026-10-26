import AppKit
import ScreenCaptureKit
import SwiftUI

@Observable
final class SwitcherModel {
    var windows: [SwitchWindow] = []
    var sel = 0
    var thumbs: [CGWindowID: NSImage] = [:]
    var tileWidth: CGFloat = 220
    var cols = 1
    @ObservationIgnored var hoverArmedAt: NSPoint?
}

private final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class SwitcherPanel {
    let model = SwitcherModel()
    var wantsShow = false
    private lazy var host = FirstMouseHost(rootView: SwitcherView(model: model))
    private lazy var panel: NSPanel = {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.contentView = host
        return p
    }()

    func show() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        layout(in: screen.visibleFrame)
        model.hoverArmedAt = mouse
        let size = host.fittingSize
        let f = screen.visibleFrame
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.midY - size.height / 2, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        captureThumbs()
    }

    func hide() {
        wantsShow = false
        panel.orderOut(nil)
    }

    // Shrink tiles until the wrapped grid fits in 80% of the screen.
    private func layout(in f: NSRect) {
        let n = model.windows.count
        var w: CGFloat = 220
        while true {
            let cols = max(1, min(n, Int((f.width * 0.8 - 2 * SwitcherView.pad + SwitcherView.gap) / (w + SwitcherView.gap))))
            let rows = (n + cols - 1) / cols
            model.tileWidth = w
            model.cols = cols
            if CGFloat(rows) * (SwitcherView.tileHeight(w) + SwitcherView.gap) <= f.height * 0.8 || w <= 100 { return }
            w -= 20
        }
    }

    private func captureThumbs() {
        let wins = model.windows.filter { !$0.minimized }
        let live = Set(model.windows.map(\.id))
        model.thumbs = model.thumbs.filter { live.contains($0.key) }
        Task { @MainActor in
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return }
            let byID = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
            for w in wins {
                guard let sc = byID[w.id] else { continue }
                Task { @MainActor in
                    let cfg = SCStreamConfiguration()
                    let scale = min(1, 480 / max(sc.frame.width, 1))
                    cfg.width = Int(sc.frame.width * scale * 2)
                    cfg.height = Int(sc.frame.height * scale * 2)
                    cfg.showsCursor = false
                    cfg.ignoreShadowsSingleWindow = true
                    let filter = SCContentFilter(desktopIndependentWindow: sc)
                    if let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) {
                        model.thumbs[w.id] = NSImage(cgImage: img, size: .zero)
                    }
                }
            }
        }
    }
}

struct SwitcherView: View {
    static let pad: CGFloat = 16
    static let gap: CGFloat = 8
    static func tileHeight(_ w: CGFloat) -> CGFloat { w * 0.62 + 40 }

    let model: SwitcherModel

    var body: some View {
        let n = model.windows.count
        let cols = max(model.cols, 1)
        VStack(spacing: Self.gap) {
            ForEach(Array(stride(from: 0, to: n, by: cols)), id: \.self) { start in
                HStack(spacing: Self.gap) {
                    ForEach(start..<min(start + cols, n), id: \.self) { tile($0) }
                }
            }
        }
        .padding(Self.pad)
        .glassEffect(.regular.tint(.black.opacity(0.45)), in: .rect(cornerRadius: 22))
        .environment(\.colorScheme, .dark)
    }

    private func tile(_ i: Int) -> some View {
        let w = model.windows[i]
        let width = model.tileWidth
        let selected = i == model.sel
        let icon = w.app.icon ?? NSImage()
        return VStack(spacing: 8) {
            Group {
                if let thumb = model.thumbs[w.id] {
                    Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 6))
                } else {
                    Image(nsImage: icon).resizable().frame(width: 64, height: 64)
                }
            }
            .frame(width: width - 16, height: width * 0.62 - 8)
            .opacity(w.minimized ? 0.6 : 1)
            HStack(spacing: 6) {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                Text(w.title).lineLimit(1).truncationMode(.tail)
            }
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
        }
        .padding(8)
        .frame(width: width, height: Self.tileHeight(width))
        .background(.white.opacity(selected ? 0.16 : 0), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
        .contentShape(.rect)
        .onHover { inside in
            // Ignore the hover fired by the panel appearing under a still mouse.
            guard inside, NSEvent.mouseLocation != model.hoverArmedAt else { return }
            model.hoverArmedAt = nil
            model.sel = i
        }
        .onTapGesture {
            model.sel = i
            Switcher.shared.commit()
        }
    }
}
