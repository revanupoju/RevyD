import Foundation
import SQLite3

struct SearchResult {
    let entityType: String   // meeting, document, commitment, person
    let entityId: String
    let title: String
    let snippet: String
    let rank: Double
}

final class KnowledgeIndex {
    private let db: RevyDatabase

    init(db: RevyDatabase = .shared) {
        self.db = db
    }

    // MARK: - Indexing

    func index(entityType: String, entityId: String, title: String, content: String) {
        // Remove existing entry first
        remove(entityType: entityType, entityId: entityId)

        db.run("""
            INSERT INTO search_index (entity_type, entity_id, title, content)
            VALUES (?, ?, ?, ?)
        """, bindings: [entityType, entityId, title, content])
    }

    func remove(entityType: String, entityId: String) {
        db.run("""
            DELETE FROM search_index WHERE entity_type = ? AND entity_id = ?
        """, bindings: [entityType, entityId])
    }

    // MARK: - Searching

    /// Full-text search across all entity types
    func search(query: String, limit: Int = 20) -> [SearchResult] {
        let ftsQuery = buildFTSQuery(query)
        return db.query("""
            SELECT entity_type, entity_id, title,
                   snippet(search_index, 3, '**', '**', '...', 32) as snippet,
                   rank
            FROM search_index
            WHERE search_index MATCH ?
            ORDER BY rank
            LIMIT ?
        """, bindings: [ftsQuery, limit]) { stmt in
            SearchResult(
                entityType: RevyDatabase.stringValue(stmt, column: 0),
                entityId: RevyDatabase.stringValue(stmt, column: 1),
                title: RevyDatabase.stringValue(stmt, column: 2),
                snippet: RevyDatabase.stringValue(stmt, column: 3),
                rank: Double(sqlite3_column_double(stmt, 4))
            )
        }
    }

    /// Search within a specific entity type
    func search(query: String, entityType: String, limit: Int = 20) -> [SearchResult] {
        let ftsQuery = buildFTSQuery(query)
        return db.query("""
            SELECT entity_type, entity_id, title,
                   snippet(search_index, 3, '**', '**', '...', 32) as snippet,
                   rank
            FROM search_index
            WHERE search_index MATCH ? AND entity_type = ?
            ORDER BY rank
            LIMIT ?
        """, bindings: [ftsQuery, entityType, limit]) { stmt in
            SearchResult(
                entityType: RevyDatabase.stringValue(stmt, column: 0),
                entityId: RevyDatabase.stringValue(stmt, column: 1),
                title: RevyDatabase.stringValue(stmt, column: 2),
                snippet: RevyDatabase.stringValue(stmt, column: 3),
                rank: Double(sqlite3_column_double(stmt, 4))
            )
        }
    }

    // MARK: - Bulk Operations

    /// Index a meeting and its content
    func indexMeeting(_ meeting: Meeting) {
        var content = meeting.title
        if let summary = meeting.summaryMarkdown { content += "\n\(summary)" }
        if let notes = meeting.notesMarkdown { content += "\n\(notes)" }
        if let transcript = meeting.transcriptText { content += "\n\(String(transcript.prefix(5000)))" }
        index(entityType: "meeting", entityId: meeting.id, title: meeting.title, content: content)
    }

    /// Index a document
    func indexDocument(_ doc: IndexedDocument) {
        let title = doc.title ?? doc.fileName
        let content = String(doc.contentText.prefix(10000))
        index(entityType: "document", entityId: doc.id, title: title, content: content)
    }

    /// Index a commitment
    func indexCommitment(_ commitment: Commitment) {
        let title = "\(commitment.ownerName): \(commitment.description)"
        var content = commitment.description
        if let quote = commitment.sourceQuote { content += "\n\(quote)" }
        index(entityType: "commitment", entityId: commitment.id, title: title, content: content)
    }

    /// Index a person
    func indexPerson(_ person: Person) {
        var content = person.name
        if let email = person.email { content += " \(email)" }
        if let summary = person.profileSummary { content += "\n\(summary)" }
        if let topics = person.topicsJson { content += "\n\(topics)" }
        index(entityType: "person", entityId: person.id, title: person.name, content: content)
    }

    /// Rebuild entire index from source tables
    func rebuildIndex() {
        db.execute("DELETE FROM search_index")

        let meetings = MeetingStore().getAll(limit: 10000)
        for m in meetings { indexMeeting(m) }

        let docs = DocumentStore().getAll(limit: 10000)
        for d in docs { indexDocument(d) }

        let commitments = CommitmentStore().getAll()
        for c in commitments { indexCommitment(c) }

        let people = PersonStore().getAll()
        for p in people { indexPerson(p) }

        SessionDebugLogger.log("search", "Index rebuilt: \(meetings.count) meetings, \(docs.count) docs, \(commitments.count) commitments, \(people.count) people")
    }

    // MARK: - Helpers

    /// Convert user query to FTS5 match syntax
    private func buildFTSQuery(_ query: String) -> String {
        let words = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .map { "\($0)*" }  // prefix matching
        return words.joined(separator: " ")
    }
}
