import SwiftUI

public struct RootShellView: View {
    @ObservedObject private var appViewModel: AppViewModel
    @ObservedObject private var sessionViewModel: SessionViewModel
    @ObservedObject private var router: AppRouter

    public init(appViewModel: AppViewModel, sessionViewModel: SessionViewModel) {
        self.appViewModel = appViewModel
        self.sessionViewModel = sessionViewModel
        self.router = appViewModel.router
    }

    public var body: some View {
        ZStack {
            PerformanceSurfaceView(sessionViewModel: sessionViewModel)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    appViewModel.handleCanvasTap()
                }

            if showsChrome {
                chromeScrims
                    .transition(.opacity)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    topChrome
                    Spacer(minLength: 0)
                    bottomChrome
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 18)
                .transition(.opacity)
            }

            if showsRevealControl {
                VStack {
                    Spacer(minLength: 0)
                    revealControl
                        .padding(.bottom, 28)
                }
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.22), value: showsChrome)
        .animation(.easeInOut(duration: 0.22), value: showsRevealControl)
        .sheet(item: Binding(
            get: { router.presentedSheet },
            set: { router.presentedSheet = $0 }
        )) { destination in
            switch destination {
            case .modePicker:
                ModePickerSheet(sessionViewModel: sessionViewModel) { router.dismiss() }
            case .feedbackSetup:
                FeedbackSetupSheet(sessionViewModel: sessionViewModel) { router.dismiss() }
            case .presetBrowser:
                PresetBrowserSheet(sessionViewModel: sessionViewModel) { router.dismiss() }
            case .recorderExport:
                RecorderExportSheet(sessionViewModel: sessionViewModel) { router.dismiss() }
            case .settingsDiagnostics:
                SettingsDiagnosticsSheet(sessionViewModel: sessionViewModel) { router.dismiss() }
            }
        }
        .task {
            await sessionViewModel.startRealtimeAudioPipeline()
        }
        .onDisappear {
            sessionViewModel.stopRealtimeAudioPipeline()
        }
    }

    private var showsChrome: Bool {
        !appViewModel.isPerformanceModeEnabled || appViewModel.isChromeVisible
    }

    private var showsRevealControl: Bool {
        appViewModel.isPerformanceModeEnabled && !appViewModel.isChromeVisible && appViewModel.isRevealControlVisible
    }

    private var isColorShiftMode: Bool {
        sessionViewModel.showsColorFeedbackAction
    }

    private var isTunnelCelsMode: Bool {
        sessionViewModel.showsTunnelVariantAction
    }

    private var chromeScrims: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.66), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.32)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private var topChrome: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                titleBlock
                Spacer(minLength: 16)
                actionCluster
            }

            VStack(alignment: .leading, spacing: 16) {
                titleBlock
                actionCluster
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHROMA")
                .font(ChromaTypography.hero)
                .tracking(1.8)
                .foregroundStyle(.white)

            Text(sessionViewModel.session.activePresetName.uppercased())
                .font(ChromaTypography.overline)
                .tracking(4)
                .foregroundStyle(.white.opacity(0.72))

            Text(sessionViewModel.activeModeDescriptor.name)
                .font(ChromaTypography.title)
                .foregroundStyle(.white)

            Text(sessionViewModel.activeModeDescriptor.summary)
                .font(ChromaTypography.bodySecondary)
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(2)
                .frame(maxWidth: 420, alignment: .leading)
        }
        .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 6)
    }

    private var actionCluster: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                chromeButton(title: "Modes", systemImage: "sparkles", action: appViewModel.presentModePicker)
                if isColorShiftMode {
                    chromeButton(title: "Feedback", systemImage: "arrow.triangle.2.circlepath.camera", action: appViewModel.presentFeedbackSetup)
                }
                if isTunnelCelsMode {
                    chromeButton(
                        title: sessionViewModel.tunnelVariantLabel,
                        systemImage: "square.3.layers.3d"
                    ) {
                        appViewModel.registerPerformanceInteraction()
                        sessionViewModel.cycleTunnelVariant()
                    }
                }
                chromeButton(title: "Presets", systemImage: "square.stack", action: appViewModel.presentPresetBrowser)
                chromeButton(title: "Export", systemImage: "record.circle", action: appViewModel.presentRecorderExport)
                chromeButton(title: "Settings", systemImage: "gearshape", action: appViewModel.presentSettingsDiagnostics)
                chromeButton(
                    title: appViewModel.isPerformanceModeEnabled ? "Exit" : "Fullscreen",
                    systemImage: appViewModel.isPerformanceModeEnabled ? "rectangle.inset.filled.and.person.filled" : "arrow.up.left.and.arrow.down.right"
                ) {
                    appViewModel.togglePerformanceMode()
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    chromeButton(title: "Modes", systemImage: "sparkles", action: appViewModel.presentModePicker)
                    if isColorShiftMode {
                        chromeButton(title: "Feedback", systemImage: "arrow.triangle.2.circlepath.camera", action: appViewModel.presentFeedbackSetup)
                    }
                    if isTunnelCelsMode {
                        chromeButton(
                            title: sessionViewModel.tunnelVariantLabel,
                            systemImage: "square.3.layers.3d"
                        ) {
                            appViewModel.registerPerformanceInteraction()
                            sessionViewModel.cycleTunnelVariant()
                        }
                    }
                    chromeButton(title: "Presets", systemImage: "square.stack", action: appViewModel.presentPresetBrowser)
                    chromeButton(title: "Export", systemImage: "record.circle", action: appViewModel.presentRecorderExport)
                }
                HStack(spacing: 10) {
                    chromeButton(title: "Settings", systemImage: "gearshape", action: appViewModel.presentSettingsDiagnostics)
                    chromeButton(
                        title: appViewModel.isPerformanceModeEnabled ? "Exit" : "Fullscreen",
                        systemImage: appViewModel.isPerformanceModeEnabled ? "rectangle.inset.filled.and.person.filled" : "arrow.up.left.and.arrow.down.right"
                    ) {
                        appViewModel.togglePerformanceMode()
                    }
                }
            }
        }
    }

    private var bottomChrome: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            SurfaceControlsPanel(
                sessionViewModel: sessionViewModel,
                noteInteraction: { appViewModel.registerPerformanceInteraction() }
            )
        }
    }

    private var revealControl: some View {
        Button {
            appViewModel.revealPerformanceChrome()
        } label: {
            Label("SHOW CONTROLS", systemImage: "line.3.horizontal.decrease.circle")
                .font(ChromaTypography.action)
                .tracking(0.8)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    private func chromeButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title.uppercased(), systemImage: systemImage)
                .font(ChromaTypography.action)
                .tracking(0.6)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct SurfaceControlsPanel: View {
    @ObservedObject var sessionViewModel: SessionViewModel
    let noteInteraction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LIVE CONTROLS")
                        .font(ChromaTypography.overline)
                        .tracking(1.8)
                    Text(sessionViewModel.activeModeDescriptor.name)
                        .font(ChromaTypography.panelTitle)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Text(frameSummary)
                    .font(ChromaTypography.metric)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }

            ForEach(sessionViewModel.primarySurfaceControlDescriptors) { descriptor in
                SurfaceSliderRow(
                    descriptor: descriptor,
                    value: sessionViewModel.parameterValue(for: descriptor).scalarValue ?? 0,
                    noteInteraction: noteInteraction,
                    onChange: { newValue in
                        sessionViewModel.updateParameter(descriptor, value: .scalar(newValue))
                    }
                )
            }
        }
        .padding(20)
        .frame(maxWidth: 760, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 8)
    }

    private var frameSummary: String {
        let renderer = sessionViewModel.diagnosticsSnapshot.renderer
        guard renderer.approximateFPS > 0 else {
            return renderer.resolutionLabel
        }
        return "\(Int(renderer.approximateFPS.rounded())) fps • \(renderer.resolutionLabel)"
    }
}

private struct SurfaceSliderRow: View {
    let descriptor: ParameterDescriptor
    let value: Double
    let noteInteraction: () -> Void
    let onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(descriptor.title.uppercased())
                    .font(ChromaTypography.action)
                    .tracking(0.6)
                Spacer(minLength: 12)
                Text(String(format: "%.2f", value))
                    .font(ChromaTypography.metric.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { value },
                    set: { newValue in
                        noteInteraction()
                        onChange(newValue)
                    }
                ),
                in: (descriptor.minimumValue ?? 0) ... (descriptor.maximumValue ?? 1),
                onEditingChanged: { _ in
                    noteInteraction()
                }
            )
            .tint(.white)
        }
    }
}
