import Foundation

struct PikoVoiceConfig {
    enum TTSProvider: String, CaseIterable {
        case none, openai, elevenlabs, fishaudio, cartesia, falai, local
    }

    enum STTProvider: String, CaseIterable {
        case none, apple, groq, deepgram, openai
    }

    var ttsProvider: TTSProvider
    var ttsVoiceId: String
    var ttsModel: String
    var ttsSpeed: Double
    var autoSpeak: Bool

    var sttProvider: STTProvider
    var sttModel: String
    var sttLanguage: String

    // Local TTS fields.
    var localModelPath: String
    var localMoodMode: String   // "auto" or "custom"
    var localLanguage: String

    // API keys from Keychain (not YAML).
    var ttsAPIKey: String?
    var sttAPIKey: String?

    static let `default` = PikoVoiceConfig(
        ttsProvider: .none,
        ttsVoiceId: "alloy",
        ttsModel: "tts-1",
        ttsSpeed: 1.0,
        autoSpeak: false,
        sttProvider: .none,
        sttModel: "whisper-large-v3-turbo",
        sttLanguage: "en",
        localModelPath: "",
        localMoodMode: "auto",
        localLanguage: "en",
        ttsAPIKey: nil,
        sttAPIKey: nil
    )
}

enum PikoVoiceConfigLoader {
    static func load(from file: URL) -> PikoVoiceConfig {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            return .default
        }

        let map = parseSimpleYAML(text)

        let ttsProvider = PikoVoiceConfig.TTSProvider(rawValue: map["tts_provider"] ?? "") ?? .none
        let ttsVoiceId = map["tts_voice_id"]?.nonEmpty ?? PikoVoiceConfig.default.ttsVoiceId
        let ttsModel = map["tts_model"]?.nonEmpty ?? PikoVoiceConfig.default.ttsModel
        let ttsSpeed = Double(map["tts_speed"] ?? "") ?? PikoVoiceConfig.default.ttsSpeed
        let autoSpeak = (map["auto_speak"] ?? "false") == "true"
        let sttProvider = PikoVoiceConfig.STTProvider(rawValue: map["stt_provider"] ?? "") ?? .none
        let sttModel = map["stt_model"]?.nonEmpty ?? PikoVoiceConfig.default.sttModel
        let sttLanguage = map["stt_language"]?.nonEmpty ?? PikoVoiceConfig.default.sttLanguage

        let localModelPath = map["local_model_path"] ?? ""
        let localMoodMode = map["local_mood_mode"]?.nonEmpty ?? "auto"
        let localLanguage = map["local_language"]?.nonEmpty ?? "en"

        // API keys: voice-specific first, then fall back to shared provider keys.
        let ttsAPIKey: String? = {
            switch ttsProvider {
            case .openai:
                return PikoKeychain.load(account: "openai_tts_api_key")
                    ?? PikoKeychain.load(account: "openai_api_key")
            case .elevenlabs:
                return PikoKeychain.load(account: "elevenlabs_api_key")
            case .fishaudio:
                return PikoKeychain.load(account: "fishaudio_api_key")
            case .cartesia:
                return PikoKeychain.load(account: "cartesia_api_key")
            case .falai:
                return PikoKeychain.load(account: "falai_api_key")
            case .local:
                return nil
            case .none:
                return nil
            }
        }()

        let sttAPIKey: String? = {
            switch sttProvider {
            case .groq:
                return PikoKeychain.load(account: "groq_stt_api_key")
                    ?? PikoKeychain.load(account: "groq_api_key")
            case .openai:
                return PikoKeychain.load(account: "openai_stt_api_key")
                    ?? PikoKeychain.load(account: "openai_api_key")
            case .deepgram:
                return PikoKeychain.load(account: "deepgram_api_key")
            case .apple:
                return nil // No API key — on-device.
            case .none:
                return nil
            }
        }()

        return PikoVoiceConfig(
            ttsProvider: ttsProvider,
            ttsVoiceId: ttsVoiceId,
            ttsModel: ttsModel,
            ttsSpeed: ttsSpeed,
            autoSpeak: autoSpeak,
            sttProvider: sttProvider,
            sttModel: sttModel,
            sttLanguage: sttLanguage,
            localModelPath: localModelPath,
            localMoodMode: localMoodMode,
            localLanguage: localLanguage,
            ttsAPIKey: ttsAPIKey,
            sttAPIKey: sttAPIKey
        )
    }

    private static func parseSimpleYAML(_ text: String) -> [String: String] {
        var map: [String: String] = [:]
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let idx = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            if let commentIdx = value.range(of: " #") {
                value = String(value[..<commentIdx.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            map[key] = value
        }
        return map
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
