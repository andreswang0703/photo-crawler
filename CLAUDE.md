# CLAUDE.md

## What this project is

photo-crawler is a macOS CLI that watches a specific Apple Photos album, extracts text from each photo using Claude API, and writes structured markdown to an Obsidian vault. The user adds photos of book pages, articles, lecture slides, flashcards, etc. to the album — everything in the album gets processed.

## Architecture

Two Swift packages:
- `Packages/PhotoCrawlerCore/` — platform-agnostic library (Models, Services, Networking)
- `Sources/CLI/` — CLI executable wrapping the core library

Pipeline: PhotoScanner (fetch from album) → LocalClassifier (category hints via Vision OCR) → ClaudeExtractor (Claude API) → MarkdownGenerator → VaultWriter (iCloud-safe writes)

Dedup: each note has `asset_id` in YAML frontmatter. On each poll, the vault is scanned for existing asset IDs. Deleting a note causes re-extraction.

Zero external dependencies — uses Foundation, Vision, Photos, URLSession only.

## Build

```bash
swift build                          # debug build
swift build -c release               # release build
cp .build/release/photo-crawler ~/bin/photo-crawler  # install
```

## Run

```bash
photo-crawler scan      # one-shot scan
photo-crawler watch     # continuous polling (30s default)
photo-crawler status    # show stats
photo-crawler config    # print config
photo-crawler help      # usage info
```

## Test a single image

```bash
photo-crawler test ~/path/to/image.jpg              # classification only (free)
photo-crawler test ~/path/to/image.jpg --extract     # + Claude extraction
photo-crawler test ~/path/to/image.jpg --save        # + save to vault
```

## Config

Config file: `~/.config/photo-crawler/config.json`

Key fields: `vault_path`, `api_key`, `album` (Photos album name), `scan_interval_seconds`, `model`

Run `photo-crawler init` to create a default config.

## Key files

- `Packages/PhotoCrawlerCore/Sources/PhotoCrawlerCore/Services/ClaudeExtractor.swift` — Claude API prompts (system prompt, extraction logic)
- `Packages/PhotoCrawlerCore/Sources/PhotoCrawlerCore/Services/MarkdownGenerator.swift` — output format (frontmatter, inline highlights)
- `Packages/PhotoCrawlerCore/Sources/PhotoCrawlerCore/Services/PhotoScanner.swift` — PhotoKit album scanning
- `Packages/PhotoCrawlerCore/Sources/PhotoCrawlerCore/Services/VaultWriter.swift` — vault writes + asset_id dedup scanning
- `Packages/PhotoCrawlerCore/Sources/PhotoCrawlerCore/Services/ProcessingPipeline.swift` — orchestrator
- `Sources/CLI/Commands.swift` — all CLI command implementations
- `Sources/CLI/ConfigFile.swift` — config JSON schema
