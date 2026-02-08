import Foundation

/// Generates Obsidian-compatible markdown files from extraction results.
public struct MarkdownGenerator: Sendable {

    public init() {}

    /// Generate a full markdown document with YAML frontmatter.
    public func generateDocument(from extraction: ExtractionResult, capturedDate: Date, assetId: String) -> String {
        var lines: [String] = []

        lines.append("---")
        lines.append("title: \"\(escapeYAML(extraction.title))\"")
        lines.append("category: \"\(escapeYAML(extraction.category))\"")
        lines.append("captured: \(iso8601(capturedDate))")
        lines.append("asset_ids: [\"\(escapeYAML(assetId))\"]")
        lines.append("---")
        lines.append("")

        lines.append(extraction.content)
        lines.append("")

        return lines.joined(separator: "\n")
    }

    /// Generate a block suitable for appending into an existing note.
    public func generateAppendBlock(from extraction: ExtractionResult, capturedDate: Date, assetId: String) -> String {
        extraction.content
    }

    // MARK: - Private Helpers

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
}
