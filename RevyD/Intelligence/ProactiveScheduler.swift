import Foundation
import EventKit

/// Checks for upcoming meetings and overdue commitments on a timer.
/// Fires callbacks to show proactive nudges on the dock character.
final class ProactiveScheduler {
    private let commitmentStore = CommitmentStore()
    private let meetingStore = MeetingStore()
    private let prepEngine = PrepEngine()
    private let calendarManager = CalendarManager()
    private var checkTimer: Timer?
    private var lastPrepEventId: String?
    private var lastOverdueAlert: Date?

    var onPrepReady: ((String, String) -> Void)?  // (event title, prep context)
    var onOverdueCommitments: (([Commitment]) -> Void)?
    var onWeeklySummaryReady: ((String) -> Void)?

    func start() {
        // Request calendar access
        calendarManager.requestAccess { granted in
            SessionDebugLogger.log("calendar", "Calendar access: \(granted)")
        }

        // Check every 60 seconds
        checkTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkProactiveActions()
        }
        // Also check immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.checkProactiveActions()
        }
    }

    func stop() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    private func checkProactiveActions() {
        checkUpcomingMeetings()
        checkOverdueCommitments()
    }

    /// If a meeting starts within 10 minutes, generate prep
    private func checkUpcomingMeetings() {
        guard let event = calendarManager.nextEvent(within: 600) else { return }
        guard event.eventIdentifier != lastPrepEventId else { return }
        lastPrepEventId = event.eventIdentifier

        let title = event.title ?? "Upcoming meeting"
        let attendees = calendarManager.attendeeNames(for: event)
        let prepContext = prepEngine.generatePrepContext(meetingTitle: title, attendeeNames: attendees)

        if !prepContext.isEmpty {
            onPrepReady?(title, prepContext)
        }
    }

    /// Alert if there are overdue commitments (max once per hour)
    private func checkOverdueCommitments() {
        if let lastAlert = lastOverdueAlert, Date().timeIntervalSince(lastAlert) < 3600 {
            return // Don't alert more than once per hour
        }

        let overdue = commitmentStore.getOverdue()
        if !overdue.isEmpty {
            lastOverdueAlert = Date()
            onOverdueCommitments?(overdue)
        }
    }

    /// Generate a weekly summary of commitments
    func generateWeeklySummary() -> String {
        let open = commitmentStore.getOpen()
        let overdue = commitmentStore.getOverdue()
        let totalMeetings = meetingStore.count()
        let totalPeople = PersonStore().count()

        var summary = "**Weekly Summary**\n\n"
        summary += "Meetings: \(totalMeetings) total\n"
        summary += "People: \(totalPeople) contacts\n"
        summary += "Open commitments: \(open.count)\n"
        summary += "Overdue: \(overdue.count)\n"

        if !overdue.isEmpty {
            summary += "\n**Overdue:**\n"
            for c in overdue {
                summary += "  •  \(c.ownerName): \(c.description)"
                if let due = c.dueDate { summary += " (due: \(String(due.prefix(10))))" }
                summary += "\n"
            }
        }

        if !open.isEmpty {
            summary += "\n**Open:**\n"
            for c in open.prefix(10) {
                summary += "  •  \(c.ownerName): \(c.description)\n"
            }
        }

        return summary
    }

    deinit {
        stop()
    }
}
