import SwiftUI

private let spring = Animation.spring(response: 0.4, dampingFraction: 0.78)
private let dim = Color.white.opacity(0.55)

struct NotchView: View {
    private let notch = Notch.shared

    var body: some View {
        let s = notch.shape
        ZStack(alignment: .top) {
            NotchShape(top: s.top, bottom: s.bottom).fill(.black)
            switch notch.mode {
            case .expanded: Expanded(inset: s.top).transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
            case .wings: Wings(inset: s.top).transition(.opacity)
            case .idle: EmptyView()
            }
        }
        .frame(width: s.size.width, height: s.size.height)
        .clipShape(NotchShape(top: s.top, bottom: s.bottom))
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: Binding(get: { notch.dropTargeted }, set: { notch.dropTargeted = $0 })) {
            Shelf.shared.add($0)
            return true
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .animation(spring, value: notch.mode)
        .animation(spring, value: s.size)
    }
}

/// Flat top with outward flares of radius `top`, rounded bottom corners of radius `bottom`.
struct NotchShape: Shape {
    var top: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set { top = newValue.first; bottom = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let t = top, b = bottom, w = r.width, h = r.height
        var p = Path()
        p.move(to: .zero)
        p.addQuadCurve(to: CGPoint(x: t, y: t), control: CGPoint(x: t, y: 0))
        p.addLine(to: CGPoint(x: t, y: h - b))
        p.addQuadCurve(to: CGPoint(x: t + b, y: h), control: CGPoint(x: t, y: h))
        p.addLine(to: CGPoint(x: w - t - b, y: h))
        p.addQuadCurve(to: CGPoint(x: w - t, y: h - b), control: CGPoint(x: w - t, y: h))
        p.addLine(to: CGPoint(x: w - t, y: t))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - t, y: 0))
        p.closeSubpath()
        return p
    }
}

// MARK: - Wings

private struct Wings: View {
    let inset: CGFloat
    private let notch = Notch.shared
    private let np = NowPlaying.shared

    var body: some View {
        HStack(spacing: 0) {
            left.frame(width: notch.wing)
            Spacer(minLength: notch.notchSize.width)
            right.frame(width: notch.wing)
        }
        .padding(.horizontal, inset)
        .frame(height: notch.notchSize.height)
    }

    @ViewBuilder private var left: some View {
        if let hud = notch.hud {
            Image(systemName: hud.icon)
                .font(.system(size: 13, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
        } else if notch.chargeFlash {
            Image(systemName: "bolt.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.green)
        } else {
            Artwork(image: np.artwork, size: 20, radius: 5)
        }
    }

    @ViewBuilder private var right: some View {
        if let hud = notch.hud {
            Capsule().fill(.white.opacity(0.2))
                .overlay(alignment: .leading) {
                    GeometryReader { g in Capsule().fill(.white).frame(width: g.size.width * CGFloat(hud.level)) }
                }
                .frame(width: notch.wing - 22, height: 5)
                .animation(.easeOut(duration: 0.15), value: hud.level)
        } else if notch.chargeFlash {
            Text("\(Battery.shared.percent)%").font(.system(size: 12, weight: .semibold)).monospacedDigit()
        } else {
            Bars()
        }
    }
}

private struct Bars: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<4) { i in
                    let d = Double(i)
                    Capsule().fill(.white).frame(width: 2.5, height: 3 + 9 * abs(sin(t * (1.7 + d * 0.6) + d * 1.3)))
                }
            }
            .frame(height: 12)
            .animation(.easeInOut(duration: 0.25), value: t)
        }
    }
}

// MARK: - Expanded

private struct Expanded: View {
    let inset: CGFloat
    private let notch = Notch.shared

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notch.notchSize.height)
            HStack(spacing: 4) {
                tab(.home, "house.fill")
                tab(.shelf, "tray.fill")
                Spacer()
                BatteryLabel()
                AwakeButton()
            }
            .frame(height: 28)
            Group {
                switch notch.tab {
                case .home: Home()
                case .shelf: ShelfView()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
            .padding(.top, 10)
            .padding(.bottom, 18)
        }
        .padding(.horizontal, inset + 16)
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
    }

    private func tab(_ t: Notch.Tab, _ icon: String) -> some View {
        let on = notch.tab == t
        return Button { notch.tab = t } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(on ? .white : dim)
                .frame(width: 30, height: 22)
                .background(on ? .white.opacity(0.14) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct BatteryLabel: View {
    private let b = Battery.shared

    var body: some View {
        if b.present {
            HStack(spacing: 4) {
                Text("\(b.percent)%").font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(dim)
                Image(systemName: b.symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(b.charging ? .green : .white)
            }
        }
    }
}

private struct AwakeButton: View {
    private let ka = KeepAwake.shared

    var body: some View {
        Button { ka.toggle() } label: {
            Image(systemName: ka.isOn ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ka.isOn ? .white : dim)
                .frame(width: 28, height: 22)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help(ka.isOn ? "Keep awake: on" : "Keep awake: off")
    }
}

private struct Home: View {
    private let np = NowPlaying.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 20) {
                if np.hasMedia {
                    NowPlayingView()
                    AgendaView().frame(width: 150)
                } else {
                    AgendaView().frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
            FitRow()
        }
    }
}

private struct FitRow: View {
    private let hub = Hub.shared

    var body: some View {
        if let f = hub.fit {
            HStack(spacing: 14) {
                if let s = f.steps { Label(s.formatted(), systemImage: "figure.walk") }
                if let m = f.sleepMin { Label("\(m / 60)h \(m % 60)m", systemImage: "bed.double.fill") }
                if let hr = f.restingHr { Label("\(hr)", systemImage: "heart.fill") }
            }
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .opacity(f.stale ? 0.5 : 1)
        }
    }
}

// MARK: - Now Playing

private struct NowPlayingView: View {
    private let np = NowPlaying.shared

    var body: some View {
        HStack(spacing: 12) {
            Artwork(image: np.artwork, size: 76, radius: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(np.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(np.artist).font(.system(size: 12)).foregroundStyle(dim).lineLimit(1)
                if np.duration > 0 { Scrubber().padding(.top, 4) }
                HStack(spacing: 0) {
                    control("backward.fill", 13) { np.previous() }
                    control(np.isPlaying ? "pause.fill" : "play.fill", 18) { np.togglePlay() }
                    control("forward.fill", 13) { np.next() }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func control(_ icon: String, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 40, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct Scrubber: View {
    private let np = NowPlaying.shared
    @State private var drag: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let d = max(np.duration, 1)
            let pos = drag ?? np.position(at: ctx.date)
            VStack(spacing: 2) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule().fill(.white).frame(width: g.size.width * min(1, pos / d))
                    }
                    .frame(height: drag == nil ? 4 : 6)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { drag = min(1, max(0, $0.location.x / g.size.width)) * d }
                        .onEnded { _ in
                            if let drag { np.seek(to: drag) }
                            drag = nil
                        })
                    .animation(.easeOut(duration: 0.15), value: drag == nil)
                }
                .frame(height: 10)
                HStack {
                    Text(Self.time(pos))
                    Spacer()
                    Text("-" + Self.time(d - pos))
                }
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(dim)
            }
        }
    }

    private static func time(_ s: Double) -> String {
        Duration.seconds(max(0, s)).formatted(.time(pattern: .minuteSecond))
    }
}

private struct Artwork: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    Image(systemName: "music.note").font(.system(size: size * 0.4)).foregroundStyle(dim)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - Calendar

private struct AgendaView: View {
    private let agenda = Agenda.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if agenda.events.isEmpty {
                Label("No upcoming events", systemImage: "calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(dim)
            }
            ForEach(agenda.events, id: \.self) { e in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(e.color).frame(width: 7, height: 7).padding(.top, 4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(Agenda.when(e)).font(.system(size: 10)).foregroundStyle(dim).lineLimit(1)
                    }
                }
            }
        }
    }
}

// MARK: - Shelf

private struct ShelfView: View {
    private let shelf = Shelf.shared

    var body: some View {
        if shelf.urls.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 22, weight: .light))
                Text("Drop files here").font(.system(size: 12))
            }
            .foregroundStyle(dim)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shelf.urls, id: \.self) { ShelfTile(url: $0) }
                    }
                }
                Button("Clear") { shelf.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(dim)
            }
        }
    }
}

private struct ShelfTile: View {
    let url: URL

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 44, height: 44)
            Text(url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
        }
        .frame(width: 76)
        .padding(.vertical, 8)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button { Shelf.shared.remove(url) } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(dim)
            }
            .buttonStyle(.plain)
            .padding(3)
        }
        .onDrag { NSItemProvider(object: url as NSURL) }
    }
}
