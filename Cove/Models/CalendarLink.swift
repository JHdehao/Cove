import EventKit
import Foundation

/// Optional (Settings): when a recording starts during a calendar event, the meeting takes
/// its title and the invitees' names, which also help the minutes name people.
enum CalendarLink {
    static let key = "calendar.link"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: key) }

    static func requestAccess() async -> Bool {
        (try? await EKEventStore().requestFullAccessToEvents()) ?? false
    }

    /// The event going on now (or starting within 15 minutes) closest to now.
    static func currentEvent() -> (title: String, attendees: [String])? {
        guard isEnabled, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }
        let store = EKEventStore()
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-4 * 3600), end: now.addingTimeInterval(15 * 60), calendars: nil)
        let events = store.events(matching: predicate).filter {
            !$0.isAllDay && $0.startDate <= now.addingTimeInterval(15 * 60) && $0.endDate >= now
        }
        guard let event = events.min(by: { abs($0.startDate.timeIntervalSince(now)) < abs($1.startDate.timeIntervalSince(now)) }) else { return nil }
        let names = (event.attendees ?? []).compactMap(\.name).filter { !$0.isEmpty && !$0.contains("@") }
        return (event.title ?? "", names)
    }
}
