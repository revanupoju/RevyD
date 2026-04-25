import Foundation

/// Runs structured meeting debriefs via Claude Code CLI.
/// Sends meeting content, gets back structured JSON with decisions/commitments/actions.
final class DebriefEngine {
    private let meetingStore = MeetingStore()
    private let commitmentTracker = CommitmentTracker()

    var onDebriefStarted: ((String) -> Void)?   // meeting title
    var onDebriefComplete: ((String, DebriefResult) -> Void)?  // meeting id, result
    var onDebriefError: ((String, String) -> Void)?  // meeting id, error

    /// Debrief a meeting by ID
    func debrief(meetingId: String) {
        guard let meeting = meetingStore.get(id: meetingId) else {
            onDebriefError?(meetingId, "Meeting not found")
            return
        }

        debrief(meeting: meeting)
    }

    /// Debrief the most recent meeting
    func debriefLatest() {
        guard let meeting = meetingStore.getRecent(limit: 1).first else {
            onDebriefError?("", "No meetings found. Sync with Granola first.")
            return
        }

        debrief(meeting: meeting)
    }

    /// Debrief a specific meeting
    func debrief(meeting: Meeting) {
        meetingStore.setDebriefStatus(.processing, for: meeting.id)
        onDebriefStarted?(meeting.title)

        let prompt = RevyPrompts.debriefPrompt(meeting: meeting)

        guard let claudePath = AppSettings.claudeCodePath() else {
            meetingStore.setDebriefStatus(.failed, for: meeting.id)
            onDebriefError?(meeting.id, "Claude Code not found")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = [
            "-p", prompt,
            "--output-format", "text",
            "--permission-mode", "dontAsk",
            "--allowedTools", "none"
        ]

        var env = ProcessInfo.processInfo.environment
        if let path = env["PATH"] {
            env["PATH"] = "\(NSString("~/.claude/local").expandingTildeInPath):/usr/local/bin:/opt/homebrew/bin:\(path)"
        }
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        process.terminationHandler = { [weak self] proc in
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outData, encoding: .utf8) ?? ""

            DispatchQueue.main.async {
                guard let self else { return }

                if proc.terminationStatus == 0, !output.isEmpty {
                    if let result = self.parseDebriefResult(output) {
                        // Store the debrief JSON
                        self.meetingStore.setDebriefResult(output, for: meeting.id)

                        // Extract and store commitments
                        self.commitmentTracker.processDebrief(result, meetingId: meeting.id, meeting: meeting)

                        self.onDebriefComplete?(meeting.id, result)
                    } else {
                        // Claude returned text but not valid JSON — store as-is
                        self.meetingStore.setDebriefResult(output, for: meeting.id)
                        self.meetingStore.setDebriefStatus(.complete, for: meeting.id)
                        self.onDebriefError?(meeting.id, "Could not parse structured debrief. Raw response saved.")
                    }
                } else {
                    self.meetingStore.setDebriefStatus(.failed, for: meeting.id)
                    self.onDebriefError?(meeting.id, "Claude Code failed to generate debrief")
                }
            }
        }

        do {
            try process.run()
        } catch {
            meetingStore.setDebriefStatus(.failed, for: meeting.id)
            onDebriefError?(meeting.id, error.localizedDescription)
        }
    }

    // MARK: - Parse

    private func parseDebriefResult(_ output: String) -> DebriefResult? {
        // Extract JSON from Claude's output
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        var jsonString = trimmed

        // Strip markdown code block if present
        if let start = trimmed.range(of: "```json\n"),
           let end = trimmed.range(of: "\n```", range: start.upperBound..<trimmed.endIndex) {
            jsonString = String(trimmed[start.upperBound..<end.lowerBound])
        } else if let start = trimmed.range(of: "```\n"),
                  let end = trimmed.range(of: "\n```", range: start.upperBound..<trimmed.endIndex) {
            jsonString = String(trimmed[start.upperBound..<end.lowerBound])
        }

        // Try to find JSON object
        if !jsonString.hasPrefix("{") {
            if let startIdx = jsonString.firstIndex(of: "{"),
               let endIdx = jsonString.lastIndex(of: "}") {
                jsonString = String(jsonString[startIdx...endIdx])
            }
        }

        guard let data = jsonString.data(using: .utf8) else { return nil }

        do {
            return try JSONDecoder().decode(DebriefResult.self, from: data)
        } catch {
            SessionDebugLogger.log("debrief", "Parse error: \(error)")
            return nil
        }
    }
}

// MARK: - Debrief Data Models

struct DebriefResult: Codable {
    let summary: String?
    let decisions: [DebriefDecision]?
    let action_items: [DebriefActionItem]?
    let commitments_given: [DebriefCommitment]?
    let commitments_received: [DebriefCommitment]?
    let open_questions: [String]?
    let follow_up_topics: [String]?
    let key_topics: [String]?
}

struct DebriefDecision: Codable {
    let description: String
    let context: String?
}

struct DebriefActionItem: Codable {
    let owner: String
    let description: String
    let due_date: String?
}

struct DebriefCommitment: Codable {
    let by: String
    let to: String?
    let description: String
    let due_date: String?
    let source_quote: String?
}
