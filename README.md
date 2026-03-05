<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-000000?style=flat&logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/swift-6.0-F05138?style=flat&logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/version-0.1.0--alpha-blue?style=flat" />
  <img src="https://img.shields.io/github/license/neur0map/PikoChan?style=flat" />
  <img src="https://img.shields.io/badge/LLM-local--first-brightgreen?style=flat" />
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

## Current State: v0.1.0-alpha

The UI foundation is in place. PikoChan can peek out of the notch, expand into a panel, accept text input, and show a listening state — all with spring-physics animations that match Apple's own Dynamic Island.

**What works today:**

- Borderless `NSPanel` anchored to the hardware notch, sitting above all other windows
- Five-state system: Hidden → Hovered (peek) → Expanded → Typing → Listening
- Spring animations on every state transition with continuous clip shapes matching Apple's hardware curves
- Dynamic mouse event passthrough — the panel never blocks your menu bar or other apps when collapsed
- Smart hover detection with debouncing and configurable zones
- Custom `NSTextField` integration that avoids SwiftUI's ViewBridge issues with non-activating panels
- Right-click context menu (Settings, Quit) accessible in any state
- Full settings window with native macOS toolbar tabs:
  - **Appearance** — background style, accent colors, sprite size
  - **Behavior** — launch at login, hover triggers, close behavior
  - **Notch Fine-Tune** — pixel-level offset adjustments for different MacBook models
  - **About** — version info, reset to defaults
- Settings changes apply live — no restart needed
- Runs as a background agent (no dock icon, no menu bar clutter)

**What doesn't exist yet:**

- No LLM backend — text input goes nowhere
- No personality system — she's silent
- No memory — she forgets everything
- No terminal or browser control
- No voice (STT/TTS)
- No skills

That's what the roadmap is for.

---

## Architecture

PikoChan is built in four layers, each with a clear responsibility:

```
┌─────────────────────────────────────────────┐
│              Layer 1: NOTCH UI              │
│  SwiftUI + AppKit, animations, state machine │
│  (v0.1.0-alpha — exists today)              │
├─────────────────────────────────────────────┤
│              Layer 2: BRAIN                 │
│  PikoBrain    — LLM orchestrator            │
│  PikoSoul     — personality + mood system   │
│  PikoMemory   — vector DB + SQLite          │
│  PikoMCP      — MCP client (Swift SDK)      │
├─────────────────────────────────────────────┤
│              Layer 3: HANDS                 │
│  PikoTerminal     — terminal control        │
│  PikoBrowser      — browser automation      │
│  PikoAccessibility — screen reading         │
│  PikoHeartbeat    — background awareness    │
├─────────────────────────────────────────────┤
│              Layer 4: SKILLS                │
│  Markdown skill files (YAML frontmatter)    │
│  User-created, downloadable, shareable      │
│  PikoChan reads them as instructions        │
└─────────────────────────────────────────────┘
```

**Layer 1** is pure UI — the notch panel, animations, and state machine. This is what v0.1.0-alpha delivers.

**Layer 2** is the brain — local LLM inference via MLX Swift, a composable personality system, semantic memory with vector search, and MCP tool integration.

**Layer 3** is the hands — how PikoChan interacts with your Mac. Terminal commands via AppleScript, browser automation via Chrome DevTools Protocol, screen reading via the Accessibility API, and a heartbeat loop that observes what you're doing.

**Layer 4** is the skills — plain Markdown files that teach PikoChan new abilities. Write one, drop it in a folder, and she knows how to do something new.

---

## Roadmap

### v0.2.0 — Brain Foundation

Give PikoChan the ability to think and respond.

- `~/.pikochan/` directory structure with human-readable YAML configs
- Local LLM inference via [MLX Swift](https://github.com/ml-explore/mlx-swift) on Apple Silicon
- Starting model targets: Phi-3.5 mini (3.8B), Qwen2.5 (3B), Gemma 2 (2B)
- Cloud API fallback (OpenAI, Anthropic) for users who want it
- Basic conversation loop: type in the notch, get a response from a local model
- Response rendering in the notch UI

### v0.3.0 — Soul & Memory

Give PikoChan personality and the ability to remember.

- **Soul container**: personality traits, communication style, behavioral constraints — all loaded from `personality.yaml`
- **Mood system**: dynamic mood state that shifts based on what PikoChan observes. Mood affects tone — she can be snarky, encouraging, concerned, or playful depending on context
- **SQLite database**: conversation history, user preferences, mood history over time
- **Semantic memory**: [VecturaKit](https://github.com/rryam/VecturaKit) for on-device vector search with hybrid BM25 + semantic matching
- **Memory pipeline**: extract key facts from conversations, embed them, recall relevant memories before responding
- **Journal**: PikoChan writes a human-readable `journal.md` of things she remembers about you

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
├── PikoChanApp.swift              # Entry point, AppDelegate, background agent setup
├── Core/
│   ├── NotchManager.swift         # State machine, mouse monitors, panel management
│   ├── NotchState.swift           # Five-state enum (hidden, hovered, expanded, typing, listening)
│   ├── PikoSettings.swift         # Observable settings store backed by UserDefaults
│   └── SettingsWindowController.swift  # Native settings window with toolbar tabs
├── Views/
│   ├── NotchContentView.swift     # Root view — routes to state-specific views
│   ├── ExpandedView.swift         # Sprite + action buttons
│   ├── TypingView.swift           # Text input state
│   ├── ListeningView.swift        # Voice input state with waveform
│   ├── WaveView.swift             # 60fps Canvas waveform animation
│   ├── NotchShape.swift           # Custom animatable notch clip shape
│   └── Settings/
│       ├── AppearanceTab.swift
│       ├── BehaviorTab.swift
│       ├── NotchTuneTab.swift
│       └── AboutTab.swift
└── Utilities/
    ├── PikoPanel.swift            # NSPanel subclass with activation state sync
    ├── PikoTextField.swift        # NSViewRepresentable text field (avoids ViewBridge bugs)
    ├── NSScreen+Notch.swift       # Notch geometry detection
    └── VisualEffectView.swift     # NSVisualEffectView wrapper
```

---

## Configuration

All PikoChan configuration will live in `~/.pikochan/` as plain text files:

```
~/.pikochan/
├── config.yaml               # LLM provider, model paths, API keys
├── soul/
│   ├── personality.yaml      # Traits, communication style, sass level
│   ├── mood.yaml             # Mood state, triggers, decay rules
│   └── voice.yaml            # TTS settings
├── skills/
│   ├── terminal.md           # Built-in terminal skill
│   ├── browser.md            # Built-in browser skill
│   └── custom/               # Your own skills
├── memory/
│   ├── pikochan.db           # SQLite database
│   ├── vectors/              # Semantic search index
│   └── journal.md            # What PikoChan remembers (human-readable)
└── mcp/
    └── servers.yaml          # MCP server connections
```

Everything is human-readable, git-friendly, and portable. Copy the folder to a new Mac and PikoChan comes with you — personality, memories, and all.

---

## Technology Stack

| Component | Technology | Credit |
|-----------|-----------|--------|
| UI Framework | Swift / SwiftUI / AppKit | [Apple](https://developer.apple.com/xcode/swiftui/) |
| Local LLM | MLX Swift | [Apple ML Explore](https://github.com/ml-explore/mlx-swift) |
| LLM Abstraction | LocalLLMClient | [tattn](https://github.com/tattn/LocalLLMClient) |
| MCP Client | Swift MCP SDK | [Model Context Protocol](https://github.com/modelcontextprotocol/swift-sdk) |
| Vector Search | VecturaKit | [rryam](https://github.com/rryam/VecturaKit) |
| Embeddings | swift-embeddings | [jkrukowski](https://github.com/jkrukowski/swift-embeddings) |
| Screen Reading | AXorcist | [steipete](https://github.com/AXorcist/AXorcist) |
| Speech (STT/TTS) | sherpa-onnx | [k2-fsa](https://github.com/k2-fsa/sherpa-onnx) |
| Ollama Integration | OllamaKit | [kevinhermawan](https://github.com/kevinhermawan/OllamaKit) |

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
