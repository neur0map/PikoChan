import SwiftUI

/// Summary checklist + "Let's go!" hero button.
struct SetupSummaryStep: View {
    let setup: SetupManager
    let manager: NotchManager

    var body: some View {
        VStack(spacing: 16) {
            Text("All set!")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            VStack(spacing: 8) {
                summaryRow(icon: "checkmark.circle.fill", color: .green,
                           label: providerLabel)
                summaryRow(icon: setup.embeddingAvailable ? "checkmark.circle.fill" : "minus.circle.fill",
                           color: setup.embeddingAvailable ? .green : .orange,
                           label: setup.embeddingAvailable ? "Semantic memory ready" : "Basic memory (no embedding)")
                summaryRow(icon: setup.gatewayReady ? "checkmark.circle.fill" : "minus.circle.fill",
                           color: setup.gatewayReady ? .green : .orange,
                           label: setup.gatewayReady ? "Gateway server running" : "Gateway not detected")
            }
            .padding(.horizontal, 8)

            Spacer()

            SetupActionButton("Let's go!", icon: "sparkles", accent: .green) {
                do {
                    try setup.finalize(configStore: PikoConfigStore.shared)
                } catch {
                    // Finalize failure is non-critical; proceed anyway.
                }
                manager.brain.reloadConfig()
                manager.sendFirstMessage()
            }

            StepDotsView(currentStep: setup.currentStep)
                .padding(.bottom, 8)
        }
    }

    private var providerLabel: String {
        switch setup.selectedProvider {
        case .local:              "Ollama (\(setup.localModel))"
        case .openai:             "OpenAI"
        case .anthropic:          "Anthropic"
        case .apple:              "Apple Intelligence"
        case .openrouter:         "OpenRouter"
        case .groq:               "Groq"
        case .huggingface:        "HuggingFace"
        case .dockerModelRunner:  "Docker Model Runner"
        case .vllm:               "vLLM"
        }
    }

    private func summaryRow(icon: String, color: Color, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color.opacity(0.8))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
        }
    }
}
