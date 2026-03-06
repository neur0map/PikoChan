import SwiftUI

/// Memory + system checks step.
struct SetupMemoryStep: View {
    let setup: SetupManager
    let store: PikoStore?
    let gatewayPort: UInt16

    @State private var checksStarted = false

    var body: some View {
        VStack(spacing: 14) {
            Text("System Check")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))

            VStack(spacing: 8) {
                CheckRow(label: "SQLite database", status: dbStatus)
                CheckRow(label: "Embedding model", status: embeddingStatus)
                CheckRow(label: "Memory indexing", status: migrationStatus)
                CheckRow(label: "Gateway server", status: gatewayStatus)
                CheckRow(label: "Log directory", status: .success)
            }
            .padding(.horizontal, 4)

            Spacer()

            SetupNavButtons(
                canGoBack: true,
                canGoNext: checksComplete,
                onBack: { setup.goBack() },
                onNext: { setup.advance() }
            )

            StepDotsView(currentStep: setup.currentStep)
                .padding(.bottom, 8)
        }
        .onAppear {
            guard !checksStarted else { return }
            checksStarted = true
            Task { await setup.runSystemChecks(store: store, gatewayPort: gatewayPort) }
        }
    }

    private var checksComplete: Bool {
        setup.dbReady && (setup.memoryMigration != .idle)
    }

    private var dbStatus: CheckRow.CheckStatus {
        setup.dbReady ? .success : .failure("Failed to open")
    }

    private var embeddingStatus: CheckRow.CheckStatus {
        if !checksStarted { return .checking }
        return setup.embeddingAvailable
            ? .success
            : .failure("Basic recall will be used")
    }

    private var migrationStatus: CheckRow.CheckStatus {
        switch setup.memoryMigration {
        case .idle: return .checking
        case .inProgress: return .checking
        case .complete, .skipped: return .success
        }
    }

    private var gatewayStatus: CheckRow.CheckStatus {
        if !checksStarted { return .checking }
        return setup.gatewayReady ? .success : .failure("Not running")
    }
}
