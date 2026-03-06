import SwiftUI

/// Provider picker — 4 pill buttons.
struct SetupProviderStep: View {
    let setup: SetupManager

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
                    ) {
                        setup.selectedProvider = .local
                        setup.providerValidation = .idle
                        setup.providerReady = false
                        setup.advance()
                    }

                    ProviderPill(
                        label: "OpenAI",
                        icon: "globe",
                        isSelected: setup.selectedProvider == .openai
                    ) {
                        setup.selectedProvider = .openai
                        setup.apiKey = ""
                        setup.providerValidation = .idle
                        setup.providerReady = false
                        setup.advance()
                    }
                }

                HStack(spacing: 10) {
                    ProviderPill(
                        label: "Anthropic",
                        icon: "brain.head.profile",
                        isSelected: setup.selectedProvider == .anthropic
                    ) {
                        setup.selectedProvider = .anthropic
                        setup.apiKey = ""
                        setup.providerValidation = .idle
                        setup.providerReady = false
                        setup.advance()
                    }

                    ProviderPill(
                        label: "Apple AI",
                        icon: "apple.logo",
                        isSelected: setup.selectedProvider == .apple
                    ) {
                        setup.selectedProvider = .apple
                        setup.providerValidation = .idle
                        setup.providerReady = false
                        setup.advance()
                    }
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
