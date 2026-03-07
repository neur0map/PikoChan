import SwiftUI
import AVFoundation

struct VoiceTab: View {
    @Bindable private var config = PikoVoiceConfigStore.shared
    @State private var testStatus: String?
    @State private var showTTSKeyOverride = false
    @State private var showSTTKeyOverride = false
    @State private var falSchema: FalAISchema.ModelSchema?
    @State private var falSchemaLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ttsSection
                Divider()
                sttSection
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if config.ttsProvider == .falai && !config.ttsModel.isEmpty {
                fetchFalSchema()
            }
        }
        .onDisappear {
            try? config.save()
        }
    }

    // MARK: - TTS Section

    private var ttsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Text-to-Speech")
                .font(.headline)

            // Use custom binding so model/voice defaults are set atomically with provider.
            Picker("Provider", selection: ttsProviderBinding) {
                ForEach(PikoVoiceConfig.TTSProvider.allCases, id: \.self) { provider in
                    Text(ttsProviderLabel(provider)).tag(provider)
                }
            }
            .pickerStyle(.menu)

            if config.ttsProvider != .none {
                // Auto-speak toggle — prominent, right after provider.
                Toggle("Speak responses aloud", isOn: $config.autoSpeak)
                    .onChange(of: config.autoSpeak) { _, _ in
                        try? config.save()
                    }

                // For fal.ai: model first (determines voices), then voice.
                ttsModelPicker
                ttsVoicePicker

                if falSchema?.hasSpeed != false || config.ttsProvider != .falai {
                    LabeledContent("Speed") {
                        HStack {
                            Slider(value: $config.ttsSpeed, in: 0.5...2.0, step: 0.1)
                                .frame(width: 140)
                            Text(String(format: "%.1fx", config.ttsSpeed))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }

                ttsKeySection

                HStack(spacing: 12) {
                    Button("Test TTS") {
                        testTTS()
                    }
                    .disabled(!hasTTSKey)

                    if let status = testStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(status.contains("Error") ? .red : .green)
                    }
                }
            }
        }
    }

    // MARK: - STT Section

    private var sttSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Speech-to-Text")
                .font(.headline)

            Picker("Provider", selection: sttProviderBinding) {
                ForEach(PikoVoiceConfig.STTProvider.allCases, id: \.self) { provider in
                    Text(sttProviderLabel(provider)).tag(provider)
                }
            }
            .pickerStyle(.menu)

            if config.sttProvider != .none {
                sttModelPicker

                Picker("Language", selection: $config.sttLanguage) {
                    ForEach(Self.languages, id: \.code) { lang in
                        Text(lang.label).tag(lang.code)
                    }
                }
                .pickerStyle(.menu)

                sttKeySection
            }
        }
    }

    // MARK: - Custom Provider Bindings (fix picker warnings)

    /// Sets defaults atomically with provider change — no stale model/voice for one render cycle.
    private var ttsProviderBinding: Binding<PikoVoiceConfig.TTSProvider> {
        Binding(
            get: { config.ttsProvider },
            set: { newValue in
                showTTSKeyOverride = false
                config.ttsAPIKey = ""
                applyTTSDefaults(for: newValue)
                config.ttsProvider = newValue
                try? config.save()
            }
        )
    }

    private var sttProviderBinding: Binding<PikoVoiceConfig.STTProvider> {
        Binding(
            get: { config.sttProvider },
            set: { newValue in
                showSTTKeyOverride = false
                config.sttAPIKey = ""
                applySTTDefaults(for: newValue)
                config.sttProvider = newValue
                try? config.save()
            }
        )
    }

    // MARK: - TTS Voice Picker

    @ViewBuilder
    private var ttsVoicePicker: some View {
        // For fal.ai, use dynamically fetched voices from the model schema.
        if config.ttsProvider == .falai {
            if let schema = falSchema, !schema.voices.isEmpty {
                Picker("Voice", selection: $config.ttsVoiceId) {
                    ForEach(schema.voices, id: \.self) { voice in
                        Text(voice).tag(voice)
                    }
                }
                .pickerStyle(.menu)
            } else if falSchemaLoading {
                LabeledContent("Voice") {
                    ProgressView()
                        .controlSize(.small)
                }
            } else {
                LabeledContent("Voice ID") {
                    TextField("Paste voice ID", text: $config.ttsVoiceId)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
            }
        } else {
            let voices = Self.ttsVoices[config.ttsProvider] ?? []
            if voices.isEmpty {
                LabeledContent("Voice ID") {
                    TextField("Paste voice ID", text: $config.ttsVoiceId)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
            } else {
                Picker("Voice", selection: $config.ttsVoiceId) {
                    ForEach(voices, id: \.id) { voice in
                        Text(voice.label).tag(voice.id)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    // MARK: - TTS Model Picker

    @ViewBuilder
    private var ttsModelPicker: some View {
        let models = Self.ttsModels[config.ttsProvider] ?? []
        if !models.isEmpty {
            Picker("Model", selection: $config.ttsModel) {
                ForEach(models, id: \.id) { model in
                    Text(model.label).tag(model.id)
                }
            }
            .pickerStyle(.menu)
        } else if Self.ttsModelTextField.contains(config.ttsProvider) {
            LabeledContent("Model ID") {
                TextField("e.g. fal-ai/kokoro/american-english", text: $config.ttsModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .onSubmit { fetchFalSchema() }
            }
            if config.ttsProvider == .falai {
                Button("Load Model") { fetchFalSchema() }
                    .font(.caption)
                    .disabled(config.ttsModel.trimmingCharacters(in: .whitespaces).isEmpty || falSchemaLoading)
            }
        }
    }

    // MARK: - STT Model Picker

    @ViewBuilder
    private var sttModelPicker: some View {
        let models = Self.sttModels[config.sttProvider] ?? []
        if !models.isEmpty {
            Picker("Model", selection: $config.sttModel) {
                ForEach(models, id: \.id) { model in
                    Text(model.label).tag(model.id)
                }
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: - TTS Key Section

    @ViewBuilder
    private var ttsKeySection: some View {
        let shared = sharedTTSKeyAccount
        if let shared {
            let hasKey = PikoKeychain.load(account: shared.account) != nil
            if hasKey && !showTTSKeyOverride {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("Using \(shared.label) key from AI Model")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Use different key") {
                        showTTSKeyOverride = true
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
            } else if hasKey && showTTSKeyOverride {
                LabeledContent("Override Key") {
                    SecureField("Leave empty to use AI Model key", text: $config.ttsAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
                Button("Use AI Model key instead") {
                    config.ttsAPIKey = ""
                    showTTSKeyOverride = false
                }
                .font(.caption)
                .buttonStyle(.link)
            } else {
                Text("No \(shared.label) key found — add one in Settings → AI Model")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } else {
            LabeledContent("API Key") {
                SecureField("Enter API key", text: $config.ttsAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }
        }
    }

    // MARK: - STT Key Section

    @ViewBuilder
    private var sttKeySection: some View {
        let shared = sharedSTTKeyAccount
        if let shared {
            let hasKey = PikoKeychain.load(account: shared.account) != nil
            if hasKey && !showSTTKeyOverride {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("Using \(shared.label) key from AI Model")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Use different key") {
                        showSTTKeyOverride = true
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
            } else if hasKey && showSTTKeyOverride {
                LabeledContent("Override Key") {
                    SecureField("Leave empty to use AI Model key", text: $config.sttAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
                Button("Use AI Model key instead") {
                    config.sttAPIKey = ""
                    showSTTKeyOverride = false
                }
                .font(.caption)
                .buttonStyle(.link)
            } else {
                Text("No \(shared.label) key found — add one in Settings → AI Model")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } else {
            LabeledContent("API Key") {
                SecureField("Enter API key", text: $config.sttAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }
        }
    }

    // MARK: - Shared Key Detection

    private var sharedTTSKeyAccount: (account: String, label: String)? {
        switch config.ttsProvider {
        case .openai: ("openai_api_key", "OpenAI")
        default:      nil
        }
    }

    private var sharedSTTKeyAccount: (account: String, label: String)? {
        switch config.sttProvider {
        case .groq:   ("groq_api_key", "Groq")
        case .openai: ("openai_api_key", "OpenAI")
        default:      nil
        }
    }

    private var hasTTSKey: Bool {
        PikoVoiceConfigStore.shared.currentConfig.ttsAPIKey != nil
    }

    // MARK: - Provider Defaults

    private func applyTTSDefaults(for provider: PikoVoiceConfig.TTSProvider) {
        switch provider {
        case .openai:
            config.ttsModel = "tts-1"
            config.ttsVoiceId = "alloy"
        case .elevenlabs:
            config.ttsModel = "eleven_turbo_v2_5"
            config.ttsVoiceId = ""
        case .fishaudio:
            config.ttsModel = ""
            config.ttsVoiceId = ""
        case .cartesia:
            config.ttsModel = "sonic-2"
            config.ttsVoiceId = ""
        case .falai:
            config.ttsModel = "fal-ai/qwen-3-tts/text-to-speech/1.7b"
            config.ttsVoiceId = "Vivian"
            fetchFalSchema()
        case .none:
            break
        }
    }

    private func applySTTDefaults(for provider: PikoVoiceConfig.STTProvider) {
        switch provider {
        case .groq:     config.sttModel = "whisper-large-v3-turbo"
        case .openai:   config.sttModel = "whisper-1"
        case .deepgram: config.sttModel = "nova-2"
        case .none:     break
        }
    }

    // MARK: - Labels

    private func ttsProviderLabel(_ provider: PikoVoiceConfig.TTSProvider) -> String {
        switch provider {
        case .none:       "None"
        case .openai:     "OpenAI"
        case .elevenlabs: "ElevenLabs"
        case .fishaudio:  "Fish Audio"
        case .cartesia:   "Cartesia"
        case .falai:      "fal.ai"
        }
    }

    private func sttProviderLabel(_ provider: PikoVoiceConfig.STTProvider) -> String {
        switch provider {
        case .none:     "None"
        case .groq:     "Groq (Whisper)"
        case .openai:   "OpenAI (Whisper)"
        case .deepgram: "Deepgram (Nova-2)"
        }
    }

    // MARK: - Test

    private func testTTS() {
        testStatus = nil
        try? config.save()

        Task {
            do {
                let voiceConfig = PikoVoiceConfigStore.shared.currentConfig
                let tts = PikoTTS()
                let audioData = try await tts.synthesize(text: "Hello! I'm PikoChan.", config: voiceConfig)

                let player = try AVAudioPlayer(data: audioData)
                player.play()
                testStatus = "Playing (\(audioData.count / 1024) KB)"
            } catch {
                testStatus = "Error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - fal.ai Schema

    private func fetchFalSchema() {
        let modelId = config.ttsModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelId.isEmpty else { return }
        falSchemaLoading = true
        falSchema = nil

        Task {
            let schema = await FalAISchema.shared.fetchAndCache(modelId: modelId)
            falSchema = schema
            falSchemaLoading = false

            // Set default voice from schema if current voice is empty or invalid.
            if let schema {
                if !schema.voices.isEmpty {
                    if config.ttsVoiceId.isEmpty || !schema.voices.contains(config.ttsVoiceId) {
                        config.ttsVoiceId = schema.defaultVoice ?? schema.voices[0]
                    }
                }
            }
        }
    }

    // MARK: - Voice / Model Catalogs

    private struct VoiceOption: Identifiable {
        let id: String
        let label: String
    }

    private struct ModelOption: Identifiable {
        let id: String
        let label: String
    }

    private static let ttsVoices: [PikoVoiceConfig.TTSProvider: [VoiceOption]] = [
        .openai: [
            VoiceOption(id: "alloy",   label: "Alloy"),
            VoiceOption(id: "ash",     label: "Ash"),
            VoiceOption(id: "ballad",  label: "Ballad"),
            VoiceOption(id: "coral",   label: "Coral"),
            VoiceOption(id: "echo",    label: "Echo"),
            VoiceOption(id: "fable",   label: "Fable"),
            VoiceOption(id: "nova",    label: "Nova"),
            VoiceOption(id: "onyx",    label: "Onyx"),
            VoiceOption(id: "sage",    label: "Sage"),
            VoiceOption(id: "shimmer", label: "Shimmer"),
        ],
        .falai: [
            VoiceOption(id: "af_heart",   label: "Heart (Female)"),
            VoiceOption(id: "af_bella",   label: "Bella (Female)"),
            VoiceOption(id: "af_nicole",  label: "Nicole (Female)"),
            VoiceOption(id: "af_sarah",   label: "Sarah (Female)"),
            VoiceOption(id: "af_sky",     label: "Sky (Female)"),
            VoiceOption(id: "am_adam",    label: "Adam (Male)"),
            VoiceOption(id: "am_michael", label: "Michael (Male)"),
            VoiceOption(id: "bf_emma",    label: "Emma (British F)"),
            VoiceOption(id: "bm_george",  label: "George (British M)"),
            VoiceOption(id: "bm_lewis",   label: "Lewis (British M)"),
        ],
    ]

    private static let ttsModels: [PikoVoiceConfig.TTSProvider: [ModelOption]] = [
        .openai: [
            ModelOption(id: "tts-1",            label: "TTS-1 (Fast)"),
            ModelOption(id: "tts-1-hd",         label: "TTS-1 HD (Quality)"),
            ModelOption(id: "gpt-4o-mini-tts",  label: "GPT-4o Mini TTS"),
        ],
        .elevenlabs: [
            ModelOption(id: "eleven_turbo_v2_5",       label: "Turbo v2.5 (Fast)"),
            ModelOption(id: "eleven_flash_v2_5",       label: "Flash v2.5 (Fastest)"),
            ModelOption(id: "eleven_multilingual_v2",   label: "Multilingual v2 (Quality)"),
        ],
        .cartesia: [
            ModelOption(id: "sonic-2",     label: "Sonic 2"),
            ModelOption(id: "sonic-mini",  label: "Sonic Mini (Fast)"),
        ],
    ]

    /// Providers that accept a freeform model ID instead of a picker.
    private static let ttsModelTextField: Set<PikoVoiceConfig.TTSProvider> = [.falai, .fishaudio]

    private static let sttModels: [PikoVoiceConfig.STTProvider: [ModelOption]] = [
        .groq: [
            ModelOption(id: "whisper-large-v3-turbo",       label: "Whisper Large v3 Turbo (Fast)"),
            ModelOption(id: "whisper-large-v3",             label: "Whisper Large v3 (Quality)"),
            ModelOption(id: "distil-whisper-large-v3-en",   label: "Distil Whisper v3 EN (Fastest)"),
        ],
        .openai: [
            ModelOption(id: "whisper-1",               label: "Whisper-1"),
            ModelOption(id: "gpt-4o-transcribe",       label: "GPT-4o Transcribe"),
            ModelOption(id: "gpt-4o-mini-transcribe",  label: "GPT-4o Mini Transcribe"),
        ],
        .deepgram: [
            ModelOption(id: "nova-2",           label: "Nova-2 (General)"),
            ModelOption(id: "nova-2-meeting",   label: "Nova-2 Meeting"),
            ModelOption(id: "nova-2-phonecall", label: "Nova-2 Phone Call"),
        ],
    ]

    private struct LanguageOption: Identifiable {
        let code: String
        let label: String
        var id: String { code }
    }

    private static let languages: [LanguageOption] = [
        LanguageOption(code: "en", label: "English"),
        LanguageOption(code: "ja", label: "Japanese"),
        LanguageOption(code: "zh", label: "Chinese"),
        LanguageOption(code: "ko", label: "Korean"),
        LanguageOption(code: "es", label: "Spanish"),
        LanguageOption(code: "fr", label: "French"),
        LanguageOption(code: "de", label: "German"),
        LanguageOption(code: "pt", label: "Portuguese"),
        LanguageOption(code: "it", label: "Italian"),
        LanguageOption(code: "ru", label: "Russian"),
        LanguageOption(code: "ar", label: "Arabic"),
        LanguageOption(code: "hi", label: "Hindi"),
    ]
}
