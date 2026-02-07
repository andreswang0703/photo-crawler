import Foundation
#if canImport(os)
import os
#endif

/// Writes generated markdown files to the Obsidian vault with structured directories.
public struct VaultWriter: Sendable {
    private let config: CrawlerConfiguration

    #if canImport(os)
    private static let logger = Logger(subsystem: "com.photocrawler", category: "VaultWriter")
    #endif

    public init(config: CrawlerConfiguration) {
        self.config = config
    }

    /// Write an extraction result as a markdown file to the vault.
    /// Returns the relative path from the vault root to the written file.
    public func write(
        markdown: String,
        extraction: ExtractionResult,
        capturedDate: Date
    ) throws -> String {
        let relativePath = buildRelativePath(extraction: extraction, capturedDate: capturedDate)
        let fullPath = (config.vaultPath as NSString).appendingPathComponent(relativePath)
        let directoryPath = (fullPath as NSString).deletingLastPathComponent

        // Create directory hierarchy
        try FileManager.default.createDirectory(
            atPath: directoryPath,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let fileURL = URL(fileURLWithPath: fullPath)

        // Use NSFileCoordinator for safe iCloud writes
        var coordinatorError: NSError?
        var writeError: Error?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            writingItemAt: fileURL,
            options: .forReplacing,
            error: &coordinatorError
        ) { coordinatedURL in
            do {
                try markdown.write(to: coordinatedURL, atomically: true, encoding: .utf8)
            } catch {
                writeError = error
            }
        }

        if let coordinatorError {
            throw VaultWriterError.coordinationFailed(coordinatorError.localizedDescription)
        }
        if let writeError {
            throw VaultWriterError.writeFailed(writeError.localizedDescription)
        }

        #if canImport(os)
        Self.logger.info("Wrote: \(relativePath)")
        #endif

        return relativePath
    }

    /// Validate that the vault path exists and contains an .obsidian directory.
    public static func validateVault(path: String) -> Bool {
        let obsidianDir = (path as NSString).appendingPathComponent(".obsidian")
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: obsidianDir, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: - Path Building

    private func buildRelativePath(extraction: ExtractionResult, capturedDate: Date) -> String {
        let category = extraction.contentType.directoryName
        let sourceName = sanitizeForFilesystem(extraction.source.title)

        var components = ["captures", category, sourceName]

        // Generate unique filename
        let filename = generateFilename(in: components.joined(separator: "/"))
        components.append(filename)

        return components.joined(separator: "/")
    }

    private func generateFilename(in relativeDirPath: String) -> String {
        let dirPath = (config.vaultPath as NSString).appendingPathComponent(relativeDirPath)
        let fm = FileManager.default

        // Find the next available snapshot number
        var number = 1
        if fm.fileExists(atPath: dirPath) {
            if let contents = try? fm.contentsOfDirectory(atPath: dirPath) {
                let snapshotNumbers = contents.compactMap { filename -> Int? in
                    guard filename.hasPrefix("snapshot-") && filename.hasSuffix(".md") else { return nil }
                    let numStr = filename
                        .replacingOccurrences(of: "snapshot-", with: "")
                        .replacingOccurrences(of: ".md", with: "")
                    return Int(numStr)
                }
                if let maxNumber = snapshotNumbers.max() {
                    number = maxNumber + 1
                }
            }
        }

        return String(format: "snapshot-%03d.md", number)
    }

    private func sanitizeForFilesystem(_ name: String) -> String {
        let cleaned = name
            .lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: ".", with: "")

        // Replace spaces and multiple hyphens
        let hyphenated = cleaned
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        // Truncate to reasonable length
        if hyphenated.count > 60 {
            return String(hyphenated.prefix(60)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }

        return hyphenated.isEmpty ? "untitled" : hyphenated
    }

    private func dateDirectory(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

public enum VaultWriterError: LocalizedError, Sendable {
    case coordinationFailed(String)
    case writeFailed(String)
    case invalidVaultPath

    public var errorDescription: String? {
        switch self {
        case .coordinationFailed(let detail): return "File coordination failed: \(detail)"
        case .writeFailed(let detail): return "Write failed: \(detail)"
        case .invalidVaultPath: return "Invalid vault path — .obsidian directory not found"
        }
    }
}
