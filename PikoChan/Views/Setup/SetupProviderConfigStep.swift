import SwiftUI

/// Provider-specific configuration + validation.
struct SetupProviderConfigStep: View {
    @Bindable var setup: SetupManager

    var body: some View {
        VStack(spacing: 14) {
            providerContent

            Spacer()

            SetupNavButtons(
                canGoBack: true,
                canGoNext: setup.providerReady,
                onBack: { setup.goBack() },
                onNext: { setup.advance() }
            )

            StepDotsView(currentStep: setup.currentStep)
                .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var providerContent: some View {
        switch setup.selectedProvider {
        case .local:
            ollamaContent
        case .openai:
            apiKeyContent(provider: "OpenAI")
        case .anthropic:
            apiKeyContent(provider: "Anthropic")
        case .apple:
            appleContent
        case .openrouter:
            apiKeyContent(provider: "OpenRouter")
        case .groq:
            apiKeyContent(provider: "Groq")
        case .huggingface:
            apiKeyContent(provider: "HuggingFace")
        case .dockerModelRunner:
            localEndpointContent(provider: "Docker Model Runner", defaultEndpoint: "http://localhost:12434")
        case .vllm:
            localEndpointContent(provider: "vLLM", defaultEndpoint: "http://localhost:8000")
        }
    }

    // MARK: - Ollama

    @ViewBuilder
    private var ollamaContent: some View {
        Text("Checking Ollama...")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))

        validationStatus

        if !setup.ollamaModels.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Select model:")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(setup.ollamaModels, id: \.self) { model in
                            ProviderPill(
                                label: model,
                                icon: "cube",
                                isSelected: setup.localModel == model
                            ) {
                                setup.localModel = model
                            }
                        }
                    }
                }
            }
        }

        if case .failure = setup.providerValidation {
            SetupActionButton("Retry", icon: "arrow.clockwise") {
                Task { await setup.validateProvider() }
            }
        }
    }

    // MARK: - API Key

    @ViewBuilder
    private func apiKeyContent(provider: String) -> some View {
        Text("Enter your \(provider) API key")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))

        SetupTextField(placeholder: "sk-...", text: $setup.apiKey, isSecure: true) {
            guard !setup.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            Task { await setup.validateProvider() }
        }
        .padding(.horizontal, 4)

        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 8))
            Text("Stored securely in macOS Keychain")
                .font(.system(size: 10))
        }
        .foregroundStyle(.white.opacity(0.35))

        validationStatus

        if setup.providerValidation != .testing {
            SetupActionButton("Test Connection", icon: "bolt") {
                Task { await setup.validateProvider() }
            }
            .disabled(setup.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(setup.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
        }
    }

    // MARK: - Apple

    @ViewBuilder
    private var appleContent: some View {
        Text("Checking Apple Intelligence...")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))

        validationStatus

        if case .failure = setup.providerValidation {
            Text("Requires macOS 26+ with Apple Intelligence enabled")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Local Endpoint

    @ViewBuilder
    private func localEndpointContent(provider: String, defaultEndpoint: String) -> some View {
        Text("Checking \(provider)...")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))

        VStack(alignment: .leading, spacing: 4) {
            Text("Endpoint (default: \(defaultEndpoint))")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
            SetupTextField(placeholder: defaultEndpoint, text: $setup.customEndpoint, isSecure: false) {
                Task { await setup.validateProvider() }
            }
            .padding(.horizontal, 4)
        }

        validationStatus

        if setup.providerValidation != .testing {
            SetupActionButton("Test Connection", icon: "bolt") {
                Task { await setup.validateProvider() }
            }
        }
    }

    // MARK: - Validation Status

    @ViewBuilder
    private var validationStatus: some View {
        switch setup.providerValidation {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Text("Testing...")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
        case .success:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green.opacity(0.8))
                Text("Connected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green.opacity(0.8))
            }
        case .failure(let message):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red.opacity(0.8))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.7))
                    .lineLimit(2)
            }
        }
    }
}

