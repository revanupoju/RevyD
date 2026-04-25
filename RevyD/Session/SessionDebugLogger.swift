import Foundation

enum SessionDebugLogger {
    static func log(_ tag: String, _ message: String) {
        guard AppSettings.debugLoggingEnabled else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] [\(tag)] \(message)")
    }

    static func trace(_ tag: String, _ message: String) {
        guard AppSettings.debugLoggingEnabled else { return }
        // Only log in debug builds to reduce noise
        #if DEBUG
        print("[TRACE] [\(tag)] \(String(message.prefix(200)))")
        #endif
    }
}
