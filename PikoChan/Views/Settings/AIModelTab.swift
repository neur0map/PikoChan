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
                    Text("Local (Ollama)").tag(PikoConfig.Provider.local)
                    Text("OpenAI").tag(PikoConfig.Provider.openai)
                    Text("Anthropic").tag(PikoConfig.Provider.anthropic)
                    Text("Apple Intelligence").tag(PikoConfig.Provider.apple)
                    Divider()
                    Text("OpenRouter").tag(PikoConfig.Provider.openrouter)
                    Text("Groq").tag(PikoConfig.Provider.groq)
                    Text("HuggingFace").tag(PikoConfig.Provider.huggingface)
                    Divider()
                    Text("Docker Model Runner").tag(PikoConfig.Provider.dockerModelRunner)
                    Text("vLLM").tag(PikoConfig.Provider.vllm)
                }
                .pickerStyle(.menu)
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
            case .openrouter:
                openRouterSection
            case .groq:
                groqSection
            case .huggingface:
                huggingFaceSection
            case .dockerModelRunner:
                dockerModelRunnerSection
            case .vllm:
                vllmSection
            }

            usageSection

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
                Text("OpenRouter").tag(PikoConfig.CloudFallback.openrouter)
                Text("Groq").tag(PikoConfig.CloudFallback.groq)
                Text("HuggingFace").tag(PikoConfig.CloudFallback.huggingface)
            }
            .pickerStyle(.menu)

            if config.cloudFallback == .openai {
                TextField("OpenAI model:", text: $config.openAIModel)
                SecureField("OpenAI API key:", text: $config.openAIAPIKey)
            }
            if config.cloudFallback == .anthropic {
                TextField("Anthropic model:", text: $config.anthropicModel)
                SecureField("Anthropic API key:", text: $config.anthropicAPIKey)
            }
            if config.cloudFallback == .openrouter {
                TextField("OpenRouter model:", text: $config.openRouterModel)
                SecureField("OpenRouter API key:", text: $config.openRouterAPIKey)
            }
            if config.cloudFallback == .groq {
                TextField("Groq model:", text: $config.groqModel)
                SecureField("Groq API key:", text: $config.groqAPIKey)
            }
            if config.cloudFallback == .huggingface {
                TextField("HuggingFace model:", text: $config.huggingFaceModel)
                SecureField("HuggingFace API key:", text: $config.huggingFaceAPIKey)
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

    private var openRouterSection: some View {
        Section {
            TextField("Model:", text: $config.openRouterModel)
            SecureField("API key:", text: $config.openRouterAPIKey)
        } header: {
            Text("OpenRouter")
        } footer: {
            Text("Access 200+ models. Get your key at openrouter.ai.")
                .foregroundStyle(.secondary)
        }
    }

    private var groqSection: some View {
        Section {
            TextField("Model:", text: $config.groqModel)
            SecureField("API key:", text: $config.groqAPIKey)
        } header: {
            Text("Groq")
        } footer: {
            Text("Ultra-fast inference. Get your key at console.groq.com.")
                .foregroundStyle(.secondary)
        }
    }

    private var huggingFaceSection: some View {
        Section {
            TextField("Model:", text: $config.huggingFaceModel)
            SecureField("API key:", text: $config.huggingFaceAPIKey)
        } header: {
            Text("HuggingFace")
        } footer: {
            Text("Serverless inference. Get your token at huggingface.co/settings/tokens.")
                .foregroundStyle(.secondary)
        }
    }

    private var dockerModelRunnerSection: some View {
        Section {
            TextField("Model:", text: $config.dockerModelRunnerModel)
            TextField("Endpoint:", text: $config.dockerModelRunnerEndpoint)
        } header: {
            Text("Docker Model Runner")
        } footer: {
            Text("Local inference via Docker Desktop. No API key needed.")
                .foregroundStyle(.secondary)
        }
    }

    private var vllmSection: some View {
        Section {
            TextField("Model:", text: $config.vllmModel)
            TextField("Endpoint:", text: $config.vllmEndpoint)
            SecureField("API key (optional):", text: $config.vllmAPIKey)
        } header: {
            Text("vLLM")
        } footer: {
            Text("High-throughput local inference server. API key is optional.")
                .foregroundStyle(.secondary)
        }
    }

    private var usageSection: some View {
        Section {
            let stats = PikoConfigStore.shared.provider == config.provider
                ? (PikoStore(path: PikoHome().memoryDBFile)?.usageSummary() ?? [])
                : []
            if stats.isEmpty {
                Text("No token usage recorded yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(stats.indices, id: \.self) { i in
                    let s = stats[i]
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.model)
                                .font(.footnote.monospaced())
                            Text(s.provider)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(s.promptTokens + s.completionTokens) tokens")
                                .font(.footnote.monospaced())
                            Text("in: \(s.promptTokens) / out: \(s.completionTokens)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Token Usage")
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
        case .local:              "Runs on your machine via Ollama. No data leaves your Mac."
        case .openai:             "Routes all requests through OpenAI's API."
        case .anthropic:          "Routes all requests through Anthropic's API."
        case .apple:              "On-device Apple Intelligence. No data leaves your Mac."
        case .openrouter:         "Routes through OpenRouter — access 200+ models with one key."
        case .groq:               "Ultra-fast cloud inference via Groq's LPU hardware."
        case .huggingface:        "Serverless inference via HuggingFace Inference API."
        case .dockerModelRunner:  "Local inference via Docker Desktop. No data leaves your Mac."
        case .vllm:               "High-throughput local inference via vLLM server."
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
            if config.cloudFallback == .openrouter && config.openRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationError = "OpenRouter API key required for fallback"
                return false
            }
            if config.cloudFallback == .groq && config.groqAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationError = "Groq API key required for fallback"
                return false
            }
            if config.cloudFallback == .huggingface && config.huggingFaceAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationError = "HuggingFace API key required for fallback"
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
        case .openrouter:
            if config.openRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationError = "API key required"
                return false
            }
        case .groq:
            if config.groqAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationError = "API key required"
                return false
            }
        case .huggingface:
            if config.huggingFaceAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationError = "API key required"
                return false
            }
        case .dockerModelRunner:
            if URL(string: config.dockerModelRunnerEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)) == nil {
                validationError = "Invalid endpoint URL"
                return false
            }
        case .vllm:
            if URL(string: config.vllmEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)) == nil {
                validationError = "Invalid endpoint URL"
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

        case .openrouter:
            var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
            request.addValue("Bearer \(config.openRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200

        case .groq:
            var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/models")!)
            request.addValue("Bearer \(config.groqAPIKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200

        case .huggingface:
            var request = URLRequest(url: URL(string: "https://router.huggingface.co/v1/chat/completions")!)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("Bearer \(config.huggingFaceAPIKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
            let body: [String: Any] = [
                "model": config.huggingFaceModel,
                "messages": [["role": "user", "content": "hi"]],
                "max_tokens": 1,
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (200..<300).contains(code)

        case .dockerModelRunner:
            let endpoint = config.dockerModelRunnerEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: endpoint)?.appendingPathComponent("engines/v1/models") else { throw URLError(.badURL) }
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200

        case .vllm:
            let endpoint = config.vllmEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: endpoint)?.appendingPathComponent("v1/models") else { throw URLError(.badURL) }
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
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
