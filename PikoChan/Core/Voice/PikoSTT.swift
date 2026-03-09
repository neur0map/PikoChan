import Foundation

@MainActor
final class PikoSTT {

    func transcribe(audioData: Data, config: PikoVoiceConfig) async throws -> String {
        guard let apiKey = config.sttAPIKey, !apiKey.isEmpty else {
            throw PikoVoiceError.noAPIKey(provider: config.sttProvider.rawValue)
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        PikoGateway.shared.logSTTStart(provider: config.sttProvider.rawValue, audioBytes: audioData.count)

        let transcript: String
        switch config.sttProvider {
        case .groq:
            transcript = try await transcribeWhisperCompatible(
                audioData: audioData,
                endpoint: "https://api.groq.com/openai/v1/audio/transcriptions",
                apiKey: apiKey,
                model: config.sttModel.isEmpty ? "whisper-large-v3-turbo" : config.sttModel,
                language: config.sttLanguage
            )
        case .openai:
            transcript = try await transcribeWhisperCompatible(
                audioData: audioData,
                endpoint: "https://api.openai.com/v1/audio/transcriptions",
                apiKey: apiKey,
                model: config.sttModel.isEmpty ? "whisper-1" : config.sttModel,
                language: config.sttLanguage
            )
        case .deepgram:
            transcript = try await transcribeDeepgram(
                audioData: audioData,
                apiKey: apiKey,
                language: config.sttLanguage
            )
        case .apple:
            throw PikoVoiceError.sttFailed(detail: "Apple STT uses streaming — not batch")
        case .none:
            throw PikoVoiceError.sttFailed(detail: "No STT provider configured")
        }

        let durationMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        PikoGateway.shared.logSTTEnd(
            provider: config.sttProvider.rawValue,
            durationMs: durationMs,
            transcript: transcript
        )

        return transcript
    }

    // MARK: - Whisper-Compatible (Groq, OpenAI)

    private func transcribeWhisperCompatible(
        audioData: Data,
        endpoint: String,
        apiKey: String,
        model: String,
        language: String
    ) async throws -> String {
        let boundary = UUID().uuidString
        var body = Data()

        // model field
        body.appendMultipart(boundary: boundary, name: "model", value: model)

        // language field (optional)
        if !language.isEmpty {
            body.appendMultipart(boundary: boundary, name: "language", value: language)
        }

        // response_format
        body.appendMultipart(boundary: boundary, name: "response_format", value: "json")

        // audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // closing boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PikoVoiceError.sttFailed(detail: "Invalid response")
        }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PikoVoiceError.sttFailed(detail: "HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        // Parse {"text": "..."}
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String
        else {
            throw PikoVoiceError.sttFailed(detail: "Unexpected response format")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Deepgram

    private func transcribeDeepgram(
        audioData: Data,
        apiKey: String,
        language: String
    ) async throws -> String {
        var urlString = "https://api.deepgram.com/v1/listen?model=nova-2"
        if !language.isEmpty {
            urlString += "&language=\(language)"
        }

        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = audioData
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PikoVoiceError.sttFailed(detail: "Invalid response")
        }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PikoVoiceError.sttFailed(detail: "HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        // Deepgram response: results.channels[0].alternatives[0].transcript
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let channels = results["channels"] as? [[String: Any]],
              let firstChannel = channels.first,
              let alternatives = firstChannel["alternatives"] as? [[String: Any]],
              let firstAlt = alternatives.first,
              let transcript = firstAlt["transcript"] as? String
        else {
            throw PikoVoiceError.sttFailed(detail: "Unexpected Deepgram response format")
        }

        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Multipart Helpers

private extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
}
