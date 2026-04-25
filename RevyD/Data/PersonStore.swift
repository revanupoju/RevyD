import Foundation

struct Person {
    let id: String
    let name: String
    var email: String?
    let firstSeenAt: String
    var lastSeenAt: String
    var meetingCount: Int
    var profileSummary: String?
    var topicsJson: String?
    var notes: String?

    var topics: [String] {
        guard let json = topicsJson?.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: json) else { return [] }
        return arr
    }
}

final class PersonStore {
    private let db: RevyDatabase

    init(db: RevyDatabase = .shared) {
        self.db = db
    }

    func findOrCreate(name: String, email: String?) -> Person {
        // Try exact name match first (case-insensitive)
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = db.queryOne(
            "SELECT * FROM people WHERE LOWER(name) = LOWER(?) OR (email IS NOT NULL AND LOWER(email) = LOWER(?))",
            bindings: [normalized, email ?? ""],
            map: mapRow
        ) {
            // Update last_seen and count
            let now = ISO8601DateFormatter().string(from: Date())
            db.run("UPDATE people SET last_seen_at = ?, meeting_count = meeting_count + 1 WHERE id = ?",
                   bindings: [now, existing.id])
            return existing
        }

        // Create new person
        let now = ISO8601DateFormatter().string(from: Date())
        let person = Person(
            id: UUID().uuidString,
            name: normalized,
            email: email,
            firstSeenAt: now,
            lastSeenAt: now,
            meetingCount: 1,
            profileSummary: nil,
            topicsJson: nil,
            notes: nil
        )

        db.run("""
            INSERT INTO people (id, name, email, first_seen_at, last_seen_at, meeting_count)
            VALUES (?, ?, ?, ?, ?, ?)
        """, bindings: [person.id, person.name, person.email, person.firstSeenAt, person.lastSeenAt, person.meetingCount])

        return person
    }

    func get(id: String) -> Person? {
        db.queryOne("SELECT * FROM people WHERE id = ?", bindings: [id], map: mapRow)
    }

    func getAll() -> [Person] {
        db.query("SELECT * FROM people ORDER BY last_seen_at DESC", map: mapRow)
    }

    func getFrequent(limit: Int = 10) -> [Person] {
        db.query("SELECT * FROM people ORDER BY meeting_count DESC LIMIT ?",
                 bindings: [limit], map: mapRow)
    }

    func search(query: String) -> [Person] {
        db.query("SELECT * FROM people WHERE name LIKE ? ORDER BY meeting_count DESC",
                 bindings: ["%\(query)%"], map: mapRow)
    }

    func updateProfile(_ personId: String, summary: String, topics: [String]) {
        let topicsJson = (try? JSONEncoder().encode(topics)).flatMap { String(data: $0, encoding: .utf8) }
        db.run("UPDATE people SET profile_summary = ?, topics_json = ? WHERE id = ?",
               bindings: [summary, topicsJson, personId])
    }

    func linkToMeeting(personId: String, meetingId: String) {
        db.run("INSERT OR IGNORE INTO meeting_people (meeting_id, person_id) VALUES (?, ?)",
               bindings: [meetingId, personId])
    }

    func count() -> Int {
        db.queryScalar("SELECT COUNT(*) FROM people")
    }

    private func mapRow(_ stmt: OpaquePointer) -> Person {
        Person(
            id: RevyDatabase.stringValue(stmt, column: 0),
            name: RevyDatabase.stringValue(stmt, column: 1),
            email: RevyDatabase.string(stmt, column: 2),
            firstSeenAt: RevyDatabase.stringValue(stmt, column: 3),
            lastSeenAt: RevyDatabase.stringValue(stmt, column: 4),
            meetingCount: RevyDatabase.int(stmt, column: 5),
            profileSummary: RevyDatabase.string(stmt, column: 6),
            topicsJson: RevyDatabase.string(stmt, column: 7),
            notes: RevyDatabase.string(stmt, column: 8)
        )
    }
}
