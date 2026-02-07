import Foundation

/// Result of the local (on-device) classification pass.
public struct ClassificationResult: Codable, Sendable {
    /// Whether the image is classified as learning content worth extracting.
    public let isLearningContent: Bool

    /// Detected category hint for the extractor.
    public let categoryHint: ContentCategory

    /// Confidence score from 0.0 to 1.0.
    public let confidence: Double

    /// Raw OCR text extracted by Vision framework.
    public let ocrText: String

    /// Number of text lines detected.
    public let lineCount: Int

    /// Text density ratio (text bounding box area / image area).
    public let textDensity: Double

    /// Keywords that matched during classification.
    public let matchedKeywords: [String]

    /// Reason for the classification decision.
    public let reason: String

    public init(
        isLearningContent: Bool,
        categoryHint: ContentCategory,
        confidence: Double,
        ocrText: String,
        lineCount: Int,
        textDensity: Double,
        matchedKeywords: [String],
        reason: String
    ) {
        self.isLearningContent = isLearningContent
        self.categoryHint = categoryHint
        self.confidence = confidence
        self.ocrText = ocrText
        self.lineCount = lineCount
        self.textDensity = textDensity
        self.matchedKeywords = matchedKeywords
        self.reason = reason
    }
}
