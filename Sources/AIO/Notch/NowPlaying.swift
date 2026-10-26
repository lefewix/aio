import AppKit
import Observation

/// MediaRemote refuses non-Apple callers, so Helper/nowplaying.dylib runs inside /usr/bin/perl.
@MainActor @Observable
final class NowPlaying {
    static let shared = NowPlaying()

    var title = ""
    var artist = ""
    var album = ""
    var artwork: NSImage?
    var isPlaying = false
    var duration: Double = 0
    /// Position in seconds at `timestamp`.
    var elapsed: Double = 0
    var timestamp = Date()

    var hasMedia: Bool { !title.isEmpty }

    @ObservationIgnored private var artData = ""

    func position(at date: Date) -> Double {
        isPlaying ? min(duration, elapsed + date.timeIntervalSince(timestamp)) : elapsed
    }

    func start() {
        Task.detached {
            while true {
                let p = Self.helper(["stream"])
                let pipe = Pipe()
                p.standardOutput = pipe
                do {
                    try p.run()
                    for try await line in pipe.fileHandleForReading.bytes.lines { await self.apply(line) }
                } catch {}
                p.terminate()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func apply(_ line: String) {
        guard let d = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return }
        let newTrack = d["title"] as? String != title
        title = d["title"] as? String ?? ""
        artist = d["artist"] as? String ?? ""
        album = d["album"] as? String ?? ""
        duration = d["duration"] as? Double ?? 0
        elapsed = d["elapsed"] as? Double ?? 0
        timestamp = (d["timestamp"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? .now
        isPlaying = d["playing"] as? Bool ?? false
        // Artwork often arrives a beat after the rest; keep the old one until then.
        if let art = d["artwork"] as? String {
            if art != artData { artData = art; artwork = Data(base64Encoded: art).flatMap(NSImage.init(data:)) }
        } else if newTrack {
            artData = ""; artwork = nil
        }
    }

    nonisolated private static func helper(_ args: [String]) -> Process {
        let res = Bundle.main.resourcePath ?? ""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["\(res)/nowplaying.pl", "\(res)/nowplaying.dylib"] + args
        return p
    }

    private func send(_ args: String...) { try? Self.helper(args).run() }

    func play() { isPlaying = true; send("send", "0") }
    func pause() { elapsed = position(at: .now); timestamp = .now; isPlaying = false; send("send", "1") }
    func togglePlay() { isPlaying ? pause() : play() }
    func next() { send("send", "4") }
    func previous() { send("send", "5") }
    func seek(to seconds: Double) { elapsed = seconds; timestamp = .now; send("seek", String(seconds)) }
}
