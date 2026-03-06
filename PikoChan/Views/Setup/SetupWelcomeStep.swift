import SwiftUI

/// Welcome step — sprite animation + typewriter greeting.
struct SetupWelcomeStep: View {
    let setup: SetupManager
    @State private var spriteScale: CGFloat = 0.8
    @State private var typewriterDone = false

    var body: some View {
        VStack(spacing: 16) {
            Image("pikochan_sprite")
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
                .frame(height: 64)
                .scaleEffect(spriteScale)
                .onAppear {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                        spriteScale = 1.0
                    }
                }

            TypewriterText("Hey! I'm PikoChan.\nI live in your notch now.") {
                withAnimation(.easeIn(duration: 0.3)) {
                    typewriterDone = true
                }
            }
            .frame(height: 40)

            if typewriterDone {
                SetupActionButton("Begin Setup", icon: "arrow.right") {
                    setup.advance()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            Spacer()

            StepDotsView(currentStep: setup.currentStep)
                .padding(.bottom, 8)
        }
    }
}
