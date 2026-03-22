//
//  ChromaProPaywallView.swift
//  Chroma
//

import SwiftUI

public enum ProPaywallEntryPoint: Equatable {
    case mode(VisualModeID)
    case recording
    case externalDisplay
    case customBuilder
    case presets
}

struct ChromaProPaywallView: View {
    @ObservedObject var billingStore: BillingStore
    let entryPoint: ProPaywallEntryPoint
    var onDismiss: () -> Void
    var onSelectMode: (VisualModeID) -> Void = { _ in }
    var onPresentModePicker: () -> Void = {}
    var onPresentBuilder: () -> Void = {}
    var onPresentRecorder: () -> Void = {}
    var onPresentSettings: () -> Void = {}
    var onPresentPresets: () -> Void = {}

    @Environment(\.openURL) private var openURL

    @State private var selectedProductID = BillingStore.annualProductID
    @State private var showSuccess = false

    private let manageURL = URL(string: "https://apps.apple.com/account/subscriptions")

    private let proAccentGradient = LinearGradient(
        colors: [
            Color(red: 47 / 255, green: 125 / 255, blue: 110 / 255),
            Color(red: 88 / 255, green: 103 / 255, blue: 168 / 255),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        NavigationStack {
            if showSuccess {
                successView
            } else {
                paywallContent
            }
        }
#if targetEnvironment(macCatalyst)
        .frame(minWidth: 460, minHeight: 480)
#endif
        .task {
            await billingStore.startIfNeeded()
        }
        .onChange(of: billingStore.isProActive) { _, isActive in
            if isActive && !showSuccess {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showSuccess = true
                }
            }
        }
    }

    // MARK: - Paywall

    private var paywallContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroSection
                    .padding(.bottom, 20)

                planPicker
                    .padding(.bottom, 16)

                primaryCTA
                    .padding(.bottom, 12)

                footerSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if billingStore.isLoadingProducts {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heroTitle)
                .font(ChromaTypography.panelTitle)
                .tracking(0.2)

            Text(heroSubtitle)
                .font(ChromaTypography.bodySecondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            featureGrid
                .padding(.top, 6)
        }
    }

    private var featureGrid: some View {
        let features: [(icon: String, label: String)] = [
            ("cube.transparent", "3 Extra Modes"),
            ("point.3.connected.trianglepath.dotted", "Node Graph"),
            ("record.circle", "Recording"),
            ("rectangle.on.rectangle", "External Display"),
            ("slider.horizontal.3", "Unlimited Presets"),
            ("arrow.triangle.merge", "Mode Morphing"),
        ]

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
            ForEach(features, id: \.label) { feature in
                HStack(spacing: 7) {
                    Image(systemName: feature.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(feature.label)
                        .font(ChromaTypography.metric)
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    // MARK: - Plan picker

    private var planPicker: some View {
        VStack(spacing: 10) {
            planRow(
                option: billingStore.paywallPlanOptions.first(where: { $0.productID == BillingStore.annualProductID })
                    ?? billingStore.paywallPlanOptions[0]
            )
            planRow(
                option: billingStore.paywallPlanOptions.first(where: { $0.productID == BillingStore.monthlyProductID })
                    ?? billingStore.paywallPlanOptions[1]
            )
        }
    }

    @ViewBuilder
    private func planRow(option: PaywallPlanOption) -> some View {
        let isSelected = option.productID == selectedProductID

        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedProductID = option.productID
            }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? Color(red: 47 / 255, green: 125 / 255, blue: 110 / 255) : .secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(option.title)
                            .font(.system(size: 17, weight: .bold, design: .rounded))

                        if let badgeText = option.badgeText {
                            Text(badgeText)
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(proAccentGradient, in: Capsule())
                                .foregroundStyle(.white)
                        }

                        if option.trialInfo != nil {
                            Text("1 wk free")
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.10), in: Capsule())
                        }
                    }

                    Text(planDetail(for: option))
                        .font(ChromaTypography.metric)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(option.priceText)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                    Text(option.periodText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.08 : 0.04))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected
                            ? Color(red: 47 / 255, green: 125 / 255, blue: 110 / 255).opacity(0.8)
                            : Color.white.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func planDetail(for option: PaywallPlanOption) -> String {
        if let trial = option.trialInfo {
            return "\(trial.detail)"
        }
        return option.subtitle
    }

    // MARK: - CTA

    private var primaryCTA: some View {
        Button {
            Task {
                await billingStore.purchase(productID: selectedProductID)
            }
        } label: {
            HStack(spacing: 10) {
                if billingStore.isPurchasing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: selectedPlan.trialInfo != nil ? "gift" : "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                }

                Text(primaryCTAText)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(0.3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(proAccentGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(billingStore.isPurchasing)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = billingStore.lastErrorMessage, !message.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Text("Auto-renews until cancelled.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)

            HStack(spacing: 14) {
                Button("Restore Purchases") {
                    Task { await billingStore.restorePurchases() }
                }

                Button("Manage") {
                    guard let manageURL else { return }
                    openURL(manageURL)
                }
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(proAccentGradient)
                    .symbolEffect(.bounce, value: showSuccess)

                Text(successTitle)
                    .font(ChromaTypography.panelTitle)
                    .tracking(0.2)
                    .multilineTextAlignment(.center)

                Text(successSubtitle)
                    .font(ChromaTypography.bodySecondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 16)

            VStack(spacing: 10) {
                ForEach(successActions, id: \.title) { action in
                    Button {
                        onDismiss()
                        action.perform()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: action.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 20)
                            Text(action.title)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 12)

            Button {
                onDismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(0.3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(proAccentGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    // MARK: - Computed strings

    private var selectedPlan: PaywallPlanOption {
        billingStore.paywallPlanOptions.first(where: { $0.productID == selectedProductID })
            ?? billingStore.paywallPlanOptions[0]
    }

    private var heroTitle: String {
        if selectedPlan.trialInfo != nil {
            return "Start your free week."
        }
        return "Unlock Chroma Pro."
    }

    private var heroSubtitle: String {
        switch entryPoint {
        case .mode(let modeID):
            return "Unlock \(modeID.displayName) and the full Pro toolset."
        case .recording:
            return "Unlock recording, export, and the full Pro toolset."
        case .externalDisplay:
            return "Unlock external display and the full Pro toolset."
        case .customBuilder:
            return "Unlock the node graph builder and the full Pro toolset."
        case .presets:
            return "Unlock unlimited presets and the full Pro toolset."
        }
    }

    private var primaryCTAText: String {
        if let trial = selectedPlan.trialInfo {
            return "Start \(trial.headline)"
        }
        return "Continue with \(selectedPlan.title)"
    }

    private var successTitle: String {
        if billingStore.proAccessVisualState == .trial {
            return "Your trial is active."
        }
        return "You're all set."
    }

    private var successSubtitle: String {
        if billingStore.proAccessVisualState == .trial {
            return "All Pro features are unlocked for the next week. After that, your annual subscription begins automatically."
        }
        return "Chroma Pro is active. All modes, recording, external display, and the node graph builder are yours."
    }

    private struct SuccessAction: Identifiable {
        let title: String
        let icon: String
        let perform: () -> Void
        var id: String { title }
    }

    private var successActions: [SuccessAction] {
        switch entryPoint {
        case .mode(let modeID):
            return [
                SuccessAction(title: "Try \(modeID.displayName)", icon: "play.fill", perform: { onSelectMode(modeID) }),
                SuccessAction(title: "Open Node Graph Builder", icon: "point.3.connected.trianglepath.dotted", perform: onPresentBuilder),
                SuccessAction(title: "Browse All Modes", icon: "square.stack.3d.up", perform: onPresentModePicker),
            ]
        case .recording:
            return [
                SuccessAction(title: "Start Recording", icon: "record.circle", perform: onPresentRecorder),
                SuccessAction(title: "Explore Pro Modes", icon: "square.stack.3d.up", perform: onPresentModePicker),
            ]
        case .externalDisplay:
            return [
                SuccessAction(title: "Set Up External Display", icon: "rectangle.on.rectangle", perform: onPresentSettings),
                SuccessAction(title: "Explore Pro Modes", icon: "square.stack.3d.up", perform: onPresentModePicker),
            ]
        case .customBuilder:
            return [
                SuccessAction(title: "Open Node Graph Builder", icon: "point.3.connected.trianglepath.dotted", perform: onPresentBuilder),
                SuccessAction(title: "Explore Pro Modes", icon: "square.stack.3d.up", perform: onPresentModePicker),
            ]
        case .presets:
            return [
                SuccessAction(title: "Manage Presets", icon: "slider.horizontal.3", perform: onPresentPresets),
                SuccessAction(title: "Explore Pro Modes", icon: "square.stack.3d.up", perform: onPresentModePicker),
            ]
        }
    }
}
