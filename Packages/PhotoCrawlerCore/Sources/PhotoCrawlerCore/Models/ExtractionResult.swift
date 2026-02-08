import Foundation

/// Result of the Claude API extraction pass.
public struct ExtractionResult: Codable, Sendable, Equatable {
    /// User-defined category name (or "default").
    public let category: String

    /// Best-effort title for the note.
    public let title: String

    /// The formatted markdown content to write.
    public let content: String

    /// Concrete write plan returned by the model.
    public let writePlan: WritePlan

    public init(category: String, title: String, content: String, writePlan: WritePlan) {
        self.category = category
        self.title = title
        self.content = content
        self.writePlan = writePlan
    }
}
