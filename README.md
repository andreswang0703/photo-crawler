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

- macOS 13+ (Ventura or later)
- Swift toolchain (`xcode-select --install`)
- An [Anthropic API key](https://console.anthropic.com/)
- An Obsidian vault (iCloud-synced or local)

## Setup

### 1. Build and install

```bash
git clone <repo-url> photo-crawler
cd photo-crawler
swift build -c release
mkdir -p ~/bin
cp .build/release/photo-crawler ~/bin/photo-crawler
```

Make sure `~/bin` is in your PATH. Add this to `~/.zshrc` if needed:

```bash
export PATH="$HOME/bin:$PATH"
```

Then reload: `source ~/.zshrc`

### 2. Create config

```bash
photo-crawler init
```

Open the config file and set your vault path and API key:

```bash
open ~/.config/photo-crawler/config.json
```

```json
{
  "album": "crawler",
  "api_key": "sk-ant-api03-...",
  "vault_path": "/Users/you/Library/Mobile Documents/com~apple~CloudDocs/obsidian/your-vault"
}
```

To find your iCloud Obsidian vault path:

```bash
ls ~/Library/Mobile\ Documents/com~apple~CloudDocs/obsidian/
```

Or for vaults synced via the Obsidian iCloud plugin:

```bash
ls ~/Library/Mobile\ Documents/iCloud~md~obsidian/Documents/
```

The path must contain a `.obsidian/` subdirectory.

### 3. Create the album in Apple Photos

Open the **Photos** app on your Mac or iPhone and create a new album called **"crawler"** (or whatever you set in the `album` config field).

This is the album photo-crawler watches. Only photos in this album will be processed.

### 4. Grant Terminal access to Photos

photo-crawler needs permission to read your Photos library. Go to:

**System Settings → Privacy & Security → Photos** → toggle on your terminal app (Terminal, iTerm2, etc.)

If you don't see your terminal app listed, run `photo-crawler scan` once — macOS will prompt you to grant access. Then go to the Settings above and make sure it's enabled.

### 5. Test it

Add a photo of a book page to your "crawler" album, then:

```bash
photo-crawler scan
```

You should see the extracted markdown appear in your vault under `captures/`.

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

## Output

Extracted content is written to `{vault}/captures/`:

```
vault/captures/
  book_page/
    genesis/
      snapshot-001.md
      snapshot-002.md
    sapiens/
      snapshot-001.md
  article/
    ai-2027/
      snapshot-001.md
  duolingo/
    spanish/
      snapshot-001.md
```

Each file has minimal YAML frontmatter and inline highlights:

```markdown
---
source: "Genesis"
captured: 2026-02-07T03:51:26Z
---

# Genesis (p. 64)

Planning machines would need to combine the linguistic fluency
of a large language model with <u>the multivariate, multistep
analyses employed by game-playing AIs</u> — and transcend the
abilities of both.

> **Summary:** Discussion of AI planning machines combining language models with game-playing capabilities.
```

Highlighted/underlined passages from the original photo are rendered inline: `<u>underlined</u>`, `==highlighted==`, `**[circled]**`.

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
- **State:** `~/Library/Application Support/PhotoCrawler/state.json` — tracks processed photo IDs
- **Output:** `{vault}/captures/`

State is safe to delete — photo-crawler will re-scan on next run.

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
