# RevyD — AI Chief of Staff for macOS

A native macOS dock companion that lives above your dock, syncs your meetings from Granola, debriefs them with structured AI analysis, tracks commitments across conversations, and proactively preps you before upcoming calls.

Built with Swift + AppKit. Zero external dependencies. Powered by Claude.

---

## What Makes RevyD Different

Granola summarizes one meeting. **RevyD connects all of them.**

| Feature | Granola | RevyD |
|---------|---------|-------|
| Meeting summaries | One at a time | Cross-meeting intelligence |
| Commitment tracking | None | Tracks who promised what, across all meetings |
| Pre-meeting prep | None | Auto-surfaces context 10 min before calls |
| Knowledge fusion | None | Cross-references meetings with your local docs |
| People profiles | None | Per-person interaction history + open items |
| Always-on presence | Open an app | Lives on your dock, proactive nudges |

---

## Features

### Dock Companion
- Pixel art robot that walks above your macOS dock
- Click to open chat, drag to reposition
- Expressions change based on state — thinking (blue), happy (green), alert (red)
- Menu bar icon with quick actions

### Granola Meeting Sync
- Reads meetings directly from Granola's local cache — instant, offline, no auth
- Auto-syncs on launch + watches for changes
- Extracts attendees and builds people profiles automatically

### AI-Powered Chat
- Ask anything about your meetings in natural language
- All meeting data served from local SQLite — no MCP tools, no permission prompts
- Powered by Claude Code CLI
- Markdown rendering with proper formatting

### Smart Debrief
- Structured meeting analysis: decisions, action items, commitments, open questions
- Extracts commitments given and received with source quotes
- Stores everything in SQLite for cross-meeting tracking

### Commitment Tracker
- Tracks commitments across all your meetings
- Open / completed / overdue status
- Per-person and per-meeting queries
- Instant local responses — no AI call needed

### Knowledge Index
- Indexes your local markdown, PDF, and text files
- Supports Obsidian vaults with YAML frontmatter
- PDFKit extraction + Vision OCR fallback for scanned documents
- SHA256 change detection for incremental re-indexing
- FTS5 full-text search with BM25 ranking

### Knowledge Fusion
- Cross-references meeting content with your local documents
- "They mentioned the auth rewrite — here's what your design doc says"
- Relevant docs injected into AI context alongside meeting data

### People Profiles
- Per-person view across all interactions
- Meeting count, topics discussed, open commitments
- Fuzzy name matching for deduplication

### Calendar Integration
- EventKit integration for reading upcoming events
- Detects meetings starting within 10 minutes
- Extracts attendee names for prep context

### Proactive Scheduler
- Checks every 60 seconds for upcoming meetings + overdue commitments
- Pre-meeting prep: surfaces past interactions, open commitments, related docs
- Overdue alerts: character shows bubble notification
- Weekly summary generation

### Polish
- Liquid glass UI with NSVisualEffectView vibrancy
- Shimmer skeleton loading while AI thinks
- Starter prompt carousel with SF Symbols
- Onboarding flow with setup status checks
- Logout & reset from menu bar
- App icon from character avatar

---

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Platform | macOS 14+ (Sonoma) |
| Language | Swift 5.9 |
| UI | AppKit + NSVisualEffectView |
| Database | SQLite via C API (libsqlite3) |
| Search | FTS5 with BM25 ranking |
| AI | Claude Code CLI |
| PDF | PDFKit + Vision (OCR) |
| Calendar | EventKit |
| Dependencies | **Zero** external packages |

---

## Project Structure

```
RevyD/
├── App/                    # App lifecycle, controller, settings, menu bar
├── Character/              # Dock avatar, movement, popover, expressions
├── Session/                # Claude Code CLI integration, prompt templates
├── Data/                   # SQLite database, stores, FTS5 search index
├── Granola/                # Local cache reader, sync engine
├── Knowledge/              # Document indexer, PDF/markdown extractors, fusion
├── Intelligence/           # Debrief engine, commitment tracker, prep, scheduler
├── Calendar/               # EventKit integration
├── Terminal/               # Chat UI, markdown renderer, shimmer loading
├── Support/                # Theme, window helpers
├── CharacterSprites/       # Robot avatar + expression variants + Granola logo
└── Assets.xcassets/        # App icon, menu bar icon
```

---

## Getting Started

### Prerequisites
- macOS 14.0+ (Sonoma)
- [Claude Code](https://claude.ai/download) installed and logged in
- [Granola](https://granola.ai) installed with meetings
- Xcode 16+ (to build)

### Build & Run

```bash
# Clone
git clone https://github.com/revanupoju/RevyD.git
cd RevyD

# Install xcodegen (if needed)
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Build
xcodebuild -project RevyD.xcodeproj -scheme RevyD -configuration Debug build

# Run
open build/Build/Products/Debug/RevyD.app
```

### First Launch
1. The robot appears on your dock
2. Click it to open the chat
3. Click "Sync Meetings" to pull your Granola meetings
4. Try: "Debrief my last meeting" or "Who do I meet with most?"

---

## Data Storage

All data stays on your machine:
- Database: `~/Library/Application Support/RevyD/revyd.db`
- Granola data read from: `~/Library/Application Support/Granola/cache-v6.json`
- No cloud sync, no external API calls for data storage

---

## License

MIT

---

Built by [@revanupoju](https://x.com/revanupoju)
