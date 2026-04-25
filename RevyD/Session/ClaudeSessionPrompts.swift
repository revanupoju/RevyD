import Foundation

enum RevyPrompts {

    /// Structured debrief prompt — instructs Claude to return JSON
    static func debriefPrompt(meeting: Meeting) -> String {
        var context = """
        You are RevyD, an AI chief of staff. Analyze this meeting and produce a structured debrief.

        Meeting: \(meeting.title)
        Date: \(String(meeting.createdAt.prefix(10)))
        Attendees: \(meeting.attendeesFormatted)
        """

        if let summary = meeting.summaryMarkdown, !summary.isEmpty {
            context += "\n\nSummary:\n\(summary)"
        }
        if let notes = meeting.notesMarkdown, !notes.isEmpty {
            context += "\n\nNotes:\n\(notes)"
        }
        if let transcript = meeting.transcriptText, !transcript.isEmpty {
            context += "\n\nTranscript:\n\(String(transcript.prefix(6000)))"
        }

        context += """

        \n\nProduce a structured debrief. Respond with ONLY valid JSON matching this exact schema — no markdown, no commentary, just the JSON object:

        {
            "summary": "2-3 sentence executive summary of the meeting",
            "decisions": [
                {"description": "what was decided", "context": "why it was decided"}
            ],
            "action_items": [
                {"owner": "person name", "description": "what they need to do", "due_date": "YYYY-MM-DD or null"}
            ],
            "commitments_given": [
                {"by": "who promised", "to": "promised to whom", "description": "what was promised", "due_date": "YYYY-MM-DD or null", "source_quote": "relevant quote from transcript"}
            ],
            "commitments_received": [
                {"by": "who promised", "to": "promised to whom", "description": "what was promised", "due_date": "YYYY-MM-DD or null", "source_quote": "relevant quote"}
            ],
            "open_questions": ["unresolved question 1", "question 2"],
            "follow_up_topics": ["topic to revisit next time"],
            "key_topics": ["main topic 1", "topic 2"]
        }

        Rules:
        - Extract EVERY commitment and action item — missing one is worse than including a borderline one
        - Use actual attendee names for owners, not "the team" or "someone"
        - If no transcript/notes available, work with the summary
        - due_date should be null if no date was mentioned
        - source_quote should be the closest relevant snippet from the transcript
        - If a section has no items, use an empty array []
        """

        return context
    }

    /// Cross-meeting intelligence prompt
    static func crossMeetingPrompt(query: String, meetings: [Meeting], commitments: [Commitment]) -> String {
        var context = """
        You are RevyD, an AI chief of staff. The user is asking about information across multiple meetings.

        Query: \(query)

        """

        if !meetings.isEmpty {
            context += "Relevant meetings:\n"
            for (i, m) in meetings.enumerated() {
                context += "\n[\(i+1)] \(m.title) (\(String(m.createdAt.prefix(10))))\n"
                context += "Attendees: \(m.attendeesFormatted)\n"
                if let summary = m.summaryMarkdown { context += "Summary: \(summary)\n" }
                if let notes = m.notesMarkdown { context += "Notes: \(String(notes.prefix(500)))\n" }
                if let debrief = m.debriefJson { context += "Debrief: \(String(debrief.prefix(500)))\n" }
            }
        }

        if !commitments.isEmpty {
            context += "\nRelated commitments:\n"
            for c in commitments {
                context += "- \(c.ownerName) -> \(c.targetName ?? "team"): \(c.description) [\(c.status)]\n"
            }
        }

        context += """

        Synthesize an answer that connects information across these meetings.
        Cite specific meetings by title and date. Highlight commitments and decisions.
        Respond in markdown.
        """

        return context
    }

    /// Person profile prompt
    static func personProfilePrompt(person: Person, meetings: [Meeting], commitments: [Commitment]) -> String {
        var context = """
        You are RevyD. Build a brief profile for this person based on meeting history.

        Person: \(person.name)
        Email: \(person.email ?? "unknown")
        Total meetings: \(person.meetingCount)

        """

        if !meetings.isEmpty {
            context += "Meetings together:\n"
            for m in meetings.prefix(10) {
                context += "- \(m.title) (\(String(m.createdAt.prefix(10))))\n"
                if let summary = m.summaryMarkdown { context += "  \(String(summary.prefix(200)))\n" }
            }
        }

        if !commitments.isEmpty {
            context += "\nCommitments involving \(person.name):\n"
            for c in commitments {
                context += "- \(c.ownerName): \(c.description) [\(c.status)]\n"
            }
        }

        context += """

        Respond in markdown with:
        1. **Role/Context** — what this person's role seems to be based on meeting content
        2. **Key Topics** — recurring themes in discussions with them
        3. **Open Items** — any unresolved commitments or action items
        4. **Relationship Summary** — 1-2 sentences on the working relationship
        """

        return context
    }

    /// Pre-meeting prep prompt
    static func prepPrompt(meetingTitle: String, attendeeNames: [String], previousMeetings: [Meeting], openCommitments: [Commitment]) -> String {
        var context = """
        You are RevyD. Prepare a brief for an upcoming meeting.

        Meeting: \(meetingTitle)
        Attendees: \(attendeeNames.joined(separator: ", "))

        """

        if !previousMeetings.isEmpty {
            context += "Previous meetings with these people:\n"
            for m in previousMeetings.prefix(5) {
                context += "- \(m.title) (\(String(m.createdAt.prefix(10))))\n"
                if let summary = m.summaryMarkdown { context += "  \(String(summary.prefix(200)))\n" }
                if let debrief = m.debriefJson { context += "  Debrief: \(String(debrief.prefix(300)))\n" }
            }
        }

        if !openCommitments.isEmpty {
            context += "\nOpen commitments involving these people:\n"
            for c in openCommitments {
                context += "- [\(c.status)] \(c.ownerName): \(c.description)\n"
            }
        }

        context += """

        Respond in markdown with:
        1. **Context** — what was discussed in previous meetings
        2. **Open Items** — commitments still outstanding
        3. **Suggested Topics** — what to bring up based on history
        4. **Key Reminders** — anything important to remember
        """

        return context
    }
}
