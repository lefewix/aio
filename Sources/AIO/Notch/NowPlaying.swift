import AppKit
import Observation

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

    func position(at date: Date) -> Double {
        isPlaying ? min(duration, elapsed + date.timeIntervalSince(timestamp)) : elapsed
    }

    // TODO: wire mediaremote-adapter stream; set fields above on the main actor.
    func start() {}

    func play() { isPlaying = true }   // TODO: send command
    func pause() { elapsed = position(at: .now); timestamp = .now; isPlaying = false }   // TODO: send command
    func togglePlay() { isPlaying ? pause() : play() }
    func next() {}   // TODO: send command
    func previous() {}   // TODO: send command
    func seek(to seconds: Double) { elapsed = seconds; timestamp = .now }   // TODO: send command
}
