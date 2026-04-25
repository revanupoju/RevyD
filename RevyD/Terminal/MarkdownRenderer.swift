import AppKit

/// Converts basic markdown to NSAttributedString for chat bubbles.
/// Supports: **bold**, *italic*, `code`, - bullet lists, ## headings, \n paragraphs
enum MarkdownRenderer {

    static func render(_ markdown: String, fontSize: CGFloat = 13, textColor: NSColor = .labelColor) -> NSAttributedString {
        let result = NSMutableAttributedString()

        let baseFont = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        let boldFont = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let italicFont = NSFont.systemFont(ofSize: fontSize, weight: .light)
        let codeFont = NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular)
        let headingFont = NSFont.systemFont(ofSize: fontSize + 1, weight: .bold)
        let subheadingFont = NSFont.systemFont(ofSize: fontSize, weight: .bold)

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: textColor
        ]

        let lines = markdown.components(separatedBy: "\n")
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 4
        paragraphStyle.lineSpacing = 2

        let bulletStyle = NSMutableParagraphStyle()
        bulletStyle.paragraphSpacing = 2
        bulletStyle.lineSpacing = 1
        bulletStyle.headIndent = 16
        bulletStyle.firstLineHeadIndent = 0

        // Pre-process: convert markdown tables to clean formatted text
        var processedLines = preprocessTables(lines)

        for (i, line) in processedLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if i > 0 {
                result.append(NSAttributedString(string: "\n"))
            }

            // Skip empty lines but keep spacing
            if trimmed.isEmpty {
                continue
            }

            // Horizontal rule ---
            if trimmed.allSatisfy({ $0 == "-" || $0 == " " }) && trimmed.filter({ $0 == "-" }).count >= 3 {
                let hrStyle = NSMutableParagraphStyle()
                hrStyle.paragraphSpacing = 6
                result.append(NSAttributedString(string: "─────────────────────────", attributes: [
                    .font: NSFont.systemFont(ofSize: 8),
                    .foregroundColor: textColor.withAlphaComponent(0.2),
                    .paragraphStyle: hrStyle
                ]))
                continue
            }

            // Table separator line (|---|---|)
            if trimmed.hasPrefix("|") && trimmed.contains("---") {
                continue  // skip, already handled in preprocessing
            }

            // Heading ###
            if trimmed.hasPrefix("### ") {
                let text = String(trimmed.dropFirst(4))
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraphStyle
                ]
                result.append(NSAttributedString(string: "\n\(text)", attributes: attrs))
                continue
            }

            // Heading ##
            if trimmed.hasPrefix("## ") {
                let text = String(trimmed.dropFirst(3))
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: subheadingFont,
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraphStyle
                ]
                result.append(NSAttributedString(string: text, attributes: attrs))
                continue
            }

            // Heading #
            if trimmed.hasPrefix("# ") {
                let text = String(trimmed.dropFirst(2))
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: headingFont,
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraphStyle
                ]
                result.append(NSAttributedString(string: text, attributes: attrs))
                continue
            }

            // Bullet point
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") {
                let text = String(trimmed.dropFirst(2))
                let bullet = NSMutableAttributedString(string: "  •  ", attributes: [
                    .font: baseFont,
                    .foregroundColor: textColor.withAlphaComponent(0.5),
                    .paragraphStyle: bulletStyle
                ])
                bullet.append(renderInlineMarkdown(text, baseFont: baseFont, boldFont: boldFont,
                                                    italicFont: italicFont, codeFont: codeFont,
                                                    textColor: textColor))
                result.append(bullet)
                continue
            }

            // Numbered list
            if let range = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                let number = String(trimmed[range])
                let text = String(trimmed[range.upperBound...])
                let numAttr = NSMutableAttributedString(string: "  \(number)", attributes: [
                    .font: baseFont,
                    .foregroundColor: textColor.withAlphaComponent(0.5),
                    .paragraphStyle: bulletStyle
                ])
                numAttr.append(renderInlineMarkdown(text, baseFont: baseFont, boldFont: boldFont,
                                                     italicFont: italicFont, codeFont: codeFont,
                                                     textColor: textColor))
                result.append(numAttr)
                continue
            }

            // Regular line — process inline markdown
            var attrs = baseAttributes
            attrs[.paragraphStyle] = paragraphStyle
            let rendered = renderInlineMarkdown(trimmed, baseFont: baseFont, boldFont: boldFont,
                                                 italicFont: italicFont, codeFont: codeFont,
                                                 textColor: textColor)
            result.append(rendered)
        }

        return result
    }

    /// Convert markdown tables to clean formatted lines
    private static func preprocessTables(_ lines: [String]) -> [String] {
        var output: [String] = []
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            // Detect table: line starts with | and has multiple |
            if trimmed.hasPrefix("|") && trimmed.filter({ $0 == "|" }).count >= 3 {
                let cells = trimmed.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                // Skip separator rows (|---|---|)
                if !cells.allSatisfy({ $0.allSatisfy({ $0 == "-" || $0 == ":" || $0 == " " }) }) {
                    // Check if this is a header row (next line is separator)
                    let isHeader = i + 1 < lines.count && lines[i + 1].contains("---")
                    if isHeader {
                        // Format as bold header
                        output.append("**\(cells.joined(separator: "  ·  "))**")
                        i += 2 // skip separator
                        continue
                    } else {
                        // Format as bullet row
                        output.append("  •  \(cells.joined(separator: "  ·  "))")
                    }
                }
            } else {
                output.append(lines[i])
            }
            i += 1
        }
        return output
    }

    /// Process inline markdown: **bold**, *italic*, `code`
    private static func renderInlineMarkdown(_ text: String, baseFont: NSFont, boldFont: NSFont,
                                              italicFont: NSFont, codeFont: NSFont,
                                              textColor: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var remaining = text

        while !remaining.isEmpty {
            // **bold**
            if let boldRange = remaining.range(of: #"\*\*(.+?)\*\*"#, options: .regularExpression) {
                // Add text before the match
                let before = String(remaining[remaining.startIndex..<boldRange.lowerBound])
                if !before.isEmpty {
                    result.append(NSAttributedString(string: before, attributes: [
                        .font: baseFont, .foregroundColor: textColor
                    ]))
                }
                // Add bold text
                let matched = String(remaining[boldRange])
                let boldText = String(matched.dropFirst(2).dropLast(2))
                result.append(NSAttributedString(string: boldText, attributes: [
                    .font: boldFont, .foregroundColor: textColor
                ]))
                remaining = String(remaining[boldRange.upperBound...])
                continue
            }

            // `code`
            if let codeRange = remaining.range(of: #"`(.+?)`"#, options: .regularExpression) {
                let before = String(remaining[remaining.startIndex..<codeRange.lowerBound])
                if !before.isEmpty {
                    result.append(NSAttributedString(string: before, attributes: [
                        .font: baseFont, .foregroundColor: textColor
                    ]))
                }
                let matched = String(remaining[codeRange])
                let codeText = String(matched.dropFirst(1).dropLast(1))
                result.append(NSAttributedString(string: codeText, attributes: [
                    .font: codeFont,
                    .foregroundColor: textColor.withAlphaComponent(0.85),
                    .backgroundColor: NSColor.white.withAlphaComponent(0.06)
                ]))
                remaining = String(remaining[codeRange.upperBound...])
                continue
            }

            // *italic*
            if let italicRange = remaining.range(of: #"\*(.+?)\*"#, options: .regularExpression) {
                let before = String(remaining[remaining.startIndex..<italicRange.lowerBound])
                if !before.isEmpty {
                    result.append(NSAttributedString(string: before, attributes: [
                        .font: baseFont, .foregroundColor: textColor
                    ]))
                }
                let matched = String(remaining[italicRange])
                let italicText = String(matched.dropFirst(1).dropLast(1))
                result.append(NSAttributedString(string: italicText, attributes: [
                    .font: italicFont, .foregroundColor: textColor.withAlphaComponent(0.85)
                ]))
                remaining = String(remaining[italicRange.upperBound...])
                continue
            }

            // No more inline markdown — add rest as plain text
            result.append(NSAttributedString(string: remaining, attributes: [
                .font: baseFont, .foregroundColor: textColor
            ]))
            break
        }

        return result
    }
}
