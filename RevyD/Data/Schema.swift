import Foundation

enum Schema {
    static let currentVersion = 1

    static func migrate(db: RevyDatabase) {
        db.execute("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)")

        let version = db.queryScalar("SELECT COALESCE(MAX(version), 0) FROM schema_version")

        if version < 1 {
            applyV1(db: db)
            db.run("INSERT INTO schema_version (version) VALUES (?)", bindings: [1])
            SessionDebugLogger.log("schema", "Migrated to v1")
        }
    }

    // MARK: - V1: Initial schema

    private static func applyV1(db: RevyDatabase) {

        // Meetings synced from Granola
        db.execute("""
            CREATE TABLE IF NOT EXISTS meetings (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                summary_markdown TEXT,
                notes_markdown TEXT,
                transcript_text TEXT,
                attendees_json TEXT,
                debrief_json TEXT,
                debrief_status TEXT DEFAULT 'pending',
                synced_at TEXT NOT NULL,
                granola_updated_at TEXT
            )
        """)

        // People (built from meeting attendees, enriched over time)
        db.execute("""
            CREATE TABLE IF NOT EXISTS people (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                email TEXT,
                first_seen_at TEXT NOT NULL,
                last_seen_at TEXT NOT NULL,
                meeting_count INTEGER DEFAULT 0,
                profile_summary TEXT,
                topics_json TEXT,
                notes TEXT
            )
        """)
        db.execute("CREATE INDEX IF NOT EXISTS idx_people_name ON people(name)")
        db.execute("CREATE INDEX IF NOT EXISTS idx_people_email ON people(email)")

        // Meeting <-> Person junction
        db.execute("""
            CREATE TABLE IF NOT EXISTS meeting_people (
                meeting_id TEXT NOT NULL REFERENCES meetings(id),
                person_id TEXT NOT NULL REFERENCES people(id),
                PRIMARY KEY (meeting_id, person_id)
            )
        """)

        // Commitments extracted from debriefs
        db.execute("""
            CREATE TABLE IF NOT EXISTS commitments (
                id TEXT PRIMARY KEY,
                meeting_id TEXT NOT NULL REFERENCES meetings(id),
                owner_person_id TEXT REFERENCES people(id),
                owner_name TEXT NOT NULL,
                target_person_id TEXT REFERENCES people(id),
                target_name TEXT,
                description TEXT NOT NULL,
                status TEXT DEFAULT 'open',
                due_date TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                completed_at TEXT,
                source_quote TEXT
            )
        """)
        db.execute("CREATE INDEX IF NOT EXISTS idx_commitments_status ON commitments(status)")
        db.execute("CREATE INDEX IF NOT EXISTS idx_commitments_owner ON commitments(owner_person_id)")
        db.execute("CREATE INDEX IF NOT EXISTS idx_commitments_meeting ON commitments(meeting_id)")

        // Decisions extracted from debriefs
        db.execute("""
            CREATE TABLE IF NOT EXISTS decisions (
                id TEXT PRIMARY KEY,
                meeting_id TEXT NOT NULL REFERENCES meetings(id),
                description TEXT NOT NULL,
                context TEXT,
                created_at TEXT NOT NULL
            )
        """)

        // Indexed local documents (knowledge base)
        db.execute("""
            CREATE TABLE IF NOT EXISTS documents (
                id TEXT PRIMARY KEY,
                file_path TEXT NOT NULL UNIQUE,
                file_name TEXT NOT NULL,
                file_type TEXT NOT NULL,
                title TEXT,
                content_text TEXT NOT NULL,
                content_hash TEXT NOT NULL,
                indexed_at TEXT NOT NULL,
                file_modified_at TEXT NOT NULL
            )
        """)
        db.execute("CREATE INDEX IF NOT EXISTS idx_documents_path ON documents(file_path)")

        // FTS5 full-text search across all entities
        db.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
                entity_type,
                entity_id,
                title,
                content,
                tokenize='porter unicode61'
            )
        """)

        // Pre-meeting prep cache
        db.execute("""
            CREATE TABLE IF NOT EXISTS prep_cache (
                calendar_event_id TEXT PRIMARY KEY,
                meeting_title TEXT NOT NULL,
                attendee_names_json TEXT,
                prep_markdown TEXT NOT NULL,
                generated_at TEXT NOT NULL,
                expires_at TEXT NOT NULL
            )
        """)
    }
}
