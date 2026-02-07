import Foundation
import Photos
#if canImport(os)
import os
#endif

/// Orchestrates the full photo processing pipeline.
public actor ProcessingPipeline {
    private let config: CrawlerConfiguration
    private let scanner: PhotoScanner
    private let classifier: LocalClassifier
    private let extractor: ClaudeExtractor
    private let markdownGenerator: MarkdownGenerator
    private let vaultWriter: VaultWriter
    private let stateStore: StateStore

    private var isRunning = false

    #if canImport(os)
    private let logger = Logger(subsystem: "com.photocrawler", category: "Pipeline")
    #endif

    /// Delegate for receiving pipeline events.
    private weak var _delegate: PipelineDelegate?

    public func setDelegate(_ delegate: PipelineDelegate?) {
        _delegate = delegate
    }

    public init(config: CrawlerConfiguration, stateStore: StateStore) {
        self.config = config
        self.stateStore = stateStore
        self.scanner = PhotoScanner(config: config, stateStore: stateStore)
        self.classifier = LocalClassifier(config: config)
        self.extractor = ClaudeExtractor(config: config)
        self.markdownGenerator = MarkdownGenerator()
        self.vaultWriter = VaultWriter(config: config)
    }

    /// Run a single scan cycle.
    public func runScan() async -> ScanResult {
        guard !isRunning else {
            return ScanResult(status: .skipped, message: "Scan already in progress")
        }

        isRunning = true
        defer { isRunning = false }

        #if canImport(os)
        logger.info("Starting scan cycle")
        #endif

        await _delegate?.pipelineDidStartScan()

        var result = ScanResult(status: .completed, message: "")
        var processedCount = 0
        var extractedCount = 0
        var errorCount = 0

        do {
            // Check which asset IDs already have notes in the vault
            let existingIds = vaultWriter.existingAssetIds()

            let photos = try await scanner.fetchNewPhotos(existingAssetIds: existingIds)
            result.photosFound = photos.count

            #if canImport(os)
            logger.info("Found \(photos.count) new photos to process (\(existingIds.count) already in vault)")
            #endif

            for (asset, imageData) in photos {
                await stateStore.incrementScanned()

                do {
                    // Pass 1: Local classification (for category hints only — album is user-curated)
                    let classification = try await classifier.classify(imageData: imageData)
                    await stateStore.incrementClassified()

                    // Pass 2: Claude extraction
                    let extraction = try await extractor.extract(
                        imageData: imageData,
                        classificationResult: classification
                    )
                    await stateStore.incrementExtracted()
                    extractedCount += 1

                    // Pass 3: Generate markdown with asset ID
                    let capturedDate = asset.creationDate ?? Date()
                    let markdown = markdownGenerator.generate(
                        from: extraction,
                        capturedDate: capturedDate,
                        assetId: asset.localIdentifier
                    )

                    // Pass 4: Write to vault
                    let relativePath = try vaultWriter.write(
                        markdown: markdown,
                        extraction: extraction,
                        capturedDate: capturedDate
                    )
                    await stateStore.incrementWritten()
                    processedCount += 1

                    #if canImport(os)
                    logger.info("Processed: \(relativePath)")
                    #endif

                    await _delegate?.pipelineDidProcess(
                        assetIdentifier: asset.localIdentifier,
                        result: extraction,
                        markdownPath: relativePath
                    )

                } catch {
                    errorCount += 1
                    await stateStore.incrementErrors()

                    #if canImport(os)
                    logger.error("Error processing \(asset.localIdentifier): \(error.localizedDescription)")
                    #endif

                    await _delegate?.pipelineDidEncounterError(
                        assetIdentifier: asset.localIdentifier,
                        error: error
                    )
                }
            }

            // Save state after processing
            try await stateStore.save()

        } catch {
            result.status = .failed
            result.message = error.localizedDescription
            errorCount += 1

            #if canImport(os)
            logger.error("Scan failed: \(error.localizedDescription)")
            #endif
        }

        result.photosProcessed = processedCount
        result.photosExtracted = extractedCount
        result.errors = errorCount

        if result.status == .completed {
            result.message = "Processed \(processedCount) photos, extracted \(extractedCount), \(errorCount) errors"
        }

        #if canImport(os)
        logger.info("Scan complete: \(result.message)")
        #endif

        await _delegate?.pipelineDidFinishScan(result: result)
        return result
    }

    /// Get the current running state.
    public func getIsRunning() -> Bool {
        isRunning
    }
}

// MARK: - Pipeline Delegate

@MainActor
public protocol PipelineDelegate: AnyObject {
    func pipelineDidStartScan()
    func pipelineDidFinishScan(result: ScanResult)
    func pipelineDidProcess(assetIdentifier: String, result: ExtractionResult, markdownPath: String)
    func pipelineDidEncounterError(assetIdentifier: String, error: Error)
}

// MARK: - Scan Result

public struct ScanResult: Sendable {
    public var status: ScanStatus
    public var message: String
    public var photosFound: Int
    public var photosProcessed: Int
    public var photosExtracted: Int
    public var errors: Int

    public init(
        status: ScanStatus = .completed,
        message: String = "",
        photosFound: Int = 0,
        photosProcessed: Int = 0,
        photosExtracted: Int = 0,
        errors: Int = 0
    ) {
        self.status = status
        self.message = message
        self.photosFound = photosFound
        self.photosProcessed = photosProcessed
        self.photosExtracted = photosExtracted
        self.errors = errors
    }
}

public enum ScanStatus: String, Sendable {
    case completed
    case failed
    case skipped
}
