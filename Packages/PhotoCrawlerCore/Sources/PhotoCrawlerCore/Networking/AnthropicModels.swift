import Foundation

// MARK: - Request Types

/// Top-level request body for the Anthropic Messages API.
public struct MessagesRequest: Encodable, Sendable {
    public let model: String
    public let maxTokens: Int
    public let system: String?
    public let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
    }

    public init(model: String, maxTokens: Int, system: String? = nil, messages: [Message]) {
        self.model = model
        self.maxTokens = maxTokens
        self.system = system
        self.messages = messages
    }
}

/// A single message in the conversation.
public struct Message: Encodable, Sendable {
    public let role: String
    public let content: [ContentBlock]

    public init(role: String, content: [ContentBlock]) {
        self.role = role
        self.content = content
    }
}

/// A content block within a message (text or image).
public enum ContentBlock: Encodable, Sendable {
    case text(String)
    case image(mediaType: String, base64Data: String)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
    }

    enum SourceCodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let mediaType, let base64Data):
            try container.encode("image", forKey: .type)
            var sourceContainer = container.nestedContainer(keyedBy: SourceCodingKeys.self, forKey: .source)
            try sourceContainer.encode("base64", forKey: .type)
            try sourceContainer.encode(mediaType, forKey: .mediaType)
            try sourceContainer.encode(base64Data, forKey: .data)
        }
    }
}

// MARK: - Response Types

/// Top-level response from the Anthropic Messages API.
public struct MessagesResponse: Decodable, Sendable {
    public let id: String
    public let type: String
    public let role: String
    public let content: [ResponseContentBlock]
    public let model: String
    public let stopReason: String?
    public let usage: Usage

    enum CodingKeys: String, CodingKey {
        case id, type, role, content, model
        case stopReason = "stop_reason"
        case usage
    }

    /// Extracts the first text block content as a string.
    public var textContent: String? {
        content.compactMap { block in
            if case .text(let text) = block { return text }
            return nil
        }.first
    }
}

/// A content block in the API response.
public enum ResponseContentBlock: Decodable, Sendable {
    case text(String)
    case other(String)

    enum CodingKeys: String, CodingKey {
        case type
        case text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        if type == "text" {
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        } else {
            self = .other(type)
        }
    }
}

/// Token usage information.
public struct Usage: Decodable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

// MARK: - Error Types

/// Error response from the Anthropic API.
public struct AnthropicErrorResponse: Decodable, Sendable {
    public let type: String
    public let error: AnthropicErrorDetail
}

public struct AnthropicErrorDetail: Decodable, Sendable {
    public let type: String
    public let message: String
}

// MARK: - Extraction JSON Schema

/// The structured JSON response expected from Claude for content extraction.
public struct ClaudeExtractionResponse: Sendable {
    public let contentType: String
    public let sourceTitle: String
    public let sourceAuthor: String?
    public let sourceApp: String?
    public let chapter: String?
    public let section: String?
    public let page: String?
    public let extractedText: String
    public let summary: String
    public let language: String
    public let tags: [String]
    public let highlights: [Highlight]

    enum CodingKeys: String, CodingKey {
        case contentType = "content_type"
        case sourceTitle = "source_title"
        case sourceAuthor = "source_author"
        case sourceApp = "source_app"
        case chapter, section, page
        case extractedText = "extracted_text"
        case summary, language, tags, highlights
    }
}

/// A highlighted or underlined passage detected in the image.
public struct Highlight: Codable, Sendable {
    public let text: String
    public let style: String // "highlight", "underline", "circled", "bracket"

    public init(text: String, style: String) {
        self.text = text
        self.style = style
    }
}

extension ClaudeExtractionResponse: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contentType = (try? container.decode(String.self, forKey: .contentType)) ?? "unknown"
        sourceTitle = (try? container.decode(String.self, forKey: .sourceTitle)) ?? "Unknown"
        sourceAuthor = try? container.decode(String.self, forKey: .sourceAuthor)
        sourceApp = try? container.decode(String.self, forKey: .sourceApp)
        chapter = try? container.decode(String.self, forKey: .chapter)
        section = try? container.decode(String.self, forKey: .section)
        page = try? container.decode(String.self, forKey: .page)
        extractedText = (try? container.decode(String.self, forKey: .extractedText)) ?? ""
        summary = (try? container.decode(String.self, forKey: .summary)) ?? ""
        language = (try? container.decode(String.self, forKey: .language)) ?? "en"
        tags = (try? container.decode([String].self, forKey: .tags)) ?? []
        highlights = (try? container.decode([Highlight].self, forKey: .highlights)) ?? []
    }
}

extension ClaudeExtractionResponse: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contentType, forKey: .contentType)
        try container.encode(sourceTitle, forKey: .sourceTitle)
        try container.encodeIfPresent(sourceAuthor, forKey: .sourceAuthor)
        try container.encodeIfPresent(sourceApp, forKey: .sourceApp)
        try container.encodeIfPresent(chapter, forKey: .chapter)
        try container.encodeIfPresent(section, forKey: .section)
        try container.encodeIfPresent(page, forKey: .page)
        try container.encode(extractedText, forKey: .extractedText)
        try container.encode(summary, forKey: .summary)
        try container.encode(language, forKey: .language)
        try container.encode(tags, forKey: .tags)
        try container.encode(highlights, forKey: .highlights)
    }
}
