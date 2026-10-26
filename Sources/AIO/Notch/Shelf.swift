import AppKit
import Observation

@MainActor @Observable
final class Shelf {
    static let shared = Shelf()

    var urls: [URL] = (UserDefaults.standard.stringArray(forKey: "shelf") ?? [])
        .filter { FileManager.default.fileExists(atPath: $0) }
        .map { URL(fileURLWithPath: $0) } {
        didSet { UserDefaults.standard.set(urls.map(\.path), forKey: "shelf") }
    }

    func add(_ providers: [NSItemProvider]) {
        for p in providers {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                DispatchQueue.main.async {
                    if !Shelf.shared.urls.contains(url) { Shelf.shared.urls.append(url) }
                }
            }
        }
    }

    func remove(_ url: URL) { urls.removeAll { $0 == url } }
    func clear() { urls = [] }
}
