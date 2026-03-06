import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Settings tab for AI model configuration.
struct AIModelTab: View {
    @Bindable private var config = PikoConfigStore.shared
    @State private var status = ""
    @State private var statusColor: Color = .secondary
    @State private var validationError = ""
    @State private var isTesting = false

    var body: some View {
        Form {
            Section {
                Picker("Provider:", selection: $config.provider) {
                    Text("Local").tag(PikoConfig.Provider.local)
                    Text("OpenAI").tag(PikoConfig.Provider.openai)
                    Text("Anthropic").tag(PikoConfig.Provider.anthropic)
                    Text("Apple").tag(PikoConfig.Provider.apple)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(providerFooter)
                    .foregroundStyle(.secondary)
            }

            // Show fields for the active provider only.
            switch config.provider {
            case .local:
                localSection
                fallbackSection
            case .openai:
                openAISection
            case .anthropic:
                anthropicSection
            case .apple:
                appleSection
            }

            Section {
                HStack {
                    Button("Save") { save() }
                    Button("Reload") {
                        config.reload()
                        showStatus("Reloaded", color: .secondary)
                    }
                    Button("Test Connection") { testConnection() }
                        .disabled(isTesting)
                    Spacer()
                    if !status.isEmpty {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(statusColor)
                    }
                }

                if !validationError.isEmpty {
                    Text(validationError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear { config.reload() }
    }

    // MARK: - Provider Sections

    private var localSection: some View {
        Section {
            TextField("Model name:", text: $config.localModel)
            TextField("Endpoint:", text: $config.localEndpoint)
        } header: {
            Text("Local LLM")
        } footer: {
            Text("Connects to Ollama or any OpenAI-compatible local server.")
                .foregroundStyle(.secondary)
        }
    }

    private var fallbackSection: some View {
        Section {
            Picker("Cloud fallback:", selection: $config.cloudFallback) {
                Text("None").tag(PikoConfig.CloudFallback.none)
                Text("OpenAI").tag(PikoConfig.CloudFallback.openai)
                Text("Anthropic").tag(PikoConfig.CloudFallback.anthropic)
            }
            .pickerStyle(.segmented)

            if config.cloudFallback == .openai {
                TextField("OpenAI model:", text: $config.openAIModel)
                SecureField("OpenAI API key:", text: $config.openAIAPIKey)
            }
            if config.cloudFallback == .anthropic {
                TextField("Anthropic model:", text: $config.anthropicModel)
                SecureField("Anthropic API key:", text: $config.anthropicAPIKey)
            }
        } header: {
            Text("Fallback")
        } footer: {
            Text("Used when the local server is unreachable.")
                .foregroundStyle(.secondary)
        }
    }

    private var openAISection: some View {
        Section {
            TextField("Model:", text: $config.openAIModel)
            SecureField("API key:", text: $config.openAIAPIKey)
        } header: {
            Text("OpenAI")
        } footer: {
            Text("Get your key at platform.openai.com.")
                .foregroundStyle(.secondary)
        }
    }

    private var anthropicSection: some View {
        Section {
            TextField("Model:", text: $config.anthropicModel)
            SecureField("API key:", text: $config.anthropicAPIKey)
        } header: {
            Text("Anthropic")
        } footer: {
            Text("Get your key at console.anthropic.com.")
                .foregroundStyle(.secondary)
        }
    }

    private var appleSection: some View {
        Section {
            HStack {
                Text("Status:")
                Spacer()
                Text(appleIntelligenceStatus)
                    .foregroundStyle(appleIntelligenceAvailable ? .green : .secondary)
            }
        } header: {
            Text("Apple Intelligence")
        } footer: {
            Text("On-device model via Apple Intelligence. No data leaves your Mac. No API key needed.")
                .foregroundStyle(.secondary)
        }
    }

    private var appleIntelligenceAvailable: Bool {
#if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
#endif
        return false
    }

    private var appleIntelligenceStatus: String {
        appleIntelligenceAvailable ? "Available" : "Not available"
    }

    // MARK: - Helpers

    private var providerFooter: String {
        switch config.provider {
        case .local:    "Runs on your machine via Ollama. No data leaves your Mac."
        case .openai:   "Routes all requests through OpenAI's API."
        case .anthropic: "Routes all requests through Anthropic's API."
        case .apple:    "On-device Apple Intelligence. No data leaves your Mac."
        }
    }

    // MARK: - Validation

    private func validate() -> Bool {
        validationError = ""

        switch config.provider {
        case .local:
            if URL(string: config.localEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)) == nil {
                validationError = "Invalid endpoint URL"
                return false
            }
            // Validate fallback keys if fallback is set.
            if config.cloudFallback == .openai && config.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationError = "OpenAI API key required for fallback"
                return false
            }
            if config.cloudFallback == .anthropic && config.anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationError = "Anthropic API key required for fallback"
                return false
            }
        case .openai:
            if config.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationError = "API key required"
                return false
            }
        case .anthropic:
            if config.anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationError = "API key required"
                return false
            }
        case .apple:
            if !appleIntelligenceAvailable {
                validationError = "Apple Intelligence is not available on this system"
                return false
            }
        }
        return true
    }

    private func save() {
        guard validate() else { return }
        do {
            try config.save()
            showStatus("Saved", color: .green)
        } catch {
            showStatus("Error: \(error.localizedDescription)", color: .red)
        }
    }

    private func testConnection() {
        guard validate() else { return }
        isTesting = true
        showStatus("Testing...", color: .secondary)

        Task {
            do {
                let ok = try await performTestConnection()
                if ok {
                    showStatus("Connected", color: .green)
                } else {
                    showStatus("No response", color: .red)
                }
            } catch {
                showStatus("Failed: \(error.localizedDescription)", color: .red)
            }
            isTesting = false
        }
    }

    private func performTestConnection() async throws -> Bool {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: sessionConfig)

        switch config.provider {
        case .local:
            let endpoint = config.localEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200

        case .openai:
            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.addValue("Bearer \(config.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200

        case .anthropic:
            // Anthropic doesn't have a lightweight list endpoint; send minimal message.
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue(config.anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "x-api-key")
            request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let body: [String: Any] = [
                "model": config.anthropicModel,
                "max_tokens": 1,
                "messages": [["role": "user", "content": "hi"]],
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (200..<300).contains(code)

        case .apple:
            return appleIntelligenceAvailable
        }
    }

    private func showStatus(_ text: String, color: Color) {
        status = text
        statusColor = color
        if text != "Testing..." {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if status == text { status = "" }
            }
        }
    }
}
