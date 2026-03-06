# PikoChan v0.3.5-alpha: First-Time Setup & Semantic Memory

**Date**: 2026-03-06
**Status**: Approved
**Version**: v0.3.5-alpha

---

## Goal

Two things:
1. **First-time setup wizard** — a guided in-notch experience that validates the user's environment (LLM provider, memory engine, gateway) before they start chatting.
2. **Semantic memory search** — replace brute-force "inject all memories" with embedding-based recall using Apple NLEmbedding (built-in) with model2vec fallback.

---

## Setup Architecture

### State Machine

New `NotchState` case:

```swift
enum NotchState: Equatable {
    case hidden
    case hovered
    case expanded
    case typing
    case listening
    case setup(step: SetupStep)  // NEW
}
```

### Setup Steps

```swift
enum SetupStep: Int, CaseIterable {
    case welcome        // Sprite + intro + "Begin Setup"
    case provider       // LLM provider selection (4 options)
    case providerConfig // API key entry or Ollama validation
    case memory         // NLEmbedding check, SQLite init, gateway verify
    case summary        // Checklist recap + "Let's go!"
}
```

Future versions add steps:
- v0.4.0: `.permissions` (Accessibility, AppleEvents)
- v0.5.0: `.voice` (microphone, TTS/STT model selection + download)

### First-Launch Detection

In `NotchManager.start()`:

```swift
if !brain.home.configFileExists || !brain.config.setupComplete {
    transition(to: .setup(step: .welcome))
} else {
    // normal flow → .hidden
}
```

### Re-Run Support

- Settings → Soul → "Re-run Setup" resets `setup_complete` to `false`
- `setup_version: Int` field in config.yaml — if app's version > config's, auto-trigger setup for new steps only

---

## Step 1: Welcome

```
┌──────────────────────────────────┐
│          ┌──────────┐            │
│          │ PikoChan │            │
│          │  sprite  │            │
│          └──────────┘            │
│                                  │
│    "Hey! I'm PikoChan."         │
│    "I live in your notch now."  │
│                                  │
│      ╭──────────────────╮        │
│      │   Begin Setup    │        │
│      ╰──────────────────╯        │
│                                  │
│    ·  ·  ·  ·  ·    (dots)      │
└──────────────────────────────────┘
```

**Animations:**
- Sprite fades in with scale-up (0.8 → 1.0, spring)
- Text typewriter effect (~30ms per character)
- "Begin Setup" button fades in after text finishes, subtle pulse glow on border
- Step progress dots at bottom: current filled, completed checkmarked, future hollow

**Panel behavior:**
- Auto-shows on launch (no hover needed)
- `ignoresMouseEvents = false` immediately
- `.nonactivatingPanel` removed for text field support in later steps
- Panel height: ~480px (vs normal ~380px)

---

## Step 2: Provider Selection

Horizontal slide-left transition between steps.

```
┌──────────────────────────────────┐
│          ┌──────────┐            │
│          │  sprite   │            │
│          └──────────┘            │
│                                  │
│    "Who should I think with?"    │
│                                  │
│   ╭────────────────────────╮     │
│   │  🦙  Ollama (local)    │     │
│   ╰────────────────────────╯     │
│   ╭────────────────────────╮     │
│   │  ◆  OpenAI             │     │
│   ╰────────────────────────╯     │
│   ╭────────────────────────╮     │
│   │  ◇  Anthropic          │     │
│   ╰────────────────────────╯     │
│   ╭────────────────────────╮     │
│   │  🍎  Apple Intelligence │     │
│   ╰────────────────────────╯     │
│                                  │
│   · · ● · ·        ◀ Back      │
└──────────────────────────────────┘
```

## Step 3: Provider Config (validation)

**Ollama:**
- Ping `GET http://127.0.0.1:11434/api/tags`
- ✅ → show detected models as picker, default `phi4-mini`
- ❌ → "Ollama isn't running" + install hint + Retry button

**OpenAI / Anthropic:**
- Secure text field: "Paste your API key"
- Validate with lightweight API call (OpenAI `GET /models`, Anthropic `POST /messages`)
- ✅ → model picker (gpt-4o-mini, claude-3-5-haiku, etc.)
- ❌ → inline red error, field stays editable

**Apple Intelligence:**
- Runtime availability check
- ✅ → capabilities note ("Single-turn only, no streaming")
- ❌ → "Requires macOS 26+" + suggest another provider

---

## Step 4: Memory Engine

Automated step — user watches PikoChan set things up.

```
┌──────────────────────────────────┐
│          ┌──────────┐            │
│          │  sprite   │            │
│          │ (working) │            │
│          └──────────┘            │
│                                  │
│   "Setting up my memory..."     │
│                                  │
│   ✅  SQLite database            │
│   ✅  Embedding model (Apple NL) │
│   ⏳  Indexing memories...       │
│   ○   Gateway server             │
│   ○   Log directory              │
│                                  │
│   ━━━━━━━━━━━━━━━━░░░░  68%     │
│                                  │
│   · · · ● ·        ◀ Back      │
└──────────────────────────────────┘
```

**Checks run sequentially:**

1. **SQLite database** — create tables (`chat_history`, `memories`, `memory_vectors`). Instant ✅
2. **Embedding model** — check `NLEmbedding.sentenceEmbedding(for: .english)`:
   - ✅ → "Apple NL (built-in)", instant
   - nil → download model2vec potion-retrieval-32M (~32MB) to `~/.pikochan/models/`, show progress bar
3. **Index existing memories** — batch-embed any memories from v0.3.0 that lack vectors. Show count. Fresh install → skip with ✅
4. **Gateway server** — ping `localhost:7878/health` ✅ or ❌ with port conflict hint
5. **Log directory** — verify `~/.pikochan/logs/` exists and writable ✅

**Progress bar:** overall completion (~20% per check), smooth animation.

**Error handling:** failed checks show ❌ with explanation + per-item "Retry" button. DB and embedding are required; gateway and logs are non-critical (user can skip).

---

## Step 5: Summary

```
┌──────────────────────────────────┐
│          ┌──────────┐            │
│          │  sprite   │            │
│          │ (playful) │            │
│          └──────────┘            │
│                                  │
│   "All set! I'll remember       │
│    everything about you."        │
│                                  │
│   ✅  LLM: gpt-4o-mini (OpenAI) │
│   ✅  Memory: Apple NL + SQLite  │
│   ✅  Gateway: localhost:7878    │
│   ✅  Logs: active               │
│                                  │
│      ╭──────────────────╮        │
│      │    Let's go!     │        │
│      ╰──────────────────╯        │
│                                  │
│   · · · · ●                     │
└──────────────────────────────────┘
```

**"Let's go!" action:**
1. Write `setup_complete: true` + `setup_version: 1` to config.yaml
2. Save provider + API key (Keychain) + model to config
3. Spring animation: panel shrinks to notch size, state → `.expanded`
4. First response bubble: one-time hint "Try saying hi" (not stored in history)

---

## Semantic Memory Search

### Embedding Strategy

**Primary: Apple NLEmbedding** — zero dependencies, ships with macOS.
- `NLEmbedding.sentenceEmbedding(for: .english)` → 512-dim static embeddings
- No download, no setup, instant availability
- Quality: good enough for matching short factual strings

**Fallback: model2vec.swift (potion-retrieval-32M)** — if NLEmbedding is nil.
- ~32MB download to `~/.pikochan/models/`
- Table lookup (no neural inference), extremely fast
- ~92% of all-MiniLM-L6-v2 quality
- 256-dim embeddings

### PikoEmbedding Protocol

```swift
protocol PikoEmbedder {
    func embed(_ text: String) -> [Float]?
    func embed(batch texts: [String]) -> [[Float]]
    var dimensions: Int { get }
    var name: String { get }
}

struct AppleNLEmbedder: PikoEmbedder { ... }
struct Model2VecEmbedder: PikoEmbedder { ... }
```

### Vector Storage

New `memory_vectors` table in existing SQLite database:

```sql
CREATE TABLE memory_vectors (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    memory_id INTEGER REFERENCES memories(id),
    embedding BLOB NOT NULL,          -- Float array as raw bytes
    embedder TEXT NOT NULL,            -- "apple_nl" or "model2vec"
    dimensions INTEGER NOT NULL,
    created_at TEXT DEFAULT (datetime('now'))
);
CREATE INDEX idx_vectors_memory ON memory_vectors(memory_id);
```

### Recall Flow (replaces current brute-force)

```
User prompt → embed(prompt) → cosine similarity against all memory_vectors
→ top-K results (K=15) → inject into system prompt
```

Cosine similarity via Accelerate.framework `vDSP_dotpr` — for hundreds of memories this runs in microseconds, no vector DB needed.

### Migration

Existing v0.3.0 memories (no embeddings) are batch-embedded during setup step 4. The `recallRelevant()` method in PikoMemory switches from "return all reversed" to "embed query → top-K cosine similarity".

---

## Files

### New (4)

| File | Purpose |
|------|---------|
| `Core/SetupManager.swift` | `@Observable` — step state, checks, validation, download coordination |
| `Views/SetupView.swift` | Root setup view — routes to step sub-views, slide transitions |
| `Views/SetupSteps/*.swift` | Per-step views: `WelcomeStep`, `ProviderStep`, `ProviderConfigStep`, `MemoryStep`, `SummaryStep` |
| `Core/Brain/PikoEmbedding.swift` | `PikoEmbedder` protocol + `AppleNLEmbedder` + `Model2VecEmbedder` + cosine similarity |

### Modified (7)

| File | Changes |
|------|---------|
| `Core/NotchState.swift` | Add `.setup(step: SetupStep)` case |
| `Core/NotchManager.swift` | First-launch detection, panel height override, setup transitions |
| `Views/NotchContentView.swift` | Route `.setup` state to `SetupView` |
| `Core/Brain/PikoHome.swift` | `configFileExists` property, `setup_complete` / `setup_version` in default YAML |
| `Core/Brain/PikoConfig.swift` | Parse `setup_complete: Bool` and `setup_version: Int` |
| `Core/Brain/PikoStore.swift` | Add `memory_vectors` table, migration logic |
| `Utilities/PikoPanel.swift` | Dynamic height changes for taller setup panel |

---

## Implementation Order

1. Add `setup_complete` / `setup_version` to PikoConfig + PikoHome
2. Add `.setup(step:)` to NotchState
3. Create `SetupManager` with step state + check logic
4. Create `SetupView` + per-step views (WelcomeStep through SummaryStep)
5. Wire first-launch detection in NotchManager
6. Create `PikoEmbedding.swift` — AppleNLEmbedder + Model2VecEmbedder + cosine similarity
7. Add `memory_vectors` table to PikoStore + migration
8. Update PikoMemory recall to use semantic search
9. Panel height adjustments in PikoPanel
10. Route `.setup` in NotchContentView
11. Build & test full flow

## Verification

1. **Fresh install**: delete `~/.pikochan/`, launch app → setup wizard appears automatically
2. **Provider validation**: select OpenAI, paste invalid key → red error; paste valid key → ✅ + model picker
3. **Ollama check**: stop Ollama → shows ❌; start Ollama → Retry → ✅
4. **Memory engine**: NLEmbedding check passes on macOS 14+; on failure, model2vec downloads with progress
5. **Migration**: create memories via v0.3.0 chat, upgrade, re-run setup → existing memories get embedded
6. **Semantic recall**: store "User likes tacos al pastor", query "what food do I like" → returns taco memory (not brute-force all)
7. **Summary**: all checks ✅, "Let's go!" transitions to normal `.expanded` state
8. **Re-run**: Settings → Soul → "Re-run Setup" → wizard reappears
9. **Version upgrade**: bump `setup_version` in code → old config triggers setup for new steps only
