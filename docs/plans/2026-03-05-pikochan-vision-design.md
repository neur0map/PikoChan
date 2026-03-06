# PikoChan Vision & Architecture Design

**Date**: 2026-03-05
**Status**: Approved
**Version**: v0.2+ roadmap

---

## What Is PikoChan?

PikoChan is an **open-source, local-first AI companion** that lives in your macOS hardware notch. She's a buddy — not a code assistant, not a corporate chatbot. She has personality, opinions, moods, and the ability to help with everyday PC tasks.

**Inspirations**:
- **Project Airi** (moeru-ai) — Soul container architecture, personality as composable middleware, Alaya memory with forgetting curves and emotional scoring
- **OpenClaw** — Terminal control, browser automation, MCP tool execution, heartbeat (proactive monitoring), skills system (SKILL.md files)
- **Neuro-sama** — A character with genuine personality that mocks you, celebrates you, and isn't afraid to have opinions

**What makes PikoChan different**: Everything is native macOS Swift. No Electron. No web stack. She lives in the notch — not in a chat window. Local LLMs first, cloud optional. Fully open source, community-first.

---

## Architecture: Four Layers

```
┌─────────────────────────────────────────────┐
│              Layer 1: NOTCH UI              │
│  SwiftUI frontend, animations, notch states │
│  (v0.1.0-alpha — exists today)              │
├─────────────────────────────────────────────┤
│              Layer 2: BRAIN                 │
│  PikoBrain    — LLM orchestrator            │
│  PikoSoul     — personality + mood system   │
│  PikoMemory   — vector DB + SQLite          │
│  PikoMCP      — MCP client (Swift SDK)      │
├─────────────────────────────────────────────┤
│              Layer 3: HANDS                 │
│  PikoTerminal     — AppleScript terminal    │
│  PikoBrowser      — CDP + AppleScript       │
│  PikoAccessibility — AXorcist screen reader │
│  PikoHeartbeat    — background awareness    │
├─────────────────────────────────────────────┤
│              Layer 4: SKILLS                │
│  Markdown skill files (YAML frontmatter)    │
│  User-created, downloadable, shareable      │
│  PikoChan reads them as instructions        │
└─────────────────────────────────────────────┘
```

---

## Layer 2: The Brain

### LLM Strategy: Local-First with Cloud Fallback

**Primary**: MLX Swift for local inference on Apple Silicon.
**Fallback**: llama.cpp via LocalLLMClient for models MLX doesn't support yet.
**Cloud optional**: OpenAI, Anthropic, or any provider via unified SDK (AnyLanguageModel / Conduit).
**User choice**: Model selection in settings. Start with small models, scale up.

**Starting models** (conversation-focused, personality-capable):
- Phi-3.5 mini (3.8B) — Microsoft, great at conversation
- Qwen2.5 (3B) — Alibaba, multilingual, personality-aware
- Gemma 2 (2B) — Google, efficient, good personality prompting
- Apple Foundation Models (~3B, macOS 26+) — zero-config, free

**Key packages**:
- [mlx-swift](https://github.com/ml-explore/mlx-swift) — Apple's ML framework for Swift
- [LocalLLMClient](https://github.com/tattn/LocalLLMClient) — Unified MLX + llama.cpp
- [AnyLanguageModel](https://huggingface.co/blog/anylanguagemodel) — Unified API for all backends
- [OllamaKit](https://github.com/kevinhermawan/OllamaKit) — Optional Ollama integration

### Soul Container + Mood System

PikoChan's personality is **not a hardcoded system prompt**. It's a composable middleware system:

**Soul Container** (inspired by Project Airi):
- Base personality traits loaded from `~/.pikochan/soul/personality.yaml`
- Communication style rules (sass level, humor, formality)
- Behavioral constraints (what she won't do, safety boundaries)
- Memory hooks (how personality connects to stored memories)

**Mood System** (unique to PikoChan):
- Dynamic mood state that shifts based on observations
- Mood affects response tone: snarky, encouraging, concerned, playful
- Mood triggers defined in personality config
- Mood decays over time back to baseline

**mood.yaml example**:
```yaml
current: neutral
baseline: playful
decay_rate: 0.1  # per hour, back toward baseline
states:
  irritated:
    triggers: [user_idle_too_long, repeated_mistakes]
    sass_modifier: +3
  proud:
    triggers: [task_completed, productive_session]
    encouragement_modifier: +2
  concerned:
    triggers: [late_night_session, no_breaks]
    care_modifier: +3
```

### Voice Layer (TTS)

**Local-first**:
- sherpa-onnx with Swift bindings (on-device TTS, multiple voices)
- MLX-based TTS models via Hugging Face
- Ollama TTS models (if available)

**Cloud optional**:
- ElevenLabs v2 API (premium, high-quality voices)
- Config in `~/.pikochan/soul/voice.yaml`

### Memory System

**VecturaKit** (pure Swift on-device vector database):
- Hybrid search: semantic similarity + BM25 keyword matching
- Embedding via swift-embeddings (MLTensor) or NaturalLanguage framework
- No external processes, no Redis, no Python

**SQLite** (structured data via SwiftData or GRDB):
- Conversation history
- User profile and preferences
- Mood history over time
- Skill execution logs

**Memory pipeline**:
1. Each conversation turn → extract key facts via LLM
2. Embed facts → store in VecturaKit
3. Before responding → query VecturaKit for relevant memories
4. Inject memories into prompt context
5. Periodic consolidation: summarize old memories into higher-level notes
6. PikoChan writes a human-readable `journal.md` of important things she remembers

### MCP Integration

**Official Swift MCP SDK** ([modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk)):
- Native Swift, no sidecar needed
- Connects to any standard MCP server
- User configures servers in `~/.pikochan/mcp/servers.yaml`
- Example tools: email access, calendar, file search, web scraping

---

## Layer 3: The Hands

### PikoTerminal — Terminal Control

**How it works**:
1. Check `NSWorkspace.shared.runningApplications` for Terminal.app or iTerm2
2. If found: use AppleScript to type command into existing window
3. User manually hits Enter (safety boundary — PikoChan never auto-executes)
4. If no terminal: ask user "want me to open one?"

**AppleScript for Terminal.app**:
```swift
let script = """
tell application "Terminal"
    do script "\(command)" in front window
end tell
"""
```

**Requirements**: Apple Events entitlement, Accessibility permission, non-sandboxed distribution.

### PikoBrowser — Browser Automation

**Three tiers**:
1. **AppleScript** — Quick tasks: open URL, execute JS in Safari/Chrome
2. **Chrome DevTools Protocol** — Full Chrome control via WebSocket (no dependencies)
3. **Playwright MCP** — Complex AI-driven automation (optional, requires Node.js)

### PikoAccessibility — Screen Reading

**AXorcist** library for reading what's on screen:
- Frontmost app name and window title
- Active text field contents (with permission)
- UI element inspection

Used by PikoHeartbeat to understand what the user is doing.

### PikoHeartbeat — Background Awareness

Runs every 30-60 seconds:
- Frontmost app (via `NSWorkspace.shared.frontmostApplication`)
- Idle time (via `CGEventSource.secondsSinceLastEventType`)
- Time of day
- Optional: active window title (via Accessibility API)

Feeds observations to PikoSoul's mood system. PikoChan may:
- Suggest a break after long sessions
- Comment on app switches
- Notice patterns ("you always open Spotify around this time")
- Stay quiet when you're focused (respects flow state)

---

## Layer 4: Skills

### Skill File Format (inspired by OpenClaw)

Skills are Markdown files with YAML frontmatter. PikoChan reads them as natural-language instructions.

**Example: `~/.pikochan/skills/weather.md`**:
```markdown
---
name: Weather Check
trigger: weather, forecast, temperature
permissions:
  - browser
description: Check the current weather for the user's location.
---

# Weather Check

When the user asks about weather:
1. Open their default browser to wttr.in/{location}
2. Or use the browser to search "{location} weather"
3. Report back with temperature and conditions
4. Add a personality comment based on the weather
```

**Skill discovery**: PikoChan scans `~/.pikochan/skills/` on startup. Users can:
- Write their own skill files
- Download community skills
- PikoChan can write new skills herself (self-improving)

---

## Home Directory Structure

```
~/.pikochan/
├── config.yaml               # Global config: LLM provider, model paths, API keys
├── soul/
│   ├── personality.yaml      # Base traits, communication style, quirks, sass level
│   ├── mood.yaml             # Current mood state, triggers, decay rules
│   └── voice.yaml            # TTS config: local model or ElevenLabs v2
├── skills/
│   ├── terminal.md           # Built-in: terminal control skill
│   ├── browser.md            # Built-in: browser control skill
│   ├── weather.md            # Built-in: weather check
│   └── custom/               # User-created or downloaded skills
├── memory/
│   ├── pikochan.db           # SQLite: conversations, user profile, mood history
│   ├── vectors/              # VecturaKit semantic search index
│   └── journal.md            # Human-readable memory log PikoChan writes
├── mcp/
│   └── servers.yaml          # MCP server configurations
└── models/
    └── (downloaded model files or symlinks)
```

All files are:
- **Plain text** (YAML, Markdown, SQLite) — human-readable and editable
- **Git-friendly** — can version control your PikoChan's personality
- **AI-modifiable** — PikoChan can edit her own configs with permission
- **Portable** — copy the folder to a new Mac, PikoChan comes with you

---

## Tech Stack Summary

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| Frontend | Swift / SwiftUI / AppKit | Native macOS, lives in notch |
| LLM (local) | MLX Swift + llama.cpp | Apple Silicon optimized, broad model support |
| LLM (cloud) | OpenAI / Anthropic / any | Optional fallback for complex tasks |
| MCP | Official Swift MCP SDK | Native, no sidecar, connects to any MCP server |
| Terminal | AppleScript via Process | Simple, reliable, well-documented |
| Browser | CDP + AppleScript | Native Chrome/Safari control |
| Screen reading | AXorcist (Accessibility API) | Modern Swift wrapper, async/await |
| Embeddings | VecturaKit + swift-embeddings | Pure Swift, on-device, hybrid search |
| Structured DB | SQLite via SwiftData/GRDB | Native, no external processes |
| TTS (local) | sherpa-onnx / MLX TTS | On-device, multiple voices |
| TTS (cloud) | ElevenLabs v2 | Optional premium voice |
| STT | sherpa-onnx / Whisper (MLX) | On-device speech recognition |
| Distribution | Developer ID (outside App Store) | Required for Accessibility, AppleEvents, MCP |

---

## Implementation Phases

### v0.2.0 — Brain Foundation ✅ (completed 2026-03-05)
- [x] `~/.pikochan/` directory structure + config loading — `PikoHome.swift` bootstraps full directory tree, `PikoConfig.swift` parses YAML, `PikoConfigStore.swift` provides reactive UI binding
- [x] PikoBrain: local LLM integration — uses Apple FoundationModels (macOS 26+) as primary, Ollama-compatible HTTP endpoint as fallback (pragmatic pivot from MLX Swift; MLX integration deferred to future release)
- [x] Basic chat: type in notch → get response from local LLM — full async flow: `TypingView` → `NotchManager.submitTextInput()` → `PikoBrain.respond(to:)` → response bubble
- [x] Cloud API fallback (OpenAI/Anthropic) when configured — both providers fully wired with API key management, model selection, and automatic fallback from local → cloud
- [x] Response displayed in notch UI (response bubble) — animated bubble overlay in expanded/typing/listening states with "Thinking...", error, and response display
- [x] Settings UI for AI model configuration — `AIModelTab.swift` with provider picker, local/cloud config, API key fields, save/reload

### v0.3.0 — Soul & Memory ✅ (completed 2026-03-06)
- [x] PikoSoul: personality.yaml loading + system prompt construction — mood-first prompt ordering, postHistoryReminder (Airi pattern)
- [x] PikoStore: SQLite (C API) for chat_history + memories tables — persists across restarts
- [x] MoodParser: emotion tag parsing from LLM responses — drives sprite changes
- [x] Memory extraction: internal LLM call extracts facts, stores in SQLite
- [x] Memory recall: oldest-first injection of all stored memories into prompt context
- [x] journal.md: PikoChan writes what she remembers about the user
- [x] PikoGateway: structured JSONL logging — daily rolling, 7-day prune, 50MB cap
- [x] PikoHTTPServer: NWListener HTTP gateway on port 7878 — /chat, /health, /history, /logs, /memories, /config, /mood
- [x] SoulTab: Settings UI for personality editing + memory management
- [x] Brain injection: PikoBrain shared between NotchManager and HTTPServer via AppDelegate

### v0.3.5 — Setup & Semantic Memory ✅ (completed 2026-03-06)
- [x] In-notch first-time setup wizard (5 steps: welcome, provider, providerConfig, memory, summary) — `SetupManager` + 7 new view files
- [x] Provider validation checks — Ollama ping + model list, API key validation for OpenAI/Anthropic, Apple Intelligence availability
- [x] PikoEmbedding: Snowflake Arctic Embed XS (384-dim CoreML, 86MB) primary + Apple NLEmbedding fallback — pivot from NLEmbedding after benchmarking proved 0.19 cosine similarity for retrieval (Arctic scores 0.5-0.7)
- [x] `memory_vectors` SQLite table (BLOB storage, FK cascade) + migration step in setup wizard
- [x] Semantic recall: asymmetric query embedding + cosine similarity top-K via Accelerate.framework, hybrid unvectorized supplement
- [x] `WordPieceTokenizer`: minimal BERT tokenizer for Arctic model (30522 vocab, max 128 tokens)
- [x] SetupManager + SetupView with animated step transitions (horizontal slide, spring 0.45/0.72)
- [x] Re-run setup from Settings → Soul → "Re-run Setup Wizard"
- [x] `PikoSecureField`: bullet-masking NSTextField for API key input in .screenSaver-level panels

### v0.3.6 — Companion Personality & Maintenance ✅ (completed 2026-03-06)
- [x] Post-setup intro message — PikoChan introduces herself and asks for the user's name after first-time setup
- [x] Companion system prompt rewrite — "You are a COMPANION, not an assistant" framing with built-in behavior rules (no "How can I help?", share opinions, react naturally)
- [x] postHistoryReminder rework — stronger personality reinforcement, genuine emotion matching, natural memory weaving
- [x] `respondStreaming(skipHistory:)` — intro messages don't pollute chat history, hardcoded fallback if LLM fails
- [x] Expanded Soul tab — editable traits, firstPerson, refersToUserAs fields + snark level with description
- [x] Storage monitoring — DB size, journal size, vector count displayed in Settings → Soul → Storage section
- [x] `PikoMaintenance` — auto journal rotation (500KB cap, monthly archives), auto chat pruning (90d+), runs on every launch
- [x] `PikoStore.pruneOldTurns(olderThanDays:)` — automatic cleanup of old conversation history
- [x] Settings window title fix — NSTabViewController `.toolbar` style title propagation
- [x] Dynamic scrolling — SoulTab Form scrolls naturally within window instead of fixed-height clipping

### v0.3.7 — Path Guard ✅ (completed 2026-03-06)
- [x] `PikoPathGuard` — OpenClaw-inspired filesystem guardrails with path containment, symlink resolution, and human-readable denial reasons
- [x] Access tiers: `~/.pikochan/` read-write, user dirs read-only, code/app bundles/system denied
- [x] Dangerous path detection — blocks `.swift`, `.app`, `.xcodeproj`, `DerivedData`, `.git`, `~/Library/`, system paths
- [x] Self-awareness injection — `PikoPathGuard.selfAwareness` in system prompt so PikoChan knows her own boundaries
- [x] Foundation for v0.4.0 Hands — every future file operation routes through `PikoPathGuard.check()`

### v0.4.0 — Hands
- [ ] PikoTerminal: detect running terminals, type commands via AppleScript
- [ ] PikoBrowser: open URLs, basic Chrome/Safari control
- [ ] PikoHeartbeat: background awareness (frontmost app, idle time)
- [ ] Mood system: mood shifts based on heartbeat observations

### v0.5.0 — Voice & Skills
- [ ] STT: speech-to-text for the listening state (sherpa-onnx or Whisper)
- [ ] TTS: text-to-speech for responses (local first, ElevenLabs optional)
- [ ] Skills loader: read skill files from ~/.pikochan/skills/
- [ ] Built-in skills: terminal, browser, weather
- [ ] MCP client: connect to external tool servers

### v0.6.0 — Community & Polish
- [ ] Skill sharing format + community repository
- [ ] Personality pack sharing
- [ ] PikoChan self-improvement: she can write new skills
- [ ] Advanced mood system: pattern recognition over time
- [ ] Memory consolidation: periodic summarization of old memories

---

## Post-Alpha Vision (Beta → Stable)

Features beyond the alpha roadmap. These require the foundation layers (Brain, Hands, Voice, Skills) to be stable first.

### Headless Mode & Chat Bridges

PikoChan already runs a headless HTTP gateway (`localhost:7878`). On machines without a notch (Mac Mini, Mac Studio, Mac Pro), she can run as a pure background service — no UI, just brain + gateway.

**Chat bridges** connect the gateway to external messaging platforms:

- **Telegram bridge** — bot that proxies messages between a Telegram chat and `localhost:7878/chat`. Configurable via `~/.pikochan/bridges/telegram.yaml` (bot token, allowed chat IDs)
- **Discord bridge** — Discord bot integration for server or DM conversations with PikoChan
- **Webhook API** — generic webhook endpoint so any platform (Slack, WhatsApp via Twilio, custom apps) can plug in

Bridges are lightweight processes (can be Swift, Python, or Node) that run alongside PikoChan. They share the same PikoBrain — memories, personality, and mood are consistent across all interfaces.

```
~/.pikochan/
├── bridges/
│   ├── telegram.yaml    # bot token, allowed chat IDs
│   ├── discord.yaml     # bot token, server/channel config
│   └── webhook.yaml     # generic webhook endpoints
```

### Proactive Companionship

PikoChan doesn't just wait for you to talk to her — she reaches out.

- **Check-in calls** — PikoChan notices if you haven't chatted in a few days and sends a message ("Hey, haven't heard from you in a while — everything good?"). Frequency configurable, never spammy
- **Voice tone detection** — when TTS/STT is active, PikoChan analyzes vocal patterns (pitch, pace, energy). If she detects signs of low mood or stress, she proactively reaches out to keep you company — not as a therapist, but as a friend who noticed something's off
- **Cross-platform presence** — check-ins work across all bridges (notch, Telegram, Discord). She picks the platform you've been most active on recently

These features require v0.5.0 Voice to be stable. Voice tone analysis uses on-device audio feature extraction — no cloud processing of voice data.

---

## Design Principles

1. **Buddy, not assistant** — PikoChan has personality first, utility second
2. **Local-first** — Everything runs on your Mac. Cloud is optional, never required
3. **Human-readable** — All configs are YAML/Markdown. No black boxes
4. **AI-modifiable** — PikoChan can edit her own configs (with permission)
5. **Start small** — Begin with 2-3B models, prove the concept, scale up
6. **Native macOS** — No Electron, no web stack, no compromise
7. **Open source** — Community-first. Free forever. Your data stays yours
8. **Safety boundaries** — PikoChan suggests, user confirms. Never auto-executes destructive actions

---

## Key Dependencies

| Package | Purpose | URL |
|---------|---------|-----|
| mlx-swift | Local LLM inference | github.com/ml-explore/mlx-swift |
| LocalLLMClient | Unified MLX + llama.cpp | github.com/tattn/LocalLLMClient |
| swift-mcp-sdk | MCP client/server | github.com/modelcontextprotocol/swift-sdk |
| VecturaKit | On-device vector DB | github.com/rryam/VecturaKit |
| swift-embeddings | Local embeddings | github.com/jkrukowski/swift-embeddings |
| AXorcist | Accessibility API | github.com/steipete/AXorcist |
| sherpa-onnx | On-device STT/TTS | github.com/k2-fsa/sherpa-onnx |
| OllamaKit | Optional Ollama integration | github.com/kevinhermawan/OllamaKit |

---

## GitHub Topics / Tags

`macos` `swift` `swiftui` `ai-assistant` `local-llm` `notch` `dynamic-island` `open-source` `ai-companion` `mlx` `mcp` `personality-ai` `desktop-assistant` `apple-silicon` `vtuber-inspired`
