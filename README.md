<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-000000?style=flat&logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/swift-6.0-F05138?style=flat&logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/version-0.5.2--alpha-blue?style=flat" />
  <img src="https://img.shields.io/github/license/neur0map/PikoChan?style=flat" />
  <img src="https://img.shields.io/badge/LLM-local--first-brightgreen?style=flat" />
</p>

<p align="center">
  <img src="PikoChan/Assets/Moods/Irritated/pikochan_irritated.png" width="180" alt="PikoChan" />
</p>

<h1 align="center">PikoChan</h1>

<p align="center">
  <b>An open-source AI companion that lives in your Mac's notch.</b><br>
  Not an assistant. Not a chatbot. A buddy.
</p>

<p align="center">
  <sub>Built with native Swift & SwiftUI. No Electron. No web stack. Runs entirely on your machine.</sub>
</p>

---

## What is PikoChan?

PikoChan is a macOS AI companion that sits inside the hardware notch on your MacBook. She has personality, opinions, moods, and the ability to help with everyday tasks on your computer.

Think of her as a desktop buddy who happens to be powered by a local language model. She can control your terminal, automate your browser, remember things about you, and react to what you're doing — all without sending a single byte to the cloud (unless you want her to).

**The notch was wasted space. Now it's hers.**

### Why PikoChan exists

Every AI assistant on the market follows the same formula: a chat window, a corporate tone, and a cloud dependency. PikoChan takes a different approach:

- **She lives in the notch** — not in a chat window, not in a sidebar, not in a browser tab
- **She has a personality** — moods that shift, opinions she'll share, sass when you deserve it
- **She runs locally** — your conversations stay on your Mac, powered by models running on Apple Silicon
- **She's yours to shape** — all personality, memory, and behavior configs are plain YAML and Markdown files you can edit, version control, and share

### Inspirations

PikoChan draws from three projects that got specific things right:

- **[Project Airi](https://github.com/moeru-ai/airi)** — Soul container architecture, personality as composable middleware, memory with emotional scoring and forgetting curves
- **[OpenClaw](https://github.com/nicepkg/OpenClaw)** — Terminal control, browser automation, heartbeat monitoring, skills as Markdown files
- **[Neuro-sama](https://www.twitch.tv/vedal987)** — Proof that an AI character with genuine personality can be more compelling than one that's merely helpful

---

## Current State: v0.5.2-alpha

PikoChan has a brain, a soul, semantic memory, voice input/output, environmental awareness, terminal control, browser automation, a skills system, a now playing music widget, a first-time setup wizard, companion personality, and filesystem guardrails. She can hear you, talk back, remember who you are, notice what you're doing, run commands, open URLs, learn new abilities from Markdown files, and show you what's playing — all from inside the notch.

**What works today:**

- Everything from v0.1.0–v0.3.9 (notch UI, brain, soul, memory, HTTP gateway, setup wizard, semantic memory, soul evolution, path guard)
- **Voice input (STT)**: push-to-talk microphone capture via AVAudioEngine (16kHz mono WAV). Cloud transcription via Groq Whisper, OpenAI Whisper, or Deepgram Nova-2
- **Voice output (TTS)**: cloud speech synthesis via OpenAI, ElevenLabs, Fish Audio, Cartesia, or fal.ai. Auto-speaks when input is voice; optional "Speak responses aloud" toggle for text input
- **Mood-aware voice**: TTS models that support emotion prompts (e.g. fal.ai Qwen-3-TTS) receive PikoChan's current mood as a style hint — her voice matches her personality state
- **Dynamic fal.ai models**: paste any fal.ai model ID, PikoChan fetches the OpenAPI schema and adapts — discovers text fields, voice options, and parameters automatically
- **Heartbeat**: background awareness loop monitoring frontmost app, idle time, and time-of-day patterns. Proactive nudges when you've been idle or working too long
- **Config commands**: PikoChan can modify her own config in response to conversation (schedule nudges, adjust behavior)
- **Terminal control**: PikoChan can execute shell commands via `[shell:CMD]` tags — safe-list for auto-execution, block-list for dangerous commands, 30s timeout, output capped at 4000 chars
- **Browser automation**: PikoChan can open URLs and perform Google searches via `[open:URL]` tags — blocks dangerous schemes (javascript:/data:/file:)
- **Skills system**: Markdown files in `~/.pikochan/skills/` with YAML frontmatter teach PikoChan new abilities. Skills inject instructions into the system prompt. Settings → Skills tab for management
- **Action pipeline**: LLM emits action tags → PikoActionHandler parses and executes → results re-queried to LLM for summary (skipHistory to avoid pollution)
- **Now Playing music widget**: system-wide music detection via MediaRemote (native apps) and CoreAudio + browser window title parsing (YouTube, Spotify Web). iTunes Search API for album art. Playback controls via MediaRemote commands (native) or CGEvent media key simulation (browsers)
- **Music interaction layers**: compact pill (album art + audio bars, same height as idle) → hover (track name) → click (full mini-player with controls + PikoChan sprite)
- **Voice settings UI**: Settings → Voice tab with provider pickers, voice/model catalogs, API key sharing with AI Model tab, and Test TTS button
- **Mic permissions**: proper `com.apple.security.device.audio-input` entitlement, native permission dialog, direct link to System Settings if denied
- Nine LLM providers: Ollama (local), OpenAI, Anthropic, Apple Intelligence, Groq, Google Gemini, Mistral, DeepSeek, xAI Grok

**Provider notes:**

- **OpenAI `gpt-4o-mini`** is the recommended LLM provider — best mood accuracy and personality adherence
- **Local models** (phi4-mini, qwen) need more prompt engineering work for reliable mood tagging
- Local models run fully offline with zero cloud dependency via [Ollama](https://ollama.com)

> **Voice status warning:** Voice responses are functional but still need significant work to feel natural and alive. Finding the right TTS model, voice preset, speed settings, and emotion mapping for PikoChan's personality requires extensive testing across providers and configurations. Local TTS models (sherpa-onnx, MLX) have not been tested yet — only cloud providers are wired up. Consider voice a working prototype, not a polished feature.

**What doesn't exist yet:**

- No local/on-device TTS or STT
- No MCP client for external tool servers
- No accessibility/screen reading integration
- No streaming TTS (sentence-by-sentence)

---

## HTTP Gateway

PikoChan runs a lightweight HTTP server on port 7878 (configurable via `gateway_port` in `~/.pikochan/config.yaml`). This lets you interact with PikoChan headlessly — useful for debugging, testing, and future integrations.

```bash
# Health check
curl -s localhost:7878/health | jq

# Chat (non-streaming)
curl -s -X POST localhost:7878/chat -d '{"prompt":"hello"}' | jq

# Chat (SSE streaming)
curl -sN -X POST localhost:7878/chat -d '{"prompt":"tell me a joke","stream":true}'

# Check memories
curl -s localhost:7878/memories | jq

# View conversation history
curl -s localhost:7878/history?limit=5 | jq

# Set mood
curl -s -X POST localhost:7878/mood -d '{"mood":"playful"}' | jq

# View config
curl -s localhost:7878/config | jq

# Tail logs
curl -s localhost:7878/logs?limit=20 | jq
```

The HTTP server shares the same `PikoBrain` instance as the notch UI — conversations, memories, and mood state are shared between both interfaces.

---

## AI Models

PikoChan supports four LLM providers. Switch between them in **Settings → AI Model**.

### Cloud APIs (recommended for now)

- **OpenAI** — default model: `gpt-4o-mini`. Best personality adherence and mood accuracy. Requires API key from [platform.openai.com](https://platform.openai.com)
- **Anthropic** — default model: `claude-3-5-haiku-latest`. Requires API key from [console.anthropic.com](https://console.anthropic.com)

API keys are stored in macOS Keychain, never written to config files.

### Local via Ollama

Runs on your machine via [Ollama](https://ollama.com). No data leaves your Mac. Default model: `phi4-mini`.

| Model | Params | Install | Notes |
|-------|--------|---------|-------|
| `phi4-mini` | 3.8B | `ollama pull phi4-mini` | Default. Fast but struggles with mood tags |
| `llama3.2` | 3B | `ollama pull llama3.2` | Fast, minimal guardrails |
| `mistral` | 7B | `ollama pull mistral` | Strong general-purpose |
| `qwen2.5` | 7B | `ollama pull qwen2.5` | Excellent reasoning, multilingual |

> **Note:** Local models need more prompt engineering work for reliable mood tagging and persona maintenance. Cloud providers (especially `gpt-4o-mini`) give significantly better results for personality-driven responses today.

### Apple Intelligence (experimental)

On-device inference via Apple's FoundationModels framework. Requires macOS 26+ (Tahoe) with Apple Intelligence enabled. No API key needed.

**Limitations:**
- ~3B parameter model with aggressive safety filters that cannot be tuned
- No multi-turn conversation support (single-shot only)
- Frequently refuses benign prompts
- No streaming — responses are simulated character-by-character

### Cloud Fallback

When using the Local provider, you can configure a cloud fallback (OpenAI or Anthropic) that activates automatically if Ollama is unreachable.

---

## Architecture

PikoChan is built in four layers, each with a clear responsibility:

```
┌─────────────────────────────────────────────┐
│              Layer 1: NOTCH UI              │
│  SwiftUI + AppKit, animations, state machine │
│  (v0.1.0 ✅)                                │
├─────────────────────────────────────────────┤
│              Layer 2: BRAIN                 │
│  PikoBrain    — LLM orchestrator            │
│  PikoSoul     — personality + mood system   │
│  PikoMemory   — semantic memory pipeline     │
│  PikoEmbedding — Arctic Embed XS (CoreML)   │
│  PikoHTTPServer — HTTP gateway (port 7878)  │
│  PikoGateway  — structured JSONL logging    │
│  SetupManager — first-time setup wizard     │
│  (v0.2.0–v0.3.9 ✅)                          │
├─────────────────────────────────────────────┤
│           Layer 2.5: VOICE                  │
│  PikoAudioCapture — AVAudioEngine mic input │
│  PikoSTT     — cloud speech-to-text         │
│  PikoTTS     — cloud text-to-speech         │
│  PikoHeartbeat — background awareness       │
│  FalAISchema — dynamic model schema fetch   │
│  (v0.4.0 ✅ — cloud providers working)       │
├─────────────────────────────────────────────┤
│              Layer 3: HANDS                 │
│  PikoTerminal     — terminal control        │
│  PikoBrowser      — browser automation      │
│  PikoActionHandler — action tag pipeline    │
│  (v0.5.0 ✅)                                │
├─────────────────────────────────────────────┤
│           Layer 3.5: MUSIC                  │
│  MediaRemoteBridge — private framework      │
│  PikoNowPlaying  — hybrid music detection   │
│  Music UI — compact / hover / extended      │
│  (v0.5.2 ✅)                                │
├─────────────────────────────────────────────┤
│              Layer 4: SKILLS                │
│  Markdown skill files (YAML frontmatter)    │
│  MCP client for external tool servers       │
│  (v0.5.0 ✅ — skills loaded, MCP planned)   │
└─────────────────────────────────────────────┘
```

**Layer 1** is pure UI — the notch panel, animations, and state machine.

**Layer 2** is the brain — multi-provider LLM orchestration (Ollama, OpenAI, Anthropic, Apple Intelligence), composable personality via `PikoSoul`, semantic memory with Arctic Embed XS embeddings and cosine similarity recall, an HTTP gateway for headless access, structured JSONL logging, and a first-time setup wizard.

**Layer 3** is the hands — how PikoChan interacts with your Mac. Terminal commands via `[shell:CMD]` tags, browser automation via `[open:URL]` tags, with safe-list/block-list controls and action result re-querying.

**Layer 3.5** is the music — system-wide Now Playing detection via MediaRemote (native apps) and CoreAudio + browser window title parsing (YouTube, Spotify Web). iTunes Search API for album art. Three interaction layers: compact pill → hover → full mini-player.

**Layer 4** is the skills — plain Markdown files in `~/.pikochan/skills/` that teach PikoChan new abilities. MCP integration for external tools is planned.

---

## Roadmap

### v0.2.0 — Brain Foundation ✅

PikoChan can think and respond.

- `~/.pikochan/` directory structure with human-readable YAML configs
- Local LLM inference via Apple FoundationModels (macOS 26+) and Ollama HTTP fallback
- Cloud API fallback (OpenAI, Anthropic) with automatic local → cloud routing
- Full conversation loop: type in the notch, get a response
- Response bubble in the notch UI with status indicators
- AI Model settings tab for provider and model configuration

### v0.3.0 — Soul & Memory ✅

PikoChan has personality, emotions, memory, and an HTTP gateway.

- **Soul container**: `PikoSoul` loads personality from `personality.yaml` — traits, sass level, communication style, rules. System prompt constructed dynamically with mood-first ordering
- **Mood system**: LLM responses start with emotion tags (`[playful]`, `[snarky]`, `[proud]`, etc.), parsed by `MoodParser` to drive sprite changes. Post-history reminder (Airi pattern) reinforces identity before each response
- **SQLite database**: `PikoStore` manages `chat_history` and `memories` tables via C SQLite API. Persists across app restarts
- **Memory pipeline**: `PikoMemory` extracts facts from conversations via internal LLM call, stores in SQLite, recalls oldest-first for context injection
- **Journal**: human-readable `~/.pikochan/memory/journal.md` updated after each extraction
- **HTTP Gateway**: `PikoHTTPServer` (NWListener) on port 7878 — POST /chat, GET /health, /history, /logs, /memories, /config, POST /mood
- **Structured logging**: `PikoGateway` JSONL logger with daily rolling, 7-day prune, 50MB cap
- **Settings**: Soul tab for personality editing and memory management

### v0.3.5 — Setup & Semantic Memory ✅

First-time setup wizard and intelligent memory recall.

- **In-notch setup wizard**: guided 5-step flow (welcome, provider, validation, memory engine, summary) with typewriter text and spring animations
- **Provider validation**: Ollama reachability + model listing, API key validation for OpenAI/Anthropic, Apple Intelligence availability check
- **Semantic memory**: Snowflake Arctic Embed XS (22M params, 384-dim, CoreML float32) replaces brute-force recall with cosine similarity top-K ranking via Accelerate.framework. Apple NLEmbedding fallback if CoreML model unavailable
- **WordPiece tokenizer**: BERT-compatible subword tokenizer for Arctic model input (30522 vocab, max 128 tokens)
- **Memory vectors**: `memory_vectors` SQLite table with BLOB storage, FK cascade, migration step in setup wizard
- **System checks**: SQLite, embedding model, gateway server, log directory — validated with visual checklist
- **Re-run support**: Settings → Soul → "Re-run Setup Wizard"

### v0.3.9 — Soul Evolution & Token Optimization ✅

PikoChan learns from behavioral feedback and uses fewer tokens per message.

- **Soul evolution**: when the user gives behavioral feedback ("stop asking so many questions", "be more direct"), PikoChan extracts rules and appends them to `personality.yaml` automatically. Personality evolves across conversations
- **Token-optimized recall**: memory injection budget-capped to ~600 chars with cosine similarity floor (0.3), replacing fixed `.prefix(15)` cap. Memories ranked by relevance, not recency
- **Smart extraction dedup**: embedding-based top-5 similarity dedup replaces dumping 50 memories into extraction prompt (~2700 chars saved per extraction)
- **Trivial message skip**: extraction skipped for "hi" / "ok" / "lol" style messages (user < 15 chars, assistant < 100 chars). Logged as `extraction_skip` gateway event
- **Expanded companion behavior**: stronger anti-interrogation rules, memory relevance framing, topic-matching guidance in system prompt and post-history reminder

### v0.4.0 — Voice & Awareness ✅

PikoChan can hear, speak, and notice what's happening on your Mac.

- **Voice input (STT)**: push-to-talk mic capture (AVAudioEngine, 16kHz mono WAV) with cloud transcription (Groq Whisper, OpenAI Whisper, Deepgram Nova-2)
- **Voice output (TTS)**: cloud speech synthesis with 5 providers (OpenAI, ElevenLabs, Fish Audio, Cartesia, fal.ai). File-based playback via AVAudioPlayer
- **Mood-aware TTS**: PikoChan's current mood is sent as an emotion prompt to TTS models that support it (e.g. Qwen-3-TTS)
- **Dynamic fal.ai schemas**: paste any fal.ai model ID — PikoChan fetches the OpenAPI schema and adapts request fields, voice options, and parameters automatically
- **Heartbeat**: background awareness loop (frontmost app, idle time, time-of-day), proactive nudges
- **Config commands**: LLM can schedule nudges and adjust behavior via response parsing
- **Voice settings UI**: full Settings → Voice tab with provider pickers, voice/model catalogs, shared API keys, Test TTS
- **Mic entitlement**: `com.apple.security.device.audio-input` + native permission flow

### v0.5.0 — Skills + Terminal + Browser ✅

PikoChan can run commands, open URLs, and learn new tricks.

- **Skills loader**: `PikoSkillLoader` scans `~/.pikochan/skills/` + `skills/custom/` for Markdown files with YAML frontmatter. Skills inject instructions into the system prompt
- **Terminal control**: `PikoTerminal` executes shell commands via Foundation.Process (`/bin/zsh -c`). Safe-list auto-execute, block-list rejection, 30s timeout, 4000 char output cap
- **Browser automation**: `PikoBrowser` opens URLs via NSWorkspace, Google search helper. Blocks dangerous schemes (javascript:/data:/file:)
- **Action pipeline**: `PikoActionHandler` parses `[shell:CMD]` and `[open:URL]` tags from LLM response → executes → re-queries LLM with results for a summary (skipHistory to avoid pollution)
- **Action cards**: `ActionCardView` shows pending actions with Run/Cancel, completed actions with exit code + collapsible output
- **Settings**: Skills tab between Voice and Awareness for skill management and terminal/browser toggles

### v0.5.2 — Now Playing Music Widget ✅

PikoChan detects and controls music playing on your Mac.

- **MediaRemote bridge**: `MediaRemoteBridge` dlopen/dlsym bridge to private MediaRemote.framework for native app track info, artwork, and play state
- **Browser fallback**: CoreAudio device activity detection + Accessibility API window title parsing for YouTube, Spotify Web, and other browser-based players
- **iTunes Search API**: fetches album art when MediaRemote has none (browser fallback), upgrades to 600×600 hi-res
- **Playback controls**: MediaRemote sendCommand for native apps, CGEvent media key simulation (subtype 8, keycodes 16/17/20) for browsers
- **Music interaction layers**: compact pill (album art + audio bars, same height as idle, horizontal-only expansion) → hover (track name revealed) → click (full mini-player with controls + PikoChan sprite)
- **Panel stability**: `suppressNextGlobalClick` prevents button clicks from dismissing, 5-second grace period before collapsing on pause/skip, `userControlUntil` cooldown prevents poll overriding user actions

### v0.6.0 — Community & Polish

Make PikoChan shareable and self-improving.

- Community skill repository — download and share skill files
- Personality pack sharing — trade personality configs with other users
- Self-improvement — PikoChan can write new skill files for herself
- Advanced mood patterns — recognition of long-term behavioral trends
- Memory consolidation — periodic summarization of old memories into higher-level notes
- Apple Foundation Models integration (macOS 26+) for zero-config local inference

### Beyond Alpha — Headless, Bridges & Proactive Companionship

Post-alpha features planned for late beta or stable release:

- **Headless mode** — run PikoChan as a pure background service on Mac Mini/Studio/Pro (no notch UI, just brain + HTTP gateway)
- **Telegram bridge** — chat with PikoChan via Telegram bot, proxied through `localhost:7878`
- **Discord bridge** — Discord bot integration for server or DM conversations
- **Webhook API** — generic webhook endpoint for any chat platform (Slack, WhatsApp, custom apps)
- **Proactive check-ins** — PikoChan reaches out if you haven't talked in a few days
- **Voice tone detection** — on-device vocal pattern analysis detects low mood or stress; PikoChan calls to keep you company
- **Cross-platform presence** — check-ins and conversations consistent across notch, Telegram, Discord

See the [vision doc](docs/plans/2026-03-05-pikochan-vision-design.md) for full details.

---

## Building from Source

**Requirements:**
- macOS 14.0+ (Sonoma or later)
- Xcode 16.0+
- A MacBook with a notch (2021 MacBook Pro or later). Works on non-notch Macs too — PikoChan uses the menu bar area instead

```bash
git clone https://github.com/neur0map/PikoChan.git
cd PikoChan
open PikoChan.xcodeproj
```

Build and run (⌘R). PikoChan will appear in your notch. Hover below the notch to see her peek out, click to expand.

**Note:** The app runs as a background agent — no dock icon. Right-click the notch area to access Settings or Quit.

---

## Project Structure

```
PikoChan/
├── PikoChanApp.swift              # Entry point, AppDelegate, brain injection wiring
├── Assets/
│   └── Models/
│       ├── ArcticEmbedXS.mlpackage  # Snowflake Arctic Embed XS (384-dim, 22M params, CoreML)
│       └── arctic_vocab.txt         # BERT WordPiece vocabulary (30522 tokens)
├── Core/
│   ├── NotchManager.swift         # State machine, mouse monitors, panel management, voice + music orchestration
│   ├── NotchState.swift           # Nine-state enum (hidden, hovered, expanded, typing, listening, setup, musicCompact, musicHover, musicExtended)
│   ├── SetupManager.swift         # First-time setup wizard state + validation + migration
│   ├── PikoSettings.swift         # Observable settings store backed by UserDefaults
│   ├── PikoHTTPServer.swift       # NWListener HTTP server (port 7878), all API endpoints
│   ├── PikoHeartbeat.swift        # Background awareness loop (frontmost app, idle, time-of-day)
│   ├── SettingsWindowController.swift  # Native settings window with toolbar tabs
│   ├── Voice/
│   │   ├── PikoAudioCapture.swift     # AVAudioEngine mic → 16kHz mono WAV
│   │   ├── PikoSTT.swift              # Cloud STT (Groq, OpenAI, Deepgram)
│   │   ├── PikoTTS.swift              # Cloud TTS (OpenAI, ElevenLabs, Fish Audio, Cartesia, fal.ai)
│   │   ├── PikoVoiceConfig.swift      # Voice config struct + YAML loader
│   │   ├── PikoVoiceConfigStore.swift # Observable voice config for settings UI
│   │   └── FalAISchema.swift          # Dynamic fal.ai OpenAPI schema fetcher
│   ├── Skills/
│   │   ├── PikoSkillLoader.swift    # Markdown skill scanner + system prompt builder
│   │   ├── PikoTerminal.swift       # Shell command execution (safe-list/block-list)
│   │   ├── PikoBrowser.swift        # URL opening + Google search
│   │   └── PikoActionHandler.swift  # Action tag parser + execution orchestrator
│   ├── Music/
│   │   ├── MediaRemoteBridge.swift  # dlopen/dlsym bridge to private MediaRemote.framework
│   │   └── PikoNowPlaying.swift     # Hybrid music detection (MR + CoreAudio + browser titles)
│   └── Brain/
│       ├── PikoBrain.swift        # LLM orchestrator — multi-provider, streaming, history
│       ├── PikoSoul.swift         # Personality YAML → system prompt + post-history reminder
│       ├── MoodParser.swift       # Emotion tag parser ([playful], [snarky], etc.)
│       ├── PikoMemory.swift       # Semantic recall (cosine similarity) + fact extraction
│       ├── PikoStore.swift        # SQLite (C API) — chat_history, memories, memory_vectors
│       ├── PikoGateway.swift      # Structured JSONL logger (daily rolling, 7-day prune)
│       ├── PikoConfig.swift       # YAML config parser (provider, model, gateway port)
│       ├── PikoConfigStore.swift  # Observable config binding for settings UI
│       └── PikoHome.swift         # ~/.pikochan/ directory bootstrapping
├── Views/
│   ├── NotchContentView.swift     # Root view — routes to state-specific views
│   ├── ExpandedView.swift         # Sprite + action buttons + response bubble
│   ├── TypingView.swift           # Text input state
│   ├── ListeningView.swift        # Voice input state with waveform
│   ├── WaveView.swift             # 60fps Canvas waveform animation
│   ├── NotchShape.swift           # Custom animatable notch clip shape
│   ├── Setup/
│   │   ├── SetupView.swift        # Root setup container with step routing
│   │   ├── SetupComponents.swift  # StepDots, NavButtons, ActionButton, TypewriterText
│   │   ├── SetupWelcomeStep.swift # Typewriter greeting + Begin Setup
│   │   ├── SetupProviderStep.swift      # Provider picker (4 pills)
│   │   ├── SetupProviderConfigStep.swift  # API key / Ollama validation
│   │   ├── SetupMemoryStep.swift  # Embedding check + memory migration
│   │   └── SetupSummaryStep.swift # Checklist + Let's go!
│   ├── Music/
│   │   ├── AudioBarsView.swift      # Animated audio level bars
│   │   ├── MusicCompactView.swift   # Compact pill (album art + bars)
│   │   ├── MusicExtendedView.swift  # Full mini-player (art + info + controls + sprite)
│   │   └── MusicMiniStripView.swift # Thin strip in assistant views (tap to return)
│   ├── ActionCardView.swift         # Shell/browser action cards (pending/completed)
│   └── Settings/
│       ├── AIModelTab.swift       # Provider picker, model config, connection test
│       ├── SoulTab.swift          # Personality editing + memory management + re-run setup
│       ├── VoiceTab.swift         # TTS/STT provider config, voice pickers, test button
│       ├── SkillsTab.swift        # Skills management, terminal/browser toggles
│       ├── AwarenessTab.swift     # Heartbeat/awareness settings
│       ├── AppearanceTab.swift
│       ├── BehaviorTab.swift
│       ├── NotchTuneTab.swift
│       └── AboutTab.swift
└── Utilities/
    ├── PikoPanel.swift            # NSPanel subclass with activation state sync
    ├── PikoKeychain.swift         # macOS Keychain wrapper for API keys
    ├── PikoTextField.swift        # NSViewRepresentable text fields (plain + bullet-masked secure)
    ├── PikoEmbedding.swift        # Arctic Embed XS (CoreML) + NLEmbedding fallback
    ├── WordPieceTokenizer.swift   # BERT WordPiece tokenizer for Arctic model
    ├── PikoConfigCommand.swift    # Response config command parser (nudges, settings)
    ├── PikoPathGuard.swift        # Filesystem guardrails for safe file access
    ├── NSScreen+Notch.swift       # Notch geometry detection
    └── VisualEffectView.swift     # NSVisualEffectView wrapper
```

---

## Configuration

All PikoChan configuration lives in `~/.pikochan/` as plain text files:

```
~/.pikochan/
├── config.yaml               # LLM provider, model, gateway_port, fallback settings
├── soul/
│   ├── personality.yaml      # Traits, communication style, sass level, rules
│   └── voice.yaml            # TTS/STT provider, model, voice ID, speed, auto-speak
├── memory/
│   ├── pikochan.db           # SQLite database (chat history + memories)
│   └── journal.md            # What PikoChan remembers (human-readable)
└── logs/
    └── YYYY-MM-DD.jsonl      # Structured gateway logs (rolling daily, 7-day prune)
```

Everything is human-readable, git-friendly, and portable. Copy the folder to a new Mac and PikoChan comes with you — personality, memories, and all.

---

## Technology Stack

| Component | Technology | Notes |
|-----------|-----------|-------|
| UI Framework | Swift / SwiftUI / AppKit | Native macOS, zero web dependencies |
| LLM (local) | Ollama HTTP API | Any Ollama-compatible model |
| LLM (cloud) | OpenAI / Anthropic / Groq / Gemini / Mistral / DeepSeek / xAI | API keys stored in macOS Keychain |
| LLM (on-device) | Apple FoundationModels | macOS 26+ experimental |
| STT (cloud) | Groq Whisper / OpenAI Whisper / Deepgram Nova-2 | Multipart WAV upload |
| TTS (cloud) | OpenAI / ElevenLabs / Fish Audio / Cartesia / fal.ai | Dynamic model schemas for fal.ai |
| Audio capture | AVAudioEngine | 16kHz mono Float32, WAV encoding |
| Audio playback | AVAudioPlayer | File-based, format auto-detection |
| Embeddings | Snowflake Arctic Embed XS (CoreML) | 384-dim, 22M params, on-device |
| Embedding fallback | Apple NLEmbedding | 512-dim, built-in, lower quality |
| Tokenizer | WordPiece (BERT-compatible) | 30522 vocab, max 128 tokens |
| Similarity | Accelerate.framework (vDSP) | Hardware-accelerated cosine similarity |
| Now Playing | MediaRemote.framework (private) | dlopen/dlsym runtime bridge, no direct linking |
| Music fallback | CoreAudio + Accessibility API | Audio device activity + browser window title parsing |
| Album art | iTunes Search API | Free, no API key, 600×600 hi-res artwork |
| Media keys | CGEvent (NSEvent) | Synthetic media key events for browser playback control |
| HTTP Server | Network.framework (NWListener) | Zero-dependency TCP server |
| Database | SQLite (C API) | Chat history, memories, embedding vectors |
| Logging | Custom JSONL | Rolling daily, auto-prune |

---

## Design Principles

1. **Buddy, not assistant** — Personality first, utility second
2. **Local-first** — Everything runs on your Mac. Cloud is optional, never required
3. **Human-readable** — All configs are YAML and Markdown. No black boxes
4. **Native macOS** — No Electron, no web stack, no compromise
5. **Start small** — Begin with 2-3B models, prove the concept, scale up
6. **Safety boundaries** — PikoChan suggests, you confirm. She never auto-executes destructive actions
7. **Open source** — Community-first. Free forever. Your data stays yours

---

## Contributing

PikoChan is in early alpha. If you're interested in contributing, here's what would help most right now:

- **Testing on different MacBook models** — notch geometry varies between generations
- **UI/UX feedback** — animation timing, interaction patterns, visual polish
- **Swift/AppKit expertise** — especially around NSPanel behavior, Accessibility API, and MLX integration

Open an issue or submit a PR. No contribution guidelines yet — just be decent.

---

## License

MIT

---

<p align="center">
  <sub>PikoChan is not affiliated with Apple, Anthropic, or OpenAI. She's her own person.</sub>
</p>
