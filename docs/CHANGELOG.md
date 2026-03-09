# Changelog

## v0.5.2-alpha — Now Playing Music Widget

PikoChan detects and controls music playing on your Mac.

- **MediaRemote bridge**: `MediaRemoteBridge` dlopen/dlsym bridge to private MediaRemote.framework for native app track info, artwork, and play state
- **Browser fallback**: CoreAudio device activity detection + Accessibility API window title parsing for YouTube, Spotify Web, and other browser-based players
- **iTunes Search API**: fetches album art when MediaRemote has none (browser fallback), upgrades to 600×600 hi-res
- **Playback controls**: MediaRemote sendCommand for native apps, CGEvent media key simulation (subtype 8, keycodes 16/17/20) for browsers
- **Music interaction layers**: compact pill (album art + audio bars, same height as idle, horizontal-only expansion) → hover (track name revealed) → click (full mini-player with controls + PikoChan sprite)
- **Panel stability**: `suppressNextGlobalClick` prevents button clicks from dismissing, 5-second grace period before collapsing on pause/skip, `userControlUntil` cooldown prevents poll overriding user actions

## v0.5.0-alpha — Skills + Terminal + Browser

PikoChan can run commands, open URLs, and learn new tricks.

- **Skills loader**: `PikoSkillLoader` scans `~/.pikochan/skills/` + `skills/custom/` for Markdown files with YAML frontmatter. Skills inject instructions into the system prompt
- **Terminal control**: `PikoTerminal` executes shell commands via Foundation.Process (`/bin/zsh -c`). Safe-list auto-execute, block-list rejection, 30s timeout, 4000 char output cap
- **Browser automation**: `PikoBrowser` opens URLs via NSWorkspace, Google search helper. Blocks dangerous schemes (javascript:/data:/file:)
- **Action pipeline**: `PikoActionHandler` parses `[shell:CMD]` and `[open:URL]` tags from LLM response → executes → re-queries LLM with results for a summary (skipHistory to avoid pollution)
- **Action cards**: `ActionCardView` shows pending actions with Run/Cancel, completed actions with exit code + collapsible output
- **Settings**: Skills tab between Voice and Awareness for skill management and terminal/browser toggles

## v0.4.0-alpha — Voice & Awareness

PikoChan can hear, speak, and notice what's happening on your Mac.

- **Voice input (STT)**: push-to-talk mic capture (AVAudioEngine, 16kHz mono WAV) with cloud transcription (Groq Whisper, OpenAI Whisper, Deepgram Nova-2)
- **Voice output (TTS)**: cloud speech synthesis with 5 providers (OpenAI, ElevenLabs, Fish Audio, Cartesia, fal.ai). File-based playback via AVAudioPlayer
- **Mood-aware TTS**: PikoChan's current mood is sent as an emotion prompt to TTS models that support it (e.g. Qwen-3-TTS)
- **Dynamic fal.ai schemas**: paste any fal.ai model ID — PikoChan fetches the OpenAPI schema and adapts request fields, voice options, and parameters automatically
- **Heartbeat**: background awareness loop (frontmost app, idle time, time-of-day), proactive nudges
- **Config commands**: LLM can schedule nudges and adjust behavior via response parsing
- **Voice settings UI**: full Settings → Voice tab with provider pickers, voice/model catalogs, shared API keys, Test TTS
- **Mic entitlement**: `com.apple.security.device.audio-input` + native permission flow

## v0.3.9-alpha — Soul Evolution & Token Optimization

PikoChan learns from behavioral feedback and uses fewer tokens per message.

- **Soul evolution**: when the user gives behavioral feedback ("stop asking so many questions", "be more direct"), PikoChan extracts rules and appends them to `personality.yaml` automatically. Personality evolves across conversations
- **Token-optimized recall**: memory injection budget-capped to ~600 chars with cosine similarity floor (0.3), replacing fixed `.prefix(15)` cap. Memories ranked by relevance, not recency
- **Smart extraction dedup**: embedding-based top-5 similarity dedup replaces dumping 50 memories into extraction prompt (~2700 chars saved per extraction)
- **Trivial message skip**: extraction skipped for "hi" / "ok" / "lol" style messages (user < 15 chars, assistant < 100 chars). Logged as `extraction_skip` gateway event
- **Expanded companion behavior**: stronger anti-interrogation rules, memory relevance framing, topic-matching guidance in system prompt and post-history reminder

## v0.3.5-alpha — Setup & Semantic Memory

First-time setup wizard and intelligent memory recall.

- **In-notch setup wizard**: guided 5-step flow (welcome, provider, validation, memory engine, summary) with typewriter text and spring animations
- **Provider validation**: Ollama reachability + model listing, API key validation for OpenAI/Anthropic, Apple Intelligence availability check
- **Semantic memory**: Snowflake Arctic Embed XS (22M params, 384-dim, CoreML float32) replaces brute-force recall with cosine similarity top-K ranking via Accelerate.framework. Apple NLEmbedding fallback if CoreML model unavailable
- **WordPiece tokenizer**: BERT-compatible subword tokenizer for Arctic model input (30522 vocab, max 128 tokens)
- **Memory vectors**: `memory_vectors` SQLite table with BLOB storage, FK cascade, migration step in setup wizard
- **System checks**: SQLite, embedding model, gateway server, log directory — validated with visual checklist
- **Re-run support**: Settings → Soul → "Re-run Setup Wizard"

## v0.3.0-alpha — Soul & Memory

PikoChan has personality, emotions, memory, and an HTTP gateway.

- **Soul container**: `PikoSoul` loads personality from `personality.yaml` — traits, sass level, communication style, rules. System prompt constructed dynamically with mood-first ordering
- **Mood system**: LLM responses start with emotion tags (`[playful]`, `[snarky]`, `[proud]`, etc.), parsed by `MoodParser` to drive sprite changes. Post-history reminder (Airi pattern) reinforces identity before each response
- **SQLite database**: `PikoStore` manages `chat_history` and `memories` tables via C SQLite API. Persists across app restarts
- **Memory pipeline**: `PikoMemory` extracts facts from conversations via internal LLM call, stores in SQLite, recalls oldest-first for context injection
- **Journal**: human-readable `~/.pikochan/memory/journal.md` updated after each extraction
- **HTTP Gateway**: `PikoHTTPServer` (NWListener) on port 7878 — POST /chat, GET /health, /history, /logs, /memories, /config, POST /mood
- **Structured logging**: `PikoGateway` JSONL logger with daily rolling, 7-day prune, 50MB cap
- **Settings**: Soul tab for personality editing and memory management

## v0.2.0-alpha — Brain Foundation

PikoChan can think and respond.

- `~/.pikochan/` directory structure with human-readable YAML configs
- Local LLM inference via Apple FoundationModels (macOS 26+) and Ollama HTTP fallback
- Cloud API fallback (OpenAI, Anthropic) with automatic local → cloud routing
- Full conversation loop: type in the notch, get a response
- Response bubble in the notch UI with status indicators
- AI Model settings tab for provider and model configuration

## Planned

### v0.6.0 — Community & Polish

- Community skill repository — download and share skill files
- Personality pack sharing — trade personality configs with other users
- Self-improvement — PikoChan can write new skill files for herself
- Advanced mood patterns — recognition of long-term behavioral trends
- Memory consolidation — periodic summarization of old memories into higher-level notes
- Apple Foundation Models integration (macOS 26+) for zero-config local inference

### Beyond Alpha — Headless, Bridges & Proactive Companionship

- **Headless mode** — run PikoChan as a pure background service on Mac Mini/Studio/Pro (no notch UI, just brain + HTTP gateway)
- **Telegram bridge** — chat with PikoChan via Telegram bot, proxied through `localhost:7878`
- **Discord bridge** — Discord bot integration for server or DM conversations
- **Webhook API** — generic webhook endpoint for any chat platform (Slack, WhatsApp, custom apps)
- **Proactive check-ins** — PikoChan reaches out if you haven't talked in a few days
- **Voice tone detection** — on-device vocal pattern analysis detects low mood or stress; PikoChan calls to keep you company
- **Cross-platform presence** — check-ins and conversations consistent across notch, Telegram, Discord

See the [vision doc](plans/2026-03-05-pikochan-vision-design.md) for full details.
