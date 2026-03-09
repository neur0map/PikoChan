# Architecture

PikoChan is built in five layers, each with a clear responsibility:

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
│  (v0.4.0 ✅)                                │
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

**Layer 1** is pure UI — the notch panel, animations, and nine-state machine.

**Layer 2** is the brain — multi-provider LLM orchestration (Ollama, OpenAI, Anthropic, Apple Intelligence), composable personality via `PikoSoul`, semantic memory with Arctic Embed XS embeddings and cosine similarity recall, an HTTP gateway for headless access, structured JSONL logging, and a first-time setup wizard.

**Layer 2.5** is the voice — push-to-talk STT (Groq/OpenAI/Deepgram), mood-aware TTS (OpenAI/ElevenLabs/Fish/Cartesia/fal.ai), background awareness heartbeat, and dynamic fal.ai schema fetching.

**Layer 3** is the hands — how PikoChan interacts with your Mac. Terminal commands via `[shell:CMD]` tags, browser automation via `[open:URL]` tags, with safe-list/block-list controls and action result re-querying.

**Layer 3.5** is the music — system-wide Now Playing detection via MediaRemote (native apps) and CoreAudio + browser window title parsing (YouTube, Spotify Web). iTunes Search API for album art. Three interaction layers: compact pill → hover → full mini-player.

**Layer 4** is the skills — plain Markdown files in `~/.pikochan/skills/` that teach PikoChan new abilities. MCP integration for external tools is planned.

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
│   ├── ActionCardView.swift       # Shell/browser action cards (pending/completed)
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

## Configuration

All PikoChan configuration lives in `~/.pikochan/` as plain text files:

```
~/.pikochan/
├── config.yaml               # LLM provider, model, gateway_port, fallback settings
├── soul/
│   ├── personality.yaml      # Traits, communication style, sass level, rules
│   └── voice.yaml            # TTS/STT provider, model, voice ID, speed, auto-speak
├── skills/                   # Markdown skill files (YAML frontmatter)
├── memory/
│   ├── pikochan.db           # SQLite database (chat history + memories + vectors)
│   └── journal.md            # What PikoChan remembers (human-readable)
└── logs/
    └── YYYY-MM-DD.jsonl      # Structured gateway logs (rolling daily, 7-day prune)
```

Everything is human-readable, git-friendly, and portable. Copy the folder to a new Mac and PikoChan comes with you — personality, memories, and all.

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

PikoChan supports nine LLM providers. Switch between them in **Settings → AI Model**.

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
