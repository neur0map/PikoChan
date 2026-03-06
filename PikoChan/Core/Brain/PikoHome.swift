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
        let dirs = [root, soulDir, skillsDir, customSkillsDir, memoryDir, mcpDir, modelsDir, logsDir]
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
gateway_port: 7878
setup_complete: false
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
"""

    static let defaultMoodYAML = """
current: neutral
baseline: neutral
decay_rate: 0.1
"""

    static let defaultVoiceYAML = """
provider: local
enabled: false
"""

    static let defaultTerminalSkill = """
---
name: Terminal Helper
trigger: terminal, shell, command
permissions:
  - terminal
---

Suggest terminal commands. User executes manually.
"""

    static let defaultBrowserSkill = """
---
name: Browser Helper
trigger: browser, web, open url
permissions:
  - browser
---

Help with browser navigation tasks.
"""

    static let defaultWeatherSkill = """
---
name: Weather Check
trigger: weather, forecast
permissions:
  - browser
---

Check current weather and summarize it.
"""
}
