import Foundation

/// Represents a photo that has been processed through the pipeline.
public struct ProcessedPhoto: Codable, Sendable {
    /// The PHAsset local identifier.
    public let assetIdentifier: String

    /// When the photo was taken.
    public let creationDate: Date

    /// When the photo was processed by PhotoCrawler.
    public let processedDate: Date

    /// Classification result from Pass 1.
    public let classification: ClassificationResult

    /// Extraction result from Pass 2 (nil if not classified as learning content).
    public let extraction: ExtractionResult?

    /// Path to the generated markdown file (relative to vault root).
    public let markdownPath: String?

    /// Processing status.
    public let status: ProcessingStatus

    /// Error message if processing failed.
    public let errorMessage: String?

    public init(
        assetIdentifier: String,
        creationDate: Date,
        processedDate: Date = Date(),
        classification: ClassificationResult,
        extraction: ExtractionResult? = nil,
        markdownPath: String? = nil,
        status: ProcessingStatus = .classified,
        errorMessage: String? = nil
    ) {
        self.assetIdentifier = assetIdentifier
        self.creationDate = creationDate
        self.processedDate = processedDate
        self.classification = classification
        self.extraction = extraction
        self.markdownPath = markdownPath
        self.status = status
        self.errorMessage = errorMessage
    }
}

/// Status of photo processing through the pipeline.
public enum ProcessingStatus: String, Codable, Sendable {
    case classified
    case extracted
    case written
    case skipped
    case failed
}
