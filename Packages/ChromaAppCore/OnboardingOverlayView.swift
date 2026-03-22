import SwiftUI

struct OnboardingOverlayView: View {
    let isLightGlassAppearance: Bool
    let onComplete: () -> Void

    @State private var currentPage = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pageCount = 4

    private let proAccentGradient = LinearGradient(
        colors: [
            Color(red: 47 / 255, green: 125 / 255, blue: 110 / 255),
            Color(red: 88 / 255, green: 103 / 255, blue: 168 / 255),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private var primaryColor: Color {
        isLightGlassAppearance ? Color.black.opacity(0.90) : Color.white
    }

    private var secondaryColor: Color {
        isLightGlassAppearance ? Color.black.opacity(0.68) : Color.white.opacity(0.76)
    }

    var body: some View {
        ZStack {
            // Glass blur background — renderer shows through
            Rectangle()
                .fill(isLightGlassAppearance ? .ultraThinMaterial : .regularMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    plugInPage.tag(1)
                    tourPage.tag(2)
                    readyPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                paginationDots
                    .padding(.top, 8)
                    .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            VStack(spacing: 16) {
                Text("CHROMA")
                    .font(ChromaTypography.hero)
                    .tracking(2.0)
                    .foregroundStyle(primaryColor)

                Text("A live visual instrument.")
                    .font(ChromaTypography.bodySecondary)
                    .foregroundStyle(secondaryColor)
            }

            Spacer(minLength: 20)

            VStack(spacing: 6) {
                Image(systemName: "chevron.compact.up")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(secondaryColor.opacity(0.6))
                Text("SWIPE TO BEGIN")
                    .font(ChromaTypography.overline)
                    .tracking(1.2)
                    .foregroundStyle(secondaryColor.opacity(0.6))
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: - Page 2: Plug In

    private var plugInPage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            VStack(spacing: 20) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(proAccentGradient)

                VStack(spacing: 12) {
                    Text("Plug in for the best experience.")
                        .font(ChromaTypography.panelTitle)
                        .tracking(0.2)
                        .foregroundStyle(primaryColor)
                        .multilineTextAlignment(.center)

                    Text("Chroma uses your GPU at full power. Charging keeps visuals running at peak quality — and your phone cool.")
                        .font(ChromaTypography.bodySecondary)
                        .foregroundStyle(secondaryColor)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Page 3: Quick Tour

    private var tourPage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            VStack(spacing: 24) {
                Text("Three things to know.")
                    .font(ChromaTypography.panelTitle)
                    .tracking(0.2)
                    .foregroundStyle(primaryColor)

                VStack(spacing: 12) {
                    tourTile(icon: "hand.tap", text: "Tap to reveal controls")
                    tourTile(icon: "square.stack.3d.up", text: "Swipe to change modes")
                    tourTile(icon: "waveform", text: "Your music drives everything")
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tourTile(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(proAccentGradient)
                .frame(width: 32)

            Text(text.uppercased())
                .font(ChromaTypography.action)
                .tracking(0.8)
                .foregroundStyle(primaryColor)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    isLightGlassAppearance
                        ? Color.black.opacity(0.06)
                        : Color.white.opacity(0.10)
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    isLightGlassAppearance
                        ? Color.black.opacity(0.08)
                        : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        }
    }

    // MARK: - Page 4: Ready

    private var readyPage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(proAccentGradient)
                    .symbolEffect(.bounce, value: currentPage == 3)

                Text("You're ready.")
                    .font(ChromaTypography.panelTitle)
                    .tracking(0.2)
                    .foregroundStyle(primaryColor)
                    .multilineTextAlignment(.center)

                Text("Tap anywhere to start.")
                    .font(ChromaTypography.bodySecondary)
                    .foregroundStyle(secondaryColor)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 16)

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    onComplete()
                }
            } label: {
                Text("Let's go")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(0.3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(proAccentGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Pagination Dots

    private var paginationDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                let isActive = index == currentPage
                Capsule()
                    .fill(
                        isActive
                            ? Color(red: 47 / 255, green: 125 / 255, blue: 110 / 255).opacity(isLightGlassAppearance ? 0.94 : 0.98)
                            : Color.secondary.opacity(isLightGlassAppearance ? 0.35 : 0.48)
                    )
                    .frame(width: isActive ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.26, dampingFraction: 0.82), value: currentPage)
            }
        }
    }
}
