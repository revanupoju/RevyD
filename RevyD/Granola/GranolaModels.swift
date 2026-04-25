import Foundation

// MARK: - Granola MCP Response Models

/// Response from listing meetings via Claude Code + Granola MCP
struct GranolaMeetingListItem: Codable {
    let id: String
    let title: String
    let created_at: String?
    let updated_at: String?
    let summary_text: String?
    let attendees: [GranolaAttendee]?
}

struct GranolaAttendee: Codable {
    let name: String
    let email: String?
}

struct GranolaMeetingDetail: Codable {
    let id: String
    let title: String
    let created_at: String?
    let updated_at: String?
    let summary_markdown: String?
    let summary_text: String?
    let notes_markdown: String?
    let notes_plain: String?
    let attendees: [GranolaAttendee]?
}

struct GranolaTranscriptChunk: Codable {
    let text: String
    let speaker: String?
    let timestamp: String?
}
