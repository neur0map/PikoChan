<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-000000?style=flat&logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/swift-6.0-F05138?style=flat&logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/version-0.5.4--alpha-blue?style=flat" />
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

### Inspirations & Credits

- **[DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit)** — by MrKai77. PikoChan's notch panel implementation (NSPanel subclass, notch geometry detection, hover monitors) was built by studying this project's approach. MIT licensed
- **[NotchNook](https://lo.cafe/notchnook)** — The gold standard for notch-based macOS UI. PikoChan's interaction patterns (compact → hover → expanded) are directly inspired by NotchNook's polish
- **[Project Airi](https://github.com/moeru-ai/airi)** — Soul container architecture, personality as composable middleware, memory with emotional scoring
- **[OpenClaw](https://github.com/nicepkg/OpenClaw)** — Terminal control, browser automation, heartbeat monitoring, skills as Markdown files
- **[Neuro-sama](https://www.twitch.tv/vedal987)** — Proof that an AI character with genuine personality can be more compelling than one that's merely helpful

---

## Current State: v0.5.4-alpha

PikoChan has a brain, a soul, semantic memory, voice I/O, terminal control, browser automation, a skills system, a now playing music widget, and an activity feed chat interface — all inside the notch.

**Features:**

- **Brain** — nine LLM providers (Ollama, OpenAI, Anthropic, Apple Intelligence, Groq, Gemini, Mistral, DeepSeek, xAI). Streaming responses, conversation history, HTTP gateway on port 7878
- **Soul** — personality loaded from YAML, mood system with emotion tags driving sprite changes, soul evolution from behavioral feedback
- **Memory** — semantic recall via Snowflake Arctic Embed XS (CoreML, 384-dim), SQLite storage, automatic fact extraction from conversations
- **Voice** — push-to-talk STT (Groq/OpenAI/Deepgram Whisper), mood-aware TTS (OpenAI/ElevenLabs/Fish/Cartesia/fal.ai)
- **Hands** — terminal commands via `[shell:CMD]`, browser automation via `[open:URL]`, three-tier approval (Deny/Allow/Always), session-wide auto-approve, action result re-querying with personality
- **Skills** — Markdown files in `~/.pikochan/skills/` with YAML frontmatter teach PikoChan new abilities
- **Music** — system-wide Now Playing detection (MediaRemote + CoreAudio + browser titles), iTunes Search API album art, playback controls for native apps and browsers
- **Chat** — activity feed with iMessage-style blue bubbles, sprite-left layout, streaming dots, collapsible command output, full-width tap targets, new chat via sprite tap
- **Awareness** — background heartbeat monitoring frontmost app, idle time, time-of-day. Proactive nudges
- **Setup** — in-notch first-time wizard with provider validation, embedding checks, and system diagnostics

> **OpenAI `gpt-4o-mini`** is the recommended LLM provider. Local models (phi4-mini, qwen) work but need more prompt engineering for reliable mood tagging. All local models run fully offline via [Ollama](https://ollama.com).

**Not yet built:** local/on-device TTS & STT, MCP client, accessibility/screen reading, streaming TTS.

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

Build and run (**⌘R**). PikoChan will appear in your notch. Hover below the notch to see her peek out, click to expand.

**Note:** The app runs as a background agent — no dock icon. Right-click the notch area to access Settings or Quit.

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

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture](docs/ARCHITECTURE.md) | Layer diagram, project structure, tech stack, configuration, HTTP gateway, AI model details |
| [Changelog](docs/CHANGELOG.md) | Version history and planned features |

---

## Contributing

PikoChan is in early alpha. Read **[CONTRIBUTING.md](CONTRIBUTING.md)** before opening a PR — PRs that don't follow the guidelines will be rejected.

What helps most right now:
- Testing on different MacBook models (notch geometry varies)
- UI/UX feedback (animation timing, interaction patterns)
- Bug reports with reproduction steps
- Swift/AppKit expertise (NSPanel, Accessibility API, CoreAudio)

---

## License

MIT

---

<p align="center">
  <sub>PikoChan is not affiliated with Apple, Anthropic, or OpenAI. She's her own person.</sub>
</p>
