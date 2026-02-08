import Foundation

/// Configuration for the PhotoCrawler pipeline.
public struct CrawlerConfiguration: Codable, Sendable {
    /// Path to the Obsidian vault root directory.
    public var vaultPath: String

    /// Claude API key.
    public var apiKey: String

    /// Scan interval in seconds. Default: 900 (15 minutes).
    public var scanIntervalSeconds: TimeInterval

    /// Claude model to use for extraction.
    public var claudeModel: String

    /// Minimum text density ratio (text area / image area) to pass classification.
    public var minTextDensity: Double

    /// Minimum number of recognized text lines to pass classification.
    public var minLineCount: Int

    /// Maximum concurrent Claude API calls.
    public var maxConcurrentAPICalls: Int

    /// Maximum image dimension (long edge) before resizing for API submission.
    public var maxImageDimension: Int

    /// Only process screenshots (not camera photos).
    public var screenshotsOnly: Bool

    /// Number of days to look back on first run.
    public var initialScanDays: Int

    /// Name of the Photos album to scan. Only photos in this album are processed.
    public var albumName: String

    /// User-defined categories for extraction.
    public var categories: [ExtractionCategoryRule]

    /// Default/fallback extraction rules.
    public var defaultRules: ExtractionDefaultRule

    /// Global rules applied to all categories.
    public var globalRules: [String]

    public init(
        vaultPath: String = "",
        apiKey: String = "",
        scanIntervalSeconds: TimeInterval = 900,
        claudeModel: String = "claude-sonnet-4-20250514",
        minTextDensity: Double = 0.10,
        minLineCount: Int = 5,
        maxConcurrentAPICalls: Int = 3,
        maxImageDimension: Int = 1568,
        screenshotsOnly: Bool = false,
        initialScanDays: Int = 30,
        albumName: String = "PhotoCrawler",
        categories: [ExtractionCategoryRule] = [],
        defaultRules: ExtractionDefaultRule = ExtractionDefaultRule(
            extractionRules: "Extract readable text. Add a short summary.",
            writeRule: "Create a new note under captures/notes/unknown/ using asset_id as filename."
        ),
        globalRules: [String] = []
    ) {
        self.vaultPath = vaultPath
        self.apiKey = apiKey
        self.scanIntervalSeconds = scanIntervalSeconds
        self.claudeModel = claudeModel
        self.minTextDensity = minTextDensity
        self.minLineCount = minLineCount
        self.maxConcurrentAPICalls = maxConcurrentAPICalls
        self.maxImageDimension = maxImageDimension
        self.screenshotsOnly = screenshotsOnly
        self.initialScanDays = initialScanDays
        self.albumName = albumName
        self.categories = categories
        self.defaultRules = defaultRules
        self.globalRules = globalRules
    }

    /// The captures directory inside the vault.
    public var capturesPath: String {
        (vaultPath as NSString).appendingPathComponent("captures")
    }

    /// Whether the configuration has the minimum required fields set.
    public var isValid: Bool {
        !vaultPath.isEmpty && !apiKey.isEmpty
    }
}
