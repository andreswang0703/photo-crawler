import Foundation
#if canImport(os)
import os
#endif

/// Persists processing state: dedup set, change tokens, and statistics.
public actor StateStore {
    private var state: PersistentState
    private let stateFileURL: URL

    #if canImport(os)
    private let logger = Logger(subsystem: "com.photocrawler", category: "StateStore")
    #endif

    /// The persistent state on disk.
    struct PersistentState: Codable {
        var processedIdentifiers: Set<String> = []
        var changeTokenData: Data?
        var stats: ProcessingStats = ProcessingStats()
        var lastScanDate: Date?
    }

    /// Processing statistics.
    public struct ProcessingStats: Codable, Sendable {
        public var totalScanned: Int = 0
        public var totalClassified: Int = 0
        public var totalExtracted: Int = 0
        public var totalWritten: Int = 0
        public var totalSkipped: Int = 0
        public var totalErrors: Int = 0
    }

    public init(directory: URL? = nil) throws {
        let appSupportDir: URL
        if let directory {
            appSupportDir = directory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            appSupportDir = appSupport.appendingPathComponent("PhotoCrawler")
        }

        try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        self.stateFileURL = appSupportDir.appendingPathComponent("state.json")

        if FileManager.default.fileExists(atPath: stateFileURL.path) {
            let data = try Data(contentsOf: stateFileURL)
            self.state = try JSONDecoder().decode(PersistentState.self, from: data)
        } else {
            self.state = PersistentState()
        }
    }

    /// Check if a photo has already been processed.
    public func isProcessed(_ identifier: String) -> Bool {
        state.processedIdentifiers.contains(identifier)
    }

    /// Mark a photo as processed.
    public func markProcessed(_ identifier: String) {
        state.processedIdentifiers.insert(identifier)
    }

    /// Get the stored change token data.
    public func getChangeTokenData() -> Data? {
        state.changeTokenData
    }

    /// Store the change token data.
    public func setChangeTokenData(_ data: Data?) {
        state.changeTokenData = data
    }

    /// Get the last scan date.
    public func getLastScanDate() -> Date? {
        state.lastScanDate
    }

    /// Update the last scan date.
    public func setLastScanDate(_ date: Date) {
        state.lastScanDate = date
    }

    /// Get current processing statistics.
    public func getStats() -> ProcessingStats {
        state.stats
    }

    /// Increment a stat counter.
    public func incrementScanned() { state.stats.totalScanned += 1 }
    public func incrementClassified() { state.stats.totalClassified += 1 }
    public func incrementExtracted() { state.stats.totalExtracted += 1 }
    public func incrementWritten() { state.stats.totalWritten += 1 }
    public func incrementSkipped() { state.stats.totalSkipped += 1 }
    public func incrementErrors() { state.stats.totalErrors += 1 }

    /// Persist state to disk.
    public func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: stateFileURL, options: .atomic)

        #if canImport(os)
        logger.debug("State saved: \(self.state.processedIdentifiers.count) processed photos")
        #endif
    }

    /// Number of processed photos.
    public func processedCount() -> Int {
        state.processedIdentifiers.count
    }
}
