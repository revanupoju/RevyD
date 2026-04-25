import Foundation
import UserNotifications

/// Manages native macOS notifications for overdue commitments and pre-meeting prep.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            SessionDebugLogger.log("notifications", "Permission granted: \(granted)")
        }
    }

    /// Notify about overdue commitments
    func notifyOverdue(_ commitments: [Commitment]) {
        let content = UNMutableNotificationContent()
        content.title = "RevyD — Overdue Commitments"

        if commitments.count == 1 {
            let c = commitments[0]
            content.body = "\(c.ownerName): \(c.description)"
        } else {
            content.body = "\(commitments.count) commitments are overdue. Click to review."
        }

        content.sound = .default
        content.categoryIdentifier = "OVERDUE"

        let request = UNNotificationRequest(
            identifier: "overdue-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // deliver immediately
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Notify about upcoming meeting
    func notifyUpcomingMeeting(title: String, inMinutes: Int, attendees: [String]) {
        let content = UNMutableNotificationContent()
        content.title = "RevyD — Meeting in \(inMinutes) min"
        content.body = title
        if !attendees.isEmpty {
            content.body += "\nWith: \(attendees.prefix(3).joined(separator: ", "))"
        }
        content.sound = .default
        content.categoryIdentifier = "MEETING_PREP"

        let request = UNNotificationRequest(
            identifier: "meeting-\(title.hashValue)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Notify weekly digest is ready
    func notifyWeeklyDigest(meetingCount: Int, commitmentCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "RevyD — Weekly Digest"
        content.body = "\(meetingCount) meetings this week, \(commitmentCount) open commitments. Click to review."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "weekly-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
