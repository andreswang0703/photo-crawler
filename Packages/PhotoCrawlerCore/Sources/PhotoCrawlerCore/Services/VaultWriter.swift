import Foundation
#if canImport(os)
import os
#endif

/// Writes generated markdown files to the Obsidian vault with structured directories.
public struct VaultWriter: Sendable {
    private let config: CrawlerConfiguration
    private let markdownGenerator: MarkdownGenerator

    #if canImport(os)
    private static let logger = Logger(subsystem: "com.photocrawler", category: "VaultWriter")
    #endif

    public init(config: CrawlerConfiguration) {
        self.config = config
        self.markdownGenerator = MarkdownGenerator()
    }

    /// Write an extraction result as a markdown file to the vault.
    /// Returns the relative path from the vault root to the written file.
    public func write(
        extraction: ExtractionResult,
        capturedDate: Date,
        assetId: String
    ) throws -> String {
        let fm = FileManager.default
        var relativePath = resolveRelativePath(
            extraction.writePlan.path,
            extraction: extraction,
            assetId: assetId
        )

        let mode = extraction.writePlan.mode

        if mode == .create {
            let fullPath = (config.vaultPath as NSString).appendingPathComponent(relativePath)
            if fm.fileExists(atPath: fullPath) {
                relativePath = nextAvailablePath(relativePath)
            }
        }

        let fullPath = (config.vaultPath as NSString).appendingPathComponent(relativePath)
        let directoryPath = (fullPath as NSString).deletingLastPathComponent

        try fm.createDirectory(
            atPath: directoryPath,
            withIntermediateDirectories: true,
            attributes: nil
        )

        if mode == .append && fm.fileExists(atPath: fullPath) {
            let existing = try String(contentsOfFile: fullPath, encoding: .utf8)
            let block = markdownGenerator.generateAppendBlock(
                from: extraction,
                capturedDate: capturedDate,
                assetId: assetId
            )
            let updatedBody = appendContent(
                existing: existing,
                block: block,
                appendTo: extraction.writePlan.appendTo
            )
            let updated = upsertFrontmatter(
                in: updatedBody,
                extraction: extraction,
                capturedDate: capturedDate,
                assetId: assetId
            )
            try writeFile(updated, to: fullPath)
        } else {
            let markdown = markdownGenerator.generateDocument(
                from: extraction,
                capturedDate: capturedDate,
                assetId: assetId
            )
            try writeFile(markdown, to: fullPath)
        }

        #if canImport(os)
        Self.logger.info("Wrote: \(relativePath)")
        #endif

        return relativePath
    }

    /// Scan all markdown files in captures/ and return the set of asset_id values found in frontmatter.
    public func existingAssetIds() -> Set<String> {
        let capturesDir = config.capturesPath
        let fm = FileManager.default
        var ids = Set<String>()

        guard let enumerator = fm.enumerator(atPath: capturesDir) else { return ids }

        while let relativePath = enumerator.nextObject() as? String {
            guard relativePath.hasSuffix(".md") else { continue }
            let fullPath = (capturesDir as NSString).appendingPathComponent(relativePath)
            guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { continue }

            let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
            var inFrontmatter = false
            var frontmatterDone = false

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed == "---" {
                    if !inFrontmatter && !frontmatterDone {
                        inFrontmatter = true
                        continue
                    }
                    if inFrontmatter {
                        inFrontmatter = false
                        frontmatterDone = true
                        continue
                    }
                }

                if inFrontmatter {
                    if trimmed.hasPrefix("asset_ids:") {
                        let value = trimmed.dropFirst("asset_ids:".count)
                            .trimmingCharacters(in: .whitespaces)
                        ids.formUnion(parseAssetIdList(value))
                    } else if trimmed.hasPrefix("asset_id:") {
                        let value = trimmed.dropFirst("asset_id:".count)
                            .trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        if !value.isEmpty { ids.insert(value) }
                    }
                } else if trimmed.contains("photo-crawler asset_id:") {
                    if let range = trimmed.range(of: "photo-crawler asset_id:") {
                        let after = trimmed[range.upperBound...]
                        let withoutTrailer = after.replacingOccurrences(of: "-->", with: "")
                        let valuePart = withoutTrailer.components(separatedBy: "captured:").first ?? withoutTrailer
                        let value = valuePart
                            .trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        if !value.isEmpty { ids.insert(value) }
                    }
                } else if !frontmatterDone && trimmed.hasPrefix("asset_id:") {
                    // Back-compat: asset_id line without explicit frontmatter delimiters.
                    let value = trimmed.dropFirst("asset_id:".count)
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    if !value.isEmpty { ids.insert(value) }
                }
            }
        }

        return ids
    }

    /// Validate that the vault path exists and contains an .obsidian directory.
    public static func validateVault(path: String) -> Bool {
        let obsidianDir = (path as NSString).appendingPathComponent(".obsidian")
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: obsidianDir, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: - Path Building

    private func resolveRelativePath(
        _ requestedPath: String,
        extraction: ExtractionResult,
        assetId: String
    ) -> String {
        let trimmed = requestedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return defaultRelativePath(extraction: extraction, assetId: assetId)
        }

        guard let sanitized = sanitizeRelativePath(trimmed) else {
            return defaultRelativePath(extraction: extraction, assetId: assetId)
        }

        return ensureMarkdownExtension(sanitized)
    }

    private func defaultRelativePath(extraction: ExtractionResult, assetId: String) -> String {
        let fallbackId = assetId.isEmpty ? UUID().uuidString : assetId
        let safeId = sanitizeForFilesystem(fallbackId)
        let category = sanitizeForFilesystem(extraction.category)

        if extraction.category.lowercased() == "default" || category.isEmpty {
            return "captures/notes/unknown/\(safeId).md"
        }

        return "captures/\(category)/\(safeId).md"
    }

    private func sanitizeRelativePath(_ path: String) -> String? {
        let cleaned = path.replacingOccurrences(of: "\\", with: "/")
        if cleaned.hasPrefix("/") || cleaned.hasPrefix("~") {
            return nil
        }

        let parts = cleaned.split(separator: "/", omittingEmptySubsequences: true)
        guard !parts.isEmpty else { return nil }
        if parts.contains("..") { return nil }

        let sanitized = parts.map { sanitizePathComponent(String($0)) }
        return sanitized.joined(separator: "/")
    }

    private func sanitizePathComponent(_ component: String) -> String {
        let cleaned = component
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "*", with: "")

        return cleaned.isEmpty ? "untitled" : cleaned
    }

    private func ensureMarkdownExtension(_ path: String) -> String {
        path.lowercased().hasSuffix(".md") ? path : "\(path).md"
    }

    private func nextAvailablePath(_ relativePath: String) -> String {
        let ext = (relativePath as NSString).pathExtension
        let base = (relativePath as NSString).deletingPathExtension
        let fm = FileManager.default

        var counter = 2
        var candidate = "\(base)-\(counter).\(ext)"
        while fm.fileExists(atPath: (config.vaultPath as NSString).appendingPathComponent(candidate)) {
            counter += 1
            candidate = "\(base)-\(counter).\(ext)"
        }

        return candidate
    }

    private func appendContent(existing: String, block: String, appendTo: String?) -> String {
        var trimmedBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBlock.isEmpty else { return existing }

        if let appendTo = appendTo?.trimmingCharacters(in: .whitespacesAndNewlines),
           !appendTo.isEmpty {
            trimmedBlock = stripLeadingHeading(appendTo: appendTo, from: trimmedBlock)
            let lines = existing.split(separator: "\n", omittingEmptySubsequences: false)
            if let index = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == appendTo }) {
                var updated = lines
                let insertLines = trimmedBlock.split(separator: "\n", omittingEmptySubsequences: false)
                updated.insert(contentsOf: insertLines, at: updated.index(after: index))
                return updated.joined(separator: "\n")
            }
            return existing + "\n\n" + appendTo + "\n" + trimmedBlock + "\n"
        }

        return existing + "\n\n" + trimmedBlock + "\n"
    }

    private func upsertFrontmatter(
        in content: String,
        extraction: ExtractionResult,
        capturedDate: Date,
        assetId: String
    ) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else {
            return markdownGenerator.generateDocument(from: extraction, capturedDate: capturedDate, assetId: assetId)
        }

        if lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
            if let endIndex = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---" }) {
                let frontmatterLines = Array(lines[1..<endIndex])
                let bodyLines = Array(lines[(endIndex + 1)...])
                let updatedFrontmatter = updateFrontmatterLines(
                    frontmatterLines,
                    assetId: assetId
                )
                let merged = ["---"] + updatedFrontmatter + ["---"] + bodyLines
                return merged.joined(separator: "\n")
            }
        }

        let frontmatter = [
            "---",
            "title: \"\(escapeYAML(extraction.title))\"",
            "category: \"\(escapeYAML(extraction.category))\"",
            "captured: \(iso8601(capturedDate))",
            "asset_ids: [\"\(escapeYAML(assetId))\"]",
            "---",
            ""
        ].joined(separator: "\n")

        return frontmatter + content
    }

    private func updateFrontmatterLines(_ lines: [String], assetId: String) -> [String] {
        var assetIds = Set<String>()
        var cleaned: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("asset_ids:") {
                let value = trimmed.dropFirst("asset_ids:".count)
                    .trimmingCharacters(in: .whitespaces)
                assetIds.formUnion(parseAssetIdList(value))
                continue
            }
            if trimmed.hasPrefix("asset_id:") {
                let value = trimmed.dropFirst("asset_id:".count)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if !value.isEmpty { assetIds.insert(value) }
                continue
            }
            cleaned.append(line)
        }

        assetIds.insert(assetId)
        let encoded = assetIds.sorted()
            .map { "\"\(escapeYAML($0))\"" }
            .joined(separator: ", ")
        cleaned.append("asset_ids: [\(encoded)]")
        return cleaned
    }

    private func parseAssetIdList(_ value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[") && trimmed.hasSuffix("]") else {
            return [trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))]
        }
        let inner = trimmed.dropFirst().dropLast()
        return inner
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            .filter { !$0.isEmpty }
    }

    private func escapeYAML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func stripLeadingHeading(appendTo: String, from block: String) -> String {
        var lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let firstIdx = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return block
        }

        if lines[firstIdx].trimmingCharacters(in: .whitespacesAndNewlines) == appendTo {
            lines.remove(at: firstIdx)
            if firstIdx < lines.count, lines[firstIdx].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.remove(at: firstIdx)
            }
        }

        return lines.joined(separator: "\n")
    }

    private func writeFile(_ content: String, to fullPath: String) throws {
        let fileURL = URL(fileURLWithPath: fullPath)
        var coordinatorError: NSError?
        var writeError: Error?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            writingItemAt: fileURL,
            options: .forReplacing,
            error: &coordinatorError
        ) { coordinatedURL in
            do {
                try content.write(to: coordinatedURL, atomically: true, encoding: .utf8)
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
