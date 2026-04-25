import Foundation

final class ClaudeSession {

    struct Message: Equatable {
        enum Role { case user, assistant, error, toolUse, toolResult }
        let role: Role
        let text: String
    }

    // MARK: - State

    var isRunning = false
    var isBusy = false
    var history: [Message] = []
    var selectedBackend: String? // path to claude CLI
    var currentProcess: Process?
    var currentProcessStdin: FileHandle?
    var isCancellingTurn = false

    // MARK: - Callbacks

    var onTextDelta: ((String) -> Void)?
    var onText: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onToolUse: ((String, String) -> Void)?  // (title, summary)
    var onToolResult: ((String, Bool) -> Void)?
    var onSessionReady: (() -> Void)?
    var onSetupRequired: ((String) -> Void)?
    var onTurnComplete: (() -> Void)?

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        if let path = AppSettings.claudeCodePath() {
            selectedBackend = path
            SessionDebugLogger.log("session", "Claude Code found at \(path)")
            onSessionReady?()
        } else {
            isRunning = false
            onSetupRequired?("Claude Code not found. Install it from claude.ai/download to use RevyD.")
        }
    }

    func send(message: String) {
        guard let claudePath = selectedBackend else {
            onSetupRequired?("Claude Code not found.")
            return
        }

        isCancellingTurn = false
        history.append(Message(role: .user, text: message))
        isBusy = true

        let prompt = buildPrompt(message: message)
        callClaudeCode(executablePath: claudePath, prompt: prompt)
    }

    func terminate() {
        currentProcess?.terminate()
        currentProcess = nil
        isRunning = false
        isBusy = false
    }

    func cancelActiveTurn() {
        isCancellingTurn = true
        if let process = currentProcess, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            kill(-process.processIdentifier, SIGKILL)
        }
        currentProcess = nil
        isBusy = false
    }

    // MARK: - Prompt Building

    private func buildPrompt(message: String) -> String {
        var parts: [String] = []

        parts.append("""
        You are RevyD, an AI chief of staff that helps users manage meetings, track commitments, and prepare for calls.

        You have access to Granola MCP tools to query the user's meetings. USE THEM to get full meeting content.

        Rules:
        - Be concise, specific, and actionable
        - Cite meeting titles, dates, and attendee names
        - When tracking commitments, specify who owns what
        - Respond in markdown format
        - Use Granola tools (query_granola_meetings, list_meetings, get_meetings, get_meeting_transcript) to fetch real data
        - When the user asks about a meeting or person, query Granola for the actual content
        - Some context from the local database is provided below as a starting point
        """)

        // Inject local meeting context from SQLite
        let meetingContext = buildMeetingContext(for: message)
        if !meetingContext.isEmpty {
            parts.append("--- Meeting Data (from local database) ---")
            parts.append(meetingContext)
            parts.append("--- End Meeting Data ---")
        }

        // Knowledge fusion — search local docs for relevant content
        let docResults = KnowledgeIndex().search(query: message, entityType: "document", limit: 3)
        if !docResults.isEmpty {
            let docStore = DocumentStore()
            parts.append("--- Related Documents from Knowledge Base ---")
            for result in docResults {
                if let doc = docStore.get(id: result.entityId) {
                    parts.append("[\(doc.title ?? doc.fileName)] \(String(doc.contentText.prefix(300)))")
                }
            }
            parts.append("--- End Documents ---")
        }

        // Commitment context
        let commitmentContext = buildCommitmentContext()
        if !commitmentContext.isEmpty {
            parts.append("--- Commitments ---")
            parts.append(commitmentContext)
            parts.append("--- End Commitments ---")
        }

        // Conversation history
        let recentHistory = history.suffix(10)
        if recentHistory.count > 1 {
            parts.append("\n--- Recent conversation ---")
            for msg in recentHistory.dropLast() {
                switch msg.role {
                case .user:
                    parts.append("User: \(msg.text)")
                case .assistant:
                    parts.append("Assistant: \(msg.text)")
                default:
                    break
                }
            }
            parts.append("--- End conversation ---\n")
        }

        parts.append("User: \(message)")

        return parts.joined(separator: "\n\n")
    }

    /// Search local meetings relevant to the user's query
    private func buildMeetingContext(for query: String) -> String {
        let meetingStore = MeetingStore()
        let knowledgeIndex = KnowledgeIndex()
        var context = ""
        var includedIds = Set<String>()

        // If query mentions a specific meeting title, find it by title match
        let allMeetings = meetingStore.getAll(limit: 200)
        let directMatches = allMeetings.filter { meeting in
            let q = query.lowercased()
            let t = meeting.title.lowercased()
            return q.contains(t) || t.contains(q.replacingOccurrences(of: "debrief my meeting ", with: "")
                .replacingOccurrences(of: "\"", with: "")
                .trimmingCharacters(in: .whitespaces))
        }

        // Include full content for direct title matches (debrief requests)
        if !directMatches.isEmpty {
            context += "MATCHED MEETINGS (full content):\n"
            for m in directMatches.prefix(3) {
                includedIds.insert(m.id)
                context += "\n## \(m.title) (\(String(m.createdAt.prefix(10))))\n"
                context += "Attendees: \(m.attendeesFormatted)\n"
                if let summary = m.summaryMarkdown, !summary.isEmpty {
                    context += "Summary: \(summary)\n"
                }
                if let notes = m.notesMarkdown, !notes.isEmpty {
                    context += "Notes:\n\(notes)\n"
                }
                if let transcript = m.transcriptText, !transcript.isEmpty {
                    context += "Transcript:\n\(String(transcript.prefix(3000)))\n"
                }
            }
            context += "\n"
        }

        // Always include recent meetings list for context
        let recent = meetingStore.getRecent(limit: 5)
        if !recent.isEmpty {
            context += "Recent meetings:\n"
            for m in recent {
                let date = String(m.createdAt.prefix(10))
                context += "- \(m.title) (\(date)) [Attendees: \(m.attendeesFormatted)]\n"
                if let summary = m.summaryMarkdown, !summary.isEmpty {
                    context += "  Summary: \(String(summary.prefix(200)))\n"
                }
            }
            context += "\n"
        }

        // FTS5 search for relevant meetings not already included
        let searchResults = knowledgeIndex.search(query: query, entityType: "meeting", limit: 5)
        let newResults = searchResults.filter { !includedIds.contains($0.entityId) }
        if !newResults.isEmpty {
            context += "Search results:\n"
            for result in newResults {
                if let meeting = meetingStore.get(id: result.entityId) {
                    let date = String(meeting.createdAt.prefix(10))
                    context += "\n## \(meeting.title) (\(date))\n"
                    context += "Attendees: \(meeting.attendeesFormatted)\n"
                    if let summary = meeting.summaryMarkdown, !summary.isEmpty {
                        context += "Summary: \(summary)\n"
                    }
                    if let notes = meeting.notesMarkdown, !notes.isEmpty {
                        context += "Notes: \(String(notes.prefix(500)))\n"
                    }
                }
            }
        }

        // Search people
        let personResults = knowledgeIndex.search(query: query, entityType: "person", limit: 3)
        if !personResults.isEmpty {
            let personStore = PersonStore()
            context += "\nRelevant people:\n"
            for result in personResults {
                if let person = personStore.get(id: result.entityId) {
                    context += "- \(person.name) (email: \(person.email ?? "n/a"), \(person.meetingCount) meetings)\n"
                    let personMeetings = meetingStore.getMeetingsWith(personId: person.id)
                    for pm in personMeetings.prefix(5) {
                        context += "  - \(pm.title) (\(String(pm.createdAt.prefix(10))))\n"
                    }
                }
            }
        }

        return context
    }

    private func buildCommitmentContext() -> String {
        let store = CommitmentStore()
        let open = store.getOpen()
        let overdue = store.getOverdue()
        if open.isEmpty && overdue.isEmpty { return "" }

        var context = ""
        if !overdue.isEmpty {
            context += "OVERDUE:\n"
            for c in overdue {
                context += "- \(c.ownerName) -> \(c.targetName ?? "team"): \(c.description) (due: \(c.dueDate ?? "none"))\n"
            }
        }
        if !open.isEmpty {
            context += "Open (\(open.count)):\n"
            for c in open.prefix(10) {
                context += "- \(c.ownerName): \(c.description)\n"
            }
        }
        return context
    }

    // MARK: - Claude Code CLI

    private func callClaudeCode(executablePath: String, prompt: String) {
        onToolUse?("Thinking", "Calling Claude...")

        let environment = resolveShellEnvironment()

        var args = [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--permission-mode", "dontAsk",
            "--allowedTools", "mcp__claude_ai_Granola__*",
            "--no-session-persistence"
        ]

        var streamedText = ""

        runProcess(
            executablePath: executablePath,
            arguments: args,
            environment: environment,
            onLineReceived: { [weak self] line in
                guard let self, !self.isCancellingTurn else { return }

                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return
                }

                // Parse Claude Code stream-json events
                let type = json["type"] as? String ?? ""
                SessionDebugLogger.log("stream", "type=\(type)")

                // 1. Assistant message with content blocks (streaming text)
                if type == "assistant",
                   let message = json["message"] as? [String: Any],
                   let content = message["content"] as? [[String: Any]] {
                    for block in content {
                        let blockType = block["type"] as? String ?? ""
                        if blockType == "text", let text = block["text"] as? String, !text.isEmpty {
                            if text != streamedText {
                                // Calculate delta
                                let delta = text.hasPrefix(streamedText)
                                    ? String(text.dropFirst(streamedText.count))
                                    : text
                                streamedText = text
                                if !delta.isEmpty {
                                    self.onTextDelta?(delta)
                                }
                            }
                        }
                    }
                }

                // 2. Final result
                if type == "result", let result = json["result"] as? String, !result.isEmpty {
                    streamedText = result
                    self.onText?(result)
                }
            }
        ) { [weak self] status, stdout, stderr in
            guard let self else { return }

            if self.isCancellingTurn {
                self.isCancellingTurn = false
                return
            }

            self.isBusy = false
            SessionDebugLogger.log("stream", "Process finished. status=\(status) stdout=\(stdout.count)chars stderr=\(stderr.count)chars streamedText=\(streamedText.count)chars")

            // Extract final result from the result event
            let resultText = self.extractResult(from: stdout) ?? streamedText

            if status == 0, !resultText.isEmpty {
                self.history.append(Message(role: .assistant, text: resultText))
                // Always fire onText with the final result to ensure UI shows it
                self.onText?(resultText)
                self.onTurnComplete?()
            } else {
                let errorMsg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayError = errorMsg.isEmpty ? "Claude Code could not complete the request." : String(errorMsg.prefix(500))
                self.history.append(Message(role: .error, text: displayError))
                self.onError?(displayError)
                self.onTurnComplete?()
            }
        }
    }

    // MARK: - Process Runner

    func runProcess(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        onLineReceived: ((String) -> Void)? = nil,
        completion: @escaping (Int32, String, String) -> Void
    ) {
        let process = Process()
        currentProcess = process
        currentProcessStdin = nil

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        var finalStdout = ""
        var finalStderr = ""
        let queue = DispatchQueue(label: "revyd.runProcess", attributes: .concurrent)
        var stdoutLineBuffer = ""
        var stderrLineBuffer = ""

        func consumeBufferedLines(_ string: String, buffer: inout String, flush: Bool = false) -> [String] {
            buffer += string
            let segments = buffer.components(separatedBy: .newlines)
            let completed: [String]

            if flush {
                completed = segments
                buffer = ""
            } else {
                completed = Array(segments.dropLast())
                buffer = segments.last ?? ""
            }

            return completed.compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        }

        let processStdout: (Data) -> Void = { data in
            guard let string = String(data: data, encoding: .utf8), !string.isEmpty else { return }
            let linesToEmit: [String] = queue.sync(flags: .barrier) {
                finalStdout += string
                return consumeBufferedLines(string, buffer: &stdoutLineBuffer)
            }
            if let onLineReceived {
                for line in linesToEmit {
                    DispatchQueue.main.async { onLineReceived(line) }
                }
            }
        }

        let processStderr: (Data) -> Void = { data in
            guard let string = String(data: data, encoding: .utf8), !string.isEmpty else { return }
            queue.sync(flags: .barrier) {
                finalStderr += string
                _ = consumeBufferedLines(string, buffer: &stderrLineBuffer)
            }
        }

        stdout.fileHandleForReading.readabilityHandler = { handle in processStdout(handle.availableData) }
        stderr.fileHandleForReading.readabilityHandler = { handle in processStderr(handle.availableData) }

        process.terminationHandler = { process in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil

            let remainingOut = stdout.fileHandleForReading.readDataToEndOfFile()
            let remainingErr = stderr.fileHandleForReading.readDataToEndOfFile()
            processStdout(remainingOut)
            processStderr(remainingErr)

            queue.sync {
                let bufferedLines = consumeBufferedLines("", buffer: &stdoutLineBuffer, flush: true)
                    + consumeBufferedLines("", buffer: &stderrLineBuffer, flush: true)
                let outText = finalStdout
                let errText = finalStderr
                DispatchQueue.main.async {
                    if let onLineReceived {
                        for line in bufferedLines { onLineReceived(line) }
                    }
                    completion(process.terminationStatus, outText, errText)
                }
            }
        }

        do {
            try process.run()
        } catch {
            currentProcess = nil
            DispatchQueue.main.async {
                completion(-1, "", error.localizedDescription)
            }
        }
    }

    // MARK: - Helpers

    private func extractResult(from stdout: String) -> String? {
        // Claude Code stream-json: find last JSON with result field
        let lines = stdout.components(separatedBy: .newlines)
        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let result = json["result"] as? String, !result.isEmpty {
                return result
            }

            // Look for the final assistant message content
            if let type = json["type"] as? String, type == "result",
               let content = json["result"] as? String {
                return content
            }
        }
        return nil
    }

    private func resolveShellEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Ensure PATH includes common locations for claude binary
        if let path = env["PATH"] {
            env["PATH"] = "\(NSString("~/.claude/local").expandingTildeInPath):/usr/local/bin:/opt/homebrew/bin:\(path)"
        }
        return env
    }
}
