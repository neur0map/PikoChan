import SwiftUI
import AVFoundation

struct VoiceTab: View {
    @Bindable private var config = PikoVoiceConfigStore.shared
    @State private var testStatus: String?
    @State private var showTTSKeyOverride = false
    @State private var showSTTKeyOverride = false
    @State private var falSchema: FalAISchema.ModelSchema?
    @State private var falSchemaLoading = false

    // Local TTS state.
    @State private var localModels: [PikoVoiceServer.InstalledModel] = []
    @State private var hasPython = false
    @State private var hasHuggingfaceCLI = false
    @State private var hasPythonDeps = false
    @State private var hasSox = false
    @State private var localDependenciesChecked = false

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
            if config.ttsProvider == .local {
                checkLocalDependencies()
                scanInstalledModels()
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

            if config.ttsProvider == .local {
                localTTSSection
            } else if config.ttsProvider != .none {
                cloudTTSSection
            }
        }
    }

    // MARK: - Cloud TTS Section

    private var cloudTTSSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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

    // MARK: - Local TTS Section

    private var localTTSSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Dependency warnings.
            if localDependenciesChecked {
                if !hasPython {
                    warningBanner(
                        icon: "xmark.octagon.fill",
                        color: .red,
                        title: "python3 not found",
                        message: "Install Python 3 to use local TTS.",
                        command: "brew install python3"
                    )
                }

                if hasPython && !hasHuggingfaceCLI {
                    warningBanner(
                        icon: "exclamationmark.triangle.fill",
                        color: .orange,
                        title: "Hugging Face CLI not found",
                        message: "Needed to download models. Install via pipx (recommended).",
                        command: "brew install pipx && pipx install huggingface_hub"
                    )
                }

                if hasPython && !hasPythonDeps {
                    warningBanner(
                        icon: "exclamationmark.triangle.fill",
                        color: .orange,
                        title: "Missing Python packages",
                        message: "Run this to create a venv and install dependencies:",
                        command: "python3 -m venv ~/.pikochan/voice/venv && ~/.pikochan/voice/venv/bin/pip install qwen-tts fastapi uvicorn soundfile"
                    )
                }

                if hasPython && !hasSox {
                    warningBanner(
                        icon: "exclamationmark.triangle.fill",
                        color: .orange,
                        title: "SoX not found",
                        message: "Required for audio processing by Qwen3-TTS.",
                        command: "brew install sox"
                    )
                }

                if localModels.isEmpty {
                    warningBanner(
                        icon: "exclamationmark.triangle.fill",
                        color: .orange,
                        title: "No models downloaded",
                        message: "Download a model to get started.",
                        command: "hf download Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice --local-dir ~/.pikochan/voice/models/Qwen3-TTS-12Hz-0.6B-CustomVoice"
                    )
                }
            }

            // Server status + controls.
            let server = PikoVoiceServer.shared
            HStack(spacing: 8) {
                Circle()
                    .fill(serverStatusColor(server.status))
                    .frame(width: 8, height: 8)
                Text(server.status.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                switch server.status {
                case .stopped, .errored:
                    Button("Start") {
                        server.start(modelPath: config.localModelPath)
                    }
                    .disabled(config.localModelPath.isEmpty)
                case .starting:
                    ProgressView()
                        .controlSize(.small)
                case .running:
                    Button("Stop") { server.stop() }
                    Button("Restart") {
                        server.restart(modelPath: config.localModelPath)
                    }
                }
            }

            // Installed models list.
            if !localModels.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Models")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(localModels) { model in
                        HStack {
                            Image(systemName: config.localModelPath == model.path
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(config.localModelPath == model.path ? .blue : .secondary)
                                .font(.caption)
                            Text(model.name)
                                .font(.caption)
                            Spacer()
                            Text(model.sizeLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            config.localModelPath = model.path
                            try? config.save()
                        }
                    }
                }
            }

            Button("Scan for Models") {
                scanInstalledModels()
            }
            .font(.caption)

            // Auto-speak toggle.
            Toggle("Speak responses aloud", isOn: $config.autoSpeak)
                .onChange(of: config.autoSpeak) { _, _ in
                    try? config.save()
                }

            // Voice picker — from server when running, text field when stopped.
            if server.status == .running && !server.availableVoices.isEmpty {
                Picker("Voice", selection: $config.ttsVoiceId) {
                    ForEach(server.availableVoices, id: \.self) { voice in
                        Text(voice).tag(voice)
                    }
                }
                .pickerStyle(.menu)
                .onAppear {
                    // Fix stale voice selection that doesn't match available voices.
                    if !server.availableVoices.contains(config.ttsVoiceId) {
                        config.ttsVoiceId = server.availableVoices[0]
                        try? config.save()
                    }
                }
                .onChange(of: server.availableVoices) { _, voices in
                    if !voices.isEmpty && !voices.contains(config.ttsVoiceId) {
                        config.ttsVoiceId = voices[0]
                        try? config.save()
                    }
                }
            } else {
                LabeledContent("Voice") {
                    TextField("e.g. Chelsie", text: $config.ttsVoiceId)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }
            }

            // Language picker.
            Picker("Language", selection: $config.localLanguage) {
                ForEach(Self.languages, id: \.code) { lang in
                    Text(lang.label).tag(lang.code)
                }
            }
            .pickerStyle(.menu)

            // Speed slider.
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

            // Mood mapping.
            VStack(alignment: .leading, spacing: 4) {
                Text("Emotion Tags")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Mode", selection: $config.localMoodMode) {
                    Text("Auto").tag("auto")
                    Text("Custom").tag("custom")
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                if config.localMoodMode == "custom" {
                    LabeledContent("Custom Prompt") {
                        TextField("Extra emotion instructions", text: Binding(
                            get: { config.ttsModel },
                            set: { config.ttsModel = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                    }
                    .font(.caption)
                }
            }

            // Test button.
            HStack(spacing: 12) {
                Button("Test TTS") {
                    testTTS()
                }
                .disabled(server.status != .running)

                if let status = testStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(status.contains("Error") ? .red : .green)
                }
            }
        }
    }

    // MARK: - Warning Banner

    private func warningBanner(icon: String, color: Color, title: String, message: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 4) {
                Text(command)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .help("Copy to clipboard")
            }
        }
        .padding(8)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    private func serverStatusColor(_ status: PikoVoiceServer.Status) -> Color {
        switch status {
        case .stopped:  .gray
        case .starting: .yellow
        case .running:  .green
        case .errored:  .red
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

            if config.sttProvider == .apple {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("On-device streaming — no API key needed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Language", selection: $config.sttLanguage) {
                    ForEach(Self.languages, id: \.code) { lang in
                        Text(lang.label).tag(lang.code)
                    }
                }
                .pickerStyle(.menu)
            } else if config.sttProvider != .none {
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
                    if !voices.contains(where: { $0.id == config.ttsVoiceId }) {
                        Text(config.ttsVoiceId.isEmpty ? "—" : config.ttsVoiceId).tag(config.ttsVoiceId)
                    }
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
                if !models.contains(where: { $0.id == config.ttsModel }) {
                    Text(config.ttsModel.isEmpty ? "—" : config.ttsModel).tag(config.ttsModel)
                }
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
                // Fallback tag prevents "invalid selection" warning during provider transitions.
                if !models.contains(where: { $0.id == config.sttModel }) {
                    Text(config.sttModel.isEmpty ? "—" : config.sttModel).tag(config.sttModel)
                }
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
        config.ttsProvider == .local || PikoVoiceConfigStore.shared.currentConfig.ttsAPIKey != nil
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
        case .local:
            config.ttsVoiceId = "Vivian"
            config.ttsModel = ""
            checkLocalDependencies()
            scanInstalledModels()
        case .none:
            break
        }
    }

    private func applySTTDefaults(for provider: PikoVoiceConfig.STTProvider) {
        switch provider {
        case .groq:     config.sttModel = "whisper-large-v3-turbo"
        case .openai:   config.sttModel = "whisper-1"
        case .deepgram: config.sttModel = "nova-2"
        case .apple:    break
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
        case .local:      "Local (Qwen3-TTS)"
        }
    }

    private func sttProviderLabel(_ provider: PikoVoiceConfig.STTProvider) -> String {
        switch provider {
        case .none:     "None"
        case .apple:    "Apple (On-Device)"
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

                // Write to temp file with correct extension — AVAudioPlayer
                // is more reliable from file (especially for WAV on macOS).
                let header = [UInt8](audioData.prefix(4))
                let ext: String
                if header[0] == 0x52, header[1] == 0x49, header[2] == 0x46, header[3] == 0x46 {
                    ext = "wav"
                } else {
                    ext = "mp3"
                }
                let tmpFile = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".\(ext)")
                try audioData.write(to: tmpFile)

                let player = try AVAudioPlayer(contentsOf: tmpFile)
                player.prepareToPlay()
                player.play()
                testStatus = "Playing (\(audioData.count / 1024) KB)"
                // Clean up after playback finishes.
                Task {
                    while player.isPlaying {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    try? FileManager.default.removeItem(at: tmpFile)
                }
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

    // MARK: - Local TTS Helpers

    private func checkLocalDependencies() {
        Task.detached {
            let python = PikoVoiceServer.pythonAvailable()
            let hfcli = PikoVoiceServer.huggingfaceCLIAvailable()
            let pyDeps = python ? PikoVoiceServer.pythonDepsAvailable() : false
            let sox = PikoVoiceServer.soxAvailable()
            await MainActor.run {
                self.hasPython = python
                self.hasHuggingfaceCLI = hfcli
                self.hasPythonDeps = pyDeps
                self.hasSox = sox
                self.localDependenciesChecked = true
            }
        }
    }

    private func scanInstalledModels() {
        Task.detached {
            let models = PikoVoiceServer.installedModels()
            await MainActor.run {
                self.localModels = models
                // Auto-select first model if none selected.
                if self.config.localModelPath.isEmpty, let first = models.first {
                    self.config.localModelPath = first.path
                    try? self.config.save()
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
