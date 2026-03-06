import SwiftUI

// MARK: - Step Dots

/// 5 horizontal dots showing wizard progress.
struct StepDotsView: View {
    let currentStep: SetupManager.Step
    private let steps = SetupManager.Step.allCases

    var body: some View {
        HStack(spacing: 8) {
            ForEach(steps, id: \.rawValue) { step in
                Circle()
                    .fill(dotColor(for: step))
                    .frame(width: 7, height: 7)
                    .overlay {
                        if step.rawValue < currentStep.rawValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 5, weight: .bold))
                                .foregroundStyle(.black)
                        }
                    }
            }
        }
    }

    private func dotColor(for step: SetupManager.Step) -> Color {
        if step == currentStep { return .white.opacity(0.9) }
        if step.rawValue < currentStep.rawValue { return .green.opacity(0.7) }
        return .white.opacity(0.2)
    }
}

// MARK: - Action Button

/// Hero CTA button matching PikoButton style from ExpandedView.
struct SetupActionButton: View {
    let label: String
    let icon: String?
    let accentColor: Color
    let action: () -> Void
    @State private var isPressed = false

    init(_ label: String, icon: String? = nil, accent: Color = Color(red: 0.15, green: 0.7, blue: 0.85), action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.accentColor = accent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background {
                ZStack {
                    Capsule().fill(accentColor.opacity(0.2))
                    Capsule().strokeBorder(
                        LinearGradient(
                            colors: [accentColor.opacity(0.5), accentColor.opacity(0.15)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                }
            }
            .scaleEffect(isPressed ? 0.94 : 1.0)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) { isPressed = pressing }
        }, perform: {})
    }
}

// MARK: - Nav Buttons

/// Back chevron + Next arrow HStack.
struct SetupNavButtons: View {
    let canGoBack: Bool
    let canGoNext: Bool
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            if canGoBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if canGoNext {
                Button(action: onNext) {
                    HStack(spacing: 4) {
                        Text("Next")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Setup Text Field

/// Dark-themed text field for setup wizard.
/// Uses NSViewRepresentable wrappers (PikoTextField / PikoSecureField) because
/// SwiftUI's TextField/SecureField don't receive focus in NSPanel at .screenSaver level.
struct SetupTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var onSubmit: () -> Void = {}

    var body: some View {
        Group {
            if isSecure {
                PikoSecureField(text: $text, placeholder: placeholder, onSubmit: onSubmit)
            } else {
                PikoTextField(text: $text, placeholder: placeholder, onSubmit: onSubmit)
            }
        }
        .frame(height: 18)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Typewriter Text

/// State-driven character reveal at 30ms intervals.
struct TypewriterText: View {
    let fullText: String
    let onComplete: (() -> Void)?
    @State private var displayedCount = 0
    @State private var timer: Timer?

    init(_ text: String, onComplete: (() -> Void)? = nil) {
        self.fullText = text
        self.onComplete = onComplete
    }

    var body: some View {
        Text(String(fullText.prefix(displayedCount)))
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .multilineTextAlignment(.center)
            .onAppear { startTyping() }
            .onDisappear { timer?.invalidate() }
    }

    private func startTyping() {
        displayedCount = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { t in
            if displayedCount < fullText.count {
                displayedCount += 1
            } else {
                t.invalidate()
                onComplete?()
            }
        }
    }
}

// MARK: - Provider Pill

/// Selectable pill button for provider selection.
struct ProviderPill: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.5))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.white.opacity(isSelected ? 0.15 : 0.05))
                    .overlay(
                        Capsule()
                            .strokeBorder(.white.opacity(isSelected ? 0.4 : 0.1), lineWidth: 0.5)
                    )
            )
            .scaleEffect(isPressed ? 0.94 : 1.0)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) { isPressed = pressing }
        }, perform: {})
    }
}

// MARK: - Check Row

/// Shows a status icon + label for system checks.
struct CheckRow: View {
    let label: String
    let status: CheckStatus

    enum CheckStatus {
        case pending, checking, success, failure(String)
    }

    var body: some View {
        HStack(spacing: 8) {
            switch status {
            case .pending:
                Image(systemName: "circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            case .checking:
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green.opacity(0.8))
            case .failure:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.8))
            }

            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            if case .failure(let detail) = status {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.6))
            }
        }
    }
}
