import Foundation

/// Generates Obsidian-compatible markdown files from extraction results.
public struct MarkdownGenerator: Sendable {

    public init() {}

    /// Generate markdown content with YAML frontmatter from an extraction result.
    public func generate(from extraction: ExtractionResult, capturedDate: Date) -> String {
        var lines: [String] = []

        // YAML Frontmatter
        lines.append("---")
        lines.append("source: \"\(escapeYAML(extraction.source.title))\"")
        lines.append("captured: \(iso8601(capturedDate))")
        lines.append("---")
        lines.append("")

        // Title
        let title = buildTitle(from: extraction)
        lines.append("# \(title)")
        lines.append("")

        // Extracted text with inline highlights
        var text = extraction.extractedText
        for highlight in extraction.highlights {
            let marker = inlineMarker(for: highlight)
            text = text.replacingOccurrences(of: highlight.text, with: marker)
        }
        lines.append(text)
        lines.append("")

        // Summary
        if !extraction.summary.isEmpty {
            lines.append("> **Summary:** \(extraction.summary)")
            lines.append("")
        }

        lines.append("")

        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private func buildTitle(from extraction: ExtractionResult) -> String {
        var parts: [String] = []

        parts.append(extraction.source.title)

        if let chapter = extraction.location.chapter {
            parts.append("— \(chapter)")
        }

        if let page = extraction.location.page {
            parts.append("(p. \(page))")
        }

        return parts.joined(separator: " ")
    }

    private func inlineMarker(for highlight: Highlight) -> String {
        switch highlight.style {
        case "underline":
            return "<u>\(highlight.text)</u>"
        case "circled", "bracket":
            return "**[\(highlight.text)]**"
        default: // "highlight" and fallback
            return "==\(highlight.text)=="
        }
    }

    private func escapeYAML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func dateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
