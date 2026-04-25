import Foundation

/// Extracts plain text from markdown files, stripping YAML frontmatter.
enum MarkdownExtractor {

    static func extractText(from url: URL) -> (title: String?, content: String)? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var content = trimmed
        var title: String?

        // Strip YAML frontmatter (--- ... ---)
        if content.hasPrefix("---") {
            let lines = content.components(separatedBy: "\n")
            var endIndex = -1
            for (i, line) in lines.enumerated() where i > 0 {
                if line.trimmingCharacters(in: .whitespaces) == "---" {
                    endIndex = i
                    break
                }
            }
            if endIndex > 0 {
                // Extract title from frontmatter if present
                for line in lines[1..<endIndex] {
                    let parts = line.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 {
                        let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                        let value = parts[1].trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        if key == "title" && !value.isEmpty {
                            title = value
                        }
                    }
                }
                content = lines[(endIndex + 1)...].joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Extract title from first # heading if not found in frontmatter
        if title == nil {
            let lines = content.components(separatedBy: "\n")
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                if trimmedLine.hasPrefix("# ") {
                    title = String(trimmedLine.dropFirst(2))
                    break
                }
            }
        }

        // Fallback title from filename
        if title == nil {
            title = url.deletingPathExtension().lastPathComponent
        }

        return (title, content)
    }
}
