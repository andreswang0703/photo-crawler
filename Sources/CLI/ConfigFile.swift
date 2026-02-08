import Foundation
import PhotoCrawlerCore

/// Handles reading/writing the JSON config file.
enum ConfigFile {
    static var configDirPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return (home as NSString).appendingPathComponent(".config/photo-crawler")
    }

    static var configFilePath: String {
        (configDirPath as NSString).appendingPathComponent("config.json")
    }

    /// The default config written by `init`.
    static var defaultConfig: FileConfig {
        FileConfig(
            vaultPath: "",
            apiKey: "",
            album: "PhotoCrawler",
            scanIntervalSeconds: 30,
            model: "claude-sonnet-4-20250514",
            minTextDensity: 0.10,
            minLineCount: 5,
            maxConcurrentAPICalls: 3,
            screenshotsOnly: false,
            initialScanDays: 30,
            categories: [],
            defaultRules: ExtractionDefaultRule(
                extractionRules: "Extract readable text. Add a short summary.",
                writeRule: "Create a new note under captures/notes/unknown/ using asset_id as filename."
            ),
            globalRules: []
        )
    }

    static func load() throws -> CrawlerConfiguration {
        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let fileConfig = try JSONDecoder().decode(FileConfig.self, from: data)
        return fileConfig.toCrawlerConfiguration()
    }

    static func save(_ config: FileConfig) throws {
        try FileManager.default.createDirectory(
            atPath: configDirPath,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: URL(fileURLWithPath: configFilePath), options: .atomic)
    }
}

/// JSON-serializable config file format.
struct FileConfig: Codable {
    var vaultPath: String
    var apiKey: String
    var album: String
    var scanIntervalSeconds: Int
    var model: String
    var minTextDensity: Double
    var minLineCount: Int
    var maxConcurrentAPICalls: Int
    var screenshotsOnly: Bool
    var initialScanDays: Int
    var categories: [ExtractionCategoryRule]
    var defaultRules: ExtractionDefaultRule
    var globalRules: [String]

    enum CodingKeys: String, CodingKey {
        case vaultPath = "vault_path"
        case apiKey = "api_key"
        case album
        case scanIntervalSeconds = "scan_interval_seconds"
        case model
        case minTextDensity = "min_text_density"
        case minLineCount = "min_line_count"
        case maxConcurrentAPICalls = "max_concurrent_api_calls"
        case screenshotsOnly = "screenshots_only"
        case initialScanDays = "initial_scan_days"
        case categories
        case defaultRules = "default"
        case globalRules = "global_rules"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vaultPath = try container.decode(String.self, forKey: .vaultPath)
        apiKey = try container.decode(String.self, forKey: .apiKey)
        album = (try? container.decode(String.self, forKey: .album)) ?? "PhotoCrawler"
        scanIntervalSeconds = (try? container.decode(Int.self, forKey: .scanIntervalSeconds)) ?? 30
        model = try container.decode(String.self, forKey: .model)
        minTextDensity = try container.decode(Double.self, forKey: .minTextDensity)
        minLineCount = try container.decode(Int.self, forKey: .minLineCount)
        maxConcurrentAPICalls = try container.decode(Int.self, forKey: .maxConcurrentAPICalls)
        screenshotsOnly = try container.decode(Bool.self, forKey: .screenshotsOnly)
        initialScanDays = try container.decode(Int.self, forKey: .initialScanDays)
        categories = (try? container.decode([ExtractionCategoryRule].self, forKey: .categories)) ?? []
        defaultRules = (try? container.decode(ExtractionDefaultRule.self, forKey: .defaultRules))
            ?? ExtractionDefaultRule(
                extractionRules: "Extract readable text. Add a short summary.",
                writeRule: "Create a new note under captures/notes/unknown/ using asset_id as filename."
            )
        globalRules = (try? container.decode([String].self, forKey: .globalRules)) ?? []
    }

    init(
        vaultPath: String,
        apiKey: String,
        album: String = "PhotoCrawler",
        scanIntervalSeconds: Int,
        model: String,
        minTextDensity: Double,
        minLineCount: Int,
        maxConcurrentAPICalls: Int,
        screenshotsOnly: Bool,
        initialScanDays: Int,
        categories: [ExtractionCategoryRule],
        defaultRules: ExtractionDefaultRule,
        globalRules: [String]
    ) {
        self.vaultPath = vaultPath
        self.apiKey = apiKey
        self.album = album
        self.scanIntervalSeconds = scanIntervalSeconds
        self.model = model
        self.minTextDensity = minTextDensity
        self.minLineCount = minLineCount
        self.maxConcurrentAPICalls = maxConcurrentAPICalls
        self.screenshotsOnly = screenshotsOnly
        self.initialScanDays = initialScanDays
        self.categories = categories
        self.defaultRules = defaultRules
        self.globalRules = globalRules
    }

    func toCrawlerConfiguration() -> CrawlerConfiguration {
        CrawlerConfiguration(
            vaultPath: vaultPath,
            apiKey: apiKey,
            scanIntervalSeconds: TimeInterval(scanIntervalSeconds),
            claudeModel: model,
            minTextDensity: minTextDensity,
            minLineCount: minLineCount,
            maxConcurrentAPICalls: maxConcurrentAPICalls,
            screenshotsOnly: screenshotsOnly,
            initialScanDays: initialScanDays,
            albumName: album,
            categories: categories,
            defaultRules: defaultRules,
            globalRules: globalRules
        )
    }
}
