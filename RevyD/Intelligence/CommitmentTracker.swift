import Foundation

/// Extracts commitments from debrief results and stores them in the database.
/// Links commitments to people for cross-meeting tracking.
final class CommitmentTracker {
    private let commitmentStore = CommitmentStore()
    private let personStore = PersonStore()
    private let knowledgeIndex = KnowledgeIndex()

    /// Process a debrief result — extract and store all commitments and decisions
    func processDebrief(_ result: DebriefResult, meetingId: String, meeting: Meeting) {
        let now = ISO8601DateFormatter().string(from: Date())

        // Store commitments given
        if let given = result.commitments_given {
            for c in given {
                let ownerPerson = personStore.findOrCreate(name: c.by, email: nil)
                let targetPerson = c.to.flatMap { personStore.findOrCreate(name: $0, email: nil) }

                let commitment = Commitment(
                    id: UUID().uuidString,
                    meetingId: meetingId,
                    ownerPersonId: ownerPerson.id,
                    ownerName: c.by,
                    targetPersonId: targetPerson?.id,
                    targetName: c.to,
                    description: c.description,
                    status: "open",
                    dueDate: c.due_date,
                    createdAt: now,
                    updatedAt: now,
                    completedAt: nil,
                    sourceQuote: c.source_quote
                )
                commitmentStore.insert(commitment)
                knowledgeIndex.indexCommitment(commitment)
            }
        }

        // Store commitments received
        if let received = result.commitments_received {
            for c in received {
                let ownerPerson = personStore.findOrCreate(name: c.by, email: nil)
                let targetPerson = c.to.flatMap { personStore.findOrCreate(name: $0, email: nil) }

                let commitment = Commitment(
                    id: UUID().uuidString,
                    meetingId: meetingId,
                    ownerPersonId: ownerPerson.id,
                    ownerName: c.by,
                    targetPersonId: targetPerson?.id,
                    targetName: c.to,
                    description: c.description,
                    status: "open",
                    dueDate: c.due_date,
                    createdAt: now,
                    updatedAt: now,
                    completedAt: nil,
                    sourceQuote: c.source_quote
                )
                commitmentStore.insert(commitment)
                knowledgeIndex.indexCommitment(commitment)
            }
        }

        // Store decisions
        if let decisions = result.decisions {
            let db = RevyDatabase.shared
            for d in decisions {
                let id = UUID().uuidString
                db.run("""
                    INSERT OR REPLACE INTO decisions (id, meeting_id, description, context, created_at)
                    VALUES (?, ?, ?, ?, ?)
                """, bindings: [id, meetingId, d.description, d.context, now])
            }
        }

        // Store action items as commitments too (they're effectively the same)
        if let actions = result.action_items {
            for a in actions {
                let ownerPerson = personStore.findOrCreate(name: a.owner, email: nil)

                let commitment = Commitment(
                    id: UUID().uuidString,
                    meetingId: meetingId,
                    ownerPersonId: ownerPerson.id,
                    ownerName: a.owner,
                    targetPersonId: nil,
                    targetName: nil,
                    description: a.description,
                    status: "open",
                    dueDate: a.due_date,
                    createdAt: now,
                    updatedAt: now,
                    completedAt: nil,
                    sourceQuote: nil
                )
                commitmentStore.insert(commitment)
                knowledgeIndex.indexCommitment(commitment)
            }
        }

        SessionDebugLogger.log("commitments",
            "Extracted \(result.commitments_given?.count ?? 0) given, " +
            "\(result.commitments_received?.count ?? 0) received, " +
            "\(result.action_items?.count ?? 0) actions, " +
            "\(result.decisions?.count ?? 0) decisions from \(meeting.title)")
    }
}
