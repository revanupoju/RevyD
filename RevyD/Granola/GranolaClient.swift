import Foundation

/// Reads meeting data directly from Granola's local cache file.
/// Granola stores all meeting data in ~/Library/Application Support/Granola/cache-v6.json.
/// This is the most reliable approach — works offline, no auth needed, instant access.
final class GranolaClient {

    enum GranolaError: Error, LocalizedError {
        case granolaNotInstalled
        case cacheNotFound
        case cacheUnreadable(String)
        case noMeetings

        var errorDescription: String? {
            switch self {
            case .granolaNotInstalled: return "Granola is not installed"
            case .cacheNotFound: return "Granola cache file not found. Make sure Granola is installed and has been opened."
            case .cacheUnreadable(let msg): return "Could not read Granola cache: \(msg)"
            case .noMeetings: return "No meetings found in Granola"
            }
        }
    }

    private static let cachePath: String = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Granola/cache-v6.json").path
    }()

    /// Check if Granola is installed and has data
    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: cachePath)
    }

    // MARK: - Read Meetings

    /// Read all meetings from Granola's local cache
    func readAllMeetings() throws -> [GranolaLocalMeeting] {
        let cache = try readCache()
        guard let state = cache["cache"] as? [String: Any],
              let stateData = state["state"] as? [String: Any],
              let documents = stateData["documents"] as? [String: [String: Any]] else {
            throw GranolaError.cacheUnreadable("Missing documents in cache structure")
        }

        var meetings: [GranolaLocalMeeting] = []

        for (docId, doc) in documents {
            // Only include actual meetings (not scratchpads)
            let docType = doc["type"] as? String
            let isScratchpad = doc["is_scratchpad"] as? Bool ?? false
            if isScratchpad { continue }

            let title = doc["title"] as? String ?? "Untitled Meeting"
            let createdAt = doc["created_at"] as? String ?? ""
            let updatedAt = doc["updated_at"] as? String ?? ""
            let deletedAt = doc["deleted_at"] as? String

            // Skip deleted meetings
            if deletedAt != nil { continue }

            // Extract summary
            let summary = doc["summary"] as? String
            let notesMarkdown = doc["notes_markdown"] as? String
            let notesPlain = doc["notes_plain"] as? String

            // Extract people/attendees
            var attendees: [GranolaLocalAttendee] = []
            if let people = doc["people"] as? [String: Any] {
                // Creator
                if let creator = people["creator"] as? [String: Any] {
                    let name = Self.extractPersonName(from: creator)
                    let email = creator["email"] as? String
                    if let name {
                        attendees.append(GranolaLocalAttendee(name: name, email: email, role: "creator"))
                    }
                }

                // Attendees array
                if let attendeeList = people["attendees"] as? [[String: Any]] {
                    for att in attendeeList {
                        let name = Self.extractPersonName(from: att)
                        let email = att["email"] as? String
                        let displayName = name ?? email?.components(separatedBy: "@").first ?? "Unknown"
                        attendees.append(GranolaLocalAttendee(name: displayName, email: email, role: "attendee"))
                    }
                }
            }

            // Extract calendar event info
            var calendarEventTitle: String?
            var calendarAttendees: [GranolaLocalAttendee] = []
            if let calEvent = doc["google_calendar_event"] as? [String: Any] {
                calendarEventTitle = calEvent["summary"] as? String
                if let calAttendees = calEvent["attendees"] as? [[String: Any]] {
                    for att in calAttendees {
                        let email = att["email"] as? String ?? ""
                        let displayName = att["displayName"] as? String ?? email
                        if !calendarAttendees.contains(where: { $0.email == email }) {
                            calendarAttendees.append(GranolaLocalAttendee(name: displayName, email: email, role: "attendee"))
                        }
                    }
                }
            }

            // Merge attendees from people and calendar
            let allAttendees = mergeAttendees(people: attendees, calendar: calendarAttendees)

            let meeting = GranolaLocalMeeting(
                id: docId,
                title: title,
                createdAt: createdAt,
                updatedAt: updatedAt,
                summary: summary,
                notesMarkdown: notesMarkdown,
                notesPlain: notesPlain,
                attendees: allAttendees,
                type: docType,
                validMeeting: doc["valid_meeting"] as? Bool ?? true
            )

            meetings.append(meeting)
        }

        // Sort by created_at descending
        meetings.sort { $0.createdAt > $1.createdAt }

        return meetings
    }

    /// Read transcripts
    func readTranscript(meetingId: String) throws -> [GranolaTranscriptChunk]? {
        let cache = try readCache()
        guard let state = cache["cache"] as? [String: Any],
              let stateData = state["state"] as? [String: Any],
              let transcripts = stateData["transcripts"] as? [String: Any],
              let chunks = transcripts[meetingId] as? [[String: Any]] else {
            return nil
        }

        return chunks.map { chunk in
            GranolaTranscriptChunk(
                text: chunk["text"] as? String ?? "",
                speaker: chunk["speaker"] as? String,
                timestamp: chunk["timestamp"] as? String
            )
        }
    }

    // MARK: - Cache File Access

    private func readCache() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: Self.cachePath) else {
            throw GranolaError.cacheNotFound
        }

        guard let data = FileManager.default.contents(atPath: Self.cachePath) else {
            throw GranolaError.cacheUnreadable("Could not read file")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GranolaError.cacheUnreadable("Invalid JSON")
        }

        return json
    }

    /// Get the cache file modification date (for change detection)
    func cacheModifiedDate() -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: Self.cachePath),
              let modDate = attrs[.modificationDate] as? Date else { return nil }
        return modDate
    }

    // MARK: - Helpers

    /// Extract person name from Granola's nested structure:
    /// Top-level "name" field, or details.person.name.fullName
    private static func extractPersonName(from dict: [String: Any]) -> String? {
        // Try top-level name first
        if let name = dict["name"] as? String, !name.isEmpty {
            return name
        }
        // Try details.person.name.fullName
        if let details = dict["details"] as? [String: Any],
           let person = details["person"] as? [String: Any],
           let nameObj = person["name"] as? [String: Any],
           let fullName = nameObj["fullName"] as? String, !fullName.isEmpty {
            return fullName
        }
        // Try displayName
        if let displayName = dict["displayName"] as? String, !displayName.isEmpty {
            return displayName
        }
        return nil
    }

    private func mergeAttendees(people: [GranolaLocalAttendee], calendar: [GranolaLocalAttendee]) -> [GranolaLocalAttendee] {
        var merged = people
        for calAtt in calendar {
            let exists = merged.contains { existing in
                if let e1 = existing.email, let e2 = calAtt.email, !e1.isEmpty, !e2.isEmpty {
                    return e1.lowercased() == e2.lowercased()
                }
                return existing.name.lowercased() == calAtt.name.lowercased()
            }
            if !exists {
                merged.append(calAtt)
            }
        }
        return merged
    }
}

// MARK: - Local Models

struct GranolaLocalMeeting {
    let id: String
    let title: String
    let createdAt: String
    let updatedAt: String
    let summary: String?
    let notesMarkdown: String?
    let notesPlain: String?
    let attendees: [GranolaLocalAttendee]
    let type: String?
    let validMeeting: Bool
}

struct GranolaLocalAttendee {
    let name: String
    let email: String?
    let role: String
}
