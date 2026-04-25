import Foundation

struct Meeting {
    let id: String
    let title: String
    let createdAt: String
    let updatedAt: String
    var summaryMarkdown: String?
    var notesMarkdown: String?
    var transcriptText: String?
    var attendeesJson: String?
    var debriefJson: String?
    var debriefStatus: String
    let syncedAt: String
    var granolaUpdatedAt: String?

    var attendees: [MeetingAttendee] {
        guard let json = attendeesJson?.data(using: .utf8),
              let arr = try? JSONDecoder().decode([MeetingAttendee].self, from: json) else { return [] }
        return arr
    }

    var attendeesFormatted: String {
        attendees.map(\.name).joined(separator: ", ")
    }
}

struct MeetingAttendee: Codable {
    let name: String
    let email: String?
}

enum DebriefStatus: String {
    case pending
    case processing
    case complete
    case failed
}

final class MeetingStore {
    private let db: RevyDatabase

    init(db: RevyDatabase = .shared) {
        self.db = db
    }

    func upsert(_ meeting: Meeting) {
        db.run("""
            INSERT OR REPLACE INTO meetings
            (id, title, created_at, updated_at, summary_markdown, notes_markdown, transcript_text,
             attendees_json, debrief_json, debrief_status, synced_at, granola_updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, bindings: [
            meeting.id, meeting.title, meeting.createdAt, meeting.updatedAt,
            meeting.summaryMarkdown, meeting.notesMarkdown, meeting.transcriptText,
            meeting.attendeesJson, meeting.debriefJson, meeting.debriefStatus,
            meeting.syncedAt, meeting.granolaUpdatedAt
        ])
    }

    func get(id: String) -> Meeting? {
        db.queryOne("SELECT * FROM meetings WHERE id = ?", bindings: [id], map: mapRow)
    }

    func getAll(limit: Int = 50, offset: Int = 0) -> [Meeting] {
        db.query("SELECT * FROM meetings ORDER BY created_at DESC LIMIT ? OFFSET ?",
                 bindings: [limit, offset], map: mapRow)
    }

    func getRecent(limit: Int = 10) -> [Meeting] {
        db.query("SELECT * FROM meetings ORDER BY created_at DESC LIMIT ?",
                 bindings: [limit], map: mapRow)
    }

    func getMeetingsWith(personId: String) -> [Meeting] {
        db.query("""
            SELECT m.* FROM meetings m
            JOIN meeting_people mp ON m.id = mp.meeting_id
            WHERE mp.person_id = ?
            ORDER BY m.created_at DESC
        """, bindings: [personId], map: mapRow)
    }

    func meetingsNeedingDebrief() -> [Meeting] {
        db.query("SELECT * FROM meetings WHERE debrief_status = 'pending' ORDER BY created_at DESC",
                 map: mapRow)
    }

    func setDebriefStatus(_ status: DebriefStatus, for meetingId: String) {
        db.run("UPDATE meetings SET debrief_status = ? WHERE id = ?",
               bindings: [status.rawValue, meetingId])
    }

    func setDebriefResult(_ json: String, for meetingId: String) {
        db.run("UPDATE meetings SET debrief_json = ?, debrief_status = 'complete' WHERE id = ?",
               bindings: [json, meetingId])
    }

    func count() -> Int {
        db.queryScalar("SELECT COUNT(*) FROM meetings")
    }

    private func mapRow(_ stmt: OpaquePointer) -> Meeting {
        Meeting(
            id: RevyDatabase.stringValue(stmt, column: 0),
            title: RevyDatabase.stringValue(stmt, column: 1),
            createdAt: RevyDatabase.stringValue(stmt, column: 2),
            updatedAt: RevyDatabase.stringValue(stmt, column: 3),
            summaryMarkdown: RevyDatabase.string(stmt, column: 4),
            notesMarkdown: RevyDatabase.string(stmt, column: 5),
            transcriptText: RevyDatabase.string(stmt, column: 6),
            attendeesJson: RevyDatabase.string(stmt, column: 7),
            debriefJson: RevyDatabase.string(stmt, column: 8),
            debriefStatus: RevyDatabase.stringValue(stmt, column: 9),
            syncedAt: RevyDatabase.stringValue(stmt, column: 10),
            granolaUpdatedAt: RevyDatabase.string(stmt, column: 11)
        )
    }
}
