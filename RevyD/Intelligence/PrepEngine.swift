import Foundation

/// Assembles pre-meeting context from past meetings, commitments, and people.
/// Sends to Claude for a structured prep brief.
final class PrepEngine {
    private let meetingStore = MeetingStore()
    private let commitmentStore = CommitmentStore()
    private let personStore = PersonStore()

    /// Generate prep context for an upcoming meeting (by title and attendee names)
    func generatePrepContext(meetingTitle: String, attendeeNames: [String]) -> String {
        var previousMeetings: [Meeting] = []
        var openCommitments: [Commitment] = []

        // Find previous meetings with these attendees
        for name in attendeeNames {
            let people = personStore.search(query: name)
            for person in people {
                let meetings = meetingStore.getMeetingsWith(personId: person.id)
                for m in meetings where !previousMeetings.contains(where: { $0.id == m.id }) {
                    previousMeetings.append(m)
                }
                let commitments = commitmentStore.getForPerson(person.id)
                for c in commitments where c.status == "open" && !openCommitments.contains(where: { $0.id == c.id }) {
                    openCommitments.append(c)
                }
            }
        }

        // Sort by date
        previousMeetings.sort { $0.createdAt > $1.createdAt }

        return RevyPrompts.prepPrompt(
            meetingTitle: meetingTitle,
            attendeeNames: attendeeNames,
            previousMeetings: Array(previousMeetings.prefix(5)),
            openCommitments: openCommitments
        )
    }
}
