<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-000000?style=flat&logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/swift-6.0-F05138?style=flat&logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/version-0.3.0--alpha-blue?style=flat" />
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

## Current State: v0.3.0-alpha

PikoChan has a brain, a soul, and memory. She remembers who you are, has moods that shift with the conversation, and can be accessed headlessly via HTTP.

**What works today:**

- Everything from v0.1.0 (notch UI, animations, state machine, settings) and v0.2.0 (brain, LLM providers, streaming)
- **Soul system**: personality loaded from `personality.yaml` — traits, communication style, sass level, behavioral rules
- **Mood system**: dynamic mood tags (`[playful]`, `[snarky]`, `[proud]`, etc.) parsed from LLM responses, driving sprite changes
- **Memory**: SQLite-backed fact extraction and recall — PikoChan remembers your name, preferences, and conversations across restarts
- **Journal**: human-readable `~/.pikochan/memory/journal.md` of everything she remembers about you
- **HTTP Gateway**: lightweight NWListener server on port 7878 — talk to PikoChan via `curl` or any HTTP client
- **Structured logging**: JSONL gateway logs at `~/.pikochan/logs/` with rolling daily files and auto-pruning
- **Settings**: Soul tab for personality editing and memory management
- Four LLM providers: Ollama (local), OpenAI, Anthropic, Apple Intelligence

**Provider notes:**

- **OpenAI `gpt-4o-mini`** is the recommended provider for now — best mood accuracy and personality adherence
- **Local models** (phi4-mini, qwen) need more prompt engineering work for reliable mood tagging and persona maintenance
- Local models run fully offline with zero cloud dependency via [Ollama](https://ollama.com)

**What doesn't exist yet:**

- No terminal or browser control
- No voice (STT/TTS)
- No skills system
- No semantic memory search (currently injects all memories oldest-first)

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
│  PikoMemory   — SQLite memory pipeline      │
│  PikoHTTPServer — HTTP gateway (port 7878)  │
│  PikoGateway  — structured JSONL logging    │
│  (v0.2.0 + v0.3.0 ✅)                       │
├─────────────────────────────────────────────┤
│              Layer 3: HANDS                 │
│  PikoTerminal     — terminal control        │
│  PikoBrowser      — browser automation      │
│  PikoAccessibility — screen reading         │
│  PikoHeartbeat    — background awareness    │
│  (v0.4.0 — planned)                         │
├─────────────────────────────────────────────┤
│              Layer 4: SKILLS                │
│  Markdown skill files (YAML frontmatter)    │
│  MCP client for external tool servers       │
│  (v0.5.0 — planned)                         │
└─────────────────────────────────────────────┘
```

**Layer 1** is pure UI — the notch panel, animations, and state machine.

**Layer 2** is the brain — multi-provider LLM orchestration (Ollama, OpenAI, Anthropic, Apple Intelligence), composable personality via `PikoSoul`, SQLite-backed memory with fact extraction, an HTTP gateway for headless access, and structured JSONL logging.

**Layer 3** is the hands — how PikoChan will interact with your Mac. Terminal commands, browser automation, screen reading, and a heartbeat loop for background awareness.

**Layer 4** is the skills — plain Markdown files that teach PikoChan new abilities, plus MCP integration for external tools.

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

### v0.3.5 — Setup & Semantic Memory

First-time setup wizard and intelligent memory recall.

- **In-notch setup wizard**: guided 5-step flow (welcome, provider, validation, memory engine, summary) with animations and typewriter text
- **Provider validation**: Ollama reachability check, API key validation for OpenAI/Anthropic, Apple Intelligence availability
- **Semantic memory search**: Apple NLEmbedding (built-in, zero dependencies) with model2vec fallback (~32MB). Replaces brute-force "inject all memories" with cosine similarity top-K recall via Accelerate.framework
- **Memory vectors**: new `memory_vectors` SQLite table with embedding BLOBs, migration for existing v0.3.0 memories
- **System checks**: SQLite, embedding model, gateway server, log directory — all validated with visual checklist
- **Re-run support**: Settings → Soul → "Re-run Setup", version-aware step discovery for future upgrades

### v0.4.0 — Hands

Give PikoChan the ability to interact with your Mac.

- **Terminal control**: detect running terminals (Terminal.app, iTerm2), type commands via AppleScript. PikoChan suggests commands — you hit Enter. She never auto-executes
- **Browser automation**: open URLs, execute JavaScript, read page content. AppleScript for quick tasks, Chrome DevTools Protocol for full control
- **Screen reading**: [AXorcist](https://github.com/AXorcist/AXorcist) for reading the frontmost app, window titles, active text fields via the Accessibility API
- **Heartbeat**: background loop every 30-60 seconds that observes frontmost app, idle time, time of day. Feeds into the mood system — she might suggest a break after a long session, notice you always open Spotify at a certain time, or stay quiet when you're in flow

### v0.5.0 — Voice & Skills

Give PikoChan a voice and the ability to learn new tricks.

- **Speech-to-text**: on-device transcription via [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) or Whisper (MLX). The listening state becomes functional
- **Text-to-speech**: local voice synthesis with sherpa-onnx or MLX TTS models. Optional premium voice via ElevenLabs
- **Skills loader**: PikoChan scans `~/.pikochan/skills/` for Markdown files with YAML frontmatter. Each file teaches her a new ability
- **Built-in skills**: terminal helper, browser automation, weather check
- **MCP client**: connect to external tool servers via the [official Swift MCP SDK](https://github.com/modelcontextprotocol/swift-sdk)

### v0.6.0 — Community & Polish

Make PikoChan shareable and self-improving.

- Community skill repository — download and share skill files
- Personality pack sharing — trade personality configs with other users
- Self-improvement — PikoChan can write new skill files for herself
- Advanced mood patterns — recognition of long-term behavioral trends
- Memory consolidation — periodic summarization of old memories into higher-level notes
- Apple Foundation Models integration (macOS 26+) for zero-config local inference

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
├── Core/
│   ├── NotchManager.swift         # State machine, mouse monitors, panel management
│   ├── NotchState.swift           # Five-state enum (hidden, hovered, expanded, typing, listening)
│   ├── PikoSettings.swift         # Observable settings store backed by UserDefaults
│   ├── PikoHTTPServer.swift       # NWListener HTTP server (port 7878), all API endpoints
│   ├── SettingsWindowController.swift  # Native settings window with toolbar tabs
│   └── Brain/
│       ├── PikoBrain.swift        # LLM orchestrator — multi-provider, streaming, history
│       ├── PikoSoul.swift         # Personality YAML → system prompt + post-history reminder
│       ├── MoodParser.swift       # Emotion tag parser ([playful], [snarky], etc.)
│       ├── PikoMemory.swift       # Fact extraction + recall coordinator
│       ├── PikoStore.swift        # SQLite (C API) — chat_history + memories tables
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
│   └── Settings/
│       ├── AIModelTab.swift       # Provider picker, model config, connection test
│       ├── SoulTab.swift          # Personality editing + memory management
│       ├── AppearanceTab.swift
│       ├── BehaviorTab.swift
│       ├── NotchTuneTab.swift
│       └── AboutTab.swift
└── Utilities/
    ├── PikoPanel.swift            # NSPanel subclass with activation state sync
    ├── PikoKeychain.swift         # macOS Keychain wrapper for API keys
    ├── PikoTextField.swift        # NSViewRepresentable text field (avoids ViewBridge bugs)
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
│   └── personality.yaml      # Traits, communication style, sass level, rules
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
| LLM (cloud) | OpenAI / Anthropic APIs | API keys stored in macOS Keychain |
| LLM (on-device) | Apple FoundationModels | macOS 26+ experimental |
| HTTP Server | Network.framework (NWListener) | Zero-dependency TCP server |
| Database | SQLite (C API) | Chat history + memory storage |
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
