import XCTest
@testable import PhotoCrawlerCore

final class PhotoCrawlerCoreTests: XCTestCase {

    // MARK: - Model Tests

    func testContentCategoryRawValues() {
        XCTAssertEqual(ContentCategory.bookPage.rawValue, "book_page")
        XCTAssertEqual(ContentCategory.article.rawValue, "article")
        XCTAssertEqual(ContentCategory.duolingo.rawValue, "duolingo")
        XCTAssertEqual(ContentCategory.codeSnippet.rawValue, "code_snippet")
    }

    func testContentCategoryDirectoryNames() {
        XCTAssertEqual(ContentCategory.bookPage.directoryName, "book_page")
        XCTAssertEqual(ContentCategory.duolingo.directoryName, "duolingo")
    }

    func testCrawlerConfigurationDefaults() {
        let config = CrawlerConfiguration()
        XCTAssertEqual(config.scanIntervalSeconds, 900)
        XCTAssertEqual(config.claudeModel, "claude-sonnet-4-20250514")
        XCTAssertEqual(config.minTextDensity, 0.10)
        XCTAssertEqual(config.minLineCount, 5)
        XCTAssertEqual(config.maxConcurrentAPICalls, 3)
        XCTAssertEqual(config.maxImageDimension, 1568)
        XCTAssertFalse(config.screenshotsOnly)
        XCTAssertEqual(config.initialScanDays, 30)
        XCTAssertTrue(config.categories.isEmpty)
        XCTAssertEqual(config.defaultRules.extractionRules, "Extract readable text. Add a short summary.")
        XCTAssertTrue(config.globalRules.isEmpty)
    }

    func testCrawlerConfigurationIsValid() {
        var config = CrawlerConfiguration()
        XCTAssertFalse(config.isValid)

        config.vaultPath = "/some/path"
        XCTAssertFalse(config.isValid)

        config.apiKey = "sk-test"
        XCTAssertTrue(config.isValid)
    }

    func testCrawlerConfigurationCapturesPath() {
        var config = CrawlerConfiguration()
        config.vaultPath = "/Users/test/vault"
        XCTAssertEqual(config.capturesPath, "/Users/test/vault/captures")
    }

    // MARK: - MarkdownGenerator Tests

    func testMarkdownGeneratorOutput() {
        let generator = MarkdownGenerator()
        let extraction = ExtractionResult(
            category: "BookNote",
            title: "Sapiens",
            content: "The great discovery that launched the Scientific Revolution...",
            writePlan: WritePlan(mode: .create, path: "captures/book_notes/sapiens.md")
        )

        let date = Date(timeIntervalSince1970: 1_770_000_000)
        let markdown = generator.generateDocument(from: extraction, capturedDate: date, assetId: "asset-123")

        XCTAssertTrue(markdown.contains("---"))
        XCTAssertTrue(markdown.contains("title: \"Sapiens\""))
        XCTAssertTrue(markdown.contains("category: \"BookNote\""))
        XCTAssertTrue(markdown.contains("asset_ids: [\"asset-123\"]"))
        XCTAssertTrue(markdown.contains("The great discovery"))
    }

    func testMarkdownGeneratorMinimalExtraction() {
        let generator = MarkdownGenerator()
        let extraction = ExtractionResult(
            category: "default",
            title: "Untitled",
            content: "Some text",
            writePlan: WritePlan(mode: .create, path: "")
        )

        let markdown = generator.generateDocument(from: extraction, capturedDate: Date(), assetId: "asset-1")
        XCTAssertTrue(markdown.contains("title: \"Untitled\""))
        XCTAssertTrue(markdown.contains("Some text"))
    }

    // MARK: - StateStore Tests

    func testStateStoreCreation() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try StateStore(directory: tempDir)

        let isProcessed = await store.isProcessed("test-id")
        XCTAssertFalse(isProcessed)

        await store.markProcessed("test-id")
        let isProcessedAfter = await store.isProcessed("test-id")
        XCTAssertTrue(isProcessedAfter)

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testStateStorePersistence() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        // Create and populate store
        let store1 = try StateStore(directory: tempDir)
        await store1.markProcessed("photo-123")
        await store1.incrementScanned()
        await store1.incrementExtracted()
        try await store1.save()

        // Reload store
        let store2 = try StateStore(directory: tempDir)
        let isProcessed = await store2.isProcessed("photo-123")
        XCTAssertTrue(isProcessed)

        let stats = await store2.getStats()
        XCTAssertEqual(stats.totalScanned, 1)
        XCTAssertEqual(stats.totalExtracted, 1)

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testStateStoreStats() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try StateStore(directory: tempDir)

        await store.incrementScanned()
        await store.incrementScanned()
        await store.incrementClassified()
        await store.incrementExtracted()
        await store.incrementWritten()
        await store.incrementErrors()

        let stats = await store.getStats()
        XCTAssertEqual(stats.totalScanned, 2)
        XCTAssertEqual(stats.totalClassified, 1)
        XCTAssertEqual(stats.totalExtracted, 1)
        XCTAssertEqual(stats.totalWritten, 1)
        XCTAssertEqual(stats.totalErrors, 1)

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - VaultWriter Tests

    func testVaultWriterSanitization() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create a fake .obsidian directory
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent(".obsidian"),
            withIntermediateDirectories: true
        )

        var config = CrawlerConfiguration()
        config.vaultPath = tempDir.path

        let writer = VaultWriter(config: config)
        let extraction = ExtractionResult(
            category: "BookNote",
            title: "Sapiens: A Brief History",
            content: "Test content",
            writePlan: WritePlan(
                mode: .create,
                path: "captures/book_notes/Sapiens: A Brief History.md"
            )
        )

        let path = try writer.write(extraction: extraction, capturedDate: Date(), assetId: "asset-123")

        XCTAssertTrue(path.hasPrefix("captures/book_notes/"))
        XCTAssertTrue(path.hasSuffix(".md"))
        XCTAssertFalse(path.contains(":"))

        // Verify file exists
        let fullPath = (tempDir.path as NSString).appendingPathComponent(path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fullPath))

        // Verify content
        let content = try String(contentsOfFile: fullPath, encoding: .utf8)
        XCTAssertTrue(content.contains("Test content"))

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testVaultValidation() {
        // Non-existent path
        XCTAssertFalse(VaultWriter.validateVault(path: "/nonexistent/path"))

        // Path without .obsidian
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        XCTAssertFalse(VaultWriter.validateVault(path: tempDir.path))

        // Path with .obsidian
        try? FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent(".obsidian"),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(VaultWriter.validateVault(path: tempDir.path))

        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - AnthropicModels Tests

    func testMessagesRequestEncoding() throws {
        let request = MessagesRequest(
            model: "claude-sonnet-4-20250514",
            maxTokens: 4096,
            system: "You are a helper.",
            messages: [
                Message(role: "user", content: [
                    .text("Hello")
                ])
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(request)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"max_tokens\":4096"))
        XCTAssertTrue(json.contains("\"model\":\"claude-sonnet-4-20250514\""))
        XCTAssertTrue(json.contains("\"role\":\"user\""))
    }

    func testImageContentBlockEncoding() throws {
        let block = ContentBlock.image(mediaType: "image/jpeg", base64Data: "dGVzdA==")
        let encoder = JSONEncoder()
        let data = try encoder.encode(block)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"type\":\"image\""))
        XCTAssertTrue(json.contains("\"media_type\":\"image\\/jpeg\""))
        XCTAssertTrue(json.contains("\"data\":\"dGVzdA==\""))
    }

    func testMessagesResponseDecoding() throws {
        let json = """
        {
            "id": "msg_123",
            "type": "message",
            "role": "assistant",
            "content": [
                {
                    "type": "text",
                    "text": "Hello there!"
                }
            ],
            "model": "claude-sonnet-4-20250514",
            "stop_reason": "end_turn",
            "usage": {
                "input_tokens": 10,
                "output_tokens": 5
            }
        }
        """

        let response = try JSONDecoder().decode(MessagesResponse.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(response.id, "msg_123")
        XCTAssertEqual(response.textContent, "Hello there!")
        XCTAssertEqual(response.usage.inputTokens, 10)
        XCTAssertEqual(response.usage.outputTokens, 5)
    }

    func testClaudeExtractionResponseDecoding() throws {
        let json = """
        {
            "category": "BookNote",
            "title": "Sapiens",
            "content": "Some text here.",
            "write": {
                "mode": "append",
                "path": "captures/book_notes/sapiens.md",
                "append_to": "## Highlights"
            }
        }
        """

        let response = try JSONDecoder().decode(ClaudeExtractionResponse.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(response.category, "BookNote")
        XCTAssertEqual(response.title, "Sapiens")
        XCTAssertEqual(response.content, "Some text here.")
        XCTAssertEqual(response.write?.mode, .append)
        XCTAssertEqual(response.write?.appendTo, "## Highlights")
    }

    // MARK: - ClassificationResult Tests

    func testClassificationResult() {
        let result = ClassificationResult(
            isLearningContent: true,
            categoryHint: .bookPage,
            confidence: 0.9,
            ocrText: "Chapter 1\nSome content here",
            lineCount: 15,
            textDensity: 0.25,
            matchedKeywords: ["chapter"],
            reason: "Book page detected"
        )

        XCTAssertTrue(result.isLearningContent)
        XCTAssertEqual(result.categoryHint, .bookPage)
        XCTAssertEqual(result.confidence, 0.9)
        XCTAssertEqual(result.lineCount, 15)
    }
}
