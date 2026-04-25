import Foundation

struct Commitment {
    let id: String
    let meetingId: String
    var ownerPersonId: String?
    let ownerName: String
    var targetPersonId: String?
    var targetName: String?
    let description: String
    var status: String       // open, completed, cancelled, overdue
    var dueDate: String?
    let createdAt: String
    var updatedAt: String
    var completedAt: String?
    var sourceQuote: String?

    var isOverdue: Bool {
        guard status == "open", let dueDate else { return false }
        let formatter = ISO8601DateFormatter()
        guard let due = formatter.date(from: dueDate) else { return false }
        return due < Date()
    }
}

final class CommitmentStore {
    private let db: RevyDatabase

    init(db: RevyDatabase = .shared) {
        self.db = db
    }

    func insert(_ commitment: Commitment) {
        db.run("""
            INSERT OR REPLACE INTO commitments
            (id, meeting_id, owner_person_id, owner_name, target_person_id, target_name,
             description, status, due_date, created_at, updated_at, completed_at, source_quote)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, bindings: [
            commitment.id, commitment.meetingId, commitment.ownerPersonId,
            commitment.ownerName, commitment.targetPersonId, commitment.targetName,
            commitment.description, commitment.status, commitment.dueDate,
            commitment.createdAt, commitment.updatedAt, commitment.completedAt,
            commitment.sourceQuote
        ])
    }

    func get(id: String) -> Commitment? {
        db.queryOne("SELECT * FROM commitments WHERE id = ?", bindings: [id], map: mapRow)
    }

    func getAll(status: String? = nil) -> [Commitment] {
        if let status {
            return db.query("SELECT * FROM commitments WHERE status = ? ORDER BY created_at DESC",
                            bindings: [status], map: mapRow)
        }
        return db.query("SELECT * FROM commitments ORDER BY created_at DESC", map: mapRow)
    }

    func getOpen() -> [Commitment] {
        getAll(status: "open")
    }

    func getOverdue() -> [Commitment] {
        let now = ISO8601DateFormatter().string(from: Date())
        return db.query("""
            SELECT * FROM commitments
            WHERE status = 'open' AND due_date IS NOT NULL AND due_date < ?
            ORDER BY due_date ASC
        """, bindings: [now], map: mapRow)
    }

    func getForMeeting(_ meetingId: String) -> [Commitment] {
        db.query("SELECT * FROM commitments WHERE meeting_id = ? ORDER BY created_at",
                 bindings: [meetingId], map: mapRow)
    }

    func getForPerson(_ personId: String) -> [Commitment] {
        db.query("""
            SELECT * FROM commitments
            WHERE owner_person_id = ? OR target_person_id = ?
            ORDER BY created_at DESC
        """, bindings: [personId, personId], map: mapRow)
    }

    func setStatus(_ status: String, for id: String) {
        let now = ISO8601DateFormatter().string(from: Date())
        let completedAt = status == "completed" ? now : nil
        db.run("UPDATE commitments SET status = ?, updated_at = ?, completed_at = ? WHERE id = ?",
               bindings: [status, now, completedAt, id])
    }

    func openCount() -> Int {
        db.queryScalar("SELECT COUNT(*) FROM commitments WHERE status = 'open'")
    }

    func overdueCount() -> Int {
        let now = ISO8601DateFormatter().string(from: Date())
        return db.queryScalar("""
            SELECT COUNT(*) FROM commitments
            WHERE status = 'open' AND due_date IS NOT NULL AND due_date < ?
        """, bindings: [now])
    }

    private func mapRow(_ stmt: OpaquePointer) -> Commitment {
        Commitment(
            id: RevyDatabase.stringValue(stmt, column: 0),
            meetingId: RevyDatabase.stringValue(stmt, column: 1),
            ownerPersonId: RevyDatabase.string(stmt, column: 2),
            ownerName: RevyDatabase.stringValue(stmt, column: 3),
            targetPersonId: RevyDatabase.string(stmt, column: 4),
            targetName: RevyDatabase.string(stmt, column: 5),
            description: RevyDatabase.stringValue(stmt, column: 6),
            status: RevyDatabase.stringValue(stmt, column: 7),
            dueDate: RevyDatabase.string(stmt, column: 8),
            createdAt: RevyDatabase.stringValue(stmt, column: 9),
            updatedAt: RevyDatabase.stringValue(stmt, column: 10),
            completedAt: RevyDatabase.string(stmt, column: 11),
            sourceQuote: RevyDatabase.string(stmt, column: 12)
        )
    }
}
