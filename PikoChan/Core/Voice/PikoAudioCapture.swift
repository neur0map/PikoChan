import AVFoundation

@MainActor
final class PikoAudioCapture {

    var hasPermission: Bool = false
    /// 0.0–1.0, driven by mic RMS. Read from WaveView.
    var audioLevel: Float = 0

    private var audioEngine: AVAudioEngine?
    private var sampleBuffer: [Float] = []
    private let sampleRate: Double = 16_000
    private let lock = NSLock()

    enum PermissionStatus { case notDetermined, granted, denied }

    var currentPermissionStatus: PermissionStatus {
        if #available(macOS 14.0, *) {
            return switch AVAudioApplication.shared.recordPermission {
            case .granted:       .granted
            case .denied:        .denied
            case .undetermined:  .notDetermined
            @unknown default:    .notDetermined
            }
        } else {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            return switch status {
            case .authorized:    .granted
            case .denied,
                 .restricted:    .denied
            case .notDetermined: .notDetermined
            @unknown default:    .notDetermined
            }
        }
    }

    func requestPermission() async -> Bool {
        if #available(macOS 14.0, *) {
            let granted = await AVAudioApplication.requestRecordPermission()
            hasPermission = granted
            return granted
        } else {
            let granted = await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    cont.resume(returning: granted)
                }
            }
            hasPermission = granted
            return granted
        }
    }

    func startCapture() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            throw PikoVoiceError.noAudioInput
        }

        // Target: 16kHz mono Float32.
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw PikoVoiceError.noAudioInput
        }

        // Converter from hardware format to 16kHz mono.
        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            throw PikoVoiceError.noAudioInput
        }

        lock.lock()
        sampleBuffer.removeAll()
        lock.unlock()
        audioLevel = 0

        let bufferSize: AVAudioFrameCount = 4096
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: hwFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Convert to 16kHz mono.
            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * (self.sampleRate / hwFormat.sampleRate)
            )
            guard frameCapacity > 0,
                  let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity)
            else { return }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard error == nil,
                  let channelData = convertedBuffer.floatChannelData?[0]
            else { return }

            let frameCount = Int(convertedBuffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

            // Compute RMS for level meter.
            var rms: Float = 0
            for s in samples { rms += s * s }
            rms = sqrt(rms / max(Float(frameCount), 1))
            let level = min(rms * 5, 1.0) // amplify for visual feedback

            self.lock.lock()
            self.sampleBuffer.append(contentsOf: samples)
            self.lock.unlock()

            Task { @MainActor in
                self.audioLevel = level
            }
        }

        try engine.start()
        self.audioEngine = engine
    }

    /// Stops capture and returns WAV-encoded audio data, or nil if no samples.
    func stopCapture() -> Data? {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioLevel = 0

        lock.lock()
        let samples = sampleBuffer
        sampleBuffer.removeAll()
        lock.unlock()

        guard !samples.isEmpty else { return nil }
        return encodeWAV(samples: samples, sampleRate: UInt32(sampleRate))
    }

    // MARK: - WAV Encoding

    private func encodeWAV(samples: [Float], sampleRate: UInt32) -> Data {
        // Convert Float32 → Int16 PCM.
        var pcm = Data(capacity: samples.count * 2)
        for s in samples {
            let clamped = max(-1.0, min(1.0, s))
            var int16 = Int16(clamped * 32767)
            pcm.append(Data(bytes: &int16, count: 2))
        }

        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcm.count)
        let chunkSize = 36 + dataSize

        var wav = Data()
        wav.append(contentsOf: "RIFF".utf8)
        wav.appendLE(chunkSize)
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        wav.appendLE(UInt32(16))              // subchunk1 size
        wav.appendLE(UInt16(1))               // PCM format
        wav.appendLE(channels)
        wav.appendLE(sampleRate)
        wav.appendLE(byteRate)
        wav.appendLE(blockAlign)
        wav.appendLE(bitsPerSample)
        wav.append(contentsOf: "data".utf8)
        wav.appendLE(dataSize)
        wav.append(pcm)

        return wav
    }
}

// MARK: - Data helpers

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 2))
    }
    mutating func appendLE(_ value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 4))
    }
}

enum PikoVoiceError: LocalizedError {
    case noAudioInput
    case noAPIKey(provider: String)
    case sttFailed(detail: String)
    case ttsFailed(detail: String)

    var errorDescription: String? {
        switch self {
        case .noAudioInput:
            "No audio input device found"
        case .noAPIKey(let provider):
            "No API key configured for \(provider)"
        case .sttFailed(let detail):
            "Speech-to-text failed: \(detail)"
        case .ttsFailed(let detail):
            "Text-to-speech failed: \(detail)"
        }
    }
}
