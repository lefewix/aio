import AppKit
import Observation
import Security

@MainActor @Observable
final class Hub {
    static let shared = Hub()

    struct Event: Decodable { let title: String; let start: Date; let end: Date; let allDay: Bool; let color: String? }
    struct Fit: Decodable { let date: String; let steps: Int?; let sleepMin: Int?; let restingHr: Int?; let stale: Bool }
    struct Glance: Decodable { let events: [Event]; let fit: Fit? }

    var events: [Event] = []
    var fit: Fit?
    @ObservationIgnored private var last = Date.distantPast

    func start() {
        refresh()
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            MainActor.assumeIsolated { Hub.shared.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Hub.shared.refresh() }
        }
    }

    /// Glance endpoint, e.g. https://hub.example.com/api/glance. Set with
    /// `defaults write ca.felix.aio hubURL <url>`; unset = the hub is off.
    private static var url: URL? {
        guard let s = UserDefaults.standard.string(forKey: "hubURL"), !s.isEmpty else { return nil }
        return URL(string: s)
    }

    func refresh() {
        guard Date().timeIntervalSince(last) >= 60, let url = Self.url, let token = Self.token() else { return }
        last = Date()
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        Task {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let g = try? dec.decode(Glance.self, from: data) else { return }
            events = g.events
            fit = g.fit
            Agenda.shared.reload()
        }
    }

    private static func token() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "aio-hub",
                                kSecAttrAccount as String: "glance", kSecReturnData as String: true]
        var r: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
