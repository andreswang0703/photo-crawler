import Foundation

/// Result of the Claude API extraction pass.
public struct ExtractionResult: Codable, Sendable {
    /// Detected content type.
    public let contentType: ContentCategory

    /// Source information.
    public let source: SourceInfo

    /// Location within the source.
    public let location: LocationInfo

    /// The extracted text content.
    public let extractedText: String

    /// Brief summary of the content.
    public let summary: String

    /// Detected language code (e.g., "en", "es").
    public let language: String

    /// Tags for Obsidian.
    public let tags: [String]

    /// Highlighted or underlined passages detected in the image.
    public let highlights: [Highlight]

    public init(
        contentType: ContentCategory,
        source: SourceInfo,
        location: LocationInfo,
        extractedText: String,
        summary: String,
        language: String,
        tags: [String],
        highlights: [Highlight] = []
    ) {
        self.contentType = contentType
        self.source = source
        self.location = location
        self.extractedText = extractedText
        self.summary = summary
        self.language = language
        self.tags = tags
        self.highlights = highlights
    }
}

/// Information about the content source.
public struct SourceInfo: Codable, Sendable {
    public let title: String
    public let author: String?
    public let app: String?

    public init(title: String, author: String? = nil, app: String? = nil) {
        self.title = title
        self.author = author
        self.app = app
    }
}

/// Location within the source material.
public struct LocationInfo: Codable, Sendable {
    public let chapter: String?
    public let section: String?
    public let page: String?

    public init(chapter: String? = nil, section: String? = nil, page: String? = nil) {
        self.chapter = chapter
        self.section = section
        self.page = page
    }
}
