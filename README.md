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
                                              captures/book_page/genesis/snapshot-001.md
```

You control what gets processed by adding photos to a specific album. No heuristic filtering — if it's in the album, it gets extracted.

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
  "vault_path": "/Users/you/Library/Mobile Documents/com~apple~CloudDocs/obsidian/your-vault"
}
```

To find your Obsidian vault path: `ls ~/Library/Mobile\ Documents/com~apple~CloudDocs/obsidian/`

### 3. Create album

Open **Photos** on your Mac or iPhone and create an album called **"crawler"**.

This is the album photo-crawler watches. Add photos you want extracted to this album.

### 4. Grant Photos access

Go to **System Settings → Privacy & Security → Photos** → toggle on **Terminal** (or your terminal app).

### 5. Run

```bash
photo-crawler watch
```

Add a photo to your "crawler" album — it shows up in your vault within 30 seconds.

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
| `album` | `"PhotoCrawler"` | Name of the Photos album to watch |
| `scan_interval_seconds` | `30` | How often `watch` mode polls |
| `model` | `claude-sonnet-4-20250514` | Claude model for extraction |
| `max_concurrent_api_calls` | `3` | Max parallel Claude API requests |
| `initial_scan_days` | `30` | How far back to scan on first run |

## Output Structure

Files are organized under `{vault}/captures/`:

```
captures/
  book_page/
    genesis/
      snapshot-001.md
  article/
    how-to-scale-your-model/
      snapshot-001.md
  flashcard/
    日语口语900句/
      snapshot-001.md
  notes/
    unknown/
      snapshot-001.md
```

## Re-scanning

Each note contains an `asset_id` in its frontmatter. photo-crawler checks the vault for existing notes before processing. **Delete a note from Obsidian and the photo will be re-extracted on the next poll** — useful if you want a better extraction or the first one was wrong.

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
→ Create an album called "crawler" in the Photos app (Mac or iPhone). The name must match the `album` field in your config.

**"Photo library access denied"**
→ System Settings → Privacy & Security → Photos → enable your terminal app.

**"No .obsidian directory found"**
→ Make sure `vault_path` points to the root of your Obsidian vault (the directory containing `.obsidian/`).

**"No config file found"**
→ Run `photo-crawler init` first.

**"command not found: photo-crawler"**
→ Make sure `~/bin` is in your PATH. Add `export PATH="$HOME/bin:$PATH"` to `~/.zshrc` and run `source ~/.zshrc`.
