import Foundation

/// Categories of learning content that PhotoCrawler can detect and process.
public enum ContentCategory: String, Codable, CaseIterable, Sendable {
    case bookPage = "book_page"
    case article = "article"
    case duolingo = "duolingo"
    case codeSnippet = "code_snippet"
    case flashcard = "flashcard"
    case notes = "notes"
    case unknown = "unknown"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .bookPage: return "Book Page"
        case .article: return "Article"
        case .duolingo: return "Duolingo"
        case .codeSnippet: return "Code Snippet"
        case .flashcard: return "Flashcard"
        case .notes: return "Notes"
        case .unknown: return "Unknown"
        }
    }

    /// Directory name used in the vault folder structure.
    public var directoryName: String {
        rawValue
    }
}
