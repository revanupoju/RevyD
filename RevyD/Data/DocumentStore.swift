import Foundation
import CommonCrypto

struct IndexedDocument {
    let id: String
    let filePath: String
    let fileName: String
    let fileType: String   // markdown, pdf, text
    var title: String?
    let contentText: String
    let contentHash: String
    let indexedAt: String
    let fileModifiedAt: String
}

final class DocumentStore {
    private let db: RevyDatabase

    init(db: RevyDatabase = .shared) {
        self.db = db
    }

    func upsert(_ doc: IndexedDocument) {
        db.run("""
            INSERT OR REPLACE INTO documents
            (id, file_path, file_name, file_type, title, content_text, content_hash, indexed_at, file_modified_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, bindings: [
            doc.id, doc.filePath, doc.fileName, doc.fileType, doc.title,
            doc.contentText, doc.contentHash, doc.indexedAt, doc.fileModifiedAt
        ])
    }

    func get(id: String) -> IndexedDocument? {
        db.queryOne("SELECT * FROM documents WHERE id = ?", bindings: [id], map: mapRow)
    }

    func getByPath(_ path: String) -> IndexedDocument? {
        db.queryOne("SELECT * FROM documents WHERE file_path = ?", bindings: [path], map: mapRow)
    }

    func getAll(limit: Int = 100) -> [IndexedDocument] {
        db.query("SELECT * FROM documents ORDER BY indexed_at DESC LIMIT ?",
                 bindings: [limit], map: mapRow)
    }

    func remove(filePath: String) {
        db.run("DELETE FROM documents WHERE file_path = ?", bindings: [filePath])
    }

    func count() -> Int {
        db.queryScalar("SELECT COUNT(*) FROM documents")
    }

    /// Check if file needs reindexing by comparing content hash
    func needsReindex(path: String, currentHash: String) -> Bool {
        guard let existing = getByPath(path) else { return true }
        return existing.contentHash != currentHash
    }

    /// Compute SHA256 hash of content for change detection
    static func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func mapRow(_ stmt: OpaquePointer) -> IndexedDocument {
        IndexedDocument(
            id: RevyDatabase.stringValue(stmt, column: 0),
            filePath: RevyDatabase.stringValue(stmt, column: 1),
            fileName: RevyDatabase.stringValue(stmt, column: 2),
            fileType: RevyDatabase.stringValue(stmt, column: 3),
            title: RevyDatabase.string(stmt, column: 4),
            contentText: RevyDatabase.stringValue(stmt, column: 5),
            contentHash: RevyDatabase.stringValue(stmt, column: 6),
            indexedAt: RevyDatabase.stringValue(stmt, column: 7),
            fileModifiedAt: RevyDatabase.stringValue(stmt, column: 8)
        )
    }
}
