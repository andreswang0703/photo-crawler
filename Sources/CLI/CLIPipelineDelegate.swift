import Foundation
import PhotoCrawlerCore

/// Pipeline delegate that prints progress to the terminal.
@MainActor
final class CLIPipelineDelegate: PipelineDelegate {
    func pipelineDidStartScan() {
        // quiet — main.swift already prints "Starting scan..."
    }

    func pipelineDidFinishScan(result: ScanResult) {
        // quiet — main.swift handles the final summary
    }

    func pipelineDidProcess(assetIdentifier: String, result: ExtractionResult, markdownPath: String) {
        let title = result.title.isEmpty ? "(untitled)" : result.title
        if result.writePlan.mode == .skip || markdownPath == "(skipped)" {
            print("  ⏭️  \(title) → skipped")
            return
        }
        let icon = iconForCategory(result.category)
        print("  \(icon) \(title) → \(markdownPath)")
    }

    func pipelineDidEncounterError(assetIdentifier: String, error: Error) {
        printError("  Failed \(assetIdentifier): \(error.localizedDescription)")
    }

    private func iconForCategory(_ category: String) -> String {
        let normalized = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("book") { return "📖" }
        if normalized.contains("article") { return "📰" }
        if normalized.contains("duolingo") { return "🌍" }
        if normalized.contains("code") { return "💻" }
        if normalized.contains("flash") { return "🗂️" }
        if normalized.contains("note") { return "📝" }
        return "📄"
    }
}
