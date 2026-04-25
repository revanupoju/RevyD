import Foundation
import EventKit

/// Reads calendar events via EventKit for pre-meeting prep.
final class CalendarManager {
    private let eventStore = EKEventStore()
    private var hasAccess = false

    /// Request calendar access
    func requestAccess(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { granted, error in
                DispatchQueue.main.async {
                    self.hasAccess = granted
                    completion(granted)
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { granted, error in
                DispatchQueue.main.async {
                    self.hasAccess = granted
                    completion(granted)
                }
            }
        }
    }

    /// Get today's events
    func todaysEvents() -> [EKEvent] {
        guard hasAccess else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        return eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    /// Get the next event happening within a time interval
    func nextEvent(within seconds: TimeInterval) -> EKEvent? {
        guard hasAccess else { return nil }
        let now = Date()
        let cutoff = now.addingTimeInterval(seconds)
        let predicate = eventStore.predicateForEvents(withStart: now, end: cutoff, calendars: nil)
        let events = eventStore.events(matching: predicate)
            .filter { $0.startDate > now } // Only future events
            .sorted { $0.startDate < $1.startDate }
        return events.first
    }

    /// Get attendee names from an event
    func attendeeNames(for event: EKEvent) -> [String] {
        guard let attendees = event.attendees else { return [] }
        return attendees.compactMap { participant in
            if let name = participant.name, !name.isEmpty {
                return name
            }
            let url = participant.url
            return url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
        }
    }

    /// Check if we have calendar access
    var isAuthorized: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .fullAccess || status == .authorized
    }
}
