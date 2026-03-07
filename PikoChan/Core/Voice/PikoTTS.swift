import Foundation

@MainActor
final class PikoTTS {

    /// Optional mood string sent as emotion/style prompt for models that support it.
    var moodHint: String?

    func synthesize(text: String, config: PikoVoiceConfig) async throws -> Data {
        guard let apiKey = config.ttsAPIKey, !apiKey.isEmpty else {
            throw PikoVoiceError.noAPIKey(provider: config.ttsProvider.rawValue)
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        PikoGateway.shared.logTTSStart(provider: config.ttsProvider.rawValue, textChars: text.count)

        let audioData: Data
        switch config.ttsProvider {
        case .openai:
            audioData = try await synthesizeOpenAI(text: text, config: config, apiKey: apiKey)
        case .elevenlabs:
            audioData = try await synthesizeElevenLabs(text: text, config: config, apiKey: apiKey)
        case .fishaudio:
            audioData = try await synthesizeFishAudio(text: text, config: config, apiKey: apiKey)
        case .cartesia:
            audioData = try await synthesizeCartesia(text: text, config: config, apiKey: apiKey)
        case .falai:
            audioData = try await synthesizeFalAI(text: text, config: config, apiKey: apiKey)
        case .none:
            throw PikoVoiceError.ttsFailed(detail: "No TTS provider configured")
        }

        let durationMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        PikoGateway.shared.logTTSEnd(
            provider: config.ttsProvider.rawValue,
            durationMs: durationMs,
            audioBytes: audioData.count
        )

        return audioData
    }

    // MARK: - OpenAI TTS

    private func synthesizeOpenAI(text: String, config: PikoVoiceConfig, apiKey: String) async throws -> Data {
        let body: [String: Any] = [
            "model": config.ttsModel.isEmpty ? "tts-1" : config.ttsModel,
            "input": text,
            "voice": config.ttsVoiceId.isEmpty ? "alloy" : config.ttsVoiceId,
            "speed": config.ttsSpeed,
            "response_format": "mp3",
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, provider: "OpenAI TTS")
        return data
    }

    // MARK: - ElevenLabs TTS

    private func synthesizeElevenLabs(text: String, config: PikoVoiceConfig, apiKey: String) async throws -> Data {
        let voiceId = config.ttsVoiceId.isEmpty ? "21m00Tcm4TlvDq8ikWAM" : config.ttsVoiceId
        let endpoint = "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)"

        var body: [String: Any] = [
            "text": text,
            "model_id": config.ttsModel.isEmpty ? "eleven_turbo_v2_5" : config.ttsModel,
        ]

        // Voice settings for speed control.
        if config.ttsSpeed != 1.0 {
            body["voice_settings"] = [
                "stability": 0.5,
                "similarity_boost": 0.5,
                "speed": config.ttsSpeed,
            ]
        }

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, provider: "ElevenLabs TTS")
        return data
    }

    // MARK: - Fish Audio TTS

    private func synthesizeFishAudio(text: String, config: PikoVoiceConfig, apiKey: String) async throws -> Data {
        var body: [String: Any] = [
            "text": text,
            "format": "mp3",
        ]
        if !config.ttsVoiceId.isEmpty {
            body["reference_id"] = config.ttsVoiceId
        }

        var request = URLRequest(url: URL(string: "https://api.fish.audio/v1/tts")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("s1", forHTTPHeaderField: "model")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, provider: "Fish Audio TTS")
        return data
    }

    // MARK: - Cartesia TTS

    private func synthesizeCartesia(text: String, config: PikoVoiceConfig, apiKey: String) async throws -> Data {
        let body: [String: Any] = [
            "transcript": text,
            "model_id": config.ttsModel.isEmpty ? "sonic-2" : config.ttsModel,
            "voice": [
                "mode": "id",
                "id": config.ttsVoiceId.isEmpty ? "a0e99841-438c-4a64-b679-ae501e7d6091" : config.ttsVoiceId,
            ],
            "output_format": [
                "container": "mp3",
                "bit_rate": 128000,
            ],
        ]

        var request = URLRequest(url: URL(string: "https://api.cartesia.ai/tts/bytes")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2024-06-10", forHTTPHeaderField: "Cartesia-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, provider: "Cartesia TTS")
        return data
    }

    // MARK: - fal.ai TTS

    private func synthesizeFalAI(text: String, config: PikoVoiceConfig, apiKey: String) async throws -> Data {
        let model = config.ttsModel.isEmpty ? "fal-ai/kokoro/american-english" : config.ttsModel

        // Fetch schema to discover the correct field names for this model.
        let schema = await FalAISchema.shared.schema(for: model)
        let textField = schema?.textFieldName ?? "prompt"

        var body: [String: Any] = [
            textField: text,
        ]
        // Send mood as emotion/style prompt if the model supports it.
        if let promptField = schema?.promptFieldName, let mood = moodHint, !mood.isEmpty {
            body[promptField] = mood
        }
        if let voiceField = schema?.voiceFieldName {
            body[voiceField] = config.ttsVoiceId.isEmpty ? (schema?.defaultVoice ?? "af_heart") : config.ttsVoiceId
        } else if !config.ttsVoiceId.isEmpty {
            body["voice"] = config.ttsVoiceId
        }
        if schema?.hasSpeed == true {
            body["speed"] = config.ttsSpeed
        }

        var request = URLRequest(url: URL(string: "https://fal.run/\(model)")!)
        request.httpMethod = "POST"
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        // fal.ai models can have cold starts of 30-60s+ (especially large models like Qwen-3-TTS 1.7B).
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, provider: "fal.ai TTS")

        // fal.ai returns JSON with audio.url — fetch the actual audio.
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let audio = json["audio"] as? [String: Any],
              let urlString = audio["url"] as? String,
              let audioURL = URL(string: urlString)
        else {
            throw PikoVoiceError.ttsFailed(detail: "Unexpected fal.ai response format")
        }

        let (audioData, audioResponse) = try await URLSession.shared.data(from: audioURL)
        try validateHTTPResponse(audioResponse, data: audioData, provider: "fal.ai TTS audio fetch")
        return audioData
    }

    // MARK: - Helpers

    private func validateHTTPResponse(_ response: URLResponse, data: Data, provider: String) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PikoVoiceError.ttsFailed(detail: "\(provider): Invalid response")
        }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data.prefix(500), encoding: .utf8) ?? "Unknown error"
            throw PikoVoiceError.ttsFailed(detail: "\(provider) HTTP \(httpResponse.statusCode): \(errorBody)")
        }
    }
}
