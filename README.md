# photo-crawler

Extract text from photos of book pages, articles, and learning content into your Obsidian vault — automatically.

You take photos of book passages, screenshot articles, Duolingo exercises, and other learning content on your phone. Getting that into Obsidian means manual retyping. This tool automates it: add photos to a designated album → extract text via Claude AI → structured markdown appears in your vault.

## How It Works

```
iPhone photo → add to "crawler" album → iCloud Photos sync → macOS
                                                                ↓
                                              photo-crawler watches the album
                                                                ↓
                                              Claude API extracts structured text
                                              (~$0.005/image)
                                                                ↓
                                              Markdown → Obsidian vault
                                              captures/... (path is prompt-driven)
```

If `album` is empty, photo-crawler scans your entire Photos library instead.

You control what gets processed by adding photos to a specific album. No heuristic filtering — if it's in the album, it gets extracted. (Set `album` to empty to scan the entire library.)

## Requirements

- macOS 13+ (Apple Silicon)
- An [Anthropic API key](https://console.anthropic.com/)
- An Obsidian vault (iCloud-synced or local)

## Setup

### 1. Install

```bash
curl -L -o photo-crawler https://github.com/andreswang0703/photo-crawler/releases/download/v0.1.0/photo-crawler
chmod +x photo-crawler
sudo mv photo-crawler /usr/local/bin/
```

### 2. Configure

```bash
photo-crawler init
open ~/.config/photo-crawler/config.json
```

Set your vault path and API key:

```json
{
  "album": "crawler",
  "api_key": "sk-ant-api03-...",
  "vault_path": "/Users/you/Library/Mobile Documents/com~apple~CloudDocs/obsidian/your-vault",
  "global_rules": [
    "Only extract book notes.",
    "Skip photos that are personal or not text-based learning content."
  ],
  "categories": [],
  "default": {
    "extraction_rules": "Extract readable text. Add a short summary.",
    "write_rule": "Create a new note under captures/notes/unknown/ using asset_id as filename."
  }
}
```

To find your Obsidian vault path: `ls ~/Library/Mobile\ Documents/com~apple~CloudDocs/obsidian/`

### 3. Create album (optional)

Open **Photos** on your Mac or iPhone and create an album called **"crawler"**.

This is the album photo-crawler watches. Add photos you want extracted to this album.
If you leave `album` empty, photo-crawler will scan your **entire Photos library** instead (higher cost).

### 4. Grant Photos access

Go to **System Settings → Privacy & Security → Photos** → toggle on **Terminal** (or your terminal app).

### 5. Run

```bash
photo-crawler watch
```

Add a photo to your "crawler" album — it shows up in your vault within 30 seconds. If you leave `album` empty, any new photo in your library can be processed.

### Build from source (optional)

If you prefer to build yourself:

```bash
git clone https://github.com/andreswang0703/photo-crawler.git
cd photo-crawler
swift build -c release
sudo cp .build/release/photo-crawler /usr/local/bin/
```

Requires Swift toolchain (`xcode-select --install`).

## Usage

### Watch mode (continuous)

```bash
photo-crawler watch
```

Polls the album every 30 seconds (configurable via `scan_interval_seconds` in config). Press Ctrl+C to stop.

### Single scan

```bash
photo-crawler scan
```

Runs once and exits.

### Test a single image file

```bash
# Classification only (free, on-device OCR)
photo-crawler test ~/Desktop/book-page.jpg

# Classification + Claude extraction
photo-crawler test ~/Desktop/book-page.jpg --extract

# Extract and save to vault
photo-crawler test ~/Desktop/book-page.jpg --save
```

### Check status

```bash
photo-crawler status
```

### View config

```bash
photo-crawler config
```

## Config Options

| Field | Default | Description |
|-------|---------|-------------|
| `vault_path` | `""` | **(required)** Path to Obsidian vault root |
| `api_key` | `""` | **(required)** Anthropic API key (or set `ANTHROPIC_API_KEY` env var) |
| `album` | `"PhotoCrawler"` | Name of the Photos album to watch. Set to `""` to scan the entire Photos library |
| `scan_interval_seconds` | `30` | How often `watch` mode polls |
| `model` | `claude-sonnet-4-20250514` | Claude model for extraction |
| `max_concurrent_api_calls` | `3` | Max parallel Claude API requests |
| `initial_scan_days` | `30` | How far back to scan on first run |
| `categories` | `[]` | Prompt-driven extraction categories (see below) |
| `default` | `{...}` | Fallback rules when no category matches |
| `global_rules` | `[]` | Natural-language rules applied to all categories |

## Prompt-Driven Categories (Natural Language)

You can define categories with natural-language rules. The app turns these rules into a concrete write plan automatically.

Example category (Duolingo):

```json
{
  "name": "duolingo",
  "hint": "screenshots of Duolingo lessons and exercises",
  "extraction_rules": "Only extract the single sentence being tested. Ignore word bank options and UI. Output content as a short bullet list with the sentence and its English translation.",
  "write_rule": "Append to a monthly note per language under captures/languages/<language>/YYYYMM.md. Add a date header (YYYY-MM-DD) and append the sentence under that header. If language is unclear, use unknown."
}
```

Example category (Recipe):

```json
{
  "name": "recipe",
  "hint": "photos or screenshots of recipes",
  "extraction_rules": "Extract ingredients and steps. Format with headings: Ingredients, Steps.",
  "write_rule": "Create a new note under captures/recipes/<title>.md."
}
```

Full config example:

```json
{
  "vault_path": "/Users/you/Library/Mobile Documents/com~apple~CloudDocs/obsidian/your-vault",
  "api_key": "sk-ant-api03-...",
  "album": "crawler",
  "scan_interval_seconds": 30,
  "model": "claude-sonnet-4-20250514",
  "global_rules": [
    "Only extract book notes.",
    "Skip anything that is not text-based learning content."
  ],
  "categories": [
    {
      "name": "duolingo",
      "hint": "screenshots of Duolingo lessons and exercises",
      "extraction_rules": "Only extract the single sentence being tested. Ignore word bank options and UI. Output content as a short bullet list with the sentence and its English translation.",
      "write_rule": "Append to a monthly note per language under captures/languages/<language>/YYYYMM.md. Add a date header (YYYY-MM-DD) and append the sentence under that header. If language is unclear, use unknown."
    }
  ],
  "default": {
    "extraction_rules": "Extract readable text. Add a short summary.",
    "write_rule": "Create a new note under captures/notes/unknown/ using asset_id as filename."
  }
}
```

## Output Structure

Files are organized under `{vault}/captures/`:

```
captures/
  notes/
    unknown/
      <asset_id>.md
  languages/
    spanish/
      202602.md
```

## Re-scanning

Each note contains `asset_ids` in frontmatter. photo-crawler checks the vault for existing asset IDs before processing. **Delete a note from Obsidian and the photo will be re-extracted on the next poll** — useful if you want a better extraction or the first one was wrong.

## Debug Mode

Print Claude prompts and raw JSON output:

```bash
PHOTO_CRAWLER_DEBUG_PROMPT=1 PHOTO_CRAWLER_DEBUG_JSON=1 photo-crawler watch
```

## Running as a Background Service

To run photo-crawler automatically using macOS `launchd`:

```bash
cat > ~/Library/LaunchAgents/com.photocrawler.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.photocrawler</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/you/bin/photo-crawler</string>
        <string>watch</string>
    </array>
    <key>StandardOutPath</key>
    <string>/tmp/photo-crawler.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/photo-crawler.err</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF

launchctl load ~/Library/LaunchAgents/com.photocrawler.plist
```

Check logs: `tail -f /tmp/photo-crawler.log`

Stop: `launchctl unload ~/Library/LaunchAgents/com.photocrawler.plist`

## State and Data

- **Config:** `~/.config/photo-crawler/config.json`
- **State:** `~/Library/Application Support/PhotoCrawler/state.json` — processing stats only
- **Output:** `{vault}/captures/` — the vault itself is the source of truth for what's been processed (via `asset_id` in frontmatter)

## Cost

~$0.005 per photo (using claude-sonnet). If you capture 10 book pages per day, that's ~$0.05/day or ~$1.50/month.

## Troubleshooting

**"Album 'crawler' not found in Photos"**
→ Create an album called "crawler" in the Photos app (Mac or iPhone). The name must match the `album` field in your config. If `album` is empty, the entire library is scanned.

**"Photo library access denied"**
→ System Settings → Privacy & Security → Photos → enable your terminal app.

**"No .obsidian directory found"**
→ Make sure `vault_path` points to the root of your Obsidian vault (the directory containing `.obsidian/`).

**"No config file found"**
→ Run `photo-crawler init` first.

**"command not found: photo-crawler"**
→ Make sure `~/bin` is in your PATH. Add `export PATH="$HOME/bin:$PATH"` to `~/.zshrc` and run `source ~/.zshrc`.
