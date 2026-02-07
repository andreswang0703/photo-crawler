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
        let icon: String
        switch result.contentType {
        case .bookPage: icon = "📖"
        case .article: icon = "📰"
        case .duolingo: icon = "🌍"
        case .codeSnippet: icon = "💻"
        case .flashcard: icon = "🗂️"
        case .notes: icon = "📝"
        case .unknown: icon = "📄"
        }
        print("  \(icon) \(result.source.title) → \(markdownPath)")
    }

    func pipelineDidEncounterError(assetIdentifier: String, error: Error) {
        printError("  Failed \(assetIdentifier): \(error.localizedDescription)")
    }
}
