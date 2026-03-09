import SwiftUI

/// Compact inline Deny / Allow / Always buttons with staggered spring animation.
struct InlineApprovalView: View {
    let onApprove: () -> Void
    let onDeny: () -> Void
    var onAllowSession: (() -> Void)?

    @State private var showDeny = false
    @State private var showAllow = false
    @State private var showSession = false

    var body: some View {
        HStack(spacing: 5) {
            capsuleButton("Deny", fg: .white.opacity(0.6), bg: .white.opacity(0.1)) {
                onDeny()
            }
            .opacity(showDeny ? 1 : 0)
            .scaleEffect(showDeny ? 1 : 0.8)

            capsuleButton("Allow", fg: .black, bg: .white.opacity(0.9)) {
                onApprove()
            }
            .opacity(showAllow ? 1 : 0)
            .scaleEffect(showAllow ? 1 : 0.8)

            if onAllowSession != nil {
                capsuleButton("Always", fg: .white.opacity(0.9), bg: Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.6)) {
                    onAllowSession?()
                }
                .opacity(showSession ? 1 : 0)
                .scaleEffect(showSession ? 1 : 0.8)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) { showDeny = true }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.10)) { showAllow = true }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.15)) { showSession = true }
        }
    }

    private func capsuleButton(
        _ label: String, fg: Color, bg: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(fg)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(bg)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
