import Foundation
import Vision
import CoreGraphics
#if canImport(AppKit)
import AppKit
#endif
#if canImport(os)
import os
#endif

/// Pass 1: On-device classification using Vision framework OCR.
/// Determines if an image contains learning content worth sending to Claude.
public struct LocalClassifier: Sendable {
    private let config: CrawlerConfiguration

    #if canImport(os)
    private static let logger = Logger(subsystem: "com.photocrawler", category: "LocalClassifier")
    #endif

    // MARK: - Keyword Sets

    private static let learningKeywords: Set<String> = [
        "chapter", "page", "definition", "vocabulary", "lesson",
        "exercise", "example", "theorem", "proof", "equation",
        "hypothesis", "conclusion", "abstract", "introduction",
        "summary", "review", "quiz", "exam", "study", "lecture",
        "textbook", "handbook", "reference", "glossary", "index",
        "bibliography", "footnote", "paragraph", "section"
    ]

    private static let duolingoKeywords: Set<String> = [
        "translate", "write this in", "duolingo", "correct solution",
        "you are correct", "meaning", "new word", "tap the pairs",
        "select the correct", "listen and choose"
    ]

    private static let codeKeywords: Set<String> = [
        "func ", "class ", "struct ", "import ", "def ", "return ",
        "var ", "let ", "const ", "function ", "public ", "private ",
        "if ", "for ", "while ", "switch ", "enum ", "protocol "
    ]

    private static let articlePatterns: Set<String> = [
        "http://", "https://", "www.", "subscribe", "newsletter",
        "published", "author", "read more", "continue reading",
        "share this", "comments"
    ]

    public init(config: CrawlerConfiguration) {
        self.config = config
    }

    /// Classify an image to determine if it contains learning content.
    public func classify(imageData: Data) async throws -> ClassificationResult {
        guard let cgImage = createCGImage(from: imageData) else {
            return ClassificationResult(
                isLearningContent: false,
                categoryHint: .unknown,
                confidence: 0,
                ocrText: "",
                lineCount: 0,
                textDensity: 0,
                matchedKeywords: [],
                reason: "Could not create image from data"
            )
        }

        let observations = try await performOCR(on: cgImage)

        let ocrText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        let lineCount = observations.count
        let textDensity = calculateTextDensity(observations: observations, imageSize: CGSize(
            width: CGFloat(cgImage.width),
            height: CGFloat(cgImage.height)
        ))

        let lowercaseText = ocrText.lowercased()
        let matchedKeywords = findMatchedKeywords(in: lowercaseText)
        let categoryHint = detectCategory(text: lowercaseText, observations: observations)

        let (isLearning, confidence, reason) = makeDecision(
            lineCount: lineCount,
            textDensity: textDensity,
            matchedKeywords: matchedKeywords,
            categoryHint: categoryHint
        )

        #if canImport(os)
        Self.logger.info("Classification: learning=\(isLearning), category=\(categoryHint.rawValue), confidence=\(confidence, format: .fixed(precision: 2)), lines=\(lineCount), density=\(textDensity, format: .fixed(precision: 3))")
        #endif

        return ClassificationResult(
            isLearningContent: isLearning,
            categoryHint: categoryHint,
            confidence: confidence,
            ocrText: ocrText,
            lineCount: lineCount,
            textDensity: textDensity,
            matchedKeywords: matchedKeywords,
            reason: reason
        )
    }

    // MARK: - Private Methods

    private func createCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return cgImage
    }

    private func performOCR(on image: CGImage) async throws -> [VNRecognizedTextObservation] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                continuation.resume(returning: observations)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func calculateTextDensity(observations: [VNRecognizedTextObservation], imageSize: CGSize) -> Double {
        guard !observations.isEmpty else { return 0 }

        var totalTextArea: Double = 0
        for observation in observations {
            let bbox = observation.boundingBox
            let width = bbox.width * imageSize.width
            let height = bbox.height * imageSize.height
            totalTextArea += Double(width * height)
        }

        let imageArea = Double(imageSize.width * imageSize.height)
        guard imageArea > 0 else { return 0 }

        return totalTextArea / imageArea
    }

    private func findMatchedKeywords(in text: String) -> [String] {
        var matched: [String] = []

        for keyword in Self.learningKeywords {
            if text.contains(keyword) {
                matched.append(keyword)
            }
        }
        for keyword in Self.duolingoKeywords {
            if text.contains(keyword) {
                matched.append(keyword)
            }
        }

        return matched
    }

    private func detectCategory(text: String, observations: [VNRecognizedTextObservation]) -> ContentCategory {
        // Check Duolingo patterns first (most specific)
        let duolingoMatches = Self.duolingoKeywords.filter { text.contains($0) }
        if duolingoMatches.count >= 2 {
            return .duolingo
        }

        // Check code patterns
        let codeMatches = Self.codeKeywords.filter { text.contains($0) }
        if codeMatches.count >= 3 {
            return .codeSnippet
        }

        // Check article patterns
        let articleMatches = Self.articlePatterns.filter { text.contains($0) }
        if articleMatches.count >= 2 {
            return .article
        }

        // Check for book page characteristics: consistent left margin, paragraph structure
        if hasConsistentLeftMargin(observations: observations) && observations.count > 8 {
            return .bookPage
        }

        // Check for notes
        if text.contains("note") || text.contains("todo") || text.contains("remember") {
            return .notes
        }

        return .unknown
    }

    private func hasConsistentLeftMargin(observations: [VNRecognizedTextObservation]) -> Bool {
        guard observations.count > 5 else { return false }

        let leftEdges = observations.map { $0.boundingBox.minX }
        let sortedEdges = leftEdges.sorted()

        // Check if most lines start near the same x position (within 5% tolerance)
        let medianLeft = sortedEdges[sortedEdges.count / 2]
        let closeToMedian = leftEdges.filter { abs($0 - medianLeft) < 0.05 }

        return Double(closeToMedian.count) / Double(observations.count) > 0.6
    }

    private func makeDecision(
        lineCount: Int,
        textDensity: Double,
        matchedKeywords: [String],
        categoryHint: ContentCategory
    ) -> (isLearning: Bool, confidence: Double, reason: String) {
        // Specific app detection — high confidence
        if categoryHint == .duolingo {
            return (true, 0.95, "Duolingo content detected via keyword patterns")
        }

        // High text density + paragraph structure = likely book page
        if textDensity > config.minTextDensity && lineCount > config.minLineCount && categoryHint == .bookPage {
            return (true, 0.9, "Book page: high text density (\(String(format: "%.1f%%", textDensity * 100))) with paragraph layout")
        }

        // Code snippet detection
        if categoryHint == .codeSnippet {
            return (true, 0.85, "Code snippet detected via syntax patterns")
        }

        // Article detection
        if categoryHint == .article && lineCount > config.minLineCount {
            return (true, 0.8, "Article detected via web/publication patterns")
        }

        // High text density alone with enough lines
        if textDensity > config.minTextDensity && lineCount > config.minLineCount {
            return (true, 0.7, "High text density (\(String(format: "%.1f%%", textDensity * 100))) with \(lineCount) lines")
        }

        // Multiple learning keywords (even with lower density)
        if matchedKeywords.count >= 2 && lineCount > 3 {
            return (true, 0.6, "Matched \(matchedKeywords.count) learning keywords: \(matchedKeywords.prefix(3).joined(separator: ", "))")
        }

        // Not enough signals
        let reason: String
        if lineCount <= config.minLineCount {
            reason = "Too few text lines (\(lineCount) < \(config.minLineCount))"
        } else if textDensity <= config.minTextDensity {
            reason = "Text density too low (\(String(format: "%.1f%%", textDensity * 100)) < \(String(format: "%.1f%%", config.minTextDensity * 100)))"
        } else {
            reason = "No strong learning content signals"
        }

        return (false, max(0, textDensity * 2), reason)
    }
}
