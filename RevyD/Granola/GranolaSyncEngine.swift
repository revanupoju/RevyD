import Foundation

/// Syncs meetings from Granola's local cache into RevyD's SQLite database.
/// Reads directly from ~/Library/Application Support/Granola/cache-v6.json.
/// Instant, offline, no auth needed.
final class GranolaSyncEngine {
    private let client = GranolaClient()
    private let meetingStore = MeetingStore()
    private let personStore = PersonStore()
    private let knowledgeIndex = KnowledgeIndex()
    private var syncTimer: Timer?
    private var isSyncing = false
    private var lastCacheModDate: Date?

    var onNewMeetingsFound: (([Meeting]) -> Void)?
    var onSyncComplete: ((Int) -> Void)?
    var onSyncError: ((Error) -> Void)?

    // MARK: - Lifecycle

    func startPeriodicSync(interval: TimeInterval = 60) {
        // Sync immediately
        syncNow()

        // Then poll for cache changes every minute
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.syncIfCacheChanged()
        }
    }

    func stopSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    /// Only sync if the cache file has been modified since last check
    private func syncIfCacheChanged() {
        guard let currentModDate = client.cacheModifiedDate() else { return }
        if let lastDate = lastCacheModDate, currentModDate <= lastDate { return }
        syncNow()
    }

    func syncNow() {
        guard !isSyncing else { return }
        isSyncing = true
        SessionDebugLogger.log("sync", "Starting Granola sync from local cache...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            do {
                let granolaItems = try self.client.readAllMeetings()
                let newMeetings = self.processSyncResults(granolaItems)
                self.lastCacheModDate = self.client.cacheModifiedDate()

                DispatchQueue.main.async {
                    self.isSyncing = false
                    SessionDebugLogger.log("sync", "Sync complete: \(newMeetings.count) new/updated out of \(granolaItems.count) total meetings")
                    AppSettings.granolaLastSyncDate = Date()

                    if !newMeetings.isEmpty {
                        self.onNewMeetingsFound?(newMeetings)
                    }
                    self.onSyncComplete?(newMeetings.count)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isSyncing = false
                    SessionDebugLogger.log("sync", "Sync failed: \(error.localizedDescription)")
                    self.onSyncError?(error)
                }
            }
        }
    }

    // MARK: - Processing

    private func processSyncResults(_ items: [GranolaLocalMeeting]) -> [Meeting] {
        let now = ISO8601DateFormatter().string(from: Date())
        var newMeetings: [Meeting] = []

        for item in items {
            let existing = meetingStore.get(id: item.id)

            // Skip if we have it and it hasn't changed
            if let existing, existing.granolaUpdatedAt == item.updatedAt {
                continue
            }

            // Encode attendees as JSON
            let attendeeModels = item.attendees.map { MeetingAttendee(name: $0.name, email: $0.email) }
            let attendeesJson = (try? JSONEncoder().encode(attendeeModels)).flatMap { String(data: $0, encoding: .utf8) }

            // Read transcript if available
            var transcriptText: String?
            if let chunks = try? client.readTranscript(meetingId: item.id), !chunks.isEmpty {
                transcriptText = chunks.map { chunk in
                    if let speaker = chunk.speaker, !speaker.isEmpty {
                        return "[\(speaker)] \(chunk.text)"
                    }
                    return chunk.text
                }.joined(separator: "\n")
            }

            let meeting = Meeting(
                id: item.id,
                title: item.title,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                summaryMarkdown: item.summary,
                notesMarkdown: item.notesMarkdown,
                transcriptText: transcriptText ?? existing?.transcriptText,
                attendeesJson: attendeesJson,
                debriefJson: existing?.debriefJson,
                debriefStatus: existing?.debriefStatus ?? "pending",
                syncedAt: now,
                granolaUpdatedAt: item.updatedAt
            )

            meetingStore.upsert(meeting)
            knowledgeIndex.indexMeeting(meeting)

            // Resolve attendees into people
            for attendee in item.attendees {
                let person = personStore.findOrCreate(name: attendee.name, email: attendee.email)
                personStore.linkToMeeting(personId: person.id, meetingId: meeting.id)
            }

            newMeetings.append(meeting)
        }

        return newMeetings
    }

    deinit {
        stopSync()
    }
}
