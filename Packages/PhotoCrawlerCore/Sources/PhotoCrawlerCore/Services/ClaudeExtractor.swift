import Foundation
import CoreGraphics
import ImageIO
#if canImport(os)
import os
#endif

/// Pass 2: Sends images to the Claude API for structured content extraction.
public actor ClaudeExtractor {
    private let client: AnthropicClient
    private let config: CrawlerConfiguration
    private var activeTasks: Int = 0

    #if canImport(os)
    private let logger = Logger(subsystem: "com.photocrawler", category: "ClaudeExtractor")
    #endif

    public init(config: CrawlerConfiguration) {
        self.client = AnthropicClient(apiKey: config.apiKey)
        self.config = config
    }

    /// Extract structured content from an image using Claude.
    public func extract(
        imageData: Data,
        classificationResult: ClassificationResult
    ) async throws -> ExtractionResult {
        // Wait for a slot if at max concurrency
        while activeTasks >= config.maxConcurrentAPICalls {
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
        }

        activeTasks += 1
        defer { activeTasks -= 1 }

        let resizedData = resizeImage(data: imageData, maxDimension: config.maxImageDimension)
        let mediaType = detectMediaType(data: resizedData)

        let systemPrompt = buildSystemPrompt()
        let userPrompt = buildUserPrompt(classification: classificationResult)

        #if canImport(os)
        logger.info("Extracting content (category hint: \(classificationResult.categoryHint.rawValue))")
        #endif

        let response = try await client.extractContent(
            imageData: resizedData,
            mediaType: mediaType,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            model: config.claudeModel
        )

        guard let textContent = response.textContent else {
            throw AnthropicClientError.noTextContent
        }

        return try parseExtractionResponse(textContent)
    }

    // MARK: - Prompt Construction

    private func buildSystemPrompt() -> String {
        """
        You are a content extraction assistant. You analyze images of text-based learning \
        content (book pages, articles, Duolingo exercises, code snippets, notes) and extract \
        structured information.

        You MUST respond with valid JSON only. No markdown, no explanation, just a JSON object \
        with these fields:

        {
          "content_type": "book_page" | "article" | "duolingo" | "code_snippet" | "flashcard" | "notes" | "unknown",
          "source_title": "string - title of the book, article, or app",
          "source_author": "string or null - author name if identifiable",
          "source_app": "string or null - app name if from a specific app",
          "chapter": "string or null - chapter name/number",
          "section": "string or null - section name",
          "page": "string or null - page number",
          "extracted_text": "string - the full text content from the image, preserving paragraphs",
          "summary": "string - 1-2 sentence summary of the content",
          "language": "string - ISO 639-1 language code (e.g., en, es, fr)",
          "tags": ["array", "of", "relevant", "topic", "tags"],
          "highlights": [
            {"text": "exact highlighted or underlined passage", "style": "highlight"},
            {"text": "exact underlined passage", "style": "underline"}
          ]
        }

        CRITICAL RULES:
        - ONLY extract text that you can actually read in the image. NEVER invent, guess, or hallucinate text.
        - If a word is unclear, use [illegible] instead of guessing.
        - If you cannot read most of the text, set extracted_text to what you CAN read and note the limitation in the summary.
        - Extract ALL legible text visible in the image, preserving paragraph structure.
        - Use \\n for line breaks within extracted_text.
        - If you can't determine a field, use null.
        - Tags should be 3-7 lowercase topic keywords relevant for note organization.
        - For Duolingo: include the language being learned and the exercise type.
        - For book pages: try to identify chapter, page number, book title from headers/footers.
        - For code: identify the programming language as a tag.
        - The image may be a photo taken at an angle. Read the text as it appears, do not fabricate content.
        - HIGHLIGHTS: Look carefully for any text that is highlighted (marker/highlighter pen), underlined, circled, or bracketed by the reader. Include each such passage in the "highlights" array with the exact text and style ("highlight", "underline", "circled", "bracket"). If no annotations are visible, return an empty array.
        - The highlights array is for reader annotations only — not for printed bold/italic text.
        """
    }

    private func buildUserPrompt(classification: ClassificationResult) -> String {
        let categoryContext: String
        switch classification.categoryHint {
        case .bookPage:
            categoryContext = "This appears to be a book page or textbook. Look for chapter headings, page numbers, and paragraph text."
        case .article:
            categoryContext = "This appears to be an article or web content. Look for headlines, bylines, and publication info."
        case .duolingo:
            categoryContext = "This appears to be a Duolingo language learning exercise. Identify the language being learned and the exercise type."
        case .codeSnippet:
            categoryContext = "This appears to be code or a programming example. Identify the language and purpose."
        case .flashcard:
            categoryContext = "This appears to be a flashcard or study material."
        case .notes:
            categoryContext = "This appears to be notes or personal study content."
        case .unknown:
            categoryContext = "Analyze this image and determine what type of learning content it contains."
        }

        return """
        Extract the text content from this image and return structured JSON.

        Context: \(categoryContext)

        Respond with JSON only.
        """
    }

    // MARK: - Response Parsing

    private func parseExtractionResponse(_ text: String) throws -> ExtractionResult {
        // Strip markdown code fences if present
        var jsonText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonText.hasPrefix("```json") {
            jsonText = String(jsonText.dropFirst(7))
        } else if jsonText.hasPrefix("```") {
            jsonText = String(jsonText.dropFirst(3))
        }
        if jsonText.hasSuffix("```") {
            jsonText = String(jsonText.dropLast(3))
        }
        jsonText = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonText.data(using: .utf8) else {
            throw ExtractionError.invalidJSON("Could not convert response to data")
        }

        let decoded: ClaudeExtractionResponse
        do {
            decoded = try JSONDecoder().decode(ClaudeExtractionResponse.self, from: data)
        } catch {
            throw ExtractionError.invalidJSON("Failed to decode: \(error.localizedDescription)")
        }

        let contentType = ContentCategory(rawValue: decoded.contentType) ?? .unknown

        return ExtractionResult(
            contentType: contentType,
            source: SourceInfo(
                title: decoded.sourceTitle,
                author: decoded.sourceAuthor,
                app: decoded.sourceApp
            ),
            location: LocationInfo(
                chapter: decoded.chapter,
                section: decoded.section,
                page: decoded.page
            ),
            extractedText: decoded.extractedText,
            summary: decoded.summary,
            language: decoded.language,
            tags: decoded.tags,
            highlights: decoded.highlights
        )
    }

    // MARK: - Image Processing

    private func resizeImage(data: Data, maxDimension: Int) -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return data
        }

        let width = cgImage.width
        let height = cgImage.height
        let maxDim = max(width, height)

        guard maxDim > maxDimension else { return data }

        let scale = Double(maxDimension) / Double(maxDim)
        let newWidth = Int(Double(width) * scale)
        let newHeight = Int(Double(height) * scale)

        guard let colorSpace = cgImage.colorSpace,
              let context = CGContext(
                  data: nil,
                  width: newWidth,
                  height: newHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return data
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        guard let resizedImage = context.makeImage() else { return data }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
            return data
        }

        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
        CGImageDestinationAddImage(destination, resizedImage, options as CFDictionary)
        CGImageDestinationFinalize(destination)

        return mutableData as Data
    }

    private func detectMediaType(data: Data) -> String {
        guard data.count >= 4 else { return "image/jpeg" }

        var header = [UInt8](repeating: 0, count: 4)
        data.copyBytes(to: &header, count: 4)

        if header[0] == 0x89 && header[1] == 0x50 { return "image/png" }
        if header[0] == 0xFF && header[1] == 0xD8 { return "image/jpeg" }
        if header[0] == 0x47 && header[1] == 0x49 { return "image/gif" }
        if header[0] == 0x52 && header[1] == 0x49 { return "image/webp" }

        return "image/jpeg"
    }
}

public enum ExtractionError: LocalizedError, Sendable {
    case invalidJSON(String)
    case noContent

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail): return "Invalid JSON response: \(detail)"
        case .noContent: return "No content extracted"
        }
    }
}
