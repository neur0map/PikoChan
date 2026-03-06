# PikoChan v0.2.0 Polish Plan

**Date**: 2026-03-05
**Status**: Approved
**Scope**: 15 fixes across 5 workstreams, shipping before v0.3.0

---

## Why This Pass Exists

v0.2.0 shipped the brain — local LLM, cloud fallback, notch chat. But the experience has sharp edges: responses truncate at 4 lines, errors say "bad HTTP response" with no guidance, API keys sit in plain text YAML, and there's no way to cancel a hung request. This pass files those edges down before building the soul and memory layer.

Every change here is about what the user sees and feels inside the app.

---

## Workstream 1: Response UX

**Issues addressed**: #6 (response truncated), #12 (no copy), #13 (no streaming)

### Streaming Text

New `PikoBrain.respondStreaming(to:) -> AsyncStream<String>` method. Each backend yields chunks differently:

- **Ollama**: `"stream": true` — newline-delimited JSON, each with `response` field
- **OpenAI**: `stream: true` — SSE format, `choices[0].delta.content` per event
- **Anthropic**: `stream: true` — SSE format, `content_block_delta` events with `delta.text`
- **FoundationModels**: No streaming API — simulate with character-by-character reveal (15ms delay per char)

`NotchManager.submitTextInput()` switches to streaming path. Each chunk appends to `lastResponseText`, which the bubble observes reactively.

### Expandable Response Bubble

**Compact mode** (default): 5 lines max, text truncated with `...` indicator at bottom-right. Panel height unchanged.

**Expanded mode** (tap bubble): `ScrollView` up to 200pt tall, `.scrollIndicators(.hidden)`. Panel height animates via spring to accommodate. Tap bubble again or tap outside to collapse.

`isResponseExpanded: Bool` on `NotchManager` drives the toggle. `NotchContentView` switches between `Text(...).lineLimit(5)` and `ScrollView { Text(...) }`.

### Copy Button

Clipboard icon at top-right of response bubble, visible on hover. Copies `lastResponseText` to `NSPasteboard.general`. Icon briefly becomes checkmark with "Copied" for 1.5s.

### Cancel In-Flight Request

While `isResponding == true`, submit button transforms to stop button (square icon). Tapping it:
1. Cancels stored `currentResponseTask`
2. Keeps whatever text streamed so far in `lastResponseText`
3. Sets `isResponding = false`

"Thinking..." text replaced with pulsing 3-dot animation (0.4s cycle).

### Files touched
- `PikoBrain.swift` — new `respondStreaming()`, streaming parsers for each backend
- `NotchManager.swift` — `currentResponseTask` storage, `isResponseExpanded`, streaming submit flow
- `NotchContentView.swift` — expandable bubble, copy button, cancel button, dot animation
- `TypingView.swift` — submit button ↔ stop button swap

---

## Workstream 2: Input Guard Rails

**Issues addressed**: #4 (submit while responding), #5 (cancel in-flight, partial)

### Submit Lock

`NotchManager.submitTextInput()` checks `isResponding` at top — bails if true. Submit button visually disabled (opacity 0.3) while responding. Button transforms to cancel/stop (from Workstream 1).

### Input Limits

Max 2000 characters enforced in `PikoTextField` delegate (`controlTextDidChange`). Subtle counter appears at bottom-right when >1500 chars: `"1847/2000"`. Paste operations truncated to limit.

### Whitespace Guard

`TypingView` submit button visibility checks `inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty` instead of just `.isEmpty`.

### Files touched
- `NotchManager.swift` — `isResponding` guard in `submitTextInput()`
- `PikoTextField.swift` — character limit in delegate, counter display
- `TypingView.swift` — whitespace trim on visibility check

---

## Workstream 3: Error Experience

**Issues addressed**: #8 (fragile JSON parsing), #14 (bootstrap errors swallowed), #15 (typo)

### Contextual Error Messages

New `PikoError` struct:
```swift
struct PikoError {
    let message: String      // What happened
    let suggestion: String?  // How to fix it
    let severity: Severity   // .warning or .error
    let opensSettings: Bool  // Tapping suggestion opens Settings
}
```

Error mapping:

| Condition | Message | Suggestion |
|-----------|---------|------------|
| Ollama not running | Can't reach local model | Start Ollama or switch to cloud in Settings |
| FoundationModels unavailable | On-device model not available | Requires macOS 26+ or set up Ollama |
| Missing API key | No API key configured | Add your key in Settings → AI Model |
| Invalid API key (401) | API key was rejected | Check your key in Settings → AI Model |
| Network timeout | Request timed out | Check your connection and try again |
| Rate limit (429) | Too many requests | Wait a moment and try again |
| Empty response | Model returned nothing | Try a different prompt or model |
| Bootstrap failed | Couldn't set up config folder | Check permissions on ~/.pikochan/ |

Response bubble shows message on line 1, suggestion on line 2 in dimmer text. When `opensSettings == true`, tapping the suggestion opens Settings directly to the AI Model tab.

### Sprite Mood on Error

When error occurs, sprite switches to `concerned` mood for 2 seconds, then reverts. Gives visual personality to failures.

### Bootstrap Error Surfacing

Replace `try? home.bootstrap()` in `PikoConfigStore.init()` with proper do/catch. On failure, populate `lastResponseError` immediately so user sees it on first expand.

### Typo Fix

`"encoraging"` → `"encouraging"` in `NotchManager.moodResourceKeywords()`.

### Files touched
- New: `Core/Brain/PikoError.swift` — error type with message/suggestion/severity
- `PikoBrain.swift` — throw `PikoError` instead of generic `PikoBrainError`
- `NotchManager.swift` — display error + suggestion, sprite mood on error, typo fix
- `NotchContentView.swift` — two-line error bubble layout, tappable suggestion
- `PikoConfigStore.swift` — proper bootstrap error handling

---

## Workstream 4: Security & Config

**Issues addressed**: #1 (plain text API keys), #3 (model mismatch), #7 (YAML parser), #9 (no validation)

### Keychain Storage

New `PikoKeychain.swift` — thin Security framework wrapper:
- `static func save(key: String, value: String)` — `SecItemAdd` / `SecItemUpdate`
- `static func load(key: String) -> String?` — `SecItemCopyMatching`
- `static func delete(key: String)` — `SecItemDelete`
- Service: `"prowlsh.PikoChan"`, accounts: `"openai_api_key"`, `"anthropic_api_key"`

`PikoConfigStore` reads/writes keys via Keychain. `config.yaml` no longer contains API key lines. `AIModelTab` SecureFields bind to Keychain-backed properties.

**Migration**: On launch, if keys exist in `config.yaml`, move them to Keychain and rewrite the file without key lines.

### YAML Parser Fix

Current `parseSimpleYAML` splits on first `:` — verify it correctly handles values containing colons (e.g., `http://127.0.0.1:11434`). Add quoted string support (strip surrounding `"` or `'`). The current implementation at `PikoConfig.swift:71` uses `firstIndex(of: ":")` which should work for the colon case, but needs verification and a test.

### Default Model Alignment

Both `PikoConfig.default.localModel` and `PikoHome.defaultConfigYAML` aligned to `phi4-mini` (the name Ollama recognizes).

### Settings Validation

"Save" in `AIModelTab` validates before writing:
- Cloud provider selected + empty API key → inline red text "API key required"
- Local provider + invalid endpoint URL → inline red text "Invalid endpoint URL"
- Validation errors prevent save

"Test Connection" button:
- Sends minimal request to configured provider (5-second timeout)
- Green checkmark + "Connected" on success
- Red X + error summary on failure
- Non-blocking async task

### Files touched
- New: `Utilities/PikoKeychain.swift` — Keychain CRUD wrapper
- `PikoConfigStore.swift` — Keychain integration, migration logic
- `PikoConfig.swift` — YAML parser hardening, remove API key fields from file format
- `PikoHome.swift` — default config without API keys, align model name
- `AIModelTab.swift` — validation, test connection button, Keychain-backed fields

---

## Workstream 5: Network Resilience

**Issues addressed**: #2 (no timeouts), #5 (task cancellation), #11 (unbounded history)

### Network Timeouts

Custom `URLSessionConfiguration`:
- `timeoutIntervalForRequest = 30` seconds (standard requests)
- `timeoutIntervalForResource = 120` seconds (streaming connections)
- Shared `URLSession` instance in `PikoBrain`

### Task Cancellation

`NotchManager` stores `currentResponseTask: Task<Void, Never>?`:
- New submit → cancel previous task first
- Panel closes to `.hidden` → cancel task, clear "Thinking..." state
- App quit (`teardown()`) → cancel task
- `PikoBrain` checks `Task.isCancelled` between streaming chunks

### History Limits

`PikoBrain.history` capped at 50 turns (sliding window). Oldest turns drop when full. Only most recent 20 turns sent as LLM context. Full in-memory history preserved until app restart.

### Codable Response Parsing

Replace nested dictionary casting with typed structs:
```swift
struct OllamaResponse: Codable { let response: String }
struct OpenAIResponse: Codable { let choices: [Choice] }
struct AnthropicResponse: Codable { let content: [ContentBlock] }
```
Decode with `JSONDecoder`. Errors become typed `DecodingError` mapped to `PikoError`.

### Files touched
- `PikoBrain.swift` — URLSession config, Codable structs, history cap, cancellation checks
- `NotchManager.swift` — task storage, cancellation on state changes

---

## Implementation Order

Execute workstreams in this order (dependencies flow downward):

1. **Workstream 5: Network Resilience** — foundational; timeouts and Codable parsing are needed by streaming
2. **Workstream 4: Security & Config** — Keychain and validation are independent; model fix unblocks testing
3. **Workstream 3: Error Experience** — `PikoError` type needed by response UX for error display
4. **Workstream 1: Response UX** — depends on streaming infra (WS5), error types (WS3)
5. **Workstream 2: Input Guard Rails** — depends on cancel button from WS1

---

## Out of Scope

These are not part of this polish pass:
- Markdown rendering in responses (v0.3.0 — needs design for notch-sized rendering)
- `preventCloseOnMouseLeave` setting (dead toggle — defer to v0.3.0 behavior overhaul)
- Conversation persistence to SQLite (v0.3.0 — PikoMemory)
- Voice input implementation (v0.5.0)
- Logging system / os.log (nice-to-have, not UX-facing)
