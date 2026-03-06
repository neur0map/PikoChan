import SwiftUI

/// Root setup container — routes currentStep to step views.
struct SetupView: View {
    let manager: NotchManager
    @Bindable var setup: SetupManager

    var body: some View {
        Group {
            switch setup.currentStep {
            case .welcome:
                SetupWelcomeStep(setup: setup)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .provider:
                SetupProviderStep(setup: setup)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .providerConfig:
                SetupProviderConfigStep(setup: setup)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .onAppear {
                        // Auto-validate for Ollama / Apple (no user input needed).
                        if (setup.selectedProvider == .local || setup.selectedProvider == .apple),
                           setup.providerValidation == .idle {
                            Task { await setup.validateProvider() }
                        }
                    }
            case .memory:
                SetupMemoryStep(
                    setup: setup,
                    store: manager.brain.store,
                    gatewayPort: manager.brain.config.gatewayPort
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            case .summary:
                SetupSummaryStep(setup: setup, manager: manager)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: setup.currentStep)
    }
}
