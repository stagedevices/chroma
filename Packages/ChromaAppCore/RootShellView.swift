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
            presentedSheet(for: destination)
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

    private var isFractalCausticsMode: Bool {
        sessionViewModel.showsFractalPaletteAction
    }

    private var isRiemannCorridorMode: Bool {
        sessionViewModel.showsRiemannPaletteAction
    }

    private var usesTileActionDeck: Bool {
#if targetEnvironment(macCatalyst)
        false
#else
        true
#endif
    }

    private struct ActionTileModel: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let action: () -> Void
        var isFullscreenAction: Bool = false
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
                if usesTileActionDeck {
                    actionTileDeck
                        .frame(maxWidth: 390)
                } else {
                    actionCluster
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                titleBlock
                if usesTileActionDeck {
                    actionTileDeck
                } else {
                    actionCluster
                }
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
                if isFractalCausticsMode {
                    chromeButton(
                        title: sessionViewModel.fractalPaletteLabel,
                        systemImage: "paintpalette"
                    ) {
                        appViewModel.registerPerformanceInteraction()
                        sessionViewModel.cycleFractalPaletteVariant()
                    }
                }
                if isRiemannCorridorMode {
                    chromeButton(
                        title: sessionViewModel.riemannPaletteLabel,
                        systemImage: "paintpalette"
                    ) {
                        appViewModel.registerPerformanceInteraction()
                        sessionViewModel.cycleRiemannPaletteVariant()
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
                    if isFractalCausticsMode {
                        chromeButton(
                            title: sessionViewModel.fractalPaletteLabel,
                            systemImage: "paintpalette"
                        ) {
                            appViewModel.registerPerformanceInteraction()
                            sessionViewModel.cycleFractalPaletteVariant()
                        }
                    }
                    if isRiemannCorridorMode {
                        chromeButton(
                            title: sessionViewModel.riemannPaletteLabel,
                            systemImage: "paintpalette"
                        ) {
                            appViewModel.registerPerformanceInteraction()
                            sessionViewModel.cycleRiemannPaletteVariant()
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

    private var actionTileDeck: some View {
        let columns = [
            GridItem(.flexible(minimum: 148), spacing: 12),
            GridItem(.flexible(minimum: 148), spacing: 12),
        ]
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(primaryActionTiles) { tile in
                    ActionTileButton(
                        title: tile.title,
                        systemImage: tile.systemImage,
                        isFullscreenAction: tile.isFullscreenAction,
                        action: tile.action
                    )
                }
            }

            ActionMasterTile(
                sessionViewModel: sessionViewModel,
                modeAction: modeStyleAction,
                openSettings: appViewModel.presentSettingsDiagnostics,
                savePreset: { appViewModel.registerPerformanceInteraction() },
                noteInteraction: appViewModel.registerPerformanceInteraction
            )
        }
    }

    private var primaryActionTiles: [ActionTileModel] {
        [
            ActionTileModel(
                id: "modes",
                title: "Modes",
                systemImage: "sparkles",
                action: appViewModel.presentModePicker
            ),
            ActionTileModel(
                id: "presets",
                title: "Presets",
                systemImage: "square.stack",
                action: appViewModel.presentPresetBrowser
            ),
            ActionTileModel(
                id: "export",
                title: "Export",
                systemImage: "record.circle",
                action: appViewModel.presentRecorderExport
            ),
            ActionTileModel(
                id: "fullscreen",
                title: appViewModel.isPerformanceModeEnabled ? "Exit" : "Fullscreen",
                systemImage: appViewModel.isPerformanceModeEnabled ? "rectangle.inset.filled.and.person.filled" : "arrow.up.left.and.arrow.down.right",
                action: appViewModel.togglePerformanceMode,
                isFullscreenAction: true
            ),
        ]
    }

    private var modeStyleAction: (title: String, systemImage: String, action: () -> Void)? {
        if isColorShiftMode {
            return ("Feedback", "arrow.triangle.2.circlepath.camera", appViewModel.presentFeedbackSetup)
        }
        if isTunnelCelsMode {
            return (sessionViewModel.tunnelVariantLabel, "square.3.layers.3d", appViewModel.presentTunnelVariantPicker)
        }
        if isFractalCausticsMode {
            return (sessionViewModel.fractalPaletteLabel, "paintpalette", appViewModel.presentFractalPalettePicker)
        }
        if isRiemannCorridorMode {
            return (sessionViewModel.riemannPaletteLabel, "paintpalette", appViewModel.presentRiemannPalettePicker)
        }
        return nil
    }

    @ViewBuilder
    private func presentedSheet(for destination: AppSheetDestination) -> some View {
        let content = AnyView(sheetContent(for: destination))
        switch appSheetDetentStyle(for: destination) {
        case .mediumOnly:
            content
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        case .mediumAndLarge:
            content
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func sheetContent(for destination: AppSheetDestination) -> some View {
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
        case .tunnelVariantPicker:
            TunnelVariantPickerSheet(sessionViewModel: sessionViewModel) { router.dismiss() }
        case .fractalPalettePicker:
            FractalPalettePickerSheet(sessionViewModel: sessionViewModel) { router.dismiss() }
        case .riemannPalettePicker:
            RiemannPalettePickerSheet(sessionViewModel: sessionViewModel) { router.dismiss() }
        }
    }

    private var bottomChrome: some View {
#if targetEnvironment(macCatalyst)
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            SurfaceControlsPanel(
                sessionViewModel: sessionViewModel,
                noteInteraction: { appViewModel.registerPerformanceInteraction() }
            )
        }
#else
        EmptyView()
#endif
    }

    private var revealControl: some View {
        Button {
            appViewModel.togglePerformanceMode()
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

private struct ActionTileButton: View {
    let title: String
    let systemImage: String
    let isFullscreenAction: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var symbolEffectToken = UUID()

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                tileIcon

                Text(title.uppercased())
                    .font(ChromaTypography.action)
                    .tracking(0.8)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .foregroundStyle(.white)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .padding(14)
        }
        .buttonStyle(.plain)
        .chromaGlassTileBackground(in: shape, isEmphasized: isFullscreenAction)
        .overlay {
            shape
                .stroke(Color.white.opacity(isFullscreenAction ? 0.22 : 0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(isFullscreenAction ? 0.26 : 0.16), radius: isFullscreenAction ? 18 : 12, x: 0, y: 6)
        .onAppear {
            guard !reduceMotion else { return }
            symbolEffectToken = UUID()
        }
    }

    @ViewBuilder
    private var tileIcon: some View {
        let icon = Image(systemName: systemImage)
            .font(.system(size: 24, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.white.opacity(isFullscreenAction ? 0.95 : 0.70))
            .padding(10)
            .background(Color.white.opacity(isFullscreenAction ? 0.20 : 0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

        if reduceMotion {
            icon
        } else if #available(iOS 18.0, macCatalyst 18.0, *) {
            icon.symbolEffect(.wiggle.byLayer, value: symbolEffectToken)
        } else {
            icon
        }
    }
}

private struct ActionMasterTile: View {
    @ObservedObject var sessionViewModel: SessionViewModel
    let modeAction: (title: String, systemImage: String, action: () -> Void)?
    let openSettings: () -> Void
    let savePreset: () -> Void
    let noteInteraction: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedPane: ActionPane = .liveControls
    @State private var transientPane: ActionPane?

    private enum ActionPane: String, Identifiable {
        case liveControls
        case modeAction
        case savePreset
        case settings

        var id: String { rawValue }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                paneButton(
                    for: .liveControls,
                    title: "Live Controls",
                    systemImage: "slider.horizontal.3"
                )

                if let modeAction {
                    paneButton(
                        for: .modeAction,
                        title: modeAction.title,
                        systemImage: modeAction.systemImage
                    )
                }

                paneButton(
                    for: .savePreset,
                    title: "Save Preset",
                    systemImage: "square.and.arrow.down"
                )

                paneButton(
                    for: .settings,
                    title: "Settings",
                    systemImage: "gearshape"
                )

                Spacer(minLength: 0)
            }

            paneContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .padding(14)
        .chromaGlassTileBackground(in: shape, isEmphasized: false)
        .overlay {
            shape
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
    }

    private func paneButton(for pane: ActionPane, title: String, systemImage: String) -> some View {
        let isExpanded = expandedPane == pane
        let isTransient = transientPane == pane
        let width: CGFloat = isTransient ? 152 : 44

        return Button {
            selectPane(pane)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .white.opacity(0.70))
                    .frame(width: 18, height: 18)

                if isTransient {
                    Text(title.uppercased())
                        .font(ChromaTypography.overline)
                        .tracking(1.0)
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, isTransient ? 12 : 0)
            .frame(width: width, height: 40, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isExpanded ? 0.24 : 0.12))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(isExpanded ? 0.24 : 0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isTransient ? 1.04 : 1.0)
    }

    private func selectPane(_ pane: ActionPane) {
        noteInteraction()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
            expandedPane = pane
            transientPane = pane
        }

        guard !reduceMotion else {
            transientPane = nil
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            withAnimation(.easeOut(duration: 0.2)) {
                if transientPane == pane {
                    transientPane = nil
                }
            }
        }
    }

    @ViewBuilder
    private var paneContent: some View {
        switch expandedPane {
        case .liveControls:
            liveControlsPane
        case .modeAction:
            modeActionPane
        case .savePreset:
            savePresetPane
        case .settings:
            settingsPane
        }
    }

    private var liveControlsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("LIVE CONTROLS")
                    .font(ChromaTypography.overline)
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.72))

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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 150, maxHeight: 210)
    }

    @ViewBuilder
    private var modeActionPane: some View {
        if let modeAction {
            VStack(alignment: .leading, spacing: 10) {
                Text("MODE ACTION")
                    .font(ChromaTypography.overline)
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.72))

                Button {
                    noteInteraction()
                    modeAction.action()
                } label: {
                    Label(modeAction.title.uppercased(), systemImage: modeAction.systemImage)
                        .font(ChromaTypography.action)
                        .tracking(0.8)
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
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("MODE ACTION")
                    .font(ChromaTypography.overline)
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.72))
                Text("No mode-specific action is available for the current mode.")
                    .font(ChromaTypography.bodySecondary)
                    .foregroundStyle(.white.opacity(0.76))
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        }
    }

    private var savePresetPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SAVE PRESET")
                .font(ChromaTypography.overline)
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.72))
            Button {
                noteInteraction()
                savePreset()
            } label: {
                Label("SAVE PRESET (SOON)", systemImage: "square.and.arrow.down")
                    .font(ChromaTypography.action)
                    .tracking(0.8)
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

            Text("Preset capture tile is wired as a placeholder and will be implemented in a follow-up task.")
                .font(ChromaTypography.bodySecondary)
                .foregroundStyle(.white.opacity(0.76))
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
    }

    private var settingsPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SETTINGS")
                .font(ChromaTypography.overline)
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.72))
            Button {
                noteInteraction()
                openSettings()
            } label: {
                Label("OPEN SETTINGS", systemImage: "gearshape")
                    .font(ChromaTypography.action)
                    .tracking(0.8)
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
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
    }
}

private extension View {
    @ViewBuilder
    func chromaGlassTileBackground<S: Shape>(in shape: S, isEmphasized: Bool) -> some View {
        let opacity = isEmphasized ? 0.16 : 0.10
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            self
                .background(Color.white.opacity(opacity), in: shape)
                .glassEffect(.regular.tint(Color.white.opacity(opacity)).interactive(), in: shape)
        } else {
            self
                .background(.regularMaterial, in: shape)
        }
    }
}
