# CLAUDE.md

## What this project is

photo-crawler is a macOS CLI that watches a specific Apple Photos album, extracts text from each photo using Claude API, and writes structured markdown to an Obsidian vault. The user adds photos of book pages, articles, lecture slides, flashcards, etc. to the album — everything in the album gets processed.

## Architecture

Two Swift packages:
- `Packages/PhotoCrawlerCore/` — platform-agnostic library (Models, Services, Networking)
- `Sources/CLI/` — CLI executable wrapping the core library

Pipeline: PhotoScanner (fetch from album) → LocalClassifier (OCR filter) → ClaudeExtractor (Claude API) → MarkdownGenerator → VaultWriter (iCloud-safe writes)

Dedup: notes store `asset_ids` in YAML frontmatter. On each poll, the vault is scanned for existing asset IDs. Deleting a note causes re-extraction.

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

Key fields: `vault_path`, `api_key`, `album` (Photos album name, empty means full library), `scan_interval_seconds`, `model`, `categories`, `default`, `global_rules`

Run `photo-crawler init` to create a default config.

### Prompt-driven categories

Each category defines natural-language rules. The app translates them into a concrete write plan.

Example category:

```json
{
  "name": "duolingo",
  "hint": "screenshots of Duolingo lessons and exercises",
  "extraction_rules": "Only extract the single sentence being tested. Ignore word bank options and UI. Output content as a short bullet list with the sentence and its English translation.",
  "write_rule": "Append to a monthly note per language under captures/languages/<language>/YYYYMM.md. Add a date header (YYYY-MM-DD) and append the sentence under that header. If language is unclear, use unknown."
}
```

### Global rules

Global rules apply to every category and are written in plain language. Example:

```json
{
  "global_rules": [
    "Only extract book notes.",
    "Skip photos that are personal or not text-based learning content."
  ]
}
```

### Debug mode

Print prompts and raw JSON:

```bash
PHOTO_CRAWLER_DEBUG_PROMPT=1 PHOTO_CRAWLER_DEBUG_JSON=1 photo-crawler watch
```

## Key files

- `Packages/PhotoCrawlerCore/Sources/PhotoCrawlerCore/Services/ClaudeExtractor.swift` — Claude API prompts (system prompt, extraction logic)
- `Packages/PhotoCrawlerCore/Sources/PhotoCrawlerCore/Services/MarkdownGenerator.swift` — output format (frontmatter)
- `Packages/PhotoCrawlerCore/Sources/PhotoCrawlerCore/Services/PhotoScanner.swift` — PhotoKit album scanning
- `Packages/PhotoCrawlerCore/Sources/PhotoCrawlerCore/Services/VaultWriter.swift` — vault writes + asset_ids dedup scanning
- `Packages/PhotoCrawlerCore/Sources/PhotoCrawlerCore/Services/ProcessingPipeline.swift` — orchestrator
- `Sources/CLI/Commands.swift` — all CLI command implementations
- `Sources/CLI/ConfigFile.swift` — config JSON schema
