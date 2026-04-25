import Foundation

enum AppSettings {

    // MARK: - UserDefaults keys

    static let debugLoggingEnabledKey = "debugLoggingEnabled"
    static let knowledgeDirectoriesKey = "knowledgeDirectories"
    static let granolaAutoSyncKey = "granolaAutoSync"
    static let granolaLastSyncKey = "granolaLastSyncDate"

    // MARK: - Preferences

    static var debugLoggingEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: debugLoggingEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: debugLoggingEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: debugLoggingEnabledKey) }
    }

    static var knowledgeDirectories: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: knowledgeDirectoriesKey) ?? [
                NSString("~/Documents/Obsidian Vault").expandingTildeInPath
            ]
        }
        set { UserDefaults.standard.set(newValue, forKey: knowledgeDirectoriesKey) }
    }

    static var granolaAutoSync: Bool {
        get { UserDefaults.standard.object(forKey: granolaAutoSyncKey) == nil ? true : UserDefaults.standard.bool(forKey: granolaAutoSyncKey) }
        set { UserDefaults.standard.set(newValue, forKey: granolaAutoSyncKey) }
    }

    static var granolaLastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: granolaLastSyncKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: granolaLastSyncKey) }
    }

    static let deepgramAPIKeyKey = "deepgramAPIKey"

    static var deepgramAPIKey: String? {
        get {
            let val = UserDefaults.standard.string(forKey: deepgramAPIKeyKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (val?.isEmpty ?? true) ? nil : val
        }
        set { UserDefaults.standard.set(newValue, forKey: deepgramAPIKeyKey) }
    }

    static var isRecordingAvailable: Bool {
        deepgramAPIKey != nil
    }

    // MARK: - Claude Code Detection

    static func claudeCodePath() -> String? {
        let candidates = [
            NSString("~/.npm-global/bin/claude").expandingTildeInPath,
            NSString("~/.claude/local/claude").expandingTildeInPath,
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isClaudeCodeAvailable: Bool {
        claudeCodePath() != nil
    }
}
