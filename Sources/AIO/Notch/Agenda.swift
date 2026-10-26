import EventKit
import Observation

@MainActor @Observable
final class Agenda {
    static let shared = Agenda()

    var events: [EKEvent] = []
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
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { events = []; return }
        let cal = Calendar.current
        let now = Date()
        let end = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: now))!
        events = Array(store.events(matching: store.predicateForEvents(withStart: now, end: end, calendars: nil))
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .prefix(3))
    }

    static func when(_ e: EKEvent) -> String {
        let t = e.startDate.formatted(date: .omitted, time: .shortened)
        if e.startDate <= .now { return "Now, until \(e.endDate.formatted(date: .omitted, time: .shortened))" }
        return Calendar.current.isDateInTomorrow(e.startDate) ? "Tomorrow \(t)" : t
    }
}
