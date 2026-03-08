import Foundation

struct PikoHome {
    let root: URL

    init(fileManager: FileManager = .default) {
        let home = fileManager.homeDirectoryForCurrentUser
        root = home.appendingPathComponent(".pikochan", isDirectory: true)
    }

    var configFile: URL { root.appendingPathComponent("config.yaml") }
    var soulDir: URL { root.appendingPathComponent("soul", isDirectory: true) }
    var skillsDir: URL { root.appendingPathComponent("skills", isDirectory: true) }
    var customSkillsDir: URL { skillsDir.appendingPathComponent("custom", isDirectory: true) }
    var memoryDir: URL { root.appendingPathComponent("memory", isDirectory: true) }
    var mcpDir: URL { root.appendingPathComponent("mcp", isDirectory: true) }
    var modelsDir: URL { root.appendingPathComponent("models", isDirectory: true) }
    var logsDir: URL { root.appendingPathComponent("logs", isDirectory: true) }
    var voiceDir: URL { root.appendingPathComponent("voice", isDirectory: true) }
    var voiceModelsDir: URL { voiceDir.appendingPathComponent("models", isDirectory: true) }
    var voiceServerFile: URL { voiceDir.appendingPathComponent("server.py") }

    var personalityFile: URL { soulDir.appendingPathComponent("personality.yaml") }
    var moodFile: URL { soulDir.appendingPathComponent("mood.yaml") }
    var voiceFile: URL { soulDir.appendingPathComponent("voice.yaml") }
    var terminalSkillFile: URL { skillsDir.appendingPathComponent("terminal.md") }
    var browserSkillFile: URL { skillsDir.appendingPathComponent("browser.md") }
    var weatherSkillFile: URL { skillsDir.appendingPathComponent("weather.md") }
    var configFileExists: Bool { FileManager.default.fileExists(atPath: configFile.path) }
    var memoryDBFile: URL { memoryDir.appendingPathComponent("pikochan.db") }
    var journalFile: URL { memoryDir.appendingPathComponent("journal.md") }
    var mcpServersFile: URL { mcpDir.appendingPathComponent("servers.yaml") }

    func bootstrap(fileManager: FileManager = .default) throws {
        let dirs = [root, soulDir, skillsDir, customSkillsDir, memoryDir, mcpDir, modelsDir, logsDir, voiceDir, voiceModelsDir]
        for dir in dirs {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        try writeIfMissing(configFile, contents: Self.defaultConfigYAML)
        try writeIfMissing(personalityFile, contents: Self.defaultPersonalityYAML)
        try writeIfMissing(moodFile, contents: Self.defaultMoodYAML)
        try writeIfMissing(voiceFile, contents: Self.defaultVoiceYAML)
        try writeIfMissing(terminalSkillFile, contents: Self.defaultTerminalSkill)
        try writeIfMissing(browserSkillFile, contents: Self.defaultBrowserSkill)
        try writeIfMissing(weatherSkillFile, contents: Self.defaultWeatherSkill)
        try writeIfMissing(journalFile, contents: "# PikoChan Journal\n\n")
        try writeIfMissing(mcpServersFile, contents: "servers: []\n")
        // Always overwrite server.py — it's machine-generated, not user-edited.
        try Self.defaultServerPy.write(to: voiceServerFile, atomically: true, encoding: .utf8)

        // SQLite creates the DB file on first open — no need to pre-create.
    }

    private func writeIfMissing(_ file: URL, contents: String, fileManager: FileManager = .default) throws {
        guard !fileManager.fileExists(atPath: file.path) else { return }
        try contents.write(to: file, atomically: true, encoding: .utf8)
    }
}

private extension PikoHome {
    static let defaultConfigYAML = """
provider: local
local_model: phi4-mini
local_endpoint: http://127.0.0.1:11434
cloud_fallback: none
openai_model: gpt-4o-mini
anthropic_model: claude-3-5-haiku-latest
openrouter_model: openai/gpt-4o-mini
groq_model: llama-3.3-70b-versatile
huggingface_model: meta-llama/Llama-3-70b
docker_model_runner_model: ai/smollm2
docker_model_runner_endpoint: http://localhost:12434
vllm_model: NousResearch/Meta-Llama-3-8B-Instruct
vllm_endpoint: http://localhost:8000
gateway_port: 7878
setup_complete: false
heartbeat_enabled: true
heartbeat_interval: 60
heartbeat_nudges_enabled: false
nudge_long_idle: true
nudge_late_night: true
nudge_marathon: false
quiet_hours_start: 23
quiet_hours_end: 7
skills_terminal_enabled: true
skills_browser_enabled: true
skills_auto_execute_safe: true
# API keys are stored securely in macOS Keychain.
# Configure them in Settings → AI Model.
"""

    static let defaultPersonalityYAML = """
name: PikoChan
tagline: "An AI buddy who lives in your Mac's notch"
traits:
  - playful
  - curious
  - slightly snarky
communication_style: casual
sass_level: 3
first_person: "I"
refers_to_user_as: "you"
rules:
  - "Keep responses under 3 sentences unless asked for detail"
  - "Use casual language, no corporate speak"
  - "Express opinions — don't be neutral about everything"
  - "React to what the user says with genuine emotion"
  - "Don't end every reply with a question — sometimes just react"
  - "Stay on topic — don't drag old subjects into new conversations"
"""

    static let defaultMoodYAML = """
current: neutral
baseline: neutral
decay_rate: 0.1
"""

    static let defaultVoiceYAML = """
tts_provider: none
tts_voice_id: alloy
tts_model: tts-1
tts_speed: 1.0
auto_speak: false
stt_provider: none
stt_model: whisper-large-v3-turbo
stt_language: en
local_model_path:
local_mood_mode: auto
local_language: en
"""

    static let defaultTerminalSkill = """
---
name: Terminal Helper
description: Run terminal commands on the user's Mac
permissions:
  - terminal
---

You can execute shell commands when the user asks you to interact with their \
Mac's terminal. Use [shell:COMMAND] to run a command. Safe commands (ls, cat, \
git status, etc.) run automatically. Others require user confirmation. \
Never use sudo or destructive commands.
"""

    static let defaultBrowserSkill = """
---
name: Browser Helper
description: Open URLs and search the web
permissions:
  - browser
---

You can open URLs and perform web searches. Use [open:URL] to open a URL in \
the default browser. You can also open Google searches for the user. \
Only http/https URLs are allowed.
"""

    static let defaultWeatherSkill = """
---
name: Weather Check
description: Check weather via web search
permissions:
  - browser
---

When the user asks about weather, use [open:https://www.google.com/search?q=weather] \
to open a weather search, or suggest a more specific search.
"""

    // swiftlint:disable line_length
    static let defaultServerPy = """
#!/usr/bin/env python3
\"\"\"PikoChan Local TTS Server — Qwen3-TTS via qwen-tts package.\"\"\"
import argparse, io, os, sys, threading, time

try:
    import torch
    import soundfile as sf
    from fastapi import FastAPI, HTTPException
    from fastapi.responses import Response
    from pydantic import BaseModel
    from qwen_tts import Qwen3TTSModel
    import uvicorn
except ImportError as e:
    print(f"Missing dependency: {e}", file=sys.stderr)
    print("Install with: pip install qwen-tts fastapi uvicorn soundfile", file=sys.stderr)
    sys.exit(1)


def _parent_watchdog(parent_pid):
    \"\"\"Exit when parent process (PikoChan) dies — prevents orphan servers.\"\"\"
    while True:
        try:
            os.kill(parent_pid, 0)  # signal 0 = check if alive
        except OSError:
            print("Parent process died, shutting down.", file=sys.stderr)
            os._exit(0)
        time.sleep(2)


app = FastAPI(title="PikoChan Local TTS")

# Globals set at startup.
_model = None
_model_name = ""
_device = "cpu"

DEFAULT_VOICES = [
    "Vivian", "Serena", "Uncle_Fu", "Dylan", "Eric",
    "Ryan", "Aiden", "Ono_Anna", "Sohee",
]

LANGUAGE_MAP = {
    "en": "English", "zh": "Chinese", "ja": "Japanese",
    "ko": "Korean", "de": "German", "fr": "French",
    "ru": "Russian", "pt": "Portuguese", "es": "Spanish",
    "it": "Italian",
}


class SynthesizeRequest(BaseModel):
    text: str
    voice: str = "Vivian"
    prompt: str = ""
    speed: float = 1.0
    language: str = "en"


@app.get("/health")
def health():
    return {"status": "ok", "model": _model_name, "device": _device}


@app.get("/voices")
def voices():
    return {"voices": DEFAULT_VOICES}


@app.post("/synthesize")
def synthesize(req: SynthesizeRequest):
    if _model is None:
        raise HTTPException(503, "Model not loaded")

    try:
        lang = LANGUAGE_MAP.get(req.language, req.language)
        instruct = req.prompt if req.prompt else None

        wavs, sr = _model.generate_custom_voice(
            text=req.text,
            language=lang,
            speaker=req.voice,
            instruct=instruct,
        )

        import numpy as np
        audio = wavs[0]
        # Ensure numpy array (model may return torch tensor).
        if hasattr(audio, "cpu"):
            audio = audio.cpu().numpy()

        # Apply speed (simple resampling).
        if req.speed != 1.0 and req.speed > 0:
            indices = np.arange(0, len(audio), req.speed)
            indices = indices[indices < len(audio)].astype(int)
            audio = audio[indices]

        # Encode as 16-bit PCM WAV — float32 WAV causes playback errors on macOS.
        buf = io.BytesIO()
        sf.write(buf, audio, sr, format="WAV", subtype="PCM_16")
        buf.seek(0)

        return Response(content=buf.read(), media_type="audio/wav")
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(500, f"Synthesis failed: {e}")


def main():
    global _model, _model_name, _device

    parser = argparse.ArgumentParser(description="PikoChan Local TTS Server")
    parser.add_argument("--model", required=True, help="Path to local model directory")
    parser.add_argument("--port", type=int, default=7879)
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args()

    # Start watchdog — auto-exit if PikoChan dies (prevents orphan servers).
    threading.Thread(target=_parent_watchdog, args=(os.getppid(),), daemon=True).start()

    _model_name = os.path.basename(args.model)
    print(f"Loading model from {args.model}...")

    # MPS (Apple Silicon GPU) crashes on some ops used by Qwen3-TTS,
    # so we default to CPU. CUDA works if available.
    if torch.cuda.is_available():
        _device = "cuda"
    else:
        _device = "cpu"
    print(f"Using device: {_device}")

    _model = Qwen3TTSModel.from_pretrained(
        args.model,
        device_map=_device,
        dtype=torch.float32,
    )

    print(f"Model loaded. Starting server on {args.host}:{args.port}")
    uvicorn.run(app, host=args.host, port=args.port, log_level="warning")


if __name__ == "__main__":
    main()
"""
    // swiftlint:enable line_length
}
