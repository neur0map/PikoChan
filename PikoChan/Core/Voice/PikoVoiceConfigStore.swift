import Observation
import Foundation

@Observable
@MainActor
final class PikoVoiceConfigStore {
    static let shared = PikoVoiceConfigStore()

    private let home = PikoHome()

    var ttsProvider: PikoVoiceConfig.TTSProvider = .none
    var ttsVoiceId: String = "alloy"
    var ttsModel: String = "tts-1"
    var ttsSpeed: Double = 1.0
    var autoSpeak: Bool = false

    var sttProvider: PikoVoiceConfig.STTProvider = .none
    var sttModel: String = "whisper-large-v3-turbo"
    var sttLanguage: String = "en"

    // API key fields for the settings UI — stored in Keychain, not YAML.
    var ttsAPIKey: String = ""
    var sttAPIKey: String = ""

    private init() {
        reload()
    }

    func reload() {
        let cfg = PikoVoiceConfigLoader.load(from: home.voiceFile)
        ttsProvider = cfg.ttsProvider
        ttsVoiceId = cfg.ttsVoiceId
        ttsModel = cfg.ttsModel
        ttsSpeed = cfg.ttsSpeed
        autoSpeak = cfg.autoSpeak
        sttProvider = cfg.sttProvider
        sttModel = cfg.sttModel
        sttLanguage = cfg.sttLanguage
        ttsAPIKey = cfg.ttsAPIKey ?? ""
        sttAPIKey = cfg.sttAPIKey ?? ""
    }

    func save() throws {
        try home.bootstrap()

        let yaml = """
        tts_provider: \(ttsProvider.rawValue)
        tts_voice_id: \(ttsVoiceId.trimmingCharacters(in: .whitespacesAndNewlines))
        tts_model: \(ttsModel.trimmingCharacters(in: .whitespacesAndNewlines))
        tts_speed: \(ttsSpeed)
        auto_speak: \(autoSpeak ? "true" : "false")
        stt_provider: \(sttProvider.rawValue)
        stt_model: \(sttModel.trimmingCharacters(in: .whitespacesAndNewlines))
        stt_language: \(sttLanguage.trimmingCharacters(in: .whitespacesAndNewlines))
        """
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")

        try yaml.write(to: home.voiceFile, atomically: true, encoding: .utf8)

        // Save TTS API key to Keychain based on provider.
        saveTTSKey()
        saveSTTKey()
    }

    /// Builds a PikoVoiceConfig from in-memory state with resolved API keys.
    /// Use this instead of loading from disk — reflects unsaved settings changes.
    var currentConfig: PikoVoiceConfig {
        PikoVoiceConfig(
            ttsProvider: ttsProvider,
            ttsVoiceId: ttsVoiceId,
            ttsModel: ttsModel,
            ttsSpeed: ttsSpeed,
            autoSpeak: autoSpeak,
            sttProvider: sttProvider,
            sttModel: sttModel,
            sttLanguage: sttLanguage,
            ttsAPIKey: resolvedTTSKey,
            sttAPIKey: resolvedSTTKey
        )
    }

    /// Resolved TTS API key: override → shared provider key.
    private var resolvedTTSKey: String? {
        let override = ttsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty { return override }
        return switch ttsProvider {
        case .openai:     PikoKeychain.load(account: "openai_api_key")
        case .elevenlabs: PikoKeychain.load(account: "elevenlabs_api_key")
        case .fishaudio:  PikoKeychain.load(account: "fishaudio_api_key")
        case .cartesia:   PikoKeychain.load(account: "cartesia_api_key")
        case .falai:      PikoKeychain.load(account: "falai_api_key")
        case .none:       nil
        }
    }

    /// Resolved STT API key: override → shared provider key.
    private var resolvedSTTKey: String? {
        let override = sttAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty { return override }
        return switch sttProvider {
        case .groq:     PikoKeychain.load(account: "groq_api_key")
        case .openai:   PikoKeychain.load(account: "openai_api_key")
        case .deepgram: PikoKeychain.load(account: "deepgram_api_key")
        case .none:     nil
        }
    }

    private func saveTTSKey() {
        let trimmed = ttsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let account: String? = switch ttsProvider {
        case .openai:     "openai_tts_api_key"
        case .elevenlabs: "elevenlabs_api_key"
        case .fishaudio:  "fishaudio_api_key"
        case .cartesia:   "cartesia_api_key"
        case .falai:      "falai_api_key"
        case .none:       nil
        }
        guard let account else { return }
        if trimmed.isEmpty {
            PikoKeychain.delete(account: account)
        } else {
            PikoKeychain.save(account: account, value: trimmed)
        }
    }

    private func saveSTTKey() {
        let trimmed = sttAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let account: String? = switch sttProvider {
        case .groq:     "groq_stt_api_key"
        case .openai:   "openai_stt_api_key"
        case .deepgram: "deepgram_api_key"
        case .none:     nil
        }
        guard let account else { return }
        if trimmed.isEmpty {
            PikoKeychain.delete(account: account)
        } else {
            PikoKeychain.save(account: account, value: trimmed)
        }
    }
}
