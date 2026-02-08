import Foundation
import PhotoCrawlerCore

@MainActor
enum Commands {

    static func runScan() async {
        guard let config = loadConfig() else { return }
        guard await checkPhotoAccess() else { return }

        printInfo("Scanning \(scanScopeDescription(config))...")

        do {
            let stateStore = try StateStore()
            let pipeline = ProcessingPipeline(config: config, stateStore: stateStore)
            let delegate = CLIPipelineDelegate()
            await pipeline.setDelegate(delegate)

            let result = await pipeline.runScan()

            switch result.status {
            case .completed:
                printSuccess("Scan complete: \(result.photosFound) found, \(result.photosExtracted) extracted, \(result.photosProcessed) written, \(result.errors) errors")
            case .failed:
                printError("Scan failed: \(result.message)")
                exit(1)
            case .skipped:
                printInfo(result.message)
            }
        } catch {
            printError("Failed to initialize: \(error.localizedDescription)")
            exit(1)
        }
    }

    static func runWatch() async {
        guard let config = loadConfig() else { return }
        guard await checkPhotoAccess() else { return }

        let intervalSecs = Int(config.scanIntervalSeconds)
        printInfo("Watching \(scanScopeDescription(config)) every \(intervalSecs)s. Press Ctrl+C to stop.")

        signal(SIGINT) { _ in
            print("\n")
            printInfo("Stopping watch...")
            exit(0)
        }

        while true {
            do {
                let stateStore = try StateStore()
                let pipeline = ProcessingPipeline(config: config, stateStore: stateStore)
                let delegate = CLIPipelineDelegate()
                await pipeline.setDelegate(delegate)

                let result = await pipeline.runScan()

                let timestamp = formatTimestamp()
                switch result.status {
                case .completed:
                    if result.photosExtracted > 0 {
                        printSuccess("[\(timestamp)] \(result.photosExtracted) new captures written")
                    } else {
                        printDim("[\(timestamp)] No new learning content found")
                    }
                case .failed:
                    printError("[\(timestamp)] Scan failed: \(result.message)")
                case .skipped:
                    printDim("[\(timestamp)] \(result.message)")
                }
            } catch {
                printError("Scan error: \(error.localizedDescription)")
            }

            try? await Task.sleep(nanoseconds: UInt64(config.scanIntervalSeconds) * 1_000_000_000)
        }
    }

    static func runInit() {
        let configPath = ConfigFile.configFilePath

        if FileManager.default.fileExists(atPath: configPath) {
            printInfo("Config already exists at \(configPath)")
            printInfo("Edit it manually or delete it and run 'init' again.")
            return
        }

        do {
            try ConfigFile.save(ConfigFile.defaultConfig)
            printSuccess("Config created at \(configPath)")
            print("")
            print("  Edit it to set your vault path and API key:")
            print("    open \(configPath)")
            print("")
            print("  Required fields:")
            print("    vault_path  — path to your Obsidian vault (must contain .obsidian/)")
            print("    api_key     — your Anthropic API key")
            print("")
            print("  Then create an album called \"PhotoCrawler\" in Apple Photos.")
            print("  (Or change the \"album\" field in config to use a different name.)")
            print("  Add photos you want captured to that album, then run: photo-crawler scan")
        } catch {
            printError("Failed to create config: \(error.localizedDescription)")
            exit(1)
        }
    }

    static func runStatus() async {
        do {
            let stateStore = try StateStore()
            let stats = await stateStore.getStats()
            let lastScan = await stateStore.getLastScanDate()
            let processedCount = await stateStore.processedCount()

            print("photo-crawler status")
            print("────────────────────")
            print("  Photos processed:  \(processedCount)")
            print("  Total scanned:     \(stats.totalScanned)")
            print("  Total classified:  \(stats.totalClassified)")
            print("  Total extracted:   \(stats.totalExtracted)")
            print("  Total written:     \(stats.totalWritten)")
            print("  Total skipped:     \(stats.totalSkipped)")
            print("  Total errors:      \(stats.totalErrors)")

            if let lastScan {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .full
                print("  Last scan:         \(formatter.localizedString(for: lastScan, relativeTo: Date()))")
            } else {
                print("  Last scan:         never")
            }

            let configPath = ConfigFile.configFilePath
            print("  Config:            \(FileManager.default.fileExists(atPath: configPath) ? configPath : "not found (run 'photo-crawler init')")")
        } catch {
            printError("Failed to read state: \(error.localizedDescription)")
            exit(1)
        }
    }

    static func runShowConfig() {
        let configPath = ConfigFile.configFilePath
        guard FileManager.default.fileExists(atPath: configPath) else {
            printError("No config file found. Run 'photo-crawler init' first.")
            exit(1)
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
            if let json = String(data: data, encoding: .utf8) {
                print(json)
            }
        } catch {
            printError("Failed to read config: \(error.localizedDescription)")
            exit(1)
        }
    }

    static func runTest(imagePath: String?) async {
        guard let imagePath else {
            printError("Usage: photo-crawler test <image-path> [--extract]")
            exit(1)
        }

        let resolvedPath: String
        if imagePath.hasPrefix("/") {
            resolvedPath = imagePath
        } else {
            resolvedPath = (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(imagePath)
        }

        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            printError("File not found: \(resolvedPath)")
            exit(1)
        }

        guard let imageData = FileManager.default.contents(atPath: resolvedPath) else {
            printError("Could not read file: \(resolvedPath)")
            exit(1)
        }

        let shouldSave = CommandLine.arguments.contains("--save")
        let shouldExtract = CommandLine.arguments.contains("--extract") || shouldSave

        printInfo("Testing image: \(resolvedPath) (\(ByteCountFormatter.string(fromByteCount: Int64(imageData.count), countStyle: .file)))")
        print("")

        // Pass 1: Local classification
        let config = CrawlerConfiguration()
        let classifier = LocalClassifier(config: config)

        printInfo("Pass 1: Local classification (Vision OCR)...")
        do {
            let result = try await classifier.classify(imageData: imageData)

            print("")
            print("  Classification Result")
            print("  ─────────────────────")
            print("  Learning content:  \(result.isLearningContent ? "✅ YES" : "❌ NO")")
            print("  Category hint:     \(result.categoryHint.displayName)")
            print("  Confidence:        \(String(format: "%.0f%%", result.confidence * 100))")
            print("  Text density:      \(String(format: "%.1f%%", result.textDensity * 100))")
            print("  Line count:        \(result.lineCount)")
            print("  Matched keywords:  \(result.matchedKeywords.isEmpty ? "(none)" : result.matchedKeywords.joined(separator: ", "))")
            print("  Reason:            \(result.reason)")

            if !result.ocrText.isEmpty {
                print("")
                print("  OCR Text (first 500 chars)")
                print("  ─────────────────────────")
                let preview = String(result.ocrText.prefix(500))
                for line in preview.split(separator: "\n", omittingEmptySubsequences: false) {
                    print("  \(line)")
                }
                if result.ocrText.count > 500 {
                    printDim("  ... (\(result.ocrText.count - 500) more characters)")
                }
            }

            // Pass 2: Claude extraction (optional)
            if shouldExtract {
                print("")

                var extractConfig = config
                if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] {
                    extractConfig.apiKey = envKey
                }

                // Try loading from config file
                if extractConfig.apiKey.isEmpty {
                    do {
                        let fileConfig = try ConfigFile.load()
                        extractConfig.apiKey = fileConfig.apiKey
                    } catch {
                        printError("Failed to load config: \(error.localizedDescription)")
                    }
                }

                guard !extractConfig.apiKey.isEmpty else {
                    printError("Pass 2 requires an API key. Set ANTHROPIC_API_KEY or configure it in config file.")
                    return
                }

                printInfo("Pass 2: Claude extraction (\(extractConfig.claudeModel))...")
                let extractor = ClaudeExtractor(config: extractConfig)
                let assetId = URL(fileURLWithPath: resolvedPath).lastPathComponent
                let capturedDate = Date()
                let extraction = try await extractor.extract(
                    imageData: imageData,
                    classificationResult: result,
                    assetId: assetId,
                    capturedDate: capturedDate
                )

                print("")
                print("  Extraction Result")
                print("  ─────────────────")
                print("  Category:          \(extraction.category)")
                print("  Title:             \(extraction.title)")
                print("  Write mode:        \(extraction.writePlan.mode.rawValue)")
                print("  Write path:        \(extraction.writePlan.path.isEmpty ? "(default)" : extraction.writePlan.path)")
                if let appendTo = extraction.writePlan.appendTo {
                    print("  Append to:         \(appendTo)")
                }

                if extraction.writePlan.mode == .skip {
                    print("")
                    print("  Skipped by rules.")
                    return
                }
                print("")
                print("  Content")
                print("  ───────")
                for line in extraction.content.split(separator: "\n", omittingEmptySubsequences: false) {
                    print("  \(line)")
                }

                // Save to vault
                if shouldSave {
                    do {
                        let fileConfig = try ConfigFile.load()
                        guard VaultWriter.validateVault(path: fileConfig.vaultPath) else {
                            printError("Invalid vault path: \(fileConfig.vaultPath)")
                            return
                        }
                        var writeConfig = extractConfig
                        writeConfig.vaultPath = fileConfig.vaultPath
                        let writer = VaultWriter(config: writeConfig)
                        let relativePath = try writer.write(
                            extraction: extraction,
                            capturedDate: capturedDate,
                            assetId: assetId
                        )
                        let fullPath = (fileConfig.vaultPath as NSString).appendingPathComponent(relativePath)
                        print("")
                        printSuccess("Saved to vault: \(fullPath)")
                    } catch {
                        printError("Failed to save: \(error.localizedDescription)")
                    }
                } else {
                    // Generate markdown preview
                    let generator = MarkdownGenerator()
                    let markdown: String
                    if extraction.writePlan.mode == .append {
                        markdown = generator.generateAppendBlock(
                            from: extraction,
                            capturedDate: capturedDate,
                            assetId: assetId
                        )
                    } else {
                        markdown = generator.generateDocument(
                            from: extraction,
                            capturedDate: capturedDate,
                            assetId: assetId
                        )
                    }

                    print("")
                    printInfo("Generated markdown preview:")
                    print("  ──────────────────────────")
                    for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
                        print("  \(line)")
                    }
                    print("")
                    printDim("  (use --save to write to vault)")
                }
            }

        } catch {
            printError("Classification failed: \(error.localizedDescription)")
            exit(1)
        }
    }

    static func printUsage() {
        print("""
        photo-crawler — Extract text from photos into Obsidian

        Usage:
          photo-crawler <command> [options]

        Commands:
          init              Create config file (~/.config/photo-crawler/config.json)
          scan              Run one scan cycle
          watch             Run continuously, scanning on an interval
          test <image>      Test classification on a single image file
          status            Show processing statistics
          config            Print current config
          help              Show this help

        Options:
          --vault <path>     Override vault path
          --api-key <key>    Override API key (or set ANTHROPIC_API_KEY env var)
          --extract          (test only) Also run Claude extraction (Pass 2)
          --save             (test only) Extract and save to vault

        Setup:
          1. photo-crawler init
          2. Edit ~/.config/photo-crawler/config.json (set vault_path, api_key)
          3. Create an album called "PhotoCrawler" in Apple Photos (or set "album" in config)
          4. Add photos you want captured to that album
          5. photo-crawler scan

        Examples:
          photo-crawler init
          photo-crawler scan
          photo-crawler test ~/Desktop/book-page.jpg --extract
          photo-crawler test ~/Desktop/book-page.jpg --save
          photo-crawler watch
        """)
    }

    // MARK: - Helpers

    static func loadConfig() -> CrawlerConfiguration? {
        let args = Array(CommandLine.arguments.dropFirst(2))
        var flagVault: String?
        var flagKey: String?

        var i = 0
        while i < args.count {
            switch args[i] {
            case "--vault":
                if i + 1 < args.count { flagVault = args[i + 1]; i += 2 } else { i += 1 }
            case "--api-key":
                if i + 1 < args.count { flagKey = args[i + 1]; i += 2 } else { i += 1 }
            default:
                i += 1
            }
        }

        do {
            var config = try ConfigFile.load()

            if let v = flagVault { config.vaultPath = v }
            if let k = flagKey { config.apiKey = k }

            if config.apiKey.isEmpty, let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] {
                config.apiKey = envKey
            }

            guard config.isValid else {
                if config.vaultPath.isEmpty {
                    printError("No vault path set. Edit \(ConfigFile.configFilePath) or pass --vault <path>")
                }
                if config.apiKey.isEmpty {
                    printError("No API key set. Edit config, pass --api-key <key>, or set ANTHROPIC_API_KEY")
                }
                return nil
            }

            guard VaultWriter.validateVault(path: config.vaultPath) else {
                printError("Invalid vault path: \(config.vaultPath) (no .obsidian directory found)")
                return nil
            }

            return config
        } catch {
            printError("No config file found. Run 'photo-crawler init' first.")
            return nil
        }
    }

    static func checkPhotoAccess() async -> Bool {
        let status = await PhotoScanner.requestAuthorization()
        switch status {
        case .authorized:
            return true
        case .denied:
            printError("Photo library access denied. Grant access in System Settings > Privacy & Security > Photos.")
            return false
        case .restricted:
            printError("Photo library access is restricted on this device.")
            return false
        case .notDetermined:
            printError("Photo library access not determined. A permission dialog should have appeared.")
            return false
        case .limited:
            printInfo("Photo library access is limited. Only selected photos will be scanned.")
            return true
        @unknown default:
            printError("Unknown photo library authorization status.")
            return false
        }
    }

    private static func formatTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    private static func scanScopeDescription(_ config: CrawlerConfiguration) -> String {
        let trimmed = config.albumName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Photos Library"
        }
        return "album \"\(config.albumName)\""
    }
}
