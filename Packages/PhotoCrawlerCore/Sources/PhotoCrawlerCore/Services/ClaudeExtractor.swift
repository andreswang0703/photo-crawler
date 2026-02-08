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
        classificationResult: ClassificationResult,
        assetId: String,
        capturedDate: Date
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
        let userPrompt = buildUserPrompt(
            classification: classificationResult,
            assetId: assetId,
            capturedDate: capturedDate
        )

        if shouldDebugPrompt() {
            print("----- CLAUDE_SYSTEM_PROMPT_START -----")
            print(systemPrompt)
            print("----- CLAUDE_SYSTEM_PROMPT_END -----")
            print("----- CLAUDE_USER_PROMPT_START -----")
            print(userPrompt)
            print("----- CLAUDE_USER_PROMPT_END -----")
        }

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

        if shouldDebugJSON() {
            print("----- CLAUDE_JSON_START -----")
            print(textContent)
            print("----- CLAUDE_JSON_END -----")
        }

        return try parseExtractionResponse(textContent)
    }

    // MARK: - Prompt Construction

    private func buildSystemPrompt() -> String {
        let rulesBlock = buildCategoryRulesBlock()
        let globalRulesBlock = buildGlobalRulesBlock()

        return """
        You are a content extraction assistant. You analyze images of text-based learning \
        content and return structured JSON that includes a concrete write plan.

        GLOBAL RULES:
        \(globalRulesBlock)

        CATEGORY RULES:
        \(rulesBlock)

        The category rules are written in natural language by end users. They do NOT know \
        the JSON schema. You must translate their intent into a concrete write plan. \
        If a rule is vague, choose a reasonable default that matches the intent.

        You MUST respond with valid JSON only. No markdown, no explanation, just a JSON object \
        with these fields:

        {
          "category": "string - MUST match exactly one configured category name, or \"default\"",
          "title": "string - best-effort title for the note",
          "content": "string - final markdown content (NO YAML frontmatter)",
          "write": {
            "mode": "create" | "append" | "upsert" | "skip",
            "path": "relative/path/to/note.md",
            "append_to": "optional heading or marker line (string)"
          }
        }

        CRITICAL RULES:
        - ONLY extract text that you can actually read in the image. NEVER invent, guess, or hallucinate text.
        - If a word is unclear, use [illegible] instead of guessing.
        - If you cannot read most of the text, make content include only what you can read.
        - Extract ALL legible text visible in the image, preserving paragraph structure.
        - Use \\n for line breaks within content.
        - Do NOT include YAML frontmatter in content.
        - The path MUST be relative to the vault root, with no leading "/" and no ".." segments.
        - If unsure, use the default rules and set category to "default".
        - Use the provided asset_id and captured_date if the write rule implies it.
        - If the write rule mentions language, infer it and pick a lowercase English slug \
          (e.g., japanese, spanish).
        - If the write rule mentions monthly or daily notes, derive YYYYMM or YYYY-MM-DD \
          from captured_date and place entries under an appropriate date header when appending.
        - If a global rule says to skip (e.g., "only extract book notes"), set write.mode to \
          "skip" and return empty content.
        """
    }

    private func buildCategoryRulesBlock() -> String {
        if config.categories.isEmpty {
            return """
            (No categories configured.)

            Default rules:
            - Extraction rules: \(config.defaultRules.extractionRules)
            - Write rule: \(config.defaultRules.writeRule)
            """
        }

        var lines: [String] = []
        lines.append("Available categories:")
        for rule in config.categories {
            lines.append("- Name: \(rule.name)")
            if let hint = rule.hint, !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("  Hint: \(hint)")
            }
            lines.append("  Extraction rules: \(rule.extractionRules)")
            lines.append("  Write rule: \(rule.writeRule)")
        }
        lines.append("")
        lines.append("Default rules:")
        lines.append("- Extraction rules: \(config.defaultRules.extractionRules)")
        lines.append("- Write rule: \(config.defaultRules.writeRule)")

        return lines.joined(separator: "\n")
    }

    private func buildGlobalRulesBlock() -> String {
        if config.globalRules.isEmpty {
            return "(none)"
        }
        return config.globalRules
            .map { "- \($0)" }
            .joined(separator: "\n")
    }

    private func buildUserPrompt(
        classification: ClassificationResult,
        assetId: String,
        capturedDate: Date
    ) -> String {
        return """
        Extract the text content from this image and return structured JSON.

        Asset context:
        - asset_id: \(assetId)
        - captured_date: \(iso8601(capturedDate))

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

        let category = normalizeCategory(decoded.category)
        let title = decoded.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = decoded.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let write = decoded.write ?? WritePlan(mode: .create, path: "")

        if content.isEmpty && write.mode != .skip {
            throw ExtractionError.noContent
        }

        return ExtractionResult(
            category: category,
            title: (title?.isEmpty ?? true) ? "Untitled" : title!,
            content: content,
            writePlan: write
        )
    }

    private func normalizeCategory(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "default" }
        if trimmed.lowercased() == "default" { return "default" }

        if let match = config.categories.first(where: { $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame }) {
            return match.name
        }

        return "default"
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func shouldDebugJSON() -> Bool {
        let value = ProcessInfo.processInfo.environment["PHOTO_CRAWLER_DEBUG_JSON"] ?? ""
        return value == "1" || value.lowercased() == "true"
    }

    private func shouldDebugPrompt() -> Bool {
        let value = ProcessInfo.processInfo.environment["PHOTO_CRAWLER_DEBUG_PROMPT"] ?? ""
        return value == "1" || value.lowercased() == "true"
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
