import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct RootShellView: View {
    @ObservedObject private var appViewModel: AppViewModel
    @ObservedObject private var sessionViewModel: SessionViewModel
    @ObservedObject private var router: AppRouter
    @State private var activePopoverDestination: AppSheetDestination?
    @State private var activePopoverTileID: String?
#if canImport(UIKit) && !targetEnvironment(macCatalyst)
    @State private var externalProgramWindow: UIWindow?
#endif
    @State private var inkTransitionProgress: CGFloat = 0.001
    @State private var inkTransitionOpacity: Double = 0
    @State private var inkTransitionResetWorkItem: DispatchWorkItem?

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

            VStack(spacing: 0) {
                topChrome
                Spacer(minLength: 0)
                bottomChrome
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 18)
            .opacity(showsChrome ? 1 : 0)
            .allowsHitTesting(showsChrome)
            .accessibilityHidden(!showsChrome)
            .animation(.easeInOut(duration: 0.22), value: showsChrome)

            VStack {
                Spacer(minLength: 0)
                revealControl
                    .padding(.bottom, 28)
            }
            .opacity(showsRevealControl ? 1 : 0)
            .allowsHitTesting(showsRevealControl)
            .accessibilityHidden(!showsRevealControl)
            .animation(.easeInOut(duration: 0.18), value: showsRevealControl)

            if inkTransitionOpacity > 0.001 {
                AppearanceInkTransitionOverlay(
                    color: isLightGlassAppearance ? Color.white : Color.black,
                    progress: inkTransitionProgress,
                    opacity: inkTransitionOpacity
                )
                .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(isLightGlassAppearance ? .light : .dark)
        .sheet(item: Binding(
            get: { router.presentedSheet },
            set: { router.presentedSheet = $0 }
        )) { destination in
            presentedSheet(for: destination)
        }
        .onChange(of: router.presentedSheet) { _, destination in
            if destination != nil {
                dismissActivePopover()
            }
        }
        .onChange(of: sessionViewModel.appearanceTransitionToken) { _, _ in
            triggerInkTransition()
        }
        .task {
            await sessionViewModel.startRealtimeAudioPipeline()
        }
        .onAppear {
            syncExternalProgramWindow()
        }
        .onChange(of: sessionViewModel.session.outputState.selectedDisplayTargetID) { _, _ in
            syncExternalProgramWindow()
        }
        .onChange(of: sessionViewModel.session.availableDisplayTargets) { _, _ in
            syncExternalProgramWindow()
        }
        .onDisappear {
            sessionViewModel.stopRealtimeAudioPipeline()
            releaseExternalProgramWindow()
        }
    }

    private var showsChrome: Bool {
        !appViewModel.isPerformanceModeEnabled || appViewModel.isChromeVisible
    }

    private var showsRevealControl: Bool {
        appViewModel.isPerformanceModeEnabled && !appViewModel.isChromeVisible && appViewModel.isRevealControlVisible
    }

    private var isLightGlassAppearance: Bool {
        sessionViewModel.isLightGlassAppearance
    }

    private var chromePrimaryColor: Color {
        isLightGlassAppearance ? Color.black.opacity(0.90) : Color.white
    }

    private var chromeSecondaryColor: Color {
        isLightGlassAppearance ? Color.black.opacity(0.68) : Color.white.opacity(0.76)
    }

    private var chromeBorderColor: Color {
        isLightGlassAppearance ? Color.black.opacity(0.16) : Color.white.opacity(0.14)
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
        true
    }

    private struct ActionTileModel: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let destination: AppSheetDestination?
        let action: () -> Void
        var isFullscreenAction: Bool = false
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
                .foregroundStyle(chromePrimaryColor)

            Text(sessionViewModel.activePresetDisplayName.uppercased())
                .font(ChromaTypography.overline)
                .tracking(4)
                .foregroundStyle(chromeSecondaryColor)

            Text(sessionViewModel.activeModeDescriptor.name)
                .font(ChromaTypography.title)
                .foregroundStyle(chromePrimaryColor)

            Text(sessionViewModel.activeModeDescriptor.summary)
                .font(ChromaTypography.bodySecondary)
                .foregroundStyle(chromeSecondaryColor)
                .lineLimit(2)
                .frame(maxWidth: 420, alignment: .leading)
        }
        .shadow(color: (isLightGlassAppearance ? Color.white : Color.black).opacity(0.24), radius: 18, x: 0, y: 6)
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
                    actionTile(for: tile)
                }
            }

#if !targetEnvironment(macCatalyst)
            ActionMasterTile(
                sessionViewModel: sessionViewModel,
                isLightAppearance: isLightGlassAppearance,
                savePreset: {
                    appViewModel.registerPerformanceInteraction()
                    return sessionViewModel.quickSaveActiveModePreset()
                },
                noteInteraction: appViewModel.registerPerformanceInteraction
            )
#endif
        }
    }

    private var primaryActionTiles: [ActionTileModel] {
        var tiles: [ActionTileModel] = [
            ActionTileModel(
                id: "modes",
                title: "Modes",
                systemImage: "sparkles",
                destination: .modePicker,
                action: appViewModel.presentModePicker
            ),
        ]
        if isColorShiftMode {
            tiles.append(
                ActionTileModel(
                    id: "feedback",
                    title: "Feedback",
                    systemImage: "arrow.triangle.2.circlepath.camera",
                    destination: .feedbackSetup,
                    action: appViewModel.presentFeedbackSetup
                )
            )
        } else if isTunnelCelsMode {
            tiles.append(
                ActionTileModel(
                    id: "tunnelVariant",
                    title: sessionViewModel.tunnelVariantLabel,
                    systemImage: "square.3.layers.3d",
                    destination: .tunnelVariantPicker,
                    action: appViewModel.presentTunnelVariantPicker
                )
            )
        } else if isFractalCausticsMode {
            tiles.append(
                ActionTileModel(
                    id: "fractalPalette",
                    title: sessionViewModel.fractalPaletteLabel,
                    systemImage: "paintpalette",
                    destination: .fractalPalettePicker,
                    action: appViewModel.presentFractalPalettePicker
                )
            )
        } else if isRiemannCorridorMode {
            tiles.append(
                ActionTileModel(
                    id: "riemannPalette",
                    title: sessionViewModel.riemannPaletteLabel,
                    systemImage: "paintpalette",
                    destination: .riemannPalettePicker,
                    action: appViewModel.presentRiemannPalettePicker
                )
            )
        }

        tiles.append(contentsOf: [
            ActionTileModel(
                id: "presets",
                title: "Presets",
                systemImage: "square.stack",
                destination: .presetBrowser,
                action: appViewModel.presentPresetBrowser
            ),
            ActionTileModel(
                id: "export",
                title: "Export",
                systemImage: "record.circle",
                destination: .recorderExport,
                action: appViewModel.presentRecorderExport
            ),
            ActionTileModel(
                id: "settings",
                title: "Settings",
                systemImage: "gearshape",
                destination: .settingsDiagnostics,
                action: appViewModel.presentSettingsDiagnostics
            ),
            ActionTileModel(
                id: "fullscreen",
                title: appViewModel.isPerformanceModeEnabled ? "Exit" : "Fullscreen",
                systemImage: appViewModel.isPerformanceModeEnabled ? "rectangle.inset.filled.and.person.filled" : "arrow.up.left.and.arrow.down.right",
                destination: nil,
                action: appViewModel.togglePerformanceMode,
                isFullscreenAction: true
            ),
        ])
        return tiles
    }

    @ViewBuilder
    private func actionTile(for tile: ActionTileModel) -> some View {
        let button = ActionTileButton(
            title: tile.title,
            systemImage: tile.systemImage,
            isLightAppearance: isLightGlassAppearance,
            isFullscreenAction: tile.isFullscreenAction,
            action: { handleActionTileTap(tile) }
        )

#if targetEnvironment(macCatalyst)
        if let destination = tile.destination, appSheetPresentationStyle(for: destination) == .popover {
            button
                .popover(
                    isPresented: popoverBinding(for: tile),
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .top
                ) {
                    popoverContent(for: destination)
                        .frame(minWidth: 360, idealWidth: 420, maxWidth: 520, minHeight: 300, idealHeight: 420, maxHeight: 640)
                }
        } else {
            button
        }
#else
        button
#endif
    }

    private func popoverBinding(for tile: ActionTileModel) -> Binding<Bool> {
        Binding(
            get: {
                activePopoverTileID == tile.id &&
                activePopoverDestination == tile.destination
            },
            set: { isPresented in
                if !isPresented {
                    dismissActivePopover()
                }
            }
        )
    }

    private func handleActionTileTap(_ tile: ActionTileModel) {
#if targetEnvironment(macCatalyst)
        if let destination = tile.destination,
           appSheetPresentationStyle(for: destination) == .popover {
            appViewModel.registerPerformanceInteraction()
            if activePopoverTileID == tile.id && activePopoverDestination == destination {
                dismissActivePopover()
            } else {
                activePopoverTileID = tile.id
                activePopoverDestination = destination
            }
            return
        }
#endif
        dismissActivePopover()
        tile.action()
    }

    private func dismissActivePopover() {
        activePopoverTileID = nil
        activePopoverDestination = nil
    }

    @ViewBuilder
    private func presentedSheet(for destination: AppSheetDestination) -> some View {
        let content = AnyView(sheetContent(for: destination))
            .preferredColorScheme(isLightGlassAppearance ? .light : .dark)
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

    @ViewBuilder
    private func popoverContent(for destination: AppSheetDestination) -> some View {
        switch destination {
        case .modePicker:
            ModePickerSheet(sessionViewModel: sessionViewModel) { dismissActivePopover() }
                .preferredColorScheme(isLightGlassAppearance ? .light : .dark)
        case .feedbackSetup:
            FeedbackSetupSheet(sessionViewModel: sessionViewModel) { dismissActivePopover() }
                .preferredColorScheme(isLightGlassAppearance ? .light : .dark)
        case .presetBrowser:
            PresetBrowserSheet(sessionViewModel: sessionViewModel) { dismissActivePopover() }
                .preferredColorScheme(isLightGlassAppearance ? .light : .dark)
        case .recorderExport:
            RecorderExportSheet(sessionViewModel: sessionViewModel) { dismissActivePopover() }
                .preferredColorScheme(isLightGlassAppearance ? .light : .dark)
        case .settingsDiagnostics:
            SettingsDiagnosticsSheet(sessionViewModel: sessionViewModel) { dismissActivePopover() }
                .preferredColorScheme(isLightGlassAppearance ? .light : .dark)
        case .tunnelVariantPicker:
            TunnelVariantPickerSheet(sessionViewModel: sessionViewModel) { dismissActivePopover() }
                .preferredColorScheme(isLightGlassAppearance ? .light : .dark)
        case .fractalPalettePicker:
            FractalPalettePickerSheet(sessionViewModel: sessionViewModel) { dismissActivePopover() }
                .preferredColorScheme(isLightGlassAppearance ? .light : .dark)
        case .riemannPalettePicker:
            RiemannPalettePickerSheet(sessionViewModel: sessionViewModel) { dismissActivePopover() }
                .preferredColorScheme(isLightGlassAppearance ? .light : .dark)
        }
    }

    private var bottomChrome: some View {
#if targetEnvironment(macCatalyst)
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            SurfaceControlsPanel(
                sessionViewModel: sessionViewModel,
                isLightAppearance: isLightGlassAppearance,
                noteInteraction: { appViewModel.registerPerformanceInteraction() }
            )
        }
#else
        EmptyView()
#endif
    }

    private var revealControl: some View {
        Button {
            appViewModel.exitPerformanceMode()
        } label: {
            Label("SHOW CONTROLS", systemImage: "line.3.horizontal.decrease.circle")
                .font(ChromaTypography.action)
                .tracking(0.8)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(chromePrimaryColor)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(chromeBorderColor, lineWidth: 1)
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
        .foregroundStyle(chromePrimaryColor)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(chromeBorderColor, lineWidth: 1)
        }
    }

    private func syncExternalProgramWindow() {
#if canImport(UIKit) && !targetEnvironment(macCatalyst)
        let externalSelected = sessionViewModel.session.outputState.selectedDisplayTargetID == "external"
        let externalAvailable = sessionViewModel.session.availableDisplayTargets
            .first(where: { $0.id == "external" })?
            .isAvailable ?? false

        guard externalSelected, externalAvailable else {
            releaseExternalProgramWindow()
            return
        }

        guard let externalScreen = UIScreen.screens.first(where: { $0 !== UIScreen.main }) else {
            releaseExternalProgramWindow()
            return
        }

        if let externalProgramWindow, externalProgramWindow.screen == externalScreen {
            externalProgramWindow.isHidden = false
            return
        }

        releaseExternalProgramWindow()

        let window = UIWindow(frame: externalScreen.bounds)
        window.screen = externalScreen
        window.backgroundColor = .black
        window.rootViewController = UIHostingController(
            rootView: PerformanceSurfaceView(sessionViewModel: sessionViewModel)
                .ignoresSafeArea()
                .background(Color.black)
        )
        window.isHidden = false
        externalProgramWindow = window
#endif
    }

    private func releaseExternalProgramWindow() {
#if canImport(UIKit) && !targetEnvironment(macCatalyst)
        externalProgramWindow?.isHidden = true
        externalProgramWindow?.rootViewController = nil
        externalProgramWindow = nil
#endif
    }

    private func triggerInkTransition() {
        inkTransitionResetWorkItem?.cancel()
        inkTransitionProgress = 0.001
        inkTransitionOpacity = 0.68
        withAnimation(.easeOut(duration: 0.75)) {
            inkTransitionProgress = 2.2
            inkTransitionOpacity = 0
        }

        // Fail-safe reset so the overlay can never remain washed over the canvas.
        let resetWorkItem = DispatchWorkItem {
            inkTransitionProgress = 2.2
            inkTransitionOpacity = 0
        }
        inkTransitionResetWorkItem = resetWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.82, execute: resetWorkItem)
    }
}

private struct SurfaceControlsPanel: View {
    @ObservedObject var sessionViewModel: SessionViewModel
    let isLightAppearance: Bool
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
                        .foregroundStyle(isLightAppearance ? Color.black.opacity(0.62) : .secondary)
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
                    value: sessionViewModel.parameterValue(for: descriptor),
                    hueShift: sessionViewModel.colorShiftHueCenterShift,
                    isLightAppearance: isLightAppearance,
                    noteInteraction: noteInteraction,
                    onHueShift: { delta in
                        noteInteraction()
                        sessionViewModel.adjustColorShiftHueCenter(by: delta)
                    },
                    onChange: { newValue in
                        sessionViewModel.updateParameter(descriptor, value: newValue)
                    }
                )
            }
        }
        .padding(20)
        .frame(maxWidth: 760, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(isLightAppearance ? Color.black.opacity(0.12) : Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: (isLightAppearance ? Color.white : Color.black).opacity(0.18), radius: 20, x: 0, y: 8)
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
    let value: ParameterValue
    let hueShift: Double
    let isLightAppearance: Bool
    let noteInteraction: () -> Void
    let onHueShift: (Double) -> Void
    let onChange: (ParameterValue) -> Void

    var body: some View {
        switch descriptor.controlStyle {
        case .slider:
            VStack(alignment: .leading, spacing: 10) {
                if descriptor.id == "mode.colorShift.excitementMode" {
                    let modeIndex = min(max(Int((value.scalarValue ?? 0).rounded()), 0), 2)
                    HStack {
                        Text(descriptor.title.uppercased())
                            .font(ChromaTypography.action)
                            .tracking(0.6)
                        Spacer(minLength: 12)
                        Text(colorShiftExcitementModeLabel(for: modeIndex).uppercased())
                            .font(ChromaTypography.metric.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Picker(
                        "",
                        selection: Binding(
                            get: { min(max(Int((value.scalarValue ?? 0).rounded()), 0), 2) },
                            set: { newValue in
                                noteInteraction()
                                onChange(.scalar(Double(newValue)))
                            }
                        )
                    ) {
                        Text("Spectral").tag(0)
                        Text("Temporal").tag(1)
                        Text("Pitch").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } else {
                    HStack {
                        Text(descriptor.title.uppercased())
                            .font(ChromaTypography.action)
                            .tracking(0.6)
                        Spacer(minLength: 12)
                        Text(String(format: "%.2f", value.scalarValue ?? 0))
                            .font(ChromaTypography.metric.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { value.scalarValue ?? 0 },
                            set: { newValue in
                                noteInteraction()
                                onChange(.scalar(newValue))
                            }
                        ),
                        in: (descriptor.minimumValue ?? 0) ... (descriptor.maximumValue ?? 1),
                        onEditingChanged: { _ in
                            noteInteraction()
                        }
                    )
                    .tint(isLightAppearance ? .black : .white)
                }
            }
        case .toggle:
            Toggle(isOn: Binding(
                get: { value.toggleValue ?? false },
                set: { isOn in
                    noteInteraction()
                    onChange(.toggle(isOn))
                }
            )) {
                Text(descriptor.title.uppercased())
                    .font(ChromaTypography.action)
                    .tracking(0.6)
            }
            .tint(isLightAppearance ? .black : .white)
        case .hueRange:
            let hueRange = value.hueRangeValue ?? (min: 0.13, max: 0.87, outside: false)
            HueRangeEditorRow(
                descriptor: descriptor,
                minValue: hueRange.min,
                maxValue: hueRange.max,
                outside: hueRange.outside,
                hueShift: hueShift,
                trackHeight: 22,
                showsModePicker: true,
                onChange: { minValue, maxValue, outside in
                    noteInteraction()
                    onChange(.hueRange(min: minValue, max: maxValue, outside: outside))
                },
                onShift: { delta in
                    onHueShift(delta)
                }
            )
        }
    }
}

private struct HueRangeEditorRow: View {
    let descriptor: ParameterDescriptor
    let minValue: Double
    let maxValue: Double
    let outside: Bool
    let hueShift: Double
    let trackHeight: CGFloat
    let showsModePicker: Bool
    let onChange: (Double, Double, Bool) -> Void
    let onShift: (Double) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var primaryLabelColor: Color {
        colorScheme == .light ? Color.black.opacity(0.84) : Color.white.opacity(0.84)
    }

    private var strongLabelColor: Color {
        colorScheme == .light ? Color.black.opacity(0.92) : Color.white.opacity(0.92)
    }

    private var secondaryLabelColor: Color {
        colorScheme == .light ? Color.black.opacity(0.76) : Color.white.opacity(0.78)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(descriptor.title.uppercased())
                    .font(ChromaTypography.overline)
                    .tracking(1.0)
                    .lineLimit(1)
                    .foregroundStyle(primaryLabelColor)

                Spacer(minLength: 4)

                if showsModePicker {
                    Picker("", selection: Binding(
                        get: { outside },
                        set: { newOutside in
                            onChange(minValue, maxValue, newOutside)
                        }
                    )) {
                        Text("Inside").tag(false)
                        Text("Outside").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 134)
                }

                Text("C \(hueDegrees(hueArcCenter(minValue: minValue, maxValue: maxValue, outside: outside, hueShift: hueShift)))°")
                    .font(ChromaTypography.metric.monospacedDigit())
                    .foregroundStyle(strongLabelColor)

                Text(
                    "\(hueDegrees(wrapUnitHue(minValue + hueShift)))° · \(hueDegrees(wrapUnitHue(maxValue + hueShift)))°"
                )
                .font(ChromaTypography.metric.monospacedDigit())
                .foregroundStyle(secondaryLabelColor)

                HueRangeTrimWheel(onDelta: onShift)
            }

            HueRangeTrack(
                minValue: minValue,
                maxValue: maxValue,
                outside: outside,
                hueShift: hueShift,
                trackHeight: trackHeight,
                onMinChange: { newMin in
                    onChange(newMin, maxValue, outside)
                },
                onMaxChange: { newMax in
                    onChange(minValue, newMax, outside)
                }
            )
            .frame(maxWidth: .infinity)
        }
    }
}

private struct HueRangeTrack: View {
    let minValue: Double
    let maxValue: Double
    let outside: Bool
    let hueShift: Double
    let trackHeight: CGFloat
    let onMinChange: (Double) -> Void
    let onMaxChange: (Double) -> Void
    @State private var activeHandle: HueRangeHandle?
    @Environment(\.colorScheme) private var colorScheme

    private enum HueRangeHandle {
        case min
        case max
    }

    private var hueGradient: LinearGradient {
        LinearGradient(
            stops: stride(from: 0.0, through: 1.0, by: 1.0 / 12.0).map { location in
                .init(color: Color(hue: wrapUnitHue(location + hueShift), saturation: 1, brightness: 1), location: location)
            },
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let trackWidth = max(proxy.size.width, 1)
            let trackHeight = max(proxy.size.height, 1)
            let handleDiameter = max(trackHeight + 8, 20)
            let handleRadius = handleDiameter * 0.5
            let travelWidth = max(trackWidth - handleDiameter, 1)
            let clampedMin = min(max(minValue, 0), 1)
            let clampedMax = min(max(maxValue, 0), 1)
            let minX = handleRadius + (CGFloat(clampedMin) * travelWidth)
            let maxX = handleRadius + (CGFloat(clampedMax) * travelWidth)

            ZStack {
                RoundedRectangle(cornerRadius: trackHeight * 0.5, style: .continuous)
                    .fill(hueGradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: trackHeight * 0.5, style: .continuous)
                            .fill(Color.black.opacity(0.36))
                    }
                    .overlay {
                        ZStack {
                            ForEach(Array(selectedHueIntervals(minValue: clampedMin, maxValue: clampedMax, outside: outside).enumerated()), id: \.offset) { _, interval in
                                let startX = CGFloat(interval.0) * trackWidth
                                let segmentWidth = max(CGFloat(interval.1 - interval.0) * trackWidth, 0)
                                hueGradient
                                    .frame(width: trackWidth, height: trackHeight)
                                    .mask(
                                        Rectangle()
                                            .frame(width: segmentWidth, height: trackHeight)
                                            .offset(x: startX - ((trackWidth - segmentWidth) * 0.5))
                                    )
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: trackHeight * 0.5, style: .continuous))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: trackHeight * 0.5, style: .continuous)
                            .stroke(
                                colorScheme == .light ? Color.black.opacity(0.20) : Color.white.opacity(0.28),
                                lineWidth: 1
                            )
                    }

                Circle()
                    .fill(.white)
                    .frame(width: handleDiameter, height: handleDiameter)
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.28), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.26), radius: 2, x: 0, y: 1)
                    .position(x: minX, y: trackHeight * 0.5)
                    .zIndex(activeHandle == .min ? 2 : 1)

                Circle()
                    .fill(.white)
                    .frame(width: handleDiameter, height: handleDiameter)
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.28), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.26), radius: 2, x: 0, y: 1)
                    .position(x: maxX, y: trackHeight * 0.5)
                    .zIndex(activeHandle == .max ? 2 : 1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let selectedHandle = activeHandle ?? (
                            abs(gesture.startLocation.x - minX) <= abs(gesture.startLocation.x - maxX)
                                ? .min
                                : .max
                        )
                        if activeHandle == nil {
                            activeHandle = selectedHandle
                        }

                        let normalized = ((gesture.location.x - handleRadius) / travelWidth).clamped(to: 0 ... 1)
                        switch selectedHandle {
                        case .min:
                            onMinChange(Double(normalized))
                        case .max:
                            onMaxChange(Double(normalized))
                        }
                    }
                    .onEnded { _ in
                        activeHandle = nil
                    }
            )
        }
        .frame(height: trackHeight)
    }
}

private struct HueRangeTrimWheel: View {
    let onDelta: (Double) -> Void
    @State private var lastTranslationY: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colorScheme == .light ? .black.opacity(0.12) : .white.opacity(0.12))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(colorScheme == .light ? .black.opacity(0.24) : .white.opacity(0.24), lineWidth: 1)
            VStack(spacing: 1) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                Text("TRIM")
                    .font(.system(size: 7, weight: .black, design: .rounded))
                    .tracking(0.6)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
            }
            .foregroundStyle(colorScheme == .light ? Color.black.opacity(0.92) : Color.white.opacity(0.92))
        }
        .frame(width: 30, height: 32)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    let deltaY = gesture.translation.height - lastTranslationY
                    lastTranslationY = gesture.translation.height
                    let rawDelta = Double(-deltaY / 280.0)
                    let clampedDelta = min(max(rawDelta, -0.06), 0.06)
                    guard abs(clampedDelta) > 0.00001 else { return }
                    onDelta(clampedDelta)
                }
                .onEnded { _ in
                    lastTranslationY = 0
                }
        )
    }
}

private func selectedHueIntervals(minValue: Double, maxValue: Double, outside: Bool) -> [(Double, Double)] {
    let clampedMin = min(max(minValue, 0), 1)
    let clampedMax = min(max(maxValue, 0), 1)
    let insideIntervals: [(Double, Double)] = clampedMin <= clampedMax
        ? [(clampedMin, clampedMax)]
        : [(clampedMin, 1), (0, clampedMax)]

    guard outside else {
        return insideIntervals
    }

    if clampedMin <= clampedMax {
        var intervals: [(Double, Double)] = []
        if clampedMin > 0 {
            intervals.append((0, clampedMin))
        }
        if clampedMax < 1 {
            intervals.append((clampedMax, 1))
        }
        return intervals
    }

    return [(clampedMax, clampedMin)]
}

private func hueArcCenter(minValue: Double, maxValue: Double, outside: Bool, hueShift: Double = 0) -> Double {
    let clampedMin = min(max(minValue, 0), 1)
    let clampedMax = min(max(maxValue, 0), 1)
    let insideWidth = wrapUnitHue(clampedMax - clampedMin)
    let (start, width): (Double, Double) = outside
        ? (clampedMax, max(1 - insideWidth, 0))
        : (clampedMin, insideWidth)
    return wrapUnitHue(start + (width * 0.5) + hueShift)
}

private func wrapUnitHue(_ value: Double) -> Double {
    let wrapped = value - floor(value)
    return wrapped < 0 ? wrapped + 1 : wrapped
}

private func hueDegrees(_ normalizedHue: Double) -> Int {
    let clamped = min(max(normalizedHue, 0), 1)
    return Int((clamped * 360).rounded()) % 360
}

private func colorShiftExcitementModeLabel(for index: Int) -> String {
    switch index {
    case 1:
        return "Temporal"
    case 2:
        return "Pitch"
    default:
        return "Spectral"
    }
}

private struct ActionTileButton: View {
    let title: String
    let systemImage: String
    let isLightAppearance: Bool
    let isFullscreenAction: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var symbolEffectToken = UUID()
    @State private var isHovered = false

    private var usesDesktopHoverAffordance: Bool {
#if targetEnvironment(macCatalyst)
        true
#else
        false
#endif
    }

    private var foregroundPrimary: Color {
        isLightAppearance ? Color.black.opacity(0.90) : Color.white
    }

    private var foregroundSecondary: Color {
        isLightAppearance ? Color.black.opacity(isFullscreenAction ? 0.92 : 0.72) : Color.white.opacity(isFullscreenAction ? 0.95 : 0.70)
    }

    private var iconBackground: Color {
        isLightAppearance ? Color.black.opacity(isFullscreenAction ? 0.12 : 0.08) : Color.white.opacity(isFullscreenAction ? 0.20 : 0.13)
    }

    private var strokeColor: Color {
        isLightAppearance
            ? Color.black.opacity(isFullscreenAction ? (isHovered ? 0.28 : 0.20) : (isHovered ? 0.20 : 0.14))
            : Color.white.opacity(
                isFullscreenAction
                    ? (isHovered ? 0.30 : 0.22)
                    : (isHovered ? 0.22 : 0.14)
            )
    }

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
                    .foregroundStyle(foregroundPrimary)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 110, maxHeight: 110, alignment: .topLeading)
            .padding(14)
            .contentShape(Rectangle())
        }
        .contentShape(shape)
        .buttonStyle(
            ChromaActionTileButtonStyle(
                isHovered: isHovered,
                enableDesktopHover: usesDesktopHoverAffordance
            )
        )
        .chromaGlassTileBackground(in: shape, isEmphasized: isFullscreenAction, isLightAppearance: isLightAppearance)
        .overlay {
            shape
                .stroke(strokeColor, lineWidth: 1)
        }
        .shadow(
            color: (isLightAppearance ? Color.white : Color.black).opacity(isFullscreenAction ? (isHovered ? 0.34 : 0.26) : (isHovered ? 0.24 : 0.16)),
            radius: isFullscreenAction ? (isHovered ? 22 : 18) : (isHovered ? 16 : 12),
            x: 0,
            y: 6
        )
        .onAppear {
            guard !reduceMotion else { return }
            symbolEffectToken = UUID()
        }
#if targetEnvironment(macCatalyst)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
#endif
    }

    @ViewBuilder
    private var tileIcon: some View {
        let icon = Image(systemName: systemImage)
            .font(.system(size: 24, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(foregroundPrimary, foregroundSecondary)
            .padding(10)
            .background(iconBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

        if reduceMotion {
            icon
        } else if #available(iOS 18.0, macCatalyst 18.0, *) {
            icon.symbolEffect(.wiggle.byLayer, value: symbolEffectToken)
        } else {
            icon
        }
    }
}

private struct ChromaActionTileButtonStyle: ButtonStyle {
    let isHovered: Bool
    let enableDesktopHover: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : (enableDesktopHover && isHovered ? 1.01 : 1.0))
            .brightness(configuration.isPressed ? -0.04 : (enableDesktopHover && isHovered ? 0.015 : 0))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ActionMasterTile: View {
    @ObservedObject var sessionViewModel: SessionViewModel
    let isLightAppearance: Bool
    let savePreset: () -> Preset?
    let noteInteraction: () -> Void

    @State private var selectedControlID: String?
    @State private var isSavePresetSelected = false
    @State private var lastSavedPresetName: String?

    private let iconTrackSpacing: CGFloat = 10
    private let tileBodyHeight: CGFloat = 110

    private var foregroundPrimary: Color {
        isLightAppearance ? Color.black.opacity(0.90) : Color.white
    }

    private var foregroundSecondary: Color {
        isLightAppearance ? Color.black.opacity(0.70) : Color.white.opacity(0.72)
    }

    private var chipFill: Color {
        isLightAppearance ? Color.black.opacity(0.10) : Color.white.opacity(0.12)
    }

    private var chipStroke: Color {
        isLightAppearance ? Color.black.opacity(0.10) : Color.white.opacity(0.08)
    }

    private var liveControlDescriptors: [ParameterDescriptor] {
        sessionViewModel.primarySurfaceControlDescriptors
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        ZStack {
            if isSavePresetSelected {
                expandedSavePresetRow
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if let descriptor = selectedControlDescriptor {
                expandedControlRow(for: descriptor)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                iconDeckPane
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: tileBodyHeight, maxHeight: tileBodyHeight, alignment: .center)
        .animation(.easeInOut(duration: 0.2), value: selectedControlID)
        .animation(.easeInOut(duration: 0.2), value: isSavePresetSelected)
        .padding(14)
        .chromaGlassTileBackground(in: shape, isEmphasized: false, isLightAppearance: isLightAppearance)
        .overlay {
            shape
                .stroke(isLightAppearance ? Color.black.opacity(0.14) : Color.white.opacity(0.14), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, minHeight: tileBodyHeight + 28, maxHeight: tileBodyHeight + 28, alignment: .topLeading)
        .shadow(color: (isLightAppearance ? Color.white : Color.black).opacity(0.18), radius: 14, x: 0, y: 6)
        .onChange(of: liveControlDescriptors.map(\.id)) { _, ids in
            if let selectedControlID, !ids.contains(selectedControlID) {
                self.selectedControlID = nil
            }
        }
    }

    private var selectedControlDescriptor: ParameterDescriptor? {
        guard let selectedControlID else { return nil }
        return liveControlDescriptors.first(where: { $0.id == selectedControlID })
    }

    private var iconDeckPane: some View {
        HStack(spacing: iconTrackSpacing) {
            ForEach(liveControlDescriptors) { descriptor in
                controlIconButton(descriptor)
                    .frame(maxWidth: .infinity)
            }
            savePresetIconButton
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, iconTrackSpacing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func controlIconButton(_ descriptor: ParameterDescriptor) -> some View {
        Button {
            selectControl(descriptor.id)
        } label: {
            Image(systemName: iconName(for: descriptor))
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(foregroundPrimary, foregroundSecondary)
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(chipFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(chipStroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var savePresetIconButton: some View {
        Button {
            selectSavePreset()
        } label: {
            Image(systemName: "arrow.down.to.line")
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(foregroundPrimary, foregroundSecondary)
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(chipFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(chipStroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func selectControl(_ descriptorID: String) {
        noteInteraction()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            if selectedControlID == descriptorID, !isSavePresetSelected {
                selectedControlID = nil
            } else {
                selectedControlID = descriptorID
                isSavePresetSelected = false
            }
        }
    }

    private func selectSavePreset() {
        noteInteraction()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            if isSavePresetSelected {
                isSavePresetSelected = false
            } else {
                selectedControlID = nil
                isSavePresetSelected = true
            }
        }
    }

    private func expandedControlRow(for descriptor: ParameterDescriptor) -> some View {
        HStack(spacing: iconTrackSpacing) {
            Button {
                selectControl(descriptor.id)
            } label: {
                Image(systemName: iconName(for: descriptor))
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(foregroundPrimary, foregroundSecondary)
                    .frame(width: 52, height: 44, alignment: .center)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isLightAppearance ? Color.black.opacity(0.16) : Color.white.opacity(0.22))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isLightAppearance ? Color.black.opacity(0.18) : Color.white.opacity(0.18), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                switch descriptor.controlStyle {
                case .slider:
                    if descriptor.id == "mode.colorShift.excitementMode" {
                        let modeIndex = min(max(Int((sessionViewModel.parameterValue(for: descriptor).scalarValue ?? 0).rounded()), 0), 2)
                        HStack(spacing: 8) {
                            Text(descriptor.title.uppercased())
                                .font(ChromaTypography.overline)
                                .tracking(1.1)
                                .lineLimit(1)
                                .foregroundStyle(foregroundPrimary.opacity(0.80))
                            Spacer(minLength: 6)
                            Text(colorShiftExcitementModeLabel(for: modeIndex).uppercased())
                                .font(ChromaTypography.metric.monospacedDigit())
                                .foregroundStyle(foregroundSecondary)
                        }

                        Picker(
                            "",
                            selection: Binding(
                                get: {
                                    min(max(Int((sessionViewModel.parameterValue(for: descriptor).scalarValue ?? 0).rounded()), 0), 2)
                                },
                                set: { newValue in
                                    noteInteraction()
                                    sessionViewModel.updateParameter(descriptor, value: .scalar(Double(newValue)))
                                }
                            )
                        ) {
                            Text("Spectral").tag(0)
                            Text("Temporal").tag(1)
                            Text("Pitch").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    } else {
                        HStack(spacing: 8) {
                            Text(descriptor.title.uppercased())
                                .font(ChromaTypography.overline)
                                .tracking(1.1)
                                .lineLimit(1)
                                .foregroundStyle(foregroundPrimary.opacity(0.80))

                            Spacer(minLength: 6)

                            Text(String(format: "%.2f", sessionViewModel.parameterValue(for: descriptor).scalarValue ?? 0))
                                .font(ChromaTypography.metric.monospacedDigit())
                                .foregroundStyle(foregroundSecondary)
                        }

                        Slider(
                            value: Binding(
                                get: { sessionViewModel.parameterValue(for: descriptor).scalarValue ?? 0 },
                                set: { newValue in
                                    noteInteraction()
                                    sessionViewModel.updateParameter(descriptor, value: .scalar(newValue))
                                }
                            ),
                            in: (descriptor.minimumValue ?? 0) ... (descriptor.maximumValue ?? 1),
                            onEditingChanged: { _ in noteInteraction() }
                        )
                        .tint(isLightAppearance ? .black : .white)
                    }
                case .toggle:
                    Toggle(isOn: Binding(
                        get: { sessionViewModel.parameterValue(for: descriptor).toggleValue ?? false },
                        set: { isOn in
                            noteInteraction()
                            sessionViewModel.updateParameter(descriptor, value: .toggle(isOn))
                        }
                    )) {
                        Text(descriptor.title.uppercased())
                            .font(ChromaTypography.overline)
                            .tracking(1.1)
                            .lineLimit(1)
                            .foregroundStyle(foregroundPrimary.opacity(0.80))
                    }
                    .tint(isLightAppearance ? .black : .white)
                case .hueRange:
                    let value = sessionViewModel.parameterValue(for: descriptor).hueRangeValue ?? (min: 0.13, max: 0.87, outside: false)
                    HueRangeEditorRow(
                        descriptor: descriptor,
                        minValue: value.min,
                        maxValue: value.max,
                        outside: value.outside,
                        hueShift: sessionViewModel.colorShiftHueCenterShift,
                        trackHeight: 18,
                        showsModePicker: true,
                        onChange: { minValue, maxValue, outside in
                            noteInteraction()
                            sessionViewModel.updateParameter(
                                descriptor,
                                value: .hueRange(min: minValue, max: maxValue, outside: outside)
                            )
                        },
                        onShift: { delta in
                            noteInteraction()
                            sessionViewModel.adjustColorShiftHueCenter(by: delta)
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, iconTrackSpacing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var expandedSavePresetRow: some View {
        HStack(spacing: iconTrackSpacing) {
            Button {
                selectSavePreset()
            } label: {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(foregroundPrimary, foregroundSecondary)
                    .frame(width: 52, height: 44, alignment: .center)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isLightAppearance ? Color.black.opacity(0.16) : Color.white.opacity(0.22))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isLightAppearance ? Color.black.opacity(0.18) : Color.white.opacity(0.18), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)

            Button {
                noteInteraction()
                if let preset = savePreset() {
                    lastSavedPresetName = preset.name
                }
            } label: {
                VStack(spacing: 2) {
                    Text("QUICK SAVE NEW PRESET")
                        .font(ChromaTypography.overline)
                        .tracking(1.1)
                        .lineLimit(1)
                    if let lastSavedPresetName {
                        Text("Saved \(lastSavedPresetName)")
                            .font(ChromaTypography.metric)
                            .foregroundStyle(foregroundSecondary)
                            .lineLimit(1)
                    } else {
                        Text("Rename from Presets")
                            .font(ChromaTypography.metric)
                            .foregroundStyle(foregroundSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(foregroundPrimary)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isLightAppearance ? Color.black.opacity(0.12) : Color.white.opacity(0.14))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isLightAppearance ? Color.black.opacity(0.12) : Color.white.opacity(0.10), lineWidth: 1)
            }
        }
        .padding(.horizontal, iconTrackSpacing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func iconName(for descriptor: ParameterDescriptor) -> String {
        switch descriptor.id {
        case "response.inputGain":
            return "mic.fill"
        case "response.smoothing":
            return "waveform.path.ecg"
        case "output.blackFloor":
            return "moon.stars.fill"
        case "output.noImageInSilence":
            return "speaker.slash.fill"
        case "mode.colorShift.hueResponse":
            return "dial.medium.fill"
        case "mode.colorShift.hueRange":
            return "circle.lefthalf.filled"
        case "mode.colorShift.excitementMode":
            return "arrow.left.and.right.circle.fill"
        case "mode.prismField.facetDensity":
            return "arrow.triangle.2.circlepath"
        case "mode.prismField.dispersion":
            return "sparkles"
        case "mode.tunnelCels.shapeScale":
            return "square.resize"
        case "mode.tunnelCels.depthSpeed":
            return "arrow.forward.to.line"
        case "mode.tunnelCels.releaseTail":
            return "waveform.path"
        case "mode.fractalCaustics.detail", "mode.riemannCorridor.detail":
            return "scope"
        case "mode.fractalCaustics.flowRate", "mode.riemannCorridor.flowRate":
            return "wind"
        case "mode.fractalCaustics.attackBloom", "mode.riemannCorridor.zeroBloom":
            return "bolt.fill"
        default:
            return "slider.horizontal.3"
        }
    }

}

private struct AppearanceInkTransitionOverlay: View {
    let color: Color
    let progress: CGFloat
    let opacity: Double

    var body: some View {
        GeometryReader { proxy in
            let radius = max(proxy.size.width, proxy.size.height) * 0.95
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            color.opacity(0.52),
                            color.opacity(0.16),
                            color.opacity(0.00),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
                .frame(width: radius * 2, height: radius * 2)
                .scaleEffect(progress)
                .opacity(opacity)
                .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)
        }
    }
}

private extension View {
    @ViewBuilder
    func chromaGlassTileBackground<S: Shape>(in shape: S, isEmphasized: Bool, isLightAppearance: Bool) -> some View {
        let baseOpacity = isEmphasized ? 0.16 : 0.10
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            self
                .background(
                    (isLightAppearance ? Color.white.opacity(baseOpacity + 0.24) : Color.white.opacity(baseOpacity)),
                    in: shape
                )
                .glassEffect(
                    .regular
                        .tint(
                            isLightAppearance
                                ? Color.black.opacity(isEmphasized ? 0.09 : 0.06)
                                : Color.white.opacity(baseOpacity)
                        )
                        .interactive(),
                    in: shape
                )
        } else {
            self
                .background(
                    isLightAppearance
                        ? AnyShapeStyle(.ultraThinMaterial)
                        : AnyShapeStyle(.regularMaterial),
                    in: shape
                )
        }
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
