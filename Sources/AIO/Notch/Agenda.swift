import EventKit
import Observation
import SwiftUI

@MainActor @Observable
final class Agenda {
    static let shared = Agenda()
    struct Item: Hashable { var title: String; var start: Date; var end: Date; var color: Color }

    var events: [Item] = []
    @ObservationIgnored private let store = EKEventStore()

    func start() {
        store.requestFullAccessToEvents { _, _ in
            DispatchQueue.main.async { Agenda.shared.reload() }
        }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { Agenda.shared.reload() }
        }
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            MainActor.assumeIsolated { Agenda.shared.reload() }
        }
    }

    func reload() {
        let cal = Calendar.current
        let now = Date()
        let end = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: now))!
        var items: [Item] = []
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            items = store.events(matching: store.predicateForEvents(withStart: now, end: end, calendars: nil))
                .filter { !$0.isAllDay }
                .map { Item(title: $0.title ?? "", start: $0.startDate, end: $0.endDate, color: Color(nsColor: $0.calendar.color)) }
        }
        let key = { (i: Item) in "\(i.title.lowercased())|\(Int(i.start.timeIntervalSince1970 / 60))" }
        var seen = Set(items.map(key))
        for e in Hub.shared.events where !e.allDay && e.end > now && e.start < end {
            let i = Item(title: e.title, start: e.start, end: e.end, color: e.color.flatMap(Self.hex) ?? .gray)
            if seen.insert(key(i)).inserted { items.append(i) }
        }
        events = Array(items.sorted { $0.start < $1.start }.prefix(3))
    }

    private static func hex(_ s: String) -> Color? {
        guard s.count == 7, let v = Int(s.dropFirst(), radix: 16) else { return nil }
        return Color(red: Double(v >> 16 & 255) / 255, green: Double(v >> 8 & 255) / 255, blue: Double(v & 255) / 255)
    }

    static func when(_ e: Item) -> String {
        let t = e.start.formatted(date: .omitted, time: .shortened)
        if e.start <= .now { return "Now, until \(e.end.formatted(date: .omitted, time: .shortened))" }
        let cal = Calendar.current
        if cal.component(.hour, from: .now) < 6 {
            if cal.isDateInToday(e.start) { return "Today \(t)" }
            if cal.isDateInTomorrow(e.start) { return "\(e.start.formatted(.dateTime.weekday(.abbreviated))) \(t)" }
            return t
        }
        return cal.isDateInTomorrow(e.start) ? "Tomorrow \(t)" : t
    }
}
