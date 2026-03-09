import Speech

/// Streaming on-device STT using Apple's SFSpeechRecognizer.
/// Partial results update live via `onPartialResult` callback.
@MainActor
final class PikoAppleSTT {
    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private(set) var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

    /// Called on main thread with partial transcript as user speaks.
    var onPartialResult: ((String) -> Void)?

    /// Final transcript after recognition ends.
    private(set) var finalTranscript: String = ""

    private var isStreaming = false

    // MARK: - Authorization

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    static var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    // MARK: - Streaming

    /// Starts streaming recognition. Returns the audio buffer request
    /// that PikoAudioCapture should feed raw buffers into.
    func startStreaming(language: String = "en") -> SFSpeechAudioBufferRecognitionRequest? {
        guard !isStreaming else { return recognitionRequest }

        let locale = Locale(identifier: language)
        recognizer = SFSpeechRecognizer(locale: locale)

        guard let recognizer, recognizer.isAvailable else {
            PikoGateway.shared.logError(
                message: "SFSpeechRecognizer not available for locale \(language)",
                subsystem: .voice
            )
            return nil
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        // Prefer on-device if available (macOS 13+).
        if #available(macOS 13, *) {
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        }

        recognitionRequest = request
        finalTranscript = ""
        isStreaming = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    let text = result.bestTranscription.formattedString
                    self.finalTranscript = text
                    self.onPartialResult?(text)

                    if result.isFinal {
                        self.cleanUp()
                    }
                }

                if let error, self.isStreaming {
                    // Ignore cancellation errors (normal when we stop).
                    let nsError = error as NSError
                    if nsError.domain != "kAFAssistantErrorDomain" || nsError.code != 216 {
                        PikoGateway.shared.logError(
                            message: "Apple STT error: \(error.localizedDescription)",
                            subsystem: .voice
                        )
                    }
                    self.cleanUp()
                }
            }
        }

        PikoGateway.shared.logSTTStart(provider: "apple", audioBytes: 0)
        return request
    }

    /// Stops streaming and returns the final transcript.
    @discardableResult
    func stopStreaming() -> String {
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        cleanUp()

        PikoGateway.shared.logSTTEnd(
            provider: "apple",
            durationMs: 0,
            transcript: finalTranscript
        )
        return finalTranscript
    }

    private func cleanUp() {
        isStreaming = false
        recognitionRequest = nil
        recognitionTask = nil
    }
}
