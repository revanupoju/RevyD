import Foundation
import SQLite3

final class RevyDatabase {
    static let shared = RevyDatabase()

    private var db: OpaquePointer?
    private let dbPath: String

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let revydDir = appSupport.appendingPathComponent("RevyD", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: revydDir, withIntermediateDirectories: true)

        dbPath = revydDir.appendingPathComponent("revyd.db").path
        open()
        configurePragmas()
        Schema.migrate(db: self)
        SessionDebugLogger.log("database", "Database ready at \(dbPath)")
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Connection

    private func open() {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(dbPath, &db, flags, nil)
        if result != SQLITE_OK {
            let error = String(cString: sqlite3_errmsg(db))
            SessionDebugLogger.log("database", "Failed to open database: \(error)")
        }
    }

    private func configurePragmas() {
        execute("PRAGMA journal_mode=WAL")
        execute("PRAGMA foreign_keys=ON")
        execute("PRAGMA synchronous=NORMAL")
    }

    // MARK: - Execute (no results)

    @discardableResult
    func execute(_ sql: String) -> Bool {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let error = errorMessage.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errorMessage)
            SessionDebugLogger.log("database", "SQL error: \(error)\nSQL: \(sql.prefix(200))")
            return false
        }
        return true
    }

    // MARK: - Prepared Statements

    func prepareStatement(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if result != SQLITE_OK {
            let error = String(cString: sqlite3_errmsg(db))
            SessionDebugLogger.log("database", "Prepare error: \(error)\nSQL: \(sql.prefix(200))")
            return nil
        }
        return stmt
    }

    /// Execute a parameterized statement with bindings
    @discardableResult
    func run(_ sql: String, bindings: [Any?]) -> Bool {
        guard let stmt = prepareStatement(sql) else { return false }
        defer { sqlite3_finalize(stmt) }
        bindValues(stmt, bindings: bindings)
        let result = sqlite3_step(stmt)
        if result != SQLITE_DONE && result != SQLITE_ROW {
            let error = String(cString: sqlite3_errmsg(db))
            SessionDebugLogger.log("database", "Run error: \(error)")
            return false
        }
        return true
    }

    /// Query rows with parameterized bindings
    func query<T>(_ sql: String, bindings: [Any?] = [], map: (OpaquePointer) -> T) -> [T] {
        guard let stmt = prepareStatement(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        bindValues(stmt, bindings: bindings)

        var results: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(map(stmt))
        }
        return results
    }

    /// Query a single row
    func queryOne<T>(_ sql: String, bindings: [Any?] = [], map: (OpaquePointer) -> T) -> T? {
        guard let stmt = prepareStatement(sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        bindValues(stmt, bindings: bindings)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return map(stmt)
        }
        return nil
    }

    /// Query a single integer value (for COUNT, etc.)
    func queryScalar(_ sql: String, bindings: [Any?] = []) -> Int {
        guard let stmt = prepareStatement(sql) else { return 0 }
        defer { sqlite3_finalize(stmt) }
        bindValues(stmt, bindings: bindings)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int64(stmt, 0))
        }
        return 0
    }

    // MARK: - Transactions

    func transaction(_ block: () -> Bool) -> Bool {
        execute("BEGIN TRANSACTION")
        if block() {
            execute("COMMIT")
            return true
        } else {
            execute("ROLLBACK")
            return false
        }
    }

    // MARK: - Helpers

    private func bindValues(_ stmt: OpaquePointer, bindings: [Any?]) {
        for (index, value) in bindings.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case nil:
                sqlite3_bind_null(stmt, position)
            case let v as String:
                sqlite3_bind_text(stmt, position, (v as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case let v as Int:
                sqlite3_bind_int64(stmt, position, Int64(v))
            case let v as Int64:
                sqlite3_bind_int64(stmt, position, v)
            case let v as Double:
                sqlite3_bind_double(stmt, position, v)
            case let v as Bool:
                sqlite3_bind_int(stmt, position, v ? 1 : 0)
            case let v as Data:
                v.withUnsafeBytes { ptr in
                    sqlite3_bind_blob(stmt, position, ptr.baseAddress, Int32(v.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            default:
                let str = "\(value!)"
                sqlite3_bind_text(stmt, position, (str as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        }
    }

    /// Read a column as optional String
    static func string(_ stmt: OpaquePointer, column: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, column) else { return nil }
        return String(cString: cString)
    }

    /// Read a column as non-optional String
    static func stringValue(_ stmt: OpaquePointer, column: Int32) -> String {
        string(stmt, column: column) ?? ""
    }

    /// Read a column as Int
    static func int(_ stmt: OpaquePointer, column: Int32) -> Int {
        Int(sqlite3_column_int64(stmt, column))
    }
}
