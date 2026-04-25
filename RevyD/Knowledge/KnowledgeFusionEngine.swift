import Foundation

/// Cross-references meeting content with local documents.
/// The moat: "They mentioned auth rewrite — here's what your design doc says."
final class KnowledgeFusionEngine {
    private let knowledgeIndex = KnowledgeIndex()
    private let documentStore = DocumentStore()
    private let meetingStore = MeetingStore()

    /// Given a meeting, find related documents from the knowledge base
    func findRelatedDocuments(for meeting: Meeting, limit: Int = 5) -> [DocumentMatch] {
        // Extract key terms from meeting content
        var searchTerms = meeting.title

        if let summary = meeting.summaryMarkdown {
            searchTerms += " " + summary
        }

        // Search documents
        let results = knowledgeIndex.search(query: searchTerms, entityType: "document", limit: limit)

        return results.compactMap { result in
            guard let doc = documentStore.get(id: result.entityId) else { return nil }
            return DocumentMatch(
                document: doc,
                relevanceScore: abs(result.rank),
                matchingSnippet: result.snippet
            )
        }
    }

    /// Build fusion context string for including in Claude prompts
    func buildFusionContext(for meeting: Meeting) -> String? {
        let matches = findRelatedDocuments(for: meeting)
        guard !matches.isEmpty else { return nil }

        var context = "Related documents from your knowledge base:\n"
        for match in matches {
            let title = match.document.title ?? match.document.fileName
            context += "\n## \(title)\n"
            context += "Path: \(match.document.filePath)\n"
            context += "Relevant excerpt: \(match.matchingSnippet)\n"
            context += "Content: \(String(match.document.contentText.prefix(500)))\n"
        }
        return context
    }

    /// Cross-reference: find meetings related to a document
    func findRelatedMeetings(for document: IndexedDocument, limit: Int = 5) -> [Meeting] {
        let searchTerms = (document.title ?? "") + " " + String(document.contentText.prefix(200))
        let results = knowledgeIndex.search(query: searchTerms, entityType: "meeting", limit: limit)

        return results.compactMap { result in
            meetingStore.get(id: result.entityId)
        }
    }
}

struct DocumentMatch {
    let document: IndexedDocument
    let relevanceScore: Double
    let matchingSnippet: String
}
