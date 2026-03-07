import SwiftUI

/// Provider picker — 9 pill buttons.
struct SetupProviderStep: View {
    let setup: SetupManager

    private func selectProvider(_ provider: PikoConfig.Provider, needsKey: Bool = false) {
        setup.selectedProvider = provider
        if needsKey { setup.apiKey = "" }
        setup.customEndpoint = ""
        setup.providerValidation = .idle
        setup.providerReady = false
        setup.advance()
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose your AI provider")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    ProviderPill(
                        label: "Ollama",
                        icon: "desktopcomputer",
                        isSelected: setup.selectedProvider == .local
                    ) { selectProvider(.local) }

                    ProviderPill(
                        label: "OpenAI",
                        icon: "globe",
                        isSelected: setup.selectedProvider == .openai
                    ) { selectProvider(.openai, needsKey: true) }
                }

                HStack(spacing: 10) {
                    ProviderPill(
                        label: "Anthropic",
                        icon: "brain.head.profile",
                        isSelected: setup.selectedProvider == .anthropic
                    ) { selectProvider(.anthropic, needsKey: true) }

                    ProviderPill(
                        label: "Apple AI",
                        icon: "apple.logo",
                        isSelected: setup.selectedProvider == .apple
                    ) { selectProvider(.apple) }
                }

                HStack(spacing: 10) {
                    ProviderPill(
                        label: "OpenRouter",
                        icon: "arrow.triangle.branch",
                        isSelected: setup.selectedProvider == .openrouter
                    ) { selectProvider(.openrouter, needsKey: true) }

                    ProviderPill(
                        label: "Groq",
                        icon: "bolt",
                        isSelected: setup.selectedProvider == .groq
                    ) { selectProvider(.groq, needsKey: true) }
                }

                HStack(spacing: 10) {
                    ProviderPill(
                        label: "HuggingFace",
                        icon: "face.smiling",
                        isSelected: setup.selectedProvider == .huggingface
                    ) { selectProvider(.huggingface, needsKey: true) }

                    ProviderPill(
                        label: "Docker",
                        icon: "shippingbox",
                        isSelected: setup.selectedProvider == .dockerModelRunner
                    ) { selectProvider(.dockerModelRunner) }
                }

                HStack(spacing: 10) {
                    ProviderPill(
                        label: "vLLM",
                        icon: "server.rack",
                        isSelected: setup.selectedProvider == .vllm
                    ) { selectProvider(.vllm) }

                    // Spacer pill for alignment
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: 0)
                }
            }

            Spacer()

            SetupNavButtons(
                canGoBack: true,
                canGoNext: false,
                onBack: { setup.goBack() },
                onNext: {}
            )

            StepDotsView(currentStep: setup.currentStep)
                .padding(.bottom, 8)
        }
    }
}
