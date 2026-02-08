# photo-crawler

Turn photos of book pages, articles, and learning content into structured notes in your Obsidian vault — automatically.

You snap a photo of a book passage on your phone, add it to a Photos album, and a few seconds later it shows up as a markdown note in Obsidian. That's it.

Works with book pages, articles, Duolingo screenshots, code snippets, recipes, flashcards — anything with text. Claude AI does the extraction (~$0.005 per photo).

**Everything is customizable with plain-English prompts.** You tell photo-crawler *what* to extract and *where* to put it — no code, no templates, just describe what you want:

```json
{
  "name": "recipe",
  "hint": "photos or screenshots of recipes",
  "extraction_rules": "Extract ingredients and steps. Format with headings.",
  "write_rule": "Create a new note under captures/recipes/<title>.md."
}
```

Want Duolingo sentences appended to a monthly log? Book highlights grouped by chapter? Just say so in your config.

## Quick Start

```bash
# 1. Install
curl -L -o photo-crawler https://github.com/andreswang0703/photo-crawler/releases/download/v0.1.0/photo-crawler
chmod +x photo-crawler && sudo mv photo-crawler /usr/local/bin/

# 2. Create a config file
photo-crawler init

# 3. Add your API key and vault path
open ~/.config/photo-crawler/config.json
# Set "api_key" and "vault_path", save the file

# 4. Create an album called "PhotoCrawler" in the Photos app

# 5. Grant Photos access: System Settings → Privacy & Security → Photos → enable Terminal

# 6. Start watching
photo-crawler watch
```

Add a photo to your "PhotoCrawler" album — it appears in your vault within 30 seconds.

## How It Works

```
Phone: snap photo → add to album → iCloud syncs to Mac
                                          ↓
                            photo-crawler detects new photo
                                          ↓
                            on-device OCR checks if it's text (free)
                                          ↓
                            Claude extracts structured content (~$0.005)
                                          ↓
                            markdown note appears in your vault
```

## Requirements

- macOS 13+ (Apple Silicon)
- [Anthropic API key](https://console.anthropic.com/)
- An Obsidian vault (iCloud-synced or local)

## Commands

| Command | What it does |
|---------|-------------|
| `photo-crawler watch` | Polls your album continuously (Ctrl+C to stop) |
| `photo-crawler scan` | One-shot scan, then exits |
| `photo-crawler test <image>` | Classify an image locally (free) |
| `photo-crawler test <image> --extract` | Classify + send to Claude |
| `photo-crawler test <image> --save` | Classify + extract + save to vault |
| `photo-crawler status` | Show processing stats |
| `photo-crawler config` | Print current config |
| `photo-crawler init` | Create default config file |

## Configuration

Config lives at `~/.config/photo-crawler/config.json`. The two required fields are:

```json
{
  "vault_path": "/Users/you/path/to/your/obsidian-vault",
  "api_key": "sk-ant-api03-..."
}
```

> **Tip:** You can also set the API key via the `ANTHROPIC_API_KEY` env var instead of putting it in the config file.

> **Finding your vault path:** Run `ls ~/Library/Mobile\ Documents/com~apple~CloudDocs/obsidian/` if your vault is iCloud-synced.

Everything else has sensible defaults. Here are the main knobs:

| Field | Default | What it does |
|-------|---------|-------------|
| `album` | `"PhotoCrawler"` | Photos album to watch (empty = entire library) |
| `scan_interval_seconds` | `30` | How often watch mode polls |
| `model` | `claude-sonnet-4-20250514` | Claude model for extraction |
| `global_rules` | `[]` | Natural-language rules applied to everything |
| `categories` | `[]` | Custom extraction categories |

### Custom categories

Each category has four fields — a `name`, a `hint` so Claude knows when to apply it, `extraction_rules` for *what* to pull out, and a `write_rule` for *where* to put it. All in plain English.

```json
{
  "categories": [
    {
      "name": "duolingo",
      "hint": "screenshots of Duolingo lessons and exercises",
      "extraction_rules": "Only extract the sentence being tested. Output as a bullet list with the sentence and its English translation.",
      "write_rule": "Append to a monthly note under captures/languages/<language>/YYYYMM.md."
    }
  ]
}
```

You can define as many categories as you want. Photos that don't match any category fall through to the `default` rules.

### Global rules

These apply to every photo, regardless of category. Useful for filtering:

```json
{
  "global_rules": [
    "Only extract book notes.",
    "Skip photos that are personal or not text-based learning content."
  ]
}
```

## Re-scanning

Each note tracks which photos it came from via `asset_ids` in the frontmatter. If you delete a note from Obsidian, the photo gets re-extracted on the next poll — handy when you want a better extraction.

## Running in the Background

You can set up `launchd` so photo-crawler starts automatically when you log in:

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
        <string>/usr/local/bin/photo-crawler</string>
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

## Debug Mode

See what's being sent to Claude and what comes back:

```bash
PHOTO_CRAWLER_DEBUG_PROMPT=1 PHOTO_CRAWLER_DEBUG_JSON=1 photo-crawler watch
```

## Cost

About **$0.005 per photo** with Claude Sonnet. 10 photos a day comes out to ~$1.50/month.

## Build from Source

```bash
git clone https://github.com/andreswang0703/photo-crawler.git
cd photo-crawler
swift build -c release
sudo cp .build/release/photo-crawler /usr/local/bin/
```

Requires Xcode command line tools (`xcode-select --install`).

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "Album not found" | Create an album matching your `album` config value in Photos. Default is "PhotoCrawler". |
| "Photo library access denied" | System Settings → Privacy & Security → Photos → enable your terminal app |
| "No .obsidian directory found" | `vault_path` should point to the folder that contains `.obsidian/` |
| "No config file found" | Run `photo-crawler init` first |
| "command not found" | Make sure `/usr/local/bin` is in your PATH |

## Data & State

| What | Where |
|------|-------|
| Config | `~/.config/photo-crawler/config.json` |
| Processing state | `~/Library/Application Support/PhotoCrawler/state.json` |
| Output notes | `{vault}/captures/` — this is the source of truth for dedup |
