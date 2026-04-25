import Foundation

/// Generates person profiles from meeting history and commitments.
final class PeopleProfileEngine {
    private let personStore = PersonStore()
    private let meetingStore = MeetingStore()
    private let commitmentStore = CommitmentStore()

    /// Build prompt context for a person profile
    func buildProfilePrompt(personName: String) -> String? {
        let people = personStore.search(query: personName)
        guard let person = people.first else { return nil }

        let meetings = meetingStore.getMeetingsWith(personId: person.id)
        let commitments = commitmentStore.getForPerson(person.id)

        return RevyPrompts.personProfilePrompt(
            person: person,
            meetings: Array(meetings.prefix(10)),
            commitments: commitments
        )
    }
}
