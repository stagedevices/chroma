import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AVKit)
import AVKit
#endif
#if canImport(Photos)
import Photos
#endif

struct ModePickerSheet: View {
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var sessionViewModel: SessionViewModel
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draftState: ModePickerDraftState
    @State private var pageMotionToken = UUID()
    @State private var applyMotionToken = UUID()

    init(appViewModel: AppViewModel, sessionViewModel: SessionViewModel, dismiss: @escaping () -> Void) {
        self.appViewModel = appViewModel
        self.sessionViewModel = sessionViewModel
        self.dismiss = dismiss
        _draftState = State(initialValue: ModePickerDraftState(activeModeID: sessionViewModel.session.activeModeID))
    }

    private var selectedModeIDBinding: Binding<VisualModeID> {
        Binding(
            get: { draftState.selectedModeID },
            set: { nextModeID in
                draftState.preview(nextModeID)
            }
        )
    }

    private var selectedModeDescriptor: VisualModeDescriptor {
        sessionViewModel.availableModes.first(where: { $0.id == draftState.selectedModeID })
            ?? sessionViewModel.activeModeDescriptor
    }

    private var selectedModePresentation: ModePickerHeroPresentation {
        modePickerHeroPresentation(for: selectedModeDescriptor.id)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TabView(selection: selectedModeIDBinding) {
                    ForEach(sessionViewModel.availableModes) { mode in
                        let presentation = modePickerHeroPresentation(for: mode.id)
                        ModePickerHeroPage(
                            mode: mode,
                            presentation: presentation,
                            isSelected: mode.id == draftState.selectedModeID,
                            pageMotionToken: pageMotionToken,
                            reduceMotion: reduceMotion,
                            showsLockedBadge: ProEntitlement.requiresPro(.mode(mode.id)) && !appViewModel.billingStore.proAccessVisualState.hasFeatureAccess
                        )
                        .tag(mode.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .padding(.top, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                modePaginationDots
                    .padding(.top, 2)

                applyButton
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .font(ChromaTypography.body)
            .navigationTitle("MODES")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetToolbarCloseButton(action: dismiss)
                }
            }
            .onChange(of: draftState.selectedModeID) { _, _ in
                guard !reduceMotion else { return }
                pageMotionToken = UUID()
            }
            .onChange(of: sessionViewModel.session.activeModeID) { _, activeModeID in
                if draftState.initialModeID == activeModeID {
                    return
                }
                draftState = ModePickerDraftState(activeModeID: activeModeID)
            }
            .onAppear {
                if sessionViewModel.availableModes.contains(where: { $0.id == draftState.selectedModeID }) {
                    return
                }
                if let first = sessionViewModel.availableModes.first?.id {
                    draftState = ModePickerDraftState(activeModeID: first)
                }
            }
        }
    }

    private var modePaginationDots: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(spacing: 8) {
                ForEach(sessionViewModel.availableModes) { mode in
                    let isActive = mode.id == draftState.selectedModeID
                    Capsule()
                        .fill(
                            isActive
                                ? selectedModePresentation.accentColor.opacity(sessionViewModel.isLightGlassAppearance ? 0.94 : 0.98)
                                : Color.secondary.opacity(sessionViewModel.isLightGlassAppearance ? 0.35 : 0.48)
                        )
                        .frame(width: isActive ? 24 : 8, height: 8)
                        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: draftState.selectedModeID)
                }
            }

            Spacer(minLength: 0)

            customShortcutChip
        }
    }

    private var customShortcutChip: some View {
        let isCustomSelected = draftState.selectedModeID == .custom
        let customPresentation = modePickerHeroPresentation(for: .custom)
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                draftState.preview(.custom)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 10, weight: .bold))
                Text("CUSTOM")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isCustomSelected
                    ? customPresentation.accentColor.opacity(0.28)
                    : Color.secondary.opacity(0.12),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        isCustomSelected
                            ? customPresentation.accentColor.opacity(0.5)
                            : Color.clear,
                        lineWidth: 1
                    )
            }
            .foregroundStyle(isCustomSelected ? customPresentation.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var applyButton: some View {
        Button {
            if !reduceMotion {
                applyMotionToken = UUID()
            }
            performImpactHaptic()

            let selectedModeID = draftState.activeModeAfterApply()
            if ProEntitlement.requiresPro(.mode(selectedModeID)),
               !appViewModel.billingStore.proAccessVisualState.hasFeatureAccess {
                appViewModel.presentPaywall(entryPoint: .mode(selectedModeID), dismissingPresentedSheet: true)
                return
            }

            sessionViewModel.selectMode(selectedModeID)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                applyIcon
                Text(
                    (
                        ProEntitlement.requiresPro(.mode(selectedModeDescriptor.id)) &&
                        !appViewModel.billingStore.proAccessVisualState.hasFeatureAccess
                    )
                    ? "UNLOCK \(selectedModeDescriptor.name.uppercased())"
                    : "SWITCH TO \(selectedModeDescriptor.name.uppercased())"
                )
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .modePickerApplyButtonBackground(
                accentGradient: selectedModePresentation.accentGradient,
                borderColor: selectedModePresentation.accentColor,
                isLightAppearance: sessionViewModel.isLightGlassAppearance
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Applies the selected mode and closes this sheet.")
    }

    @ViewBuilder
    private var applyIcon: some View {
        let icon = Image(systemName: selectedModePresentation.systemImage)
            .font(.system(size: 18, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                sessionViewModel.isLightGlassAppearance ? Color.black.opacity(0.90) : Color.white.opacity(0.96),
                selectedModePresentation.accentColor
            )
            .frame(width: 34, height: 34)
            .background(
                sessionViewModel.isLightGlassAppearance ? Color.black.opacity(0.10) : Color.white.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )

        if reduceMotion {
            icon
        } else if #available(iOS 18.0, macCatalyst 18.0, *) {
            icon.symbolEffect(.bounce, value: applyMotionToken)
        } else {
            icon
        }
    }

    private func performImpactHaptic() {
#if canImport(UIKit) && !targetEnvironment(macCatalyst)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
#endif
    }
}

struct ModePickerDraftState {
    let initialModeID: VisualModeID
    private(set) var selectedModeID: VisualModeID

    init(activeModeID: VisualModeID) {
        initialModeID = activeModeID
        selectedModeID = activeModeID
    }

    mutating func preview(_ modeID: VisualModeID) {
        selectedModeID = modeID
    }

    func activeModeAfterDismissWithoutApply() -> VisualModeID {
        initialModeID
    }

    func activeModeAfterApply() -> VisualModeID {
        selectedModeID
    }
}

struct ModePickerHeroPresentation {
    let systemImage: String
    let tagline: String
    let behaviorTags: [String]
    let accentStartHue: Double
    let accentEndHue: Double

    var accentColor: Color {
        Color(hue: accentStartHue, saturation: 0.80, brightness: 0.96)
    }

    var accentGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hue: accentStartHue, saturation: 0.82, brightness: 0.95),
                Color(hue: accentEndHue, saturation: 0.84, brightness: 0.98),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

func modePickerHeroPresentationMap() -> [VisualModeID: ModePickerHeroPresentation] {
    [
        .colorShift: ModePickerHeroPresentation(
            systemImage: "rainbow",
            tagline: "Flat Hue Instrument",
            behaviorTags: ["Tone-Locked", "Directional PWM", "Color Feedback"],
            accentStartHue: 0.56,
            accentEndHue: 0.82
        ),
        .prismField: ModePickerHeroPresentation(
            systemImage: "rays",
            tagline: "Refracted Stage Flow",
            behaviorTags: ["Facet Field", "Dispersion", "Attack Shards"],
            accentStartHue: 0.62,
            accentEndHue: 0.88
        ),
        .tunnelCels: ModePickerHeroPresentation(
            systemImage: "square.stack.3d.up.fill",
            tagline: "Attack Shapes in Depth",
            behaviorTags: ["ADSR Cels", "Infinite Tunnel", "Variant Stacks"],
            accentStartHue: 0.50,
            accentEndHue: 0.70
        ),
        .fractalCaustics: ModePickerHeroPresentation(
            systemImage: "snowflake",
            tagline: "Orbit-Driven Fractal Field",
            behaviorTags: ["Julia Core", "Pulse Events", "Palette Banks"],
            accentStartHue: 0.74,
            accentEndHue: 0.96
        ),
        .riemannCorridor: ModePickerHeroPresentation(
            systemImage: "infinity",
            tagline: "Classic Mandelbrot Flight",
            behaviorTags: ["Boundary Zoom", "Guided POIs", "Stream Variants"],
            accentStartHue: 0.60,
            accentEndHue: 0.84
        ),
        .custom: ModePickerHeroPresentation(
            systemImage: "point.3.connected.trianglepath.dotted",
            tagline: "Node Graph Builder",
            behaviorTags: ["Patch Canvas", "Node Graph", "Live Output"],
            accentStartHue: 0.10,
            accentEndHue: 0.32
        ),
    ]
}

func modePickerHeroPresentation(for modeID: VisualModeID) -> ModePickerHeroPresentation {
    modePickerHeroPresentationMap()[modeID] ?? ModePickerHeroPresentation(
        systemImage: "sparkles",
        tagline: "Visual Mode",
        behaviorTags: ["Live", "Reactive", "Stage"],
        accentStartHue: 0.56,
        accentEndHue: 0.80
    )
}

private struct ModePickerHeroPage: View {
    let mode: VisualModeDescriptor
    let presentation: ModePickerHeroPresentation
    let isSelected: Bool
    let pageMotionToken: UUID
    let reduceMotion: Bool
    let showsLockedBadge: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(presentation.accentGradient.opacity(0.24))
                    .overlay {
                        Circle()
                            .stroke(presentation.accentColor.opacity(0.34), lineWidth: 1)
                    }
                    .frame(width: 140, height: 140)

                heroIcon
            }
            .frame(width: 148, height: 148)
            .frame(maxWidth: .infinity, alignment: .center)

            VStack(spacing: 8) {
                Text(mode.name.uppercased())
                    .font(.system(size: 31, weight: .black, design: .rounded))
                    .tracking(0.8)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(mode.summary)
                    .font(ChromaTypography.bodySecondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 8)
            }

            HStack(spacing: 8) {
                ForEach(presentation.behaviorTags.prefix(3), id: \.self) { tag in
                    Text(tag.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            Color.secondary.opacity(0.15),
                            in: Capsule()
                        )
                }
            }

            Spacer(minLength: 0)
        }
        .overlay(alignment: .topTrailing) {
            if showsLockedBadge {
                ChromaProBadge(style: .locked)
                    .padding(.top, 6)
                    .padding(.trailing, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private var heroIcon: some View {
        let icon = Image(systemName: presentation.systemImage)
            .resizable()
            .scaledToFit()
            .frame(width: 68, height: 68)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white.opacity(0.95), presentation.accentColor)
            .frame(width: 80, height: 80)

        if reduceMotion {
            icon
                .scaleEffect(isSelected ? 1.0 : 0.88)
                .opacity(isSelected ? 1.0 : 0.76)
        } else {
            icon
                .symbolEffect(.bounce.byLayer, value: pageMotionToken)
                .symbolEffect(.breathe, isActive: mode.id == .colorShift && isSelected)
                .symbolEffect(.rotate, isActive: mode.id == .prismField && isSelected)
                .symbolEffect(.variableColor.iterative.reversing, isActive: mode.id == .tunnelCels && isSelected)
                .symbolEffect(.variableColor.cumulative, isActive: mode.id == .fractalCaustics && isSelected)
                .symbolEffect(.rotate, isActive: mode.id == .riemannCorridor && isSelected)
                .symbolEffect(.wiggle, isActive: mode.id == .custom && isSelected)
                .scaleEffect(isSelected ? 1.0 : 0.88)
                .opacity(isSelected ? 1.0 : 0.68)
                .animation(.spring(response: 0.36, dampingFraction: 0.76), value: isSelected)
        }
    }
}

struct CustomPatchBuilderSheet: View {
    @ObservedObject var sessionViewModel: SessionViewModel
    let dismiss: () -> Void

    @State private var renameDraft = ""
    @State private var selectedNodeID: UUID?
    @State private var multiSelectedNodeIDs: Set<UUID> = []
    @State private var showExportShare = false
    @State private var groupNameDraft = ""

    private var activePatch: CustomPatch? {
        sessionViewModel.activeCustomPatch
    }

    private var isLightAppearance: Bool {
        sessionViewModel.isLightGlassAppearance
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                patchHeader
                toolStrip
                builderWorkspace
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .font(ChromaTypography.body)
            .navigationTitle("CUSTOM BUILDER")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetToolbarCloseButton(action: dismiss)
                }
            }
            .onAppear {
                syncRenameDraft()
            }
            .onChange(of: activePatch?.id) { _, _ in
                syncRenameDraft()
                selectedNodeID = nil
                multiSelectedNodeIDs.removeAll()
            }
        }
    }

    private var patchHeader: some View {
        HStack(spacing: 8) {
            Picker(
                "Patch",
                selection: Binding<UUID?>(
                    get: { activePatch?.id },
                    set: { nextID in
                        guard let nextID else { return }
                        sessionViewModel.selectCustomPatch(id: nextID)
                    }
                )
            ) {
                ForEach(sessionViewModel.customPatches) { patch in
                    Text(patch.name).tag(Optional(patch.id))
                }
            }
            .pickerStyle(.menu)
            .lineLimit(1)

            Spacer(minLength: 4)

            TextField("Rename", text: $renameDraft)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .onSubmit { commitRename() }
                .font(ChromaTypography.metric)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: 180)
                .background(
                    isLightAppearance ? Color.black.opacity(0.08) : Color.white.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )

            Button {
                commitRename()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(isLightAppearance ? .black : .white)
            .foregroundStyle(isLightAppearance ? Color.white : Color.black)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .recorderGlassCardBackground(cornerRadius: 14, isLightAppearance: isLightAppearance)
    }

    private var toolStrip: some View {
        HStack(spacing: 6) {
            // Undo / Redo
            Button { sessionViewModel.undoPatchEdit() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .semibold))
            }
            .disabled(!sessionViewModel.canUndoPatch)

            Button { sessionViewModel.redoPatchEdit() } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 14, weight: .semibold))
            }
            .disabled(!sessionViewModel.canRedoPatch)

            Divider().frame(height: 18).padding(.horizontal, 4)

            // Copy / Paste
            Button {
                var ids = multiSelectedNodeIDs
                if let sel = selectedNodeID { ids.insert(sel) }
                sessionViewModel.copyNodesFromActiveCustomPatch(nodeIDs: ids)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
            }
            .disabled(selectedNodeID == nil && multiSelectedNodeIDs.isEmpty)

            Button {
                sessionViewModel.pasteNodesIntoActiveCustomPatch()
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 13, weight: .semibold))
            }
            .disabled(sessionViewModel.patchClipboard == nil)

            Divider().frame(height: 18).padding(.horizontal, 4)

            // Duplicate patch
            Button {
                sessionViewModel.duplicateActiveCustomPatch()
            } label: {
                Image(systemName: "plus.square.on.square")
                    .font(.system(size: 13, weight: .semibold))
            }

            // Export
            Button {
                exportPatchToClipboard()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .semibold))
            }

            // Import
            Button {
                importPatchFromClipboard()
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 13, weight: .semibold))
            }

            Spacer(minLength: 0)

            // Node count
            if let patch = activePatch {
                Text("\(patch.nodes.count) NODES")
                    .font(ChromaTypography.metric.monospacedDigit())
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .recorderGlassCardBackground(cornerRadius: 14, isLightAppearance: isLightAppearance)
    }

    private var builderWorkspace: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                CustomPatchNodeLibraryRail(
                    isLightAppearance: isLightAppearance,
                    onAddNode: addNode
                )
                .frame(width: 156)

                CustomPatchGraphCanvas(
                    patch: activePatch,
                    isLightAppearance: isLightAppearance,
                    selectedNodeID: $selectedNodeID,
                    onMoveNode: { nodeID, position in
                        sessionViewModel.moveNodeInActiveCustomPatch(nodeID: nodeID, to: position)
                    },
                    onConnect: { fromNodeID, fromPort, toNodeID, toPort in
                        sessionViewModel.addConnectionToActiveCustomPatch(
                            fromNodeID: fromNodeID, fromPort: fromPort,
                            toNodeID: toNodeID, toPort: toPort
                        )
                    },
                    onDeleteConnection: { connectionID in
                        sessionViewModel.removeConnectionFromActiveCustomPatch(connectionID: connectionID)
                    },
                    onViewportChange: { viewport in
                        sessionViewModel.updateViewportInActiveCustomPatch(viewport: viewport)
                    }
                )

                inspectorPane
                .frame(width: 218)
            }

            VStack(spacing: 10) {
                CustomPatchGraphCanvas(
                    patch: activePatch,
                    isLightAppearance: isLightAppearance,
                    selectedNodeID: $selectedNodeID,
                    onMoveNode: { nodeID, position in
                        sessionViewModel.moveNodeInActiveCustomPatch(nodeID: nodeID, to: position)
                    },
                    onConnect: { fromNodeID, fromPort, toNodeID, toPort in
                        sessionViewModel.addConnectionToActiveCustomPatch(
                            fromNodeID: fromNodeID, fromPort: fromPort,
                            toNodeID: toNodeID, toPort: toPort
                        )
                    },
                    onDeleteConnection: { connectionID in
                        sessionViewModel.removeConnectionFromActiveCustomPatch(connectionID: connectionID)
                    },
                    onViewportChange: { viewport in
                        sessionViewModel.updateViewportInActiveCustomPatch(viewport: viewport)
                    }
                )

                HStack(spacing: 10) {
                    CustomPatchNodeLibraryRail(
                        isLightAppearance: isLightAppearance,
                        onAddNode: addNode
                    )
                    inspectorPane
                }
                .frame(height: 186)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspectorPane: some View {
        CustomPatchInspectorPane(
            patch: activePatch,
            selectedNodeID: selectedNodeID,
            isLightAppearance: isLightAppearance,
            nodeTimings: sessionViewModel.rendererService.patchNodeTimings,
            onParameterChange: { nodeID, paramName, value in
                sessionViewModel.updateNodeParameterInActiveCustomPatch(
                    nodeID: nodeID, parameterName: paramName, value: value
                )
            },
            onDeleteNode: { nodeID in
                if selectedNodeID == nodeID { selectedNodeID = nil }
                sessionViewModel.deleteNodeFromActiveCustomPatch(nodeID: nodeID)
            },
            onGroupSelected: { nodeIDs, name in
                sessionViewModel.groupNodesInActiveCustomPatch(nodeIDs: nodeIDs, name: name)
            },
            onUngroup: { groupID in
                sessionViewModel.ungroupInActiveCustomPatch(groupID: groupID)
            }
        )
    }

    private func addNode(kind: CustomPatchNodeKind) {
        let viewport = activePatch?.viewport ?? CustomPatchViewport()
        let position = CustomPatchPoint(
            x: 300 - viewport.offsetX + Double.random(in: -20...20),
            y: 200 - viewport.offsetY + Double.random(in: -20...20)
        )
        sessionViewModel.addNodeToActiveCustomPatch(kind: kind, at: position)
    }

    private func exportPatchToClipboard() {
        guard let data = sessionViewModel.exportActiveCustomPatch(),
              let json = String(data: data, encoding: .utf8) else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = json
        #endif
    }

    private func importPatchFromClipboard() {
        #if canImport(UIKit)
        guard let json = UIPasteboard.general.string,
              let data = json.data(using: .utf8) else { return }
        _ = sessionViewModel.importCustomPatch(from: data)
        #endif
    }

    private func syncRenameDraft() {
        renameDraft = activePatch?.name ?? ""
    }

    private func commitRename() {
        sessionViewModel.renameActiveCustomPatch(renameDraft)
        syncRenameDraft()
    }
}

// MARK: - Node Library Rail

private struct CustomPatchNodeLibraryRail: View {
    let isLightAppearance: Bool
    let onAddNode: (CustomPatchNodeKind) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("NODE LIBRARY")
                    .font(ChromaTypography.overline)
                    .tracking(1.1)
                    .foregroundStyle(.secondary)

                ForEach(CustomPatchNodeKind.allCases, id: \.self) { kind in
                    Button {
                        onAddNode(kind)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.orange.opacity(0.86))
                            Text(kind.displayName.uppercased())
                                .font(ChromaTypography.metric)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            isLightAppearance ? Color.black.opacity(0.07) : Color.white.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .recorderGlassCardBackground(cornerRadius: 16, isLightAppearance: isLightAppearance)
    }
}

// MARK: - Inspector Pane

private struct CustomPatchInspectorPane: View {
    let patch: CustomPatch?
    let selectedNodeID: UUID?
    let isLightAppearance: Bool
    let nodeTimings: [UUID: Double]
    let onParameterChange: (UUID, String, Double) -> Void
    let onDeleteNode: (UUID) -> Void
    let onGroupSelected: (Set<UUID>, String) -> Void
    let onUngroup: (UUID) -> Void

    @State private var groupNameDraft = ""

    private var selectedNode: CustomPatchNode? {
        guard let patch, let selectedNodeID else { return nil }
        return patch.nodes.first(where: { $0.id == selectedNodeID })
    }

    private var selectedNodeGroup: CustomPatchGroup? {
        guard let patch, let selectedNodeID else { return nil }
        return patch.groups.first(where: { $0.nodeIDs.contains(selectedNodeID) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("INSPECTOR")
                    .font(ChromaTypography.overline)
                    .tracking(1.1)
                    .foregroundStyle(.secondary)

                if let selectedNode, let selectedNodeID {
                    Text(selectedNode.title.uppercased())
                        .font(ChromaTypography.sheetRowTitle)
                    Text(selectedNode.kind.displayName)
                        .font(ChromaTypography.bodySecondary)
                        .foregroundStyle(.secondary)
                    inspectorRow("Inputs", "\(selectedNode.inputPorts.count)")
                    inspectorRow("Outputs", "\(selectedNode.outputPorts.count)")

                    // Performance profiling
                    if let timing = nodeTimings[selectedNodeID] {
                        inspectorRow("CPU", String(format: "%.2f ms", timing))
                    }

                    if !selectedNode.parameters.isEmpty {
                        Divider().padding(.vertical, 2)
                        Text("PARAMETERS")
                            .font(ChromaTypography.overline)
                            .tracking(1.1)
                            .foregroundStyle(.secondary)

                        ForEach(selectedNode.parameters, id: \.name) { param in
                            CustomPatchParameterSlider(
                                param: param,
                                isLightAppearance: isLightAppearance,
                                onChange: { newValue in
                                    onParameterChange(selectedNodeID, param.name, newValue)
                                }
                            )
                        }
                    }

                    Divider().padding(.vertical, 2)

                    // Ports reference
                    if !selectedNode.inputPorts.isEmpty {
                        Text("IN: \(selectedNode.inputPorts.joined(separator: ", "))")
                            .font(ChromaTypography.bodySecondary)
                            .foregroundStyle(.secondary)
                    }
                    if !selectedNode.outputPorts.isEmpty {
                        Text("OUT: \(selectedNode.outputPorts.joined(separator: ", "))")
                            .font(ChromaTypography.bodySecondary)
                            .foregroundStyle(.secondary)
                    }

                    // Group membership
                    if let group = selectedNodeGroup {
                        Divider().padding(.vertical, 2)
                        HStack {
                            Text("GROUP: \(group.name)")
                                .font(ChromaTypography.metric)
                                .tracking(0.5)
                            Spacer(minLength: 4)
                            Button {
                                onUngroup(group.id)
                            } label: {
                                Text("Ungroup")
                                    .font(ChromaTypography.metric)
                                    .foregroundStyle(.orange)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Divider().padding(.vertical, 2)
                        HStack(spacing: 6) {
                            TextField("Group name", text: $groupNameDraft)
                                .font(ChromaTypography.metric)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    isLightAppearance ? Color.black.opacity(0.06) : Color.white.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                            Button {
                                let name = groupNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !name.isEmpty else { return }
                                onGroupSelected([selectedNodeID], name)
                                groupNameDraft = ""
                            } label: {
                                Image(systemName: "rectangle.3.group")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .disabled(groupNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    Divider().padding(.vertical, 2)

                    Button(role: .destructive) {
                        onDeleteNode(selectedNodeID)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Delete Node")
                                .font(ChromaTypography.metric)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Color.red.opacity(isLightAppearance ? 0.12 : 0.18),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                } else {
                    Text("Select a node to inspect.")
                        .font(ChromaTypography.bodySecondary)
                        .foregroundStyle(.secondary)
                }

                // Groups list
                if let patch, !patch.groups.isEmpty {
                    Divider().padding(.vertical, 2)
                    Text("GROUPS")
                        .font(ChromaTypography.overline)
                        .tracking(1.1)
                        .foregroundStyle(.secondary)

                    ForEach(patch.groups) { group in
                        HStack {
                            Circle()
                                .fill(groupColor(index: group.colorIndex))
                                .frame(width: 8, height: 8)
                            Text(group.name.uppercased())
                                .font(ChromaTypography.metric)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(group.nodeIDs.count)")
                                .font(ChromaTypography.metric.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .recorderGlassCardBackground(cornerRadius: 16, isLightAppearance: isLightAppearance)
    }

    private func groupColor(index: Int) -> Color {
        let colors: [Color] = [.orange, .blue, .green, .purple, .red, .teal, .pink, .yellow]
        return colors[index % colors.count].opacity(0.76)
    }

    private func inspectorRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label.uppercased())
                .font(ChromaTypography.metric)
                .tracking(0.6)
            Spacer(minLength: 8)
            Text(value)
                .font(ChromaTypography.metric.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Parameter Slider

private struct CustomPatchParameterSlider: View {
    let param: PatchNodeParameter
    let isLightAppearance: Bool
    let onChange: (Double) -> Void

    @State private var localValue: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(param.displayName.uppercased())
                    .font(ChromaTypography.metric)
                    .tracking(0.5)
                Spacer(minLength: 4)
                Text(formatValue(localValue))
                    .font(ChromaTypography.metric.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: $localValue, in: param.min...param.max) { editing in
                if !editing {
                    onChange(localValue)
                }
            }
            .tint(Color.orange.opacity(0.78))
            .onChange(of: localValue) { _, newVal in
                onChange(newVal)
            }
        }
        .onAppear { localValue = param.value }
        .onChange(of: param.value) { _, newVal in
            if abs(localValue - newVal) > 0.001 {
                localValue = newVal
            }
        }
    }

    private func formatValue(_ value: Double) -> String {
        if param.max - param.min > 10 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.3f", value)
    }
}

// MARK: - Graph Canvas

private struct CustomPatchGraphCanvas: View {
    let patch: CustomPatch?
    let isLightAppearance: Bool
    @Binding var selectedNodeID: UUID?
    let onMoveNode: (UUID, CustomPatchPoint) -> Void
    let onConnect: (UUID, String, UUID, String) -> Void
    let onDeleteConnection: (UUID) -> Void
    let onViewportChange: (CustomPatchViewport) -> Void

    private static let nodeWidth: CGFloat = 150
    private static let nodeHeight: CGFloat = 86
    private static let portDotRadius: CGFloat = 7

    @State private var dragOffsets: [UUID: CGSize] = [:]
    @State private var viewportZoom: CGFloat = 1.0
    @State private var viewportOffset: CGSize = .zero
    @State private var pendingPanOffset: CGSize = .zero
    @State private var pendingMagnification: CGFloat = 1.0
    @State private var connectionDrag: ConnectionDragState?

    private struct ConnectionDragState {
        var fromNodeID: UUID
        var fromPort: String
        var fromPortType: PatchPortType
        var startPoint: CGPoint
        var currentPoint: CGPoint
    }

    var body: some View {
        GeometryReader { proxy in
            let canvasCenter = CGPoint(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)

            ZStack {
                CustomPatchGridBackground(isLightAppearance: isLightAppearance)

                if let patch {
                    canvasContent(patch: patch, canvasCenter: canvasCenter)
                } else {
                    Text("No patch loaded.")
                        .font(ChromaTypography.bodySecondary)
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
            .gesture(panGesture)
            .gesture(zoomGesture)
        }
        .frame(minHeight: 320)
        .padding(2)
        .recorderGlassCardBackground(cornerRadius: 16, isLightAppearance: isLightAppearance)
        .onAppear {
            if let viewport = patch?.viewport {
                viewportZoom = CGFloat(viewport.zoom)
                viewportOffset = CGSize(width: viewport.offsetX, height: viewport.offsetY)
            }
        }
    }

    @ViewBuilder
    private func canvasContent(patch: CustomPatch, canvasCenter: CGPoint) -> some View {
        let effectiveZoom = viewportZoom * pendingMagnification
        let effectiveOffset = CGSize(
            width: viewportOffset.width + pendingPanOffset.width,
            height: viewportOffset.height + pendingPanOffset.height
        )

        // Group background rectangles
        ForEach(patch.groups) { group in
            let groupNodes = patch.nodes.filter { group.nodeIDs.contains($0.id) }
            if !groupNodes.isEmpty {
                let positions = groupNodes.map { node in
                    nodeCanvasPosition(node: node, canvasCenter: canvasCenter, offset: effectiveOffset, zoom: effectiveZoom)
                }
                let minX = positions.map(\.x).min()! - Self.nodeWidth * effectiveZoom * 0.6
                let maxX = positions.map(\.x).max()! + Self.nodeWidth * effectiveZoom * 0.6
                let minY = positions.map(\.y).min()! - Self.nodeHeight * effectiveZoom * 0.6
                let maxY = positions.map(\.y).max()! + Self.nodeHeight * effectiveZoom * 0.6
                let groupColors: [Color] = [.orange, .blue, .green, .purple, .red, .teal, .pink, .yellow]
                let color = groupColors[group.colorIndex % groupColors.count]

                RoundedRectangle(cornerRadius: 14 * effectiveZoom, style: .continuous)
                    .fill(color.opacity(isLightAppearance ? 0.08 : 0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14 * effectiveZoom, style: .continuous)
                            .stroke(color.opacity(0.30), lineWidth: 1)
                    }
                    .frame(width: maxX - minX, height: maxY - minY)
                    .position(x: (minX + maxX) * 0.5, y: (minY + maxY) * 0.5)
                    .overlay(alignment: .topLeading) {
                        Text(group.name.uppercased())
                            .font(ChromaTypography.metric)
                            .tracking(0.6)
                            .foregroundStyle(color.opacity(0.60))
                            .position(x: minX + 12 * effectiveZoom, y: minY + 10 * effectiveZoom)
                    }
                    .allowsHitTesting(false)
            }
        }

        // Connection layer (established connections)
        CustomPatchConnectionLayerInteractive(
            patch: patch,
            canvasCenter: canvasCenter,
            effectiveOffset: effectiveOffset,
            effectiveZoom: effectiveZoom,
            nodeWidth: Self.nodeWidth,
            nodeHeight: Self.nodeHeight,
            isLightAppearance: isLightAppearance,
            onDeleteConnection: onDeleteConnection
        )

        // In-progress connection drag
        if let drag = connectionDrag {
            Canvas { context, _ in
                let from = drag.startPoint
                let to = drag.currentPoint
                let deltaX = max(abs(to.x - from.x) * 0.44, 36)
                let c1 = CGPoint(x: from.x + deltaX, y: from.y)
                let c2 = CGPoint(x: to.x - deltaX, y: to.y)
                var path = Path()
                path.move(to: from)
                path.addCurve(to: to, control1: c1, control2: c2)
                context.stroke(
                    path,
                    with: .color(Color.orange.opacity(0.72)),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 4])
                )
            }
            .allowsHitTesting(false)
        }

        // Node layer
        ForEach(patch.nodes) { node in
            let dragOffset = dragOffsets[node.id] ?? .zero
            let position = nodeCanvasPosition(
                node: node,
                canvasCenter: canvasCenter,
                offset: effectiveOffset,
                zoom: effectiveZoom
            )
            let adjustedPosition = CGPoint(
                x: position.x + dragOffset.width,
                y: position.y + dragOffset.height
            )

            CustomPatchNodeView(
                node: node,
                isSelected: selectedNodeID == node.id,
                nodeWidth: Self.nodeWidth,
                nodeHeight: Self.nodeHeight,
                isLightAppearance: isLightAppearance,
                effectiveZoom: effectiveZoom,
                onSelect: { selectedNodeID = node.id },
                onDragChanged: { value in
                    dragOffsets[node.id] = value.translation
                },
                onDragEnded: { value in
                    dragOffsets[node.id] = nil
                    let newX = node.position.x + Double(value.translation.width / effectiveZoom)
                    let newY = node.position.y + Double(value.translation.height / effectiveZoom)
                    onMoveNode(node.id, CustomPatchPoint(x: newX, y: newY))
                },
                onPortDragChanged: { portName, portType, startPt, currentPt in
                    connectionDrag = ConnectionDragState(
                        fromNodeID: node.id,
                        fromPort: portName,
                        fromPortType: portType,
                        startPoint: startPt,
                        currentPoint: currentPt
                    )
                },
                onPortDragEnded: { portName, portType, endLocation in
                    completeConnectionDrag(
                        patch: patch,
                        canvasCenter: canvasCenter,
                        effectiveOffset: effectiveOffset,
                        effectiveZoom: effectiveZoom,
                        endLocation: endLocation
                    )
                    connectionDrag = nil
                }
            )
            .position(x: adjustedPosition.x, y: adjustedPosition.y)
        }
    }

    private func nodeCanvasPosition(
        node: CustomPatchNode, canvasCenter: CGPoint,
        offset: CGSize, zoom: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: canvasCenter.x + (CGFloat(node.position.x) + offset.width) * zoom,
            y: canvasCenter.y + (CGFloat(node.position.y) + offset.height) * zoom
        )
    }

    private func completeConnectionDrag(
        patch: CustomPatch,
        canvasCenter: CGPoint,
        effectiveOffset: CGSize,
        effectiveZoom: CGFloat,
        endLocation: CGPoint
    ) {
        guard let drag = connectionDrag else { return }

        // Find target node/port under the drop point
        for node in patch.nodes {
            guard node.id != drag.fromNodeID else { continue }
            let pos = nodeCanvasPosition(
                node: node, canvasCenter: canvasCenter,
                offset: effectiveOffset, zoom: effectiveZoom
            )
            let scaledWidth = Self.nodeWidth * effectiveZoom
            let scaledHeight = Self.nodeHeight * effectiveZoom
            let nodeRect = CGRect(
                x: pos.x - scaledWidth * 0.5,
                y: pos.y - scaledHeight * 0.5,
                width: scaledWidth,
                height: scaledHeight
            )

            guard nodeRect.contains(endLocation) else { continue }

            // Check if drop is on the input side (left half)
            let isInputSide = endLocation.x < pos.x

            if isInputSide {
                // Find compatible input port
                let inputDescs = node.kind.inputPortDescriptors
                for inputDesc in inputDescs {
                    if inputDesc.type == drag.fromPortType {
                        onConnect(drag.fromNodeID, drag.fromPort, node.id, inputDesc.name)
                        return
                    }
                }
            } else {
                // Drop on output side — connect from target output to drag source's input
                let outputDescs = node.kind.outputPortDescriptors
                let fromInputDescs = patch.nodes.first(where: { $0.id == drag.fromNodeID })?.kind.inputPortDescriptors ?? []
                for outputDesc in outputDescs {
                    for inputDesc in fromInputDescs {
                        if outputDesc.type == inputDesc.type {
                            onConnect(node.id, outputDesc.name, drag.fromNodeID, inputDesc.name)
                            return
                        }
                    }
                }
            }
            return
        }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                pendingPanOffset = CGSize(
                    width: value.translation.width / (viewportZoom * pendingMagnification),
                    height: value.translation.height / (viewportZoom * pendingMagnification)
                )
            }
            .onEnded { value in
                viewportOffset.width += value.translation.width / (viewportZoom * pendingMagnification)
                viewportOffset.height += value.translation.height / (viewportZoom * pendingMagnification)
                pendingPanOffset = .zero
                commitViewport()
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                pendingMagnification = value.magnification
            }
            .onEnded { value in
                viewportZoom = max(0.25, min(viewportZoom * value.magnification, 3.0))
                pendingMagnification = 1.0
                commitViewport()
            }
    }

    private func commitViewport() {
        onViewportChange(CustomPatchViewport(
            zoom: Double(viewportZoom),
            offsetX: Double(viewportOffset.width),
            offsetY: Double(viewportOffset.height)
        ))
    }
}

// MARK: - Node View

private struct CustomPatchNodeView: View {
    let node: CustomPatchNode
    let isSelected: Bool
    let nodeWidth: CGFloat
    let nodeHeight: CGFloat
    let isLightAppearance: Bool
    let effectiveZoom: CGFloat
    let onSelect: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void
    let onPortDragChanged: (String, PatchPortType, CGPoint, CGPoint) -> Void
    let onPortDragEnded: (String, PatchPortType, CGPoint) -> Void

    var body: some View {
        ZStack {
            // Node body
            VStack(alignment: .leading, spacing: 4) {
                Text(node.title.uppercased())
                    .font(ChromaTypography.overline)
                    .tracking(0.8)
                    .lineLimit(1)
                Text(node.kind.displayName)
                    .font(ChromaTypography.bodySecondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(node.inputPorts.count) in · \(node.outputPorts.count) out")
                    .font(ChromaTypography.metric.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(width: nodeWidth, height: nodeHeight, alignment: .topLeading)
            .background(
                (isSelected
                    ? (isLightAppearance ? Color.black.opacity(0.20) : Color.white.opacity(0.22))
                    : (isLightAppearance ? Color.black.opacity(0.11) : Color.white.opacity(0.14))),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected
                            ? Color.orange.opacity(isLightAppearance ? 0.66 : 0.78)
                            : (isLightAppearance ? Color.black.opacity(0.18) : Color.white.opacity(0.16)),
                        lineWidth: 1
                    )
            }
            .contentShape(Rectangle())
            .onTapGesture { onSelect() }
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged(onDragChanged)
                    .onEnded(onDragEnded)
            )

            // Input port dots (left edge)
            let inputDescs = node.kind.inputPortDescriptors
            if !inputDescs.isEmpty {
                VStack(spacing: portSpacing(count: inputDescs.count)) {
                    ForEach(Array(inputDescs.enumerated()), id: \.element.name) { _, desc in
                        portDot(type: desc.type, isOutput: false)
                    }
                }
                .position(x: 0, y: nodeHeight * 0.5)
            }

            // Output port dots (right edge)
            let outputDescs = node.kind.outputPortDescriptors
            if !outputDescs.isEmpty {
                VStack(spacing: portSpacing(count: outputDescs.count)) {
                    ForEach(Array(outputDescs.enumerated()), id: \.element.name) { _, desc in
                        portDot(type: desc.type, isOutput: true)
                            .gesture(
                                DragGesture(coordinateSpace: .global)
                                    .onChanged { value in
                                        onPortDragChanged(desc.name, desc.type, value.startLocation, value.location)
                                    }
                                    .onEnded { value in
                                        onPortDragEnded(desc.name, desc.type, value.location)
                                    }
                            )
                    }
                }
                .position(x: nodeWidth, y: nodeHeight * 0.5)
            }
        }
        .frame(width: nodeWidth, height: nodeHeight)
        .scaleEffect(effectiveZoom)
    }

    private func portDot(type: PatchPortType, isOutput: Bool) -> some View {
        Circle()
            .fill(portColor(for: type))
            .frame(width: 12, height: 12)
            .overlay {
                Circle().stroke(
                    isLightAppearance ? Color.black.opacity(0.26) : Color.white.opacity(0.30),
                    lineWidth: 1
                )
            }
    }

    private func portColor(for type: PatchPortType) -> Color {
        switch type {
        case .signal: return Color.orange.opacity(0.86)
        case .field: return Color(hue: 0.58, saturation: 0.76, brightness: 0.92)
        case .trigger: return Color.red.opacity(0.76)
        case .color: return Color.purple.opacity(0.76)
        case .vector: return Color.green.opacity(0.76)
        }
    }

    private func portSpacing(count: Int) -> CGFloat {
        count <= 1 ? 0 : max((nodeHeight - 24) / CGFloat(count), 8)
    }
}

// MARK: - Interactive Connection Layer

private struct CustomPatchConnectionLayerInteractive: View {
    let patch: CustomPatch
    let canvasCenter: CGPoint
    let effectiveOffset: CGSize
    let effectiveZoom: CGFloat
    let nodeWidth: CGFloat
    let nodeHeight: CGFloat
    let isLightAppearance: Bool
    let onDeleteConnection: (UUID) -> Void

    var body: some View {
        Canvas { context, _ in
            let nodesByID = Dictionary(uniqueKeysWithValues: patch.nodes.map { ($0.id, $0) })
            for connection in patch.connections {
                guard
                    let fromNode = nodesByID[connection.fromNodeID],
                    let toNode = nodesByID[connection.toNodeID]
                else { continue }

                let from = connectionEndpoint(node: fromNode, isOutput: true)
                let to = connectionEndpoint(node: toNode, isOutput: false)
                let deltaX = max(abs(to.x - from.x) * 0.44, 36 * effectiveZoom)
                let c1 = CGPoint(x: from.x + deltaX, y: from.y)
                let c2 = CGPoint(x: to.x - deltaX, y: to.y)
                var path = Path()
                path.move(to: from)
                path.addCurve(to: to, control1: c1, control2: c2)

                context.stroke(
                    path,
                    with: .color(Color.orange.opacity(isLightAppearance ? 0.50 : 0.66)),
                    lineWidth: 2
                )
            }
        }
        .allowsHitTesting(false)

        // Tap targets for deleting connections
        ForEach(patch.connections) { connection in
            let nodesByID = Dictionary(uniqueKeysWithValues: patch.nodes.map { ($0.id, $0) })
            if let fromNode = nodesByID[connection.fromNodeID],
               let toNode = nodesByID[connection.toNodeID] {
                let from = connectionEndpoint(node: fromNode, isOutput: true)
                let to = connectionEndpoint(node: toNode, isOutput: false)
                let midPoint = CGPoint(x: (from.x + to.x) * 0.5, y: (from.y + to.y) * 0.5)
                Circle()
                    .fill(Color.clear)
                    .frame(width: 20, height: 20)
                    .contentShape(Circle().scale(2))
                    .position(midPoint)
                    .contextMenu {
                        Button(role: .destructive) {
                            onDeleteConnection(connection.id)
                        } label: {
                            Label("Remove Connection", systemImage: "trash")
                        }
                    }
            }
        }
    }

    private func connectionEndpoint(node: CustomPatchNode, isOutput: Bool) -> CGPoint {
        let x = canvasCenter.x + (CGFloat(node.position.x) + effectiveOffset.width) * effectiveZoom
            + (isOutput ? nodeWidth * 0.5 : -nodeWidth * 0.5) * effectiveZoom
        let y = canvasCenter.y + (CGFloat(node.position.y) + effectiveOffset.height) * effectiveZoom
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Grid Background

private struct CustomPatchGridBackground: View {
    let isLightAppearance: Bool

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 28
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(
                path,
                with: .color(isLightAppearance ? Color.black.opacity(0.09) : Color.white.opacity(0.10)),
                lineWidth: 0.9
            )
        }
        .background(
            LinearGradient(
                colors: isLightAppearance
                    ? [Color.white.opacity(0.88), Color(hue: 0.59, saturation: 0.10, brightness: 0.98)]
                    : [Color.black.opacity(0.92), Color(hue: 0.60, saturation: 0.18, brightness: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

struct FeedbackSetupSheet: View {
    @ObservedObject var sessionViewModel: SessionViewModel
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                guidanceSection
                controlSection
            }
            .font(ChromaTypography.body)
            .navigationTitle("FEEDBACK")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetToolbarCloseButton(action: dismiss)
                }
            }
        }
    }

    private var guidanceSection: some View {
        Section {
            Text("Hold the phone parallel with a mirror, keep the front camera centered, and avoid major tilt before starting feedback.")
                .font(ChromaTypography.bodySecondary)
                .foregroundStyle(.secondary)

            LabeledContent("Mode", value: sessionViewModel.activeModeDescriptor.name)
            LabeledContent("Camera", value: sessionViewModel.cameraFeedbackAuthorizationStatus.rawValue)
            LabeledContent("Feedback", value: sessionViewModel.isColorFeedbackRunning ? "Running" : "Stopped")
            if let statusMessage = sessionViewModel.cameraFeedbackStatusMessage {
                Text(statusMessage)
                    .font(ChromaTypography.bodySecondary)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Setup")
        }
    }

    private var controlSection: some View {
        Section {
            Button("START FEEDBACK") {
                Task {
                    await sessionViewModel.startColorFeedbackCapture()
                }
            }
            .disabled(sessionViewModel.session.activeModeID != .colorShift)

            Button("STOP FEEDBACK") {
                sessionViewModel.stopColorFeedbackCapture()
            }
            .disabled(!sessionViewModel.isColorFeedbackRunning)
        } header: {
            sectionHeader("Controls")
        } footer: {
            if sessionViewModel.session.activeModeID != .colorShift {
                Text("Switch to Color Shift to enable mirror feedback.")
                    .font(ChromaTypography.bodySecondary)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(ChromaTypography.sheetSectionHeader)
            .tracking(1.4)
    }
}

struct TunnelVariantPickerPresentation: Identifiable, Equatable {
    let index: Int
    let title: String
    let summary: String
    let systemImage: String
    let tintHue: Double

    var id: Int { index }

    var tintColor: Color {
        Color(hue: tintHue, saturation: 0.80, brightness: 0.96)
    }
}

func tunnelVariantPickerPresentationCatalog() -> [TunnelVariantPickerPresentation] {
    [
        TunnelVariantPickerPresentation(
            index: 0,
            title: "Cel Cards",
            summary: "Flat graphic cards with clean tunnel silhouettes.",
            systemImage: "square.on.square.fill",
            tintHue: 0.57
        ),
        TunnelVariantPickerPresentation(
            index: 1,
            title: "Prism Shards",
            summary: "Facet-driven shard silhouettes with angular edges.",
            systemImage: "diamond.fill",
            tintHue: 0.67
        ),
        TunnelVariantPickerPresentation(
            index: 2,
            title: "Glyph Slabs",
            summary: "Thicker slab silhouettes with bold panel feel.",
            systemImage: "rectangle.stack.fill",
            tintHue: 0.50
        ),
    ]
}

struct PalettePickerPresentation: Identifiable, Equatable {
    let index: Int
    let name: String
    let systemImage: String
    let swatchHues: [Double]

    var id: Int { index }

    var accentColor: Color {
        Color(hue: swatchHues.first ?? 0.56, saturation: 0.82, brightness: 0.96)
    }
}

func chromaPalettePickerPresentationCatalog() -> [PalettePickerPresentation] {
    [
        PalettePickerPresentation(index: 0, name: "Aurora", systemImage: "sparkles", swatchHues: [0.47, 0.55, 0.65, 0.78]),
        PalettePickerPresentation(index: 1, name: "Solar", systemImage: "sun.max.fill", swatchHues: [0.07, 0.10, 0.14, 0.18]),
        PalettePickerPresentation(index: 2, name: "Abyss", systemImage: "moon.stars.fill", swatchHues: [0.54, 0.60, 0.67, 0.74]),
        PalettePickerPresentation(index: 3, name: "Neon", systemImage: "bolt.fill", swatchHues: [0.86, 0.93, 0.02, 0.12]),
        PalettePickerPresentation(index: 4, name: "Infra", systemImage: "flame.fill", swatchHues: [0.99, 0.04, 0.08, 0.13]),
        PalettePickerPresentation(index: 5, name: "Glass", systemImage: "drop.fill", swatchHues: [0.52, 0.57, 0.62, 0.69]),
        PalettePickerPresentation(index: 6, name: "Mono", systemImage: "circle.lefthalf.filled.inverse", swatchHues: [0.00, 0.00, 0.00, 0.00]),
        PalettePickerPresentation(index: 7, name: "Prism", systemImage: "diamond.fill", swatchHues: [0.58, 0.69, 0.82, 0.92]),
    ]
}

struct PresetPickerDraftState {
    let initialPresetID: UUID?
    private(set) var selectedPresetID: UUID?

    init(activePresetID: UUID?, presets: [Preset]) {
        initialPresetID = activePresetID
        if let activePresetID, presets.contains(where: { $0.id == activePresetID }) {
            selectedPresetID = activePresetID
        } else {
            selectedPresetID = presets.first?.id
        }
    }

    mutating func preview(_ presetID: UUID?) {
        selectedPresetID = presetID
    }

    func selectedPreset(in presets: [Preset]) -> Preset? {
        guard let selectedPresetID else { return nil }
        return presets.first(where: { $0.id == selectedPresetID })
    }

    func activePresetAfterDismissWithoutApply() -> UUID? {
        initialPresetID
    }

    func activePresetAfterApply() -> UUID? {
        selectedPresetID
    }
}

struct TunnelVariantPickerSheet: View {
    @ObservedObject var sessionViewModel: SessionViewModel
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectionMotionToken = UUID()
    private let options = tunnelVariantPickerPresentationCatalog()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Choose the shape family used for attack-spawned tunnel cels.")
                    .font(ChromaTypography.bodySecondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 8)

                VStack(spacing: 10) {
                    ForEach(options) { option in
                        VariantSelectorTile(
                            title: option.title,
                            subtitle: option.summary,
                            systemImage: option.systemImage,
                            accentColor: option.tintColor,
                            isLightAppearance: sessionViewModel.isLightGlassAppearance,
                            isSelected: option.index == sessionViewModel.tunnelVariantSelectionIndex,
                            motionToken: selectionMotionToken,
                            reduceMotion: reduceMotion
                        ) {
                            if !reduceMotion {
                                selectionMotionToken = UUID()
                            }
                            performImpactHaptic()
                            sessionViewModel.setTunnelVariant(index: option.index)
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, 1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .font(ChromaTypography.body)
            .navigationTitle("VARIANT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetToolbarCloseButton(action: dismiss)
                }
            }
        }
    }

    private func performImpactHaptic() {
#if canImport(UIKit) && !targetEnvironment(macCatalyst)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
#endif
    }
}

struct FractalPalettePickerSheet: View {
    @ObservedObject var sessionViewModel: SessionViewModel
    let dismiss: () -> Void

    var body: some View {
        PalettePickerSheetContent(
            title: "PALETTE",
            subtitle: "Select a palette bank for Fractal Caustics.",
            selectedIndex: sessionViewModel.fractalPaletteSelectionIndex,
            isLightAppearance: sessionViewModel.isLightGlassAppearance,
            dismiss: dismiss
        ) { index in
            sessionViewModel.setFractalPaletteVariant(index: index)
        }
    }
}

struct RiemannPalettePickerSheet: View {
    @ObservedObject var sessionViewModel: SessionViewModel
    let dismiss: () -> Void

    var body: some View {
        PalettePickerSheetContent(
            title: "PALETTE",
            subtitle: "Select a palette bank for Mandelbrot Navigator.",
            selectedIndex: sessionViewModel.riemannPaletteSelectionIndex,
            isLightAppearance: sessionViewModel.isLightGlassAppearance,
            dismiss: dismiss
        ) { index in
            sessionViewModel.setRiemannPaletteVariant(index: index)
        }
    }
}

// MARK: - Preset & Cue Paginated Sheet

private enum PresetCuePage: Int, CaseIterable {
    case presets
    case cues

    var title: String {
        switch self {
        case .presets: return "PRESETS"
        case .cues: return "CUES"
        }
    }
}

struct PresetBrowserSheet: View {
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var sessionViewModel: SessionViewModel
    let dismiss: () -> Void

    @State private var activePage: PresetCuePage = .presets

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $activePage) {
                    PresetBrowserPage(
                        appViewModel: appViewModel,
                        sessionViewModel: sessionViewModel,
                        dismiss: dismiss
                    )
                    .tag(PresetCuePage.presets)

                    CueComposerPage(
                        appViewModel: appViewModel,
                        sessionViewModel: sessionViewModel,
                        dismiss: dismiss
                    )
                    .tag(PresetCuePage.cues)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                presetCuePaginationDots
                    .padding(.top, 6)
                    .padding(.bottom, 12)
            }
            .font(ChromaTypography.body)
            .navigationTitle(activePage.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetToolbarCloseButton(action: dismiss)
                }
            }
        }
    }

    private var presetCuePaginationDots: some View {
        HStack(spacing: 8) {
            ForEach(PresetCuePage.allCases, id: \.rawValue) { page in
                let isActive = page == activePage
                Capsule()
                    .fill(
                        isActive
                            ? Color.blue.opacity(sessionViewModel.isLightGlassAppearance ? 0.94 : 0.98)
                            : Color.secondary.opacity(sessionViewModel.isLightGlassAppearance ? 0.35 : 0.48)
                    )
                    .frame(width: isActive ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.26, dampingFraction: 0.82), value: activePage)
            }
        }
    }
}

// MARK: - Presets Page (extracted from former PresetBrowserSheet)

private struct PresetBrowserPage: View {
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var sessionViewModel: SessionViewModel
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draftState: PresetPickerDraftState
    @State private var selectionMotionToken = UUID()
    @State private var applyMotionToken = UUID()
    @State private var renamingPreset: Preset?
    @State private var renameDraft: String = ""
    @State private var deletingPreset: Preset?

    init(appViewModel: AppViewModel, sessionViewModel: SessionViewModel, dismiss: @escaping () -> Void) {
        self.appViewModel = appViewModel
        self.sessionViewModel = sessionViewModel
        self.dismiss = dismiss
        _draftState = State(
            initialValue: PresetPickerDraftState(
                activePresetID: sessionViewModel.session.activePresetID,
                presets: sessionViewModel.presetsForActiveMode
            )
        )
    }

    private var selectedPreset: Preset? {
        draftState.selectedPreset(in: sessionViewModel.presetsForActiveMode)
    }

    private var presetsForActiveMode: [Preset] {
        sessionViewModel.presetsForActiveMode
    }

    var body: some View {
        presetBrowserContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .onChange(of: draftState.selectedPresetID) { _, _ in
                guard !reduceMotion else { return }
                selectionMotionToken = UUID()
            }
            .onChange(of: presetsForActiveMode.map(\.id)) { _, _ in
                reconcileDraftSelection()
            }
            .onChange(of: sessionViewModel.session.activeModeID) { _, _ in
                draftState = PresetPickerDraftState(
                    activePresetID: sessionViewModel.session.activePresetID,
                    presets: presetsForActiveMode
                )
            }
            .alert(
                "Rename Preset",
                isPresented: Binding(
                    get: { renamingPreset != nil },
                    set: { if !$0 { renamingPreset = nil } }
                )
            ) {
                TextField("Preset Name", text: $renameDraft)
                Button("Cancel", role: .cancel) {
                    renamingPreset = nil
                }
                Button("Save") {
                    guard let renamingPreset else { return }
                    sessionViewModel.renamePreset(id: renamingPreset.id, newName: renameDraft)
                    self.renamingPreset = nil
                }
            }
            .alert(
                "Delete Preset?",
                isPresented: Binding(
                    get: { deletingPreset != nil },
                    set: { if !$0 { deletingPreset = nil } }
                ),
                presenting: deletingPreset
            ) { preset in
                Button("Delete", role: .destructive) {
                    sessionViewModel.deletePreset(id: preset.id)
                    deletingPreset = nil
                }
                Button("Cancel", role: .cancel) {
                    deletingPreset = nil
                }
            } message: { preset in
                Text("'\(preset.name)' will be removed.")
            }
    }

    @ViewBuilder
    private var presetBrowserContent: some View {
        VStack(spacing: 14) {
            if presetsForActiveMode.isEmpty {
                presetEmptyState
            } else {
                presetScrollList
                applyPresetButton
            }
        }
    }

    private var presetScrollList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(presetsForActiveMode) { preset in
                    let presentation = modePickerHeroPresentation(for: preset.modeID)
                    PresetSelectorTile(
                        title: preset.name,
                        subtitle: ParameterCatalog.modeDescriptor(for: preset.modeID).name,
                        systemImage: presentation.systemImage,
                        accentColor: presentation.accentColor,
                        isSelected: preset.id == draftState.selectedPresetID,
                        isLightAppearance: sessionViewModel.isLightGlassAppearance,
                        motionToken: selectionMotionToken,
                        reduceMotion: reduceMotion
                    ) {
                        if !reduceMotion {
                            selectionMotionToken = UUID()
                        }
                        performImpactHaptic()
                        draftState.preview(preset.id)
                    }
                    .contextMenu {
                        presetContextMenu(for: preset)
                    }
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func presetContextMenu(for preset: Preset) -> some View {
        if preset.id == draftState.selectedPresetID {
            Button("Rename") {
                guard appViewModel.billingStore.proAccessVisualState.hasFeatureAccess else {
                    appViewModel.presentPaywall(entryPoint: .presets, dismissingPresentedSheet: true)
                    return
                }
                renamingPreset = preset
                renameDraft = preset.name
            }

            Button("Delete", role: .destructive) {
                guard appViewModel.billingStore.proAccessVisualState.hasFeatureAccess else {
                    appViewModel.presentPaywall(entryPoint: .presets, dismissingPresentedSheet: true)
                    return
                }
                deletingPreset = preset
            }
        }
    }

    private var presetEmptyState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 4)
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 32, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    sessionViewModel.isLightGlassAppearance ? Color.black.opacity(0.88) : Color.white.opacity(0.94),
                    Color.secondary.opacity(0.65)
                )
            Text("No presets for \(sessionViewModel.activeModeDescriptor.name) yet.")
                .font(ChromaTypography.sheetRowTitle)
                .multilineTextAlignment(.center)
            Text("Use the save action on the live controls tile to capture a new preset.")
                .font(ChromaTypography.bodySecondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .recorderGlassCardBackground(
            cornerRadius: 18,
            isLightAppearance: sessionViewModel.isLightGlassAppearance
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var applyPresetButton: some View {
        Button {
            guard let selectedPreset else { return }
            if !reduceMotion {
                applyMotionToken = UUID()
            }
            performImpactHaptic()
            sessionViewModel.applyPreset(selectedPreset)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                applyIcon
                Text("APPLY PRESET")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .modePickerApplyButtonBackground(
                accentGradient: selectedPresetGradient,
                borderColor: selectedPresetTint,
                isLightAppearance: sessionViewModel.isLightGlassAppearance
            )
        }
        .buttonStyle(.plain)
        .disabled(selectedPreset == nil)
        .opacity(selectedPreset == nil ? 0.45 : 1)
    }

    @ViewBuilder
    private var applyIcon: some View {
        let icon = Image(systemName: selectedPresetSystemImage)
            .font(.system(size: 18, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                sessionViewModel.isLightGlassAppearance ? Color.black.opacity(0.90) : Color.white.opacity(0.96),
                selectedPresetTint
            )
            .frame(width: 34, height: 34)
            .background(
                sessionViewModel.isLightGlassAppearance ? Color.black.opacity(0.10) : Color.white.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )

        if reduceMotion {
            icon
        } else if #available(iOS 18.0, macCatalyst 18.0, *) {
            icon.symbolEffect(.bounce, value: applyMotionToken)
        } else {
            icon
        }
    }

    private var selectedPresetSystemImage: String {
        selectedPreset.map { modePickerHeroPresentation(for: $0.modeID).systemImage } ?? "square.stack.3d.up"
    }

    private var selectedPresetTint: Color {
        selectedPreset.map { modePickerHeroPresentation(for: $0.modeID).accentColor } ?? .blue
    }

    private var selectedPresetGradient: LinearGradient {
        selectedPreset.map { modePickerHeroPresentation(for: $0.modeID).accentGradient }
            ?? LinearGradient(
                colors: [Color.blue.opacity(0.82), Color.indigo.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
    }

    private func reconcileDraftSelection() {
        let presets = sessionViewModel.presetsForActiveMode
        if presets.isEmpty {
            draftState.preview(nil)
            return
        }

        if let selectedPresetID = draftState.selectedPresetID,
           presets.contains(where: { $0.id == selectedPresetID }) {
            return
        }

        if let activePresetID = sessionViewModel.session.activePresetID,
           presets.contains(where: { $0.id == activePresetID }) {
            draftState.preview(activePresetID)
            return
        }

        draftState.preview(presets.first?.id)
    }

    private func performImpactHaptic() {
#if canImport(UIKit) && !targetEnvironment(macCatalyst)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
#endif
    }
}

// MARK: - Cue Composer Page

private struct CueComposerPage: View {
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var sessionViewModel: SessionViewModel
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var activeSetID: UUID?
    @State private var isCreatingSet = false
    @State private var newSetName: String = ""
    @State private var renamingSet: PerformanceSet?
    @State private var renameSetDraft: String = ""
    @State private var deletingSet: PerformanceSet?
    @State private var renamingCue: PerformanceCue?
    @State private var renameCueDraft: String = ""
    @State private var editingTimingCue: PerformanceCue?
    @State private var delayDraft: String = ""
    @State private var transitionDraft: String = ""
    @State private var deletingCue: PerformanceCue?

    private var activeSet: PerformanceSet? {
        if let activeSetID {
            return sessionViewModel.performanceSets.first(where: { $0.id == activeSetID })
        }
        return sessionViewModel.performanceSets.first
    }

    var body: some View {
        VStack(spacing: 14) {
            if sessionViewModel.performanceSets.isEmpty {
                cueEmptyState
            } else {
                setHeader
                if let set = activeSet {
                    if set.cues.isEmpty {
                        cueListEmptyState
                    } else {
                        cueScrollList(for: set)
                    }
                    addCueButton(for: set)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .onAppear {
            if activeSetID == nil {
                activeSetID = sessionViewModel.performanceSets.first?.id
            }
        }
        .onChange(of: sessionViewModel.performanceSets.map(\.id)) { _, newIDs in
            if let activeSetID, !newIDs.contains(activeSetID) {
                self.activeSetID = newIDs.first
            }
        }
        .alert(
            "New Set",
            isPresented: $isCreatingSet
        ) {
            TextField("Set Name", text: $newSetName)
            Button("Cancel", role: .cancel) {
                isCreatingSet = false
            }
            Button("Create") {
                sessionViewModel.createPerformanceSet(name: newSetName)
                if let created = sessionViewModel.performanceSets.first(where: {
                    $0.name == newSetName.trimmingCharacters(in: .whitespacesAndNewlines)
                }) {
                    activeSetID = created.id
                }
                newSetName = ""
                isCreatingSet = false
            }
        }
        .alert(
            "Rename Set",
            isPresented: Binding(
                get: { renamingSet != nil },
                set: { if !$0 { renamingSet = nil } }
            )
        ) {
            TextField("Set Name", text: $renameSetDraft)
            Button("Cancel", role: .cancel) {
                renamingSet = nil
            }
            Button("Save") {
                guard let renamingSet else { return }
                sessionViewModel.renamePerformanceSet(id: renamingSet.id, newName: renameSetDraft)
                self.renamingSet = nil
            }
        }
        .alert(
            "Delete Set?",
            isPresented: Binding(
                get: { deletingSet != nil },
                set: { if !$0 { deletingSet = nil } }
            ),
            presenting: deletingSet
        ) { set in
            Button("Delete", role: .destructive) {
                sessionViewModel.deletePerformanceSet(id: set.id)
                deletingSet = nil
            }
            Button("Cancel", role: .cancel) {
                deletingSet = nil
            }
        } message: { set in
            Text("'\(set.name)' and all its cues will be removed.")
        }
        .alert(
            "Rename Cue",
            isPresented: Binding(
                get: { renamingCue != nil },
                set: { if !$0 { renamingCue = nil } }
            )
        ) {
            TextField("Cue Name", text: $renameCueDraft)
            Button("Cancel", role: .cancel) {
                renamingCue = nil
            }
            Button("Save") {
                guard let setID = activeSet?.id, var cue = renamingCue else { return }
                cue.name = renameCueDraft
                sessionViewModel.updateCue(in: setID, cue: cue)
                renamingCue = nil
            }
        }
        .alert(
            "Edit Timing",
            isPresented: Binding(
                get: { editingTimingCue != nil },
                set: { if !$0 { editingTimingCue = nil } }
            )
        ) {
            TextField("Delay (seconds)", text: $delayDraft)
#if canImport(UIKit)
                .keyboardType(.decimalPad)
#endif
            TextField("Transition (seconds)", text: $transitionDraft)
#if canImport(UIKit)
                .keyboardType(.decimalPad)
#endif
            Button("Cancel", role: .cancel) {
                editingTimingCue = nil
            }
            Button("Save") {
                guard let setID = activeSet?.id, var cue = editingTimingCue else { return }
                cue.delayFromPrevious = max(0, Double(delayDraft) ?? 0)
                cue.transitionDuration = max(0, Double(transitionDraft) ?? 0)
                sessionViewModel.updateCue(in: setID, cue: cue)
                editingTimingCue = nil
            }
        }
        .alert(
            "Delete Cue?",
            isPresented: Binding(
                get: { deletingCue != nil },
                set: { if !$0 { deletingCue = nil } }
            ),
            presenting: deletingCue
        ) { cue in
            Button("Delete", role: .destructive) {
                guard let setID = activeSet?.id else { return }
                sessionViewModel.deleteCue(from: setID, cueID: cue.id)
                deletingCue = nil
            }
            Button("Cancel", role: .cancel) {
                deletingCue = nil
            }
        } message: { cue in
            Text("'\(cue.name)' will be removed from this set.")
        }
    }

    // MARK: - Empty States

    private var cueEmptyState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 4)
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 32, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    sessionViewModel.isLightGlassAppearance ? Color.black.opacity(0.88) : Color.white.opacity(0.94),
                    Color.secondary.opacity(0.65)
                )
            Text("No cue sets yet.")
                .font(ChromaTypography.sheetRowTitle)
                .multilineTextAlignment(.center)
            Text("Create a set to build a sequence of preset recalls for live performance.")
                .font(ChromaTypography.bodySecondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            Spacer(minLength: 8)
            Button {
                newSetName = ""
                isCreatingSet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("CREATE SET")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .tracking(0.6)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    Color.blue.opacity(sessionViewModel.isLightGlassAppearance ? 0.18 : 0.22),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.blue)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .recorderGlassCardBackground(
            cornerRadius: 18,
            isLightAppearance: sessionViewModel.isLightGlassAppearance
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cueListEmptyState: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 4)
            Text("No cues in this set.")
                .font(ChromaTypography.bodySecondary)
                .foregroundStyle(.secondary)
            Text("Add a cue to capture the current preset into this sequence.")
                .font(ChromaTypography.bodySecondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .recorderGlassCardBackground(
            cornerRadius: 18,
            isLightAppearance: sessionViewModel.isLightGlassAppearance
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Set Header

    private var setHeader: some View {
        HStack(spacing: 10) {
            if sessionViewModel.performanceSets.count > 1 {
                setSwitcher
            } else if let set = activeSet {
                Text(set.name.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if let set = activeSet {
                Menu {
                    Button {
                        renamingSet = set
                        renameSetDraft = set.name
                    } label: {
                        Label("Rename Set", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        deletingSet = set
                    } label: {
                        Label("Delete Set", systemImage: "trash")
                    }
                    Divider()
                    Button {
                        newSetName = ""
                        isCreatingSet = true
                    } label: {
                        Label("New Set", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var setSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(sessionViewModel.performanceSets) { set in
                    let isActive = set.id == (activeSetID ?? sessionViewModel.performanceSets.first?.id)
                    Button {
                        activeSetID = set.id
                    } label: {
                        Text(set.name.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(0.4)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                isActive
                                    ? Color.blue.opacity(0.28)
                                    : Color.secondary.opacity(0.12),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .stroke(
                                        isActive ? Color.blue.opacity(0.5) : Color.clear,
                                        lineWidth: 1
                                    )
                            }
                            .foregroundStyle(isActive ? Color.blue : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Cue List

    private func cueScrollList(for set: PerformanceSet) -> some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(Array(set.cues.enumerated()), id: \.element.id) { index, cue in
                    cueTile(cue: cue, index: index + 1, setID: set.id)
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func cueTile(cue: PerformanceCue, index: Int, setID: UUID) -> some View {
        let linkedPresetName = cue.presetID.flatMap { pid in
            sessionViewModel.presets.first(where: { $0.id == pid })?.name
        } ?? "No preset"

        return Button {
            performImpactHaptic()
            sessionViewModel.fireCue(cue)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text("\(index)")
                    .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                    .frame(width: 28, height: 28)
                    .background(
                        Color.blue.opacity(sessionViewModel.isLightGlassAppearance ? 0.14 : 0.18),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .foregroundStyle(Color.blue.opacity(sessionViewModel.isLightGlassAppearance ? 0.86 : 0.92))

                VStack(alignment: .leading, spacing: 2) {
                    Text(cue.name)
                        .font(ChromaTypography.sheetRowTitle)
                        .lineLimit(1)
                    Text(linkedPresetName.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if cue.delayFromPrevious > 0 {
                    cueTimingBadge(text: formatSeconds(cue.delayFromPrevious) + " delay")
                }
                if cue.transitionDuration > 0 {
                    cueTimingBadge(text: formatSeconds(cue.transitionDuration) + " fade")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .recorderGlassCardBackground(cornerRadius: 16, isLightAppearance: sessionViewModel.isLightGlassAppearance)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renamingCue = cue
                renameCueDraft = cue.name
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                editingTimingCue = cue
                delayDraft = cue.delayFromPrevious > 0 ? formatSeconds(cue.delayFromPrevious) : ""
                transitionDraft = cue.transitionDuration > 0 ? formatSeconds(cue.transitionDuration) : ""
            } label: {
                Label("Edit Timing", systemImage: "clock")
            }
            Divider()
            Button(role: .destructive) {
                deletingCue = cue
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func cueTimingBadge(text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(0.3)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Color.orange.opacity(sessionViewModel.isLightGlassAppearance ? 0.16 : 0.20),
                in: Capsule()
            )
            .foregroundStyle(Color.orange)
    }

    // MARK: - Add Cue Button

    private func addCueButton(for set: PerformanceSet) -> some View {
        Button {
            performImpactHaptic()
            sessionViewModel.addCueFromActivePreset(to: set.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.blue)
                    .frame(width: 34, height: 34)
                    .background(
                        sessionViewModel.isLightGlassAppearance ? Color.black.opacity(0.10) : Color.white.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                Text("ADD CUE FROM CURRENT PRESET")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .modePickerApplyButtonBackground(
                accentGradient: LinearGradient(
                    colors: [Color.blue.opacity(0.82), Color.indigo.opacity(0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                borderColor: Color.blue,
                isLightAppearance: sessionViewModel.isLightGlassAppearance
            )
        }
        .buttonStyle(.plain)
        .disabled(sessionViewModel.session.activePresetID == nil)
        .opacity(sessionViewModel.session.activePresetID == nil ? 0.45 : 1)
    }

    // MARK: - Helpers

    private func formatSeconds(_ value: TimeInterval) -> String {
        if value == value.rounded() && value < 100 {
            return String(format: "%.0fs", value)
        }
        return String(format: "%.1fs", value)
    }

    private func performImpactHaptic() {
#if canImport(UIKit) && !targetEnvironment(macCatalyst)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
#endif
    }
}

struct RecorderExportSheet: View {
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var sessionViewModel: SessionViewModel
    let dismiss: () -> Void
    @State private var captureStartDate: Date?
    @State private var now = Date()
    @State private var shareItem: ExportShareItem?
    @State private var completedExportURL: URL?
    @State private var saveToPhotosStatusMessage: String?
    @State private var isSavingToPhotos = false

    private let elapsedTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    init(appViewModel: AppViewModel, sessionViewModel: SessionViewModel, dismiss: @escaping () -> Void) {
        self.appViewModel = appViewModel
        self.sessionViewModel = sessionViewModel
        self.dismiss = dismiss
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                statusStrip
                micToggleRow
                captureActionTile
                HStack(spacing: 12) {
                    saveToPhotosTile
                    shareTile
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .font(ChromaTypography.body)
            .navigationTitle("RECORDER")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetToolbarCloseButton(action: dismiss)
                }
            }
            .onReceive(elapsedTimer) { now = $0 }
            .onChange(of: sessionViewModel.recorderCaptureState) { _, state in
                switch state {
                case .recording:
                    if captureStartDate == nil {
                        captureStartDate = Date()
                    }
                    completedExportURL = nil
                    saveToPhotosStatusMessage = nil
                    performImpactHaptic()
                case .completed(let url):
                    captureStartDate = nil
                    completedExportURL = url
                    performNotificationHaptic(.success)
                case .idle, .starting, .finalizing, .failed:
                    if case .starting = state {
                        break
                    }
                    captureStartDate = nil
                    if case .failed = state {
                        performNotificationHaptic(.error)
                    }
                }
            }
            .sheet(item: $shareItem) { item in
                ChromaShareSheet(items: [item.url])
            }
        }
    }

    private var statusStrip: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIconName)
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(recorderPrimaryColor, statusColor.opacity(0.90))
                .frame(width: 36, height: 36)
                .background(
                    sessionViewModel.isLightGlassAppearance ? Color.black.opacity(0.09) : Color.white.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitleText)
                    .font(ChromaTypography.sheetRowTitle)
                Text(statusDetailText)
                    .font(ChromaTypography.bodySecondary)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 10)
            if case .recording = sessionViewModel.recorderCaptureState {
                Text(elapsedLabel)
                    .font(ChromaTypography.metric.monospacedDigit())
                    .foregroundStyle(recorderStrongSecondaryColor)
            }
        }
        .padding(14)
        .recorderGlassCardBackground(
            cornerRadius: 18,
            isLightAppearance: sessionViewModel.isLightGlassAppearance
        )
    }

    private var micToggleRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(recorderPrimaryColor)
                .frame(width: 28, height: 28)
                .background(
                    sessionViewModel.isLightGlassAppearance ? Color.black.opacity(0.09) : Color.white.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Include Mic Audio")
                    .font(ChromaTypography.sheetRowTitle)
                Text(exportSettingsSummary)
                    .font(ChromaTypography.bodySecondary)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Toggle(
                "",
                isOn: Binding(
                    get: { sessionViewModel.includeMicAudioInExport },
                    set: { sessionViewModel.setIncludeMicAudioInExport($0) }
                )
            )
            .labelsHidden()
            .disabled(isCaptureInFlight)
            .tint(sessionViewModel.isLightGlassAppearance ? .black : .white)
        }
        .padding(14)
        .recorderGlassCardBackground(
            cornerRadius: 18,
            isLightAppearance: sessionViewModel.isLightGlassAppearance
        )
    }

    private var captureActionTile: some View {
        RecorderConsoleActionTile(
            title: actionButtonTitle,
            subtitle: appViewModel.billingStore.isProActive ? actionButtonSubtitle : "Pro required for recording & export",
            systemImage: actionButtonIcon,
            accentColor: .red.opacity(0.88),
            isLightAppearance: sessionViewModel.isLightGlassAppearance,
            isEnabled: !actionButtonDisabled
        ) {
            if case .recording = sessionViewModel.recorderCaptureState {
                Task {
                    performImpactHaptic()
                    await sessionViewModel.stopRecorderCapture()
                }
                return
            }

            guard appViewModel.billingStore.proAccessVisualState.hasFeatureAccess else {
                performImpactHaptic()
                appViewModel.presentPaywall(entryPoint: .recording, dismissingPresentedSheet: true)
                return
            }

            Task {
                performImpactHaptic()
                await sessionViewModel.startRecorderCapture()
            }
        }
        .overlay(alignment: .topTrailing) {
            if !appViewModel.billingStore.isProActive {
                ChromaProBadge(style: .locked)
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var saveToPhotosTile: some View {
        RecorderConsoleActionTile(
            title: "Save to Photos",
            subtitle: saveToPhotosSubtitle,
            systemImage: "photo.on.rectangle.angled",
            accentColor: .green.opacity(0.84),
            isLightAppearance: sessionViewModel.isLightGlassAppearance,
            isEnabled: completedExportURL != nil && !isSavingToPhotos
        ) {
            guard let completedExportURL else { return }
            Task {
                isSavingToPhotos = true
                defer { isSavingToPhotos = false }
                performImpactHaptic()
                do {
                    try await saveVideoToPhotos(url: completedExportURL)
                    saveToPhotosStatusMessage = "Saved to Photos."
                    performNotificationHaptic(.success)
                } catch {
                    saveToPhotosStatusMessage = error.localizedDescription
                    performNotificationHaptic(.error)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var shareTile: some View {
        RecorderConsoleActionTile(
            title: "Share",
            subtitle: shareSubtitle,
            systemImage: "square.and.arrow.up",
            accentColor: .blue.opacity(0.86),
            isLightAppearance: sessionViewModel.isLightGlassAppearance,
            isEnabled: completedExportURL != nil
        ) {
            guard let completedExportURL else { return }
            performImpactHaptic()
            shareItem = ExportShareItem(url: completedExportURL)
        }
        .frame(maxWidth: .infinity)
    }

    private var elapsedLabel: String {
        guard let captureStartDate else { return "00:00" }
        let elapsedSeconds = Int(now.timeIntervalSince(captureStartDate))
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var isCaptureInFlight: Bool {
        switch sessionViewModel.recorderCaptureState {
        case .starting, .recording, .finalizing:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }

    private var actionButtonTitle: String {
        switch sessionViewModel.recorderCaptureState {
        case .idle:
            return "Start Recording"
        case .starting:
            return "Starting…"
        case .recording:
            return "Stop & Export"
        case .finalizing:
            return "Finalizing…"
        case .completed:
            return "Record Again"
        case .failed:
            return "Retry Recording"
        }
    }

    private var actionButtonIcon: String {
        switch sessionViewModel.recorderCaptureState {
        case .recording:
            return "stop.circle.fill"
        default:
            return "record.circle.fill"
        }
    }

    private var actionButtonSubtitle: String {
        switch sessionViewModel.recorderCaptureState {
        case .idle:
            return "Clean program feed"
        case .starting:
            return "Waiting for first frame"
        case .recording:
            return "Tap to finalize export"
        case .finalizing:
            return "Finalizing file"
        case .completed(let url):
            return url.lastPathComponent
        case .failed(let message):
            return message
        }
    }

    private var actionButtonDisabled: Bool {
        switch sessionViewModel.recorderCaptureState {
        case .starting, .finalizing:
            return true
        case .idle, .recording, .completed, .failed:
            return false
        }
    }

    private var statusTitleText: String {
        switch sessionViewModel.recorderCaptureState {
        case .idle:
            return "Recorder Idle"
        case .starting:
            return "Starting Capture"
        case .recording:
            return "Recording"
        case .finalizing:
            return "Finalizing"
        case .completed:
            return "Export Ready"
        case .failed:
            return "Export Failed"
        }
    }

    private var statusDetailText: String {
        if let saveToPhotosStatusMessage, !saveToPhotosStatusMessage.isEmpty {
            return saveToPhotosStatusMessage
        }
        if let recorderStatusMessage = sessionViewModel.recorderStatusMessage,
           !recorderStatusMessage.isEmpty {
            return recorderStatusMessage
        }
        switch sessionViewModel.recorderCaptureState {
        case .idle:
            return "Ready to record clean output."
        case .starting:
            return "Writer initializes on first frame."
        case .recording:
            return "Program feed only (no chrome)."
        case .finalizing:
            return "Preparing movie file."
        case .completed(let url):
            return url.lastPathComponent
        case .failed(let message):
            return message
        }
    }

    private var statusIconName: String {
        switch sessionViewModel.recorderCaptureState {
        case .failed:
            return "exclamationmark.triangle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .recording:
            return "record.circle.fill"
        case .finalizing:
            return "hourglass"
        case .starting:
            return "dot.radiowaves.left.and.right"
        case .idle:
            return "video.fill"
        }
    }

    private var statusColor: Color {
        switch sessionViewModel.recorderCaptureState {
        case .failed:
            return .red.opacity(0.85)
        case .completed:
            return .green.opacity(0.82)
        default:
            return .secondary
        }
    }

    private var exportSettingsSummary: String {
        let settings = sessionViewModel.exportCaptureSettings
        return "\(settings.resolutionPreset.label) • \(settings.frameRate.label) fps • \(settings.codec.label)"
    }

    private var saveToPhotosSubtitle: String {
        if isSavingToPhotos {
            return "Saving…"
        }
        if let saveToPhotosStatusMessage, !saveToPhotosStatusMessage.isEmpty {
            return saveToPhotosStatusMessage
        }
        return completedExportURL == nil ? "Available after export" : "Add to photo library"
    }

    private var shareSubtitle: String {
        completedExportURL == nil ? "Available after export" : "Open system share sheet"
    }

    private var recorderPrimaryColor: Color {
        sessionViewModel.isLightGlassAppearance ? Color.black.opacity(0.88) : Color.white
    }

    private var recorderStrongSecondaryColor: Color {
        sessionViewModel.isLightGlassAppearance ? Color.black.opacity(0.82) : Color.white.opacity(0.92)
    }

    @MainActor
    private func saveVideoToPhotos(url: URL) async throws {
#if canImport(Photos) && !targetEnvironment(macCatalyst)
        let authorizationStatus = await requestPhotoAddAuthorizationIfNeeded()
        switch authorizationStatus {
        case .authorized, .limited:
            break
        case .denied, .restricted:
            throw SaveToPhotosError.permissionDenied
        default:
            throw SaveToPhotosError.unavailable
        }

        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? SaveToPhotosError.saveFailed)
                }
            }
        }
#else
        throw SaveToPhotosError.unavailable
#endif
    }

#if canImport(Photos)
    @MainActor
    private func requestPhotoAddAuthorizationIfNeeded() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if current == .notDetermined {
            return await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        return current
    }
#endif

    private enum SaveToPhotosError: LocalizedError {
        case permissionDenied
        case unavailable
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Photos access denied. Enable access in Settings."
            case .unavailable:
                return "Save to Photos is unavailable on this device."
            case .saveFailed:
                return "Could not save to Photos."
            }
        }
    }

    private func performImpactHaptic() {
#if canImport(UIKit) && !targetEnvironment(macCatalyst)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
#endif
    }

    private func performNotificationHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
#if canImport(UIKit) && !targetEnvironment(macCatalyst)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
#endif
    }
}

struct SettingsDiagnosticsSheet: View {
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var sessionViewModel: SessionViewModel
    let dismiss: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var inkTransitionProgress: CGFloat = 0.001
    @State private var inkTransitionOpacity: Double = 0
    @State private var diagnosticsExpanded = false
    @State private var showsResetSessionConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    chromaProSection
                    performanceSection
                    audioCalibrationSection
                    if sessionViewModel.session.activeModeID == .riemannCorridor {
                        navigationSection
                    }
                    modeDefaultsSection
                    sessionRecoverySection
                    audioInputSection
                    midiSection
                    playbackSection
                    outputSection
                    appearanceSection
                    aboutSection
                    exportSection
                    diagnosticsSection
                }
                .font(ChromaTypography.body)
                .navigationTitle("SETTINGS / DIAGNOSTICS")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        SheetToolbarCloseButton(action: dismiss)
                    }
                }
                .onChange(of: sessionViewModel.appearanceTransitionToken) { _, _ in
                    triggerInkTransition()
                }

                AppearanceInkTransitionOverlay(
                    color: sessionViewModel.isLightGlassAppearance ? Color.white : Color.black,
                    progress: inkTransitionProgress,
                    opacity: inkTransitionOpacity
                )
                .allowsHitTesting(false)
            }
        }
        .confirmationDialog(
            "Reset to clean state?",
            isPresented: $showsResetSessionConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Session", role: .destructive) {
                Task {
                    await sessionViewModel.resetToCleanState()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears current session state and live parameters. Presets and mode defaults are preserved.")
        }
    }
    
    private var chromaProSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ChromaProBadge(style: .status(appViewModel.billingStore.proAccessVisualState))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(appViewModel.billingStore.proAccessVisualSignals.title)
                            .font(ChromaTypography.sheetRowTitle)

                        if let caption = appViewModel.billingStore.proAccessVisualSignals.caption {
                            Text(caption)
                                .font(ChromaTypography.bodySecondary)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    ExportSettingTileButton(
                        title: "Restore Purchases",
                        subtitle: nil,
                        isSelected: false,
                        isEnabled: !appViewModel.billingStore.isPurchasing,
                        tintColor: exportSettingsTintColor,
                        isLightAppearance: sessionViewModel.isLightGlassAppearance
                    ) {
                        Task {
                            await appViewModel.billingStore.restorePurchases()
                        }
                    }

                    ExportSettingTileButton(
                        title: "Manage Subscription",
                        subtitle: nil,
                        isSelected: false,
                        isEnabled: true,
                        tintColor: exportSettingsTintColor,
                        isLightAppearance: sessionViewModel.isLightGlassAppearance
                    ) {
                        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
                        openURL(url)
                    }
                }
            }
            .padding(.vertical, 2)
        } header: {
            sectionHeader("Chroma Pro")
        }
    }

    private var performanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(PerformanceMode.allCases, id: \.self) { mode in
                        ExportSettingTileButton(
                            title: mode.label,
                            subtitle: nil,
                            isSelected: sessionViewModel.session.performanceSettings.mode == mode,
                            isEnabled: true,
                            tintColor: exportSettingsTintColor,
                            isLightAppearance: sessionViewModel.isLightGlassAppearance
                        ) {
                            sessionViewModel.setPerformanceMode(mode)
                        }
                    }
                }

                ExportSettingTileButton(
                    title: "Thermal Fallback",
                    subtitle: sessionViewModel.thermalFallbackIsActive ? "Active" : "Standby",
                    isSelected: sessionViewModel.session.performanceSettings.thermalAwareFallbackEnabled,
                    isEnabled: true,
                    tintColor: exportSettingsTintColor,
                    isLightAppearance: sessionViewModel.isLightGlassAppearance
                ) {
                    sessionViewModel.setThermalAwareFallbackEnabled(!sessionViewModel.session.performanceSettings.thermalAwareFallbackEnabled)
                }

                if sessionViewModel.thermalFallbackIsActive {
                    Text("Thermal state is elevated. Safe FPS policy is temporarily forced.")
                        .font(ChromaTypography.bodySecondary)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        } header: {
            sectionHeader("Performance")
        }
    }

    private var audioCalibrationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                ExportSettingTileButton(
                    title: sessionViewModel.isCalibratingInput ? "Calibrating…" : "Calibrate Room Noise",
                    subtitle: sessionViewModel.isCalibratingInput ? "Capturing 2.5s ambient window" : "Capture venue floor and apply recommendations",
                    isSelected: sessionViewModel.isCalibratingInput,
                    isEnabled: !sessionViewModel.isCalibratingInput,
                    tintColor: exportSettingsTintColor,
                    isLightAppearance: sessionViewModel.isLightGlassAppearance
                ) {
                    Task {
                        await sessionViewModel.calibrateRoomNoise()
                    }
                }

                calibrationStepperRow(
                    title: "Attack Gate",
                    valueLabel: String(format: "%.1f dB", sessionViewModel.session.audioCalibrationSettings.attackThresholdDB),
                    onDecrement: { sessionViewModel.adjustAttackThreshold(by: -0.5) },
                    onIncrement: { sessionViewModel.adjustAttackThreshold(by: 0.5) }
                )

                calibrationStepperRow(
                    title: "Silence Gate",
                    valueLabel: String(format: "%.3f", sessionViewModel.session.audioCalibrationSettings.silenceGateThreshold),
                    onDecrement: { sessionViewModel.adjustSilenceGateThreshold(by: -0.005) },
                    onIncrement: { sessionViewModel.adjustSilenceGateThreshold(by: 0.005) }
                )

                if let calibrationStatusMessage = sessionViewModel.calibrationStatusMessage {
                    Text(calibrationStatusMessage)
                        .font(ChromaTypography.bodySecondary)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        } header: {
            sectionHeader("Audio Calibration")
        }
    }

    private var navigationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ExportSettingTileButton(
                        title: "Guided Zoom",
                        subtitle: nil,
                        isSelected: !sessionViewModel.riemannNavigationIsFreeFlight,
                        isEnabled: true,
                        tintColor: exportSettingsTintColor,
                        isLightAppearance: sessionViewModel.isLightGlassAppearance
                    ) {
                        sessionViewModel.setRiemannNavigationMode(freeFlight: false)
                    }
                    ExportSettingTileButton(
                        title: "Free Flight",
                        subtitle: nil,
                        isSelected: sessionViewModel.riemannNavigationIsFreeFlight,
                        isEnabled: true,
                        tintColor: exportSettingsTintColor,
                        isLightAppearance: sessionViewModel.isLightGlassAppearance
                    ) {
                        sessionViewModel.setRiemannNavigationMode(freeFlight: true)
                    }
                }

                calibrationStepperRow(
                    title: "Steering Strength",
                    valueLabel: String(format: "%.2f", sessionViewModel.riemannSteeringStrength),
                    onDecrement: { sessionViewModel.adjustRiemannSteeringStrength(by: -0.04) },
                    onIncrement: { sessionViewModel.adjustRiemannSteeringStrength(by: 0.04) }
                )
            }
            .padding(.vertical, 2)
        } header: {
            sectionHeader("Navigation")
        }
    }

    private var modeDefaultsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ExportSettingTileButton(
                        title: "Set Current as Default",
                        subtitle: nil,
                        isSelected: false,
                        isEnabled: true,
                        tintColor: exportSettingsTintColor,
                        isLightAppearance: sessionViewModel.isLightGlassAppearance
                    ) {
                        sessionViewModel.setCurrentModeAsDefault()
                    }

                    ExportSettingTileButton(
                        title: "Reset Mode Defaults",
                        subtitle: nil,
                        isSelected: false,
                        isEnabled: true,
                        tintColor: exportSettingsTintColor,
                        isLightAppearance: sessionViewModel.isLightGlassAppearance
                    ) {
                        sessionViewModel.resetCurrentModeDefaults()
                    }
                }

                if let modeDefaultsStatusMessage = sessionViewModel.modeDefaultsStatusMessage {
                    Text(modeDefaultsStatusMessage)
                        .font(ChromaTypography.bodySecondary)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        } header: {
            sectionHeader("Mode Defaults")
        }
    }

    private var sessionRecoverySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ExportSettingTileButton(
                        title: "Auto-save Session",
                        subtitle: sessionViewModel.session.sessionRecoverySettings.autoSaveEnabled ? "On" : "Off",
                        isSelected: sessionViewModel.session.sessionRecoverySettings.autoSaveEnabled,
                        isEnabled: true,
                        tintColor: exportSettingsTintColor,
                        isLightAppearance: sessionViewModel.isLightGlassAppearance
                    ) {
                        sessionViewModel.setSessionAutoSaveEnabled(!sessionViewModel.session.sessionRecoverySettings.autoSaveEnabled)
                    }
                    ExportSettingTileButton(
                        title: "Restore on Launch",
                        subtitle: sessionViewModel.session.sessionRecoverySettings.restoreOnLaunchEnabled ? "On" : "Off",
                        isSelected: sessionViewModel.session.sessionRecoverySettings.restoreOnLaunchEnabled,
                        isEnabled: true,
                        tintColor: exportSettingsTintColor,
                        isLightAppearance: sessionViewModel.isLightGlassAppearance
                    ) {
                        sessionViewModel.setRestoreOnLaunchEnabled(!sessionViewModel.session.sessionRecoverySettings.restoreOnLaunchEnabled)
                    }
                }

                ExportSettingTileButton(
                    title: "Reset to Clean State",
                    subtitle: "Panic action (keeps presets/default libraries)",
                    isSelected: false,
                    isEnabled: true,
                    tintColor: .red,
                    isLightAppearance: sessionViewModel.isLightGlassAppearance
                ) {
                    showsResetSessionConfirmation = true
                }

                if let sessionRecoveryStatusMessage = sessionViewModel.sessionRecoveryStatusMessage {
                    Text(sessionRecoveryStatusMessage)
                        .font(ChromaTypography.bodySecondary)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        } header: {
            sectionHeader("Session Recovery")
        }
    }

    @ViewBuilder
    private func calibrationStepperRow(
        title: String,
        valueLabel: String,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            ExportSettingTileButton(
                title: "−",
                subtitle: nil,
                isSelected: false,
                isEnabled: true,
                tintColor: exportSettingsTintColor,
                isLightAppearance: sessionViewModel.isLightGlassAppearance,
                action: onDecrement
            )
            .frame(width: 72)

            Text("\(title): \(valueLabel)")
                .font(ChromaTypography.metric.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .recorderGlassCardBackground(
                    cornerRadius: 12,
                    isLightAppearance: sessionViewModel.isLightGlassAppearance
                )

            ExportSettingTileButton(
                title: "+",
                subtitle: nil,
                isSelected: false,
                isEnabled: true,
                tintColor: exportSettingsTintColor,
                isLightAppearance: sessionViewModel.isLightGlassAppearance,
                action: onIncrement
            )
            .frame(width: 72)
        }
    }

    private var exportSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                Text("Resolution")
                    .font(ChromaTypography.sheetRowTitle)
                HStack(spacing: 8) {
                    ForEach(ExportResolutionPreset.allCases, id: \.self) { preset in
                        ExportSettingTileButton(
                            title: preset.label,
                            subtitle: nil,
                            isSelected: sessionViewModel.exportCaptureSettings.resolutionPreset == preset,
                            isEnabled: true,
                            tintColor: exportSettingsTintColor,
                            isLightAppearance: sessionViewModel.isLightGlassAppearance
                        ) {
                            sessionViewModel.setExportResolutionPreset(preset)
                        }
                    }
                }

                Text("Frame Rate")
                    .font(ChromaTypography.sheetRowTitle)
                HStack(spacing: 8) {
                    ForEach(ExportFrameRate.allCases, id: \.self) { frameRate in
                        ExportSettingTileButton(
                            title: "\(frameRate.label) fps",
                            subtitle: nil,
                            isSelected: sessionViewModel.exportCaptureSettings.frameRate == frameRate,
                            isEnabled: true,
                            tintColor: exportSettingsTintColor,
                            isLightAppearance: sessionViewModel.isLightGlassAppearance
                        ) {
                            sessionViewModel.setExportFrameRate(frameRate)
                        }
                    }
                }

                Text("Codec")
                    .font(ChromaTypography.sheetRowTitle)
                HStack(spacing: 8) {
                    ForEach(ExportVideoCodec.allCases, id: \.self) { codec in
                        let isEnabled = sessionViewModel.isExportCodecSupported(codec)
                        ExportSettingTileButton(
                            title: codec.label,
                            subtitle: codecSubtitle(for: codec),
                            isSelected: sessionViewModel.exportCaptureSettings.codec == codec,
                            isEnabled: isEnabled,
                            tintColor: exportSettingsTintColor,
                            isLightAppearance: sessionViewModel.isLightGlassAppearance
                        ) {
                            sessionViewModel.setExportVideoCodec(codec)
                        }
                    }
                }

                let unsupported = ExportVideoCodec.allCases
                    .filter { !sessionViewModel.isExportCodecSupported($0) }
                    .map(\.label)

                if !unsupported.isEmpty {
                    Text("Unavailable on this device: \(unsupported.joined(separator: ", ")).")
                        .font(ChromaTypography.bodySecondary)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            sectionHeader("Export")
        }
    }

    private var appearanceSection: some View {
        Section {
            GlassAppearanceToggleTile(
                isLightAppearance: sessionViewModel.isLightGlassAppearance
            ) {
                sessionViewModel.toggleGlassAppearanceStyle()
            }
            .padding(.vertical, 2)
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            sectionHeader("Appearance")
        }
    }

    private var aboutSection: some View {
        Section {
            NavigationLink {
                AboutChromaView(isLightAppearance: sessionViewModel.isLightGlassAppearance)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(exportSettingsTintColor)
                        .frame(width: 34, height: 34)
                        .background(
                            sessionViewModel.isLightGlassAppearance ? Color.black.opacity(0.09) : Color.white.opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("About Chroma")
                            .font(ChromaTypography.sheetRowTitle)
                        Text("Website, privacy, support, and version info.")
                            .font(ChromaTypography.bodySecondary)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(14)
                .recorderGlassCardBackground(
                    cornerRadius: 16,
                    isLightAppearance: sessionViewModel.isLightGlassAppearance
                )
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            sectionHeader("About")
        }
    }

    private var exportSettingsTintColor: Color {
        let rangeValue = sessionViewModel.parameterStore.value(for: "mode.colorShift.hueRange", scope: .mode(.colorShift))
        let hueRange = rangeValue?.hueRangeValue ?? (min: 0.13, max: 0.87, outside: false)
        let hueCenter = settingsHueArcCenter(
            minValue: hueRange.min,
            maxValue: hueRange.max,
            outside: hueRange.outside,
            hueShift: sessionViewModel.colorShiftHueCenterShift
        )
        return Color(hue: hueCenter, saturation: 0.72, brightness: 0.95)
    }

    private func codecSubtitle(for codec: ExportVideoCodec) -> String? {
        switch codec {
        case .hevc:
            return "Efficient"
        case .h264:
            return "Compatible"
        case .proRes422:
            return "Master"
        }
    }

    private var audioInputSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Authorization")
                        .font(ChromaTypography.sheetRowTitle)
                    Spacer(minLength: 10)
                    Text(sessionViewModel.audioAuthorizationStatus.rawValue)
                        .font(ChromaTypography.metric)
                        .foregroundStyle(.secondary)
                }

                if sessionViewModel.availableAudioInputSources.isEmpty {
                    Text("No input sources are currently available.")
                        .font(ChromaTypography.bodySecondary)
                        .foregroundStyle(.secondary)
                } else {
                    let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(sessionViewModel.availableAudioInputSources) { source in
                            ExportSettingTileButton(
                                title: source.name,
                                subtitle: source.transportSummary,
                                isSelected: source.id == sessionViewModel.selectedAudioInputSourceID,
                                isEnabled: true,
                                tintColor: exportSettingsTintColor,
                                isLightAppearance: sessionViewModel.isLightGlassAppearance
                            ) {
                                sessionViewModel.selectAudioInputSource(id: source.id)
                                Task {
                                    await sessionViewModel.restartRealtimeAudioPipeline()
                                }
                            }
                        }
                    }
                }

                ExportSettingTileButton(
                    title: "Restart Input",
                    subtitle: "Reinitialize audio capture",
                    isSelected: false,
                    isEnabled: true,
                    tintColor: exportSettingsTintColor,
                    isLightAppearance: sessionViewModel.isLightGlassAppearance
                ) {
                    Task {
                        await sessionViewModel.restartRealtimeAudioPipeline()
                    }
                }
            }
            .padding(.vertical, 2)
        } header: {
            sectionHeader("Input")
        }
    }

    // MARK: - MIDI Section

    private var midiSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Status")
                        .font(ChromaTypography.sheetRowTitle)
                    Spacer(minLength: 10)
                    if sessionViewModel.isMIDIActive {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Active")
                                .font(ChromaTypography.metric)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Inactive")
                            .font(ChromaTypography.metric)
                            .foregroundStyle(.secondary)
                    }
                }

                if sessionViewModel.midiConnectedDevices.isEmpty {
                    Text("No MIDI devices connected. Connect a device via USB or Bluetooth.")
                        .font(ChromaTypography.bodySecondary)
                        .foregroundStyle(.secondary)
                } else {
                    let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(sessionViewModel.midiConnectedDevices) { device in
                            ExportSettingTileButton(
                                title: device.name,
                                subtitle: device.manufacturer.isEmpty ? "MIDI" : device.manufacturer,
                                isSelected: true,
                                isEnabled: true,
                                tintColor: exportSettingsTintColor,
                                isLightAppearance: sessionViewModel.isLightGlassAppearance
                            ) { }
                        }
                    }
                }

                if let tempo = sessionViewModel.midiTempoState, tempo.bpm > 0 {
                    HStack {
                        Text("Tempo")
                            .font(ChromaTypography.sheetRowTitle)
                        Spacer(minLength: 10)
                        Text(String(format: "%.0f BPM", tempo.bpm))
                            .font(ChromaTypography.metric)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    ExportSettingTileButton(
                        title: sessionViewModel.isMIDIActive ? "Stop MIDI" : "Start MIDI",
                        subtitle: sessionViewModel.isMIDIActive ? "Disconnect" : "Listen for devices",
                        isSelected: sessionViewModel.isMIDIActive,
                        isEnabled: true,
                        tintColor: exportSettingsTintColor,
                        isLightAppearance: sessionViewModel.isLightGlassAppearance
                    ) {
                        if sessionViewModel.isMIDIActive {
                            sessionViewModel.stopMIDI()
                        } else {
                            sessionViewModel.startMIDI()
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        } header: {
            sectionHeader("MIDI")
        }
    }

    // MARK: - Playback Section

    private var playbackSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                if let title = sessionViewModel.playbackNowPlayingTitle {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(ChromaTypography.sheetRowTitle)
                            if let artist = sessionViewModel.playbackNowPlayingArtist {
                                Text(artist)
                                    .font(ChromaTypography.bodySecondary)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 10)
                        if sessionViewModel.isPlaybackActive {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                        }
                    }

                    HStack(spacing: 8) {
                        ExportSettingTileButton(
                            title: sessionViewModel.isPlaybackActive ? "Pause" : "Resume",
                            subtitle: nil,
                            isSelected: sessionViewModel.isPlaybackActive,
                            isEnabled: true,
                            tintColor: exportSettingsTintColor,
                            isLightAppearance: sessionViewModel.isLightGlassAppearance
                        ) {
                            if sessionViewModel.isPlaybackActive {
                                sessionViewModel.pausePlayback()
                            } else {
                                sessionViewModel.resumePlayback()
                            }
                        }

                        ExportSettingTileButton(
                            title: "Stop",
                            subtitle: nil,
                            isSelected: false,
                            isEnabled: true,
                            tintColor: exportSettingsTintColor,
                            isLightAppearance: sessionViewModel.isLightGlassAppearance
                        ) {
                            sessionViewModel.stopPlayback()
                        }
                    }
                } else {
                    Text("Select a song from your device library to drive visuals directly — no microphone needed.")
                        .font(ChromaTypography.bodySecondary)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        } header: {
            sectionHeader("Playback")
        }
    }

    private var outputSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(sessionViewModel.session.availableDisplayTargets, id: \.id) { target in
                        let selectingExternalRequiresPro =
                            target.id == "external" &&
                            !appViewModel.billingStore.proAccessVisualState.hasFeatureAccess

                        ExportSettingTileButton(
                            title: target.name,
                            subtitle: selectingExternalRequiresPro ? "Pro required" : (target.isAvailable ? "Ready" : "Unavailable"),
                            isSelected: target.id == sessionViewModel.session.outputState.selectedDisplayTargetID,
                            isEnabled: target.isAvailable,
                            tintColor: exportSettingsTintColor,
                            isLightAppearance: sessionViewModel.isLightGlassAppearance
                        ) {
                            if target.id == "external" && !appViewModel.billingStore.proAccessVisualState.hasFeatureAccess {
                                appViewModel.presentPaywall(entryPoint: .externalDisplay, dismissingPresentedSheet: true)
                                return
                            }
                            sessionViewModel.selectDisplayTarget(id: target.id)
                        }
                        .overlay(alignment: .topTrailing) {
                            if selectingExternalRequiresPro {
                                ChromaProBadge(style: .locked)
                                    .padding(6)
                            }
                        }
                    }
                }

#if canImport(AVKit) && !targetEnvironment(macCatalyst)
                HStack(spacing: 12) {
                    Image(systemName: "airplayvideo")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(
                            sessionViewModel.isLightGlassAppearance ? Color.black.opacity(0.09) : Color.white.opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AirPlay Route")
                            .font(ChromaTypography.sheetRowTitle)
                        Text("Choose an external route for clean output.")
                            .font(ChromaTypography.bodySecondary)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    AirPlayRoutePickerRow()
                        .frame(width: 44, height: 30)
                }
                .padding(14)
                .recorderGlassCardBackground(
                    cornerRadius: 16,
                    isLightAppearance: sessionViewModel.isLightGlassAppearance
                )
#endif
            }
            .padding(.vertical, 2)
        } header: {
            sectionHeader("Output")
        }
    }

    private var diagnosticsSection: some View {
        Section {
            DisclosureGroup(
                isExpanded: $diagnosticsExpanded
            ) {
                VStack(spacing: 8) {
                    LabeledContent("Audio", value: sessionViewModel.diagnosticsSnapshot.audioStatus)
                    LabeledContent("Meter RMS", value: String(format: "%.3f", sessionViewModel.latestAudioMeterFrame.rms))
                    LabeledContent("Meter Peak", value: String(format: "%.3f", sessionViewModel.latestAudioMeterFrame.peak))
                    LabeledContent("Feature Amplitude", value: String(format: "%.3f", sessionViewModel.latestAudioFeatureFrame.amplitude))
                    LabeledContent("Transient", value: String(format: "%.3f", sessionViewModel.latestAudioFeatureFrame.transientStrength))
                    LabeledContent("Renderer", value: sessionViewModel.diagnosticsSnapshot.rendererStatus)
                    LabeledContent("Renderer Message", value: sessionViewModel.diagnosticsSnapshot.renderer.statusMessage)
                    LabeledContent("Resolution", value: sessionViewModel.diagnosticsSnapshot.renderer.resolutionLabel)
                    LabeledContent("Approx. FPS", value: String(format: "%.1f", sessionViewModel.diagnosticsSnapshot.renderer.approximateFPS))
                    LabeledContent("Average Frame", value: String(format: "%.2f ms", sessionViewModel.diagnosticsSnapshot.averageFrameTimeMS))
                    LabeledContent("Dropped Frames", value: String(sessionViewModel.diagnosticsSnapshot.droppedFrameCount))
                    LabeledContent("Active Mode", value: sessionViewModel.diagnosticsSnapshot.renderer.activeModeSummary)
                }
                .padding(.top, 8)
            } label: {
                Text("Show Diagnostics")
                    .font(ChromaTypography.sheetRowTitle)
            }
        } header: {
            sectionHeader("Diagnostics")
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(ChromaTypography.sheetSectionHeader)
            .tracking(1.4)
    }

    private func triggerInkTransition() {
        inkTransitionProgress = 0.001
        inkTransitionOpacity = 0.60
        withAnimation(.easeOut(duration: 0.68)) {
            inkTransitionProgress = 2.05
            inkTransitionOpacity = 0
        }
    }
}

struct AboutChromaLink: Equatable, Identifiable {
    let title: String
    let subtitle: String
    let systemImage: String
    let urlString: String

    var id: String {
        title
    }
}

func chromaAboutLinkCatalog() -> [AboutChromaLink] {
    [
        AboutChromaLink(
            title: "Chroma",
            subtitle: "Product site and release notes",
            systemImage: "globe",
            urlString: "https://stagedevices.github.io/chroma"
        ),
        AboutChromaLink(
            title: "Privacy",
            subtitle: "Privacy policy and data handling",
            systemImage: "hand.raised",
            urlString: "https://stagedevices.github.io/chroma/privacy"
        ),
        AboutChromaLink(
            title: "Support",
            subtitle: "Get help and contact options",
            systemImage: "questionmark.circle",
            urlString: "https://stagedevices.github.io/chroma/support"
        ),
    ]
}

func chromaAboutVersionString(infoDictionary: [String: Any]?) -> String {
    let version = (infoDictionary?["CFBundleShortVersionString"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let build = (infoDictionary?["CFBundleVersion"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines)

    let validVersion = (version?.isEmpty == false) ? version : nil
    let validBuild = (build?.isEmpty == false) ? build : nil

    switch (validVersion, validBuild) {
    case let (version?, build?):
        return "\(version) (\(build))"
    case let (version?, nil):
        return version
    case let (nil, build?):
        return "Build \(build)"
    case (nil, nil):
        return "Version unavailable"
    }
}

private struct AboutChromaView: View {
    let isLightAppearance: Bool

    @Environment(\.openURL) private var openURL
    @State private var copyStatusMessage: String?

    private var aboutLinks: [AboutChromaLink] { chromaAboutLinkCatalog() }
    private var versionString: String { chromaAboutVersionString(infoDictionary: Bundle.main.infoDictionary) }
    private var versionAndBuild: (version: String, build: String) {
        chromaAboutVersionBuild(infoDictionary: Bundle.main.infoDictionary)
    }
    private var appURL: URL? {
        URL(string: "https://stagedevices.github.io/chroma")
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.cyan.opacity(isLightAppearance ? 0.28 : 0.22),
                                            Color.indigo.opacity(isLightAppearance ? 0.20 : 0.30),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Image(systemName: "waveform.path.ecg.rectangle")
                                .font(.system(size: 22, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(
                                    isLightAppearance ? Color.black.opacity(0.90) : Color.white.opacity(0.92),
                                    Color.cyan.opacity(0.90)
                                )
                        }
                        .frame(width: 52, height: 52)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Chroma")
                                .font(.system(size: 34, weight: .black, design: .default))
                                .lineLimit(1)
                            Text("Live audio-reactive visual instrument")
                                .font(ChromaTypography.bodySecondary)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Text("Designed for stage performance, projection output, and clean capture workflows.")
                        .font(ChromaTypography.bodySecondary)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        AboutMetaPill(title: "Version", value: versionAndBuild.version, isLightAppearance: isLightAppearance)
                        AboutMetaPill(title: "Build", value: versionAndBuild.build, isLightAppearance: isLightAppearance)
                        Spacer(minLength: 0)
                    }
                }
                .padding(16)
                .recorderGlassCardBackground(cornerRadius: 18, isLightAppearance: isLightAppearance)
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                Text("Overview")
                    .font(ChromaTypography.sheetSectionHeader)
                    .tracking(1.4)
            }

            Section {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(Array(aboutLinks.enumerated()), id: \.element.id) { index, link in
                        let tile = AboutQuickActionTile(
                            link: link,
                            isLightAppearance: isLightAppearance
                        ) {
                            open(link: link)
                        }
                        if index == aboutLinks.count - 1 {
                            tile.gridCellColumns(2)
                        } else {
                            tile
                        }
                    }
                }
                .padding(.vertical, 2)
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                Text("Actions")
                    .font(ChromaTypography.sheetSectionHeader)
                    .tracking(1.4)
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        AboutUtilityPillButton(
                            title: "Copy Version",
                            systemImage: "document.on.document",
                            isLightAppearance: isLightAppearance
                        ) {
                            copyToClipboard(versionString, status: "Version copied")
                        }
                        if let appURL {
                            ShareLink(item: appURL) {
                                AboutUtilityPillButtonLabel(
                                    title: "Share App Link",
                                    systemImage: "square.and.arrow.up",
                                    isLightAppearance: isLightAppearance
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let copyStatusMessage {
                        Text(copyStatusMessage)
                            .font(ChromaTypography.bodySecondary)
                            .foregroundStyle(.secondary)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Text("stagedevices.github.io/chroma")
                        .font(ChromaTypography.bodySecondary)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .recorderGlassCardBackground(cornerRadius: 16, isLightAppearance: isLightAppearance)
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                Text("Details")
                    .font(ChromaTypography.sheetSectionHeader)
                    .tracking(1.4)
            }
        }
        .font(ChromaTypography.body)
        .navigationTitle("ABOUT")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func open(link: AboutChromaLink) {
        guard let url = URL(string: link.urlString), url.scheme == "https", url.host != nil else {
            return
        }
        openURL(url)
    }

    private func copyToClipboard(_ text: String, status: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
#if canImport(UIKit)
        UIPasteboard.general.string = text
#endif
        withAnimation(.easeInOut(duration: 0.18)) {
            copyStatusMessage = status
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(.easeInOut(duration: 0.20)) {
                if copyStatusMessage == status {
                    copyStatusMessage = nil
                }
            }
        }
    }
}

private func chromaAboutVersionBuild(infoDictionary: [String: Any]?) -> (version: String, build: String) {
    let version = (infoDictionary?["CFBundleShortVersionString"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let build = (infoDictionary?["CFBundleVersion"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines)

    let resolvedVersion = (version?.isEmpty == false) ? version! : "Unknown"
    let resolvedBuild = (build?.isEmpty == false) ? build! : "Unknown"
    return (version: resolvedVersion, build: resolvedBuild)
}

private struct SettingsSurfaceSliderRow: View {
    let descriptor: ParameterDescriptor
    let value: ParameterValue
    let hueShift: Double
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
                        Text(settingsExcitementModeLabel(for: modeIndex).uppercased())
                            .font(ChromaTypography.metric.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Picker(
                        "",
                        selection: Binding(
                            get: { min(max(Int((value.scalarValue ?? 0).rounded()), 0), 2) },
                            set: { newValue in
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
                                onChange(.scalar(newValue))
                            }
                        ),
                        in: (descriptor.minimumValue ?? 0) ... (descriptor.maximumValue ?? 1)
                    )
                    .tint(.primary)
                }
            }
            .padding(.vertical, 4)
        case .toggle:
            Toggle(isOn: Binding(
                get: { value.toggleValue ?? false },
                set: { isOn in onChange(.toggle(isOn)) }
            )) {
                Text(descriptor.title.uppercased())
                    .font(ChromaTypography.action)
                    .tracking(0.6)
            }
            .tint(.primary)
            .padding(.vertical, 4)
        case .hueRange:
            let hueRange = value.hueRangeValue ?? (min: 0.13, max: 0.87, outside: false)
            SettingsHueRangeEditorRow(
                descriptor: descriptor,
                minValue: hueRange.min,
                maxValue: hueRange.max,
                outside: hueRange.outside,
                hueShift: hueShift,
                onChange: { minValue, maxValue, outside in
                    onChange(.hueRange(min: minValue, max: maxValue, outside: outside))
                },
                onShift: { delta in
                    onHueShift(delta)
                }
            )
            .padding(.vertical, 4)
        }
    }
}

private struct SettingsHueRangeEditorRow: View {
    let descriptor: ParameterDescriptor
    let minValue: Double
    let maxValue: Double
    let outside: Bool
    let hueShift: Double
    let onChange: (Double, Double, Bool) -> Void
    let onShift: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(descriptor.title.uppercased())
                    .font(ChromaTypography.action)
                    .tracking(0.6)
                Spacer(minLength: 8)

                Picker("", selection: Binding(
                    get: { outside },
                    set: { onChange(minValue, maxValue, $0) }
                )) {
                    Text("Inside").tag(false)
                    Text("Outside").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 134)

                Text("C \(settingsHueDegrees(settingsHueArcCenter(minValue: minValue, maxValue: maxValue, outside: outside, hueShift: hueShift)))°")
                    .font(ChromaTypography.metric.monospacedDigit())
                    .foregroundStyle(.primary)
                Text(
                    "\(settingsHueDegrees(settingsWrapUnitHue(minValue + hueShift)))° · \(settingsHueDegrees(settingsWrapUnitHue(maxValue + hueShift)))°"
                )
                .font(ChromaTypography.metric.monospacedDigit())
                .foregroundStyle(.secondary)

                SettingsHueRangeTrimWheel(onDelta: onShift)
            }

            SettingsHueRangeTrack(
                minValue: minValue,
                maxValue: maxValue,
                outside: outside,
                hueShift: hueShift,
                onMinChange: { onChange($0, maxValue, outside) },
                onMaxChange: { onChange(minValue, $0, outside) }
            )
        }
    }
}

private struct SettingsHueRangeTrack: View {
    let minValue: Double
    let maxValue: Double
    let outside: Bool
    let hueShift: Double
    let onMinChange: (Double) -> Void
    let onMaxChange: (Double) -> Void
    @State private var activeHandle: HueRangeHandle?
    @Environment(\.colorScheme) private var colorScheme

    private let trackHeight: CGFloat = 22

    private enum HueRangeHandle {
        case min
        case max
    }

    private var hueGradient: LinearGradient {
        LinearGradient(
            stops: stride(from: 0.0, through: 1.0, by: 1.0 / 12.0).map { location in
                .init(color: Color(hue: settingsWrapUnitHue(location + hueShift), saturation: 1, brightness: 1), location: location)
            },
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)
            let handleDiameter = max(height + 8, 20)
            let handleRadius = handleDiameter * 0.5
            let travelWidth = max(width - handleDiameter, 1)
            let clampedMin = min(max(minValue, 0), 1)
            let clampedMax = min(max(maxValue, 0), 1)
            let minX = handleRadius + (CGFloat(clampedMin) * travelWidth)
            let maxX = handleRadius + (CGFloat(clampedMax) * travelWidth)

            ZStack {
                RoundedRectangle(cornerRadius: height * 0.5, style: .continuous)
                    .fill(hueGradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: height * 0.5, style: .continuous)
                            .fill(Color.black.opacity(0.36))
                    }
                    .overlay {
                        ZStack {
                            ForEach(Array(settingsSelectedHueIntervals(minValue: clampedMin, maxValue: clampedMax, outside: outside).enumerated()), id: \.offset) { _, interval in
                                let startX = CGFloat(interval.0) * width
                                let segmentWidth = max(CGFloat(interval.1 - interval.0) * width, 0)
                                hueGradient
                                    .frame(width: width, height: height)
                                    .mask(
                                        Rectangle()
                                            .frame(width: segmentWidth, height: height)
                                            .offset(x: startX - ((width - segmentWidth) * 0.5))
                                    )
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: height * 0.5, style: .continuous))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: height * 0.5, style: .continuous)
                            .stroke(
                                colorScheme == .light ? Color.black.opacity(0.20) : Color.white.opacity(0.24),
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
                    .shadow(color: .black.opacity(0.20), radius: 2, x: 0, y: 1)
                    .position(x: minX, y: height * 0.5)
                    .zIndex(activeHandle == .min ? 2 : 1)

                Circle()
                    .fill(.white)
                    .frame(width: handleDiameter, height: handleDiameter)
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.28), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.20), radius: 2, x: 0, y: 1)
                    .position(x: maxX, y: height * 0.5)
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

private struct SettingsHueRangeTrimWheel: View {
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

private func settingsSelectedHueIntervals(minValue: Double, maxValue: Double, outside: Bool) -> [(Double, Double)] {
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

private func settingsHueArcCenter(minValue: Double, maxValue: Double, outside: Bool, hueShift: Double = 0) -> Double {
    let clampedMin = min(max(minValue, 0), 1)
    let clampedMax = min(max(maxValue, 0), 1)
    let insideWidth = settingsWrapUnitHue(clampedMax - clampedMin)
    let (start, width): (Double, Double) = outside
        ? (clampedMax, max(1 - insideWidth, 0))
        : (clampedMin, insideWidth)
    return settingsWrapUnitHue(start + (width * 0.5) + hueShift)
}

private func settingsWrapUnitHue(_ value: Double) -> Double {
    let wrapped = value - floor(value)
    return wrapped < 0 ? wrapped + 1 : wrapped
}

private func settingsHueDegrees(_ normalizedHue: Double) -> Int {
    let clamped = min(max(normalizedHue, 0), 1)
    return Int((clamped * 360).rounded()) % 360
}

private func settingsExcitementModeLabel(for index: Int) -> String {
    switch index {
    case 1:
        return "Temporal"
    case 2:
        return "Pitch"
    default:
        return "Spectral"
    }
}

private struct PalettePickerSheetContent: View {
    let title: String
    let subtitle: String
    let selectedIndex: Int
    let isLightAppearance: Bool
    let dismiss: () -> Void
    let onSelect: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectionMotionToken = UUID()
    private let options = chromaPalettePickerPresentationCatalog()
    private let columns = [
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10),
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(subtitle)
                    .font(ChromaTypography.bodySecondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 8)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(options) { option in
                        PaletteSelectorTile(
                            option: option,
                            isSelected: option.index == selectedIndex,
                            isLightAppearance: isLightAppearance,
                            motionToken: selectionMotionToken,
                            reduceMotion: reduceMotion
                        ) {
                            if !reduceMotion {
                                selectionMotionToken = UUID()
                            }
                            performImpactHaptic()
                            onSelect(option.index)
                            dismiss()
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .font(ChromaTypography.body)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetToolbarCloseButton(action: dismiss)
                }
            }
        }
    }

    private func performImpactHaptic() {
#if canImport(UIKit) && !targetEnvironment(macCatalyst)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
#endif
    }
}

private struct VariantSelectorTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accentColor: Color
    let isLightAppearance: Bool
    let isSelected: Bool
    let motionToken: UUID
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                iconView

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(ChromaTypography.sheetRowTitle)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(ChromaTypography.bodySecondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accentColor.opacity(isLightAppearance ? 0.86 : 0.92))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .recorderGlassCardBackground(cornerRadius: 16, isLightAppearance: isLightAppearance)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? accentColor.opacity(isLightAppearance ? 0.62 : 0.56)
                            : Color.secondary.opacity(isLightAppearance ? 0.24 : 0.30),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var iconView: some View {
        let icon = Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                isLightAppearance ? Color.black.opacity(0.90) : Color.white.opacity(0.94),
                accentColor.opacity(isLightAppearance ? 0.84 : 0.90)
            )
            .frame(width: 34, height: 34)
            .background(
                isLightAppearance ? Color.black.opacity(0.09) : Color.white.opacity(0.11),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )

        if reduceMotion {
            icon
        } else if #available(iOS 18.0, macCatalyst 18.0, *) {
            icon.symbolEffect(.bounce, value: motionToken)
        } else {
            icon
        }
    }
}

private struct PaletteSelectorTile: View {
    let option: PalettePickerPresentation
    let isSelected: Bool
    let isLightAppearance: Bool
    let motionToken: UUID
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    iconView
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(option.accentColor.opacity(isLightAppearance ? 0.86 : 0.92))
                    }
                }

                Text(option.name)
                    .font(ChromaTypography.sheetRowTitle)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    ForEach(Array(option.swatchHues.enumerated()), id: \.offset) { _, hue in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                hue == 0
                                    ? Color.white.opacity(isLightAppearance ? 0.34 : 0.24)
                                    : Color(hue: hue, saturation: 0.82, brightness: 0.95)
                            )
                            .frame(height: 5)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .recorderGlassCardBackground(cornerRadius: 16, isLightAppearance: isLightAppearance)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected
                            ? option.accentColor.opacity(isLightAppearance ? 0.62 : 0.56)
                            : Color.secondary.opacity(isLightAppearance ? 0.24 : 0.30),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var iconView: some View {
        let icon = Image(systemName: option.systemImage)
            .font(.system(size: 16, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                isLightAppearance ? Color.black.opacity(0.90) : Color.white.opacity(0.94),
                option.accentColor.opacity(isLightAppearance ? 0.84 : 0.90)
            )
            .frame(width: 30, height: 30)
            .background(
                isLightAppearance ? Color.black.opacity(0.09) : Color.white.opacity(0.11),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )

        if reduceMotion {
            icon
        } else if #available(iOS 18.0, macCatalyst 18.0, *) {
            icon.symbolEffect(.bounce, value: motionToken)
        } else {
            icon
        }
    }
}

private struct PresetSelectorTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accentColor: Color
    let isSelected: Bool
    let isLightAppearance: Bool
    let motionToken: UUID
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                iconView
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(ChromaTypography.sheetRowTitle)
                        .lineLimit(1)
                    Text(subtitle.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accentColor.opacity(isLightAppearance ? 0.86 : 0.92))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .recorderGlassCardBackground(cornerRadius: 16, isLightAppearance: isLightAppearance)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? accentColor.opacity(isLightAppearance ? 0.62 : 0.56)
                            : Color.secondary.opacity(isLightAppearance ? 0.24 : 0.30),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var iconView: some View {
        let icon = Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                isLightAppearance ? Color.black.opacity(0.90) : Color.white.opacity(0.94),
                accentColor.opacity(isLightAppearance ? 0.84 : 0.90)
            )
            .frame(width: 34, height: 34)
            .background(
                isLightAppearance ? Color.black.opacity(0.09) : Color.white.opacity(0.11),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )

        if reduceMotion {
            icon
        } else if #available(iOS 18.0, macCatalyst 18.0, *) {
            icon.symbolEffect(.bounce, value: motionToken)
        } else {
            icon
        }
    }
}

private struct RecorderConsoleActionTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accentColor: Color
    let isLightAppearance: Bool
    let isEnabled: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var symbolEffectToken = UUID()

    var body: some View {
        Button {
            if !reduceMotion {
                symbolEffectToken = UUID()
            }
            action()
        } label: {
            HStack(spacing: 12) {
                iconView

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(ChromaTypography.sheetRowTitle)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(ChromaTypography.bodySecondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .recorderGlassCardBackground(
                cornerRadius: 18,
                isLightAppearance: isLightAppearance
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
    }

    @ViewBuilder
    private var iconView: some View {
        let icon = Image(systemName: systemImage)
            .font(.system(size: 20, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(isLightAppearance ? Color.black.opacity(0.88) : .white, accentColor)
            .frame(width: 38, height: 38)
            .background(
                isLightAppearance ? Color.black.opacity(0.09) : Color.white.opacity(0.11),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )

        if reduceMotion {
            icon
        } else if #available(iOS 18.0, macCatalyst 18.0, *) {
            icon.symbolEffect(.bounce, value: symbolEffectToken)
        } else {
            icon
        }
    }
}

private struct AboutMetaPill: View {
    let title: String
    let value: String
    let isLightAppearance: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .default))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(value)
                .font(ChromaTypography.metric.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isLightAppearance ? Color.black.opacity(0.09) : Color.white.opacity(0.11),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}

private struct AboutQuickActionTile: View {
    let link: AboutChromaLink
    let isLightAppearance: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var symbolEffectToken = UUID()

    var body: some View {
        Button {
            if !reduceMotion {
                symbolEffectToken = UUID()
            }
            performImpactHaptic()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    iconView
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                .padding(.horizontal, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(link.title)
                        .font(ChromaTypography.sheetRowTitle)
                        .lineLimit(1)
                    Text(link.subtitle)
                        .font(ChromaTypography.bodySecondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 116, maxHeight: 116)
            .recorderGlassCardBackground(
                cornerRadius: 18,
                isLightAppearance: isLightAppearance
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var iconView: some View {
        let icon = Image(systemName: link.systemImage)
            .font(.system(size: 18, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                isLightAppearance ? Color.black.opacity(0.90) : Color.white.opacity(0.92),
                aboutAccentColor.opacity(isLightAppearance ? 0.86 : 0.88)
            )
            .frame(width: 32, height: 32)
            .background(
                isLightAppearance ? Color.black.opacity(0.09) : Color.white.opacity(0.11),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )

        if reduceMotion {
            icon
        } else if #available(iOS 18.0, macCatalyst 18.0, *) {
            icon.symbolEffect(.bounce, value: symbolEffectToken)
        } else {
            icon
        }
    }

    private var aboutAccentColor: Color {
        switch link.title {
        case "Privacy":
            return .mint
        case "Support":
            return .orange
        default:
            return .cyan
        }
    }

    private func performImpactHaptic() {
#if canImport(UIKit) && !targetEnvironment(macCatalyst)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
#endif
    }
}

private struct AboutUtilityPillButton: View {
    let title: String
    let systemImage: String
    let isLightAppearance: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AboutUtilityPillButtonLabel(
                title: title,
                systemImage: systemImage,
                isLightAppearance: isLightAppearance
            )
        }
        .buttonStyle(.plain)
    }
}

private struct AboutUtilityPillButtonLabel: View {
    let title: String
    let systemImage: String
    let isLightAppearance: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .default))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, minHeight: 36)
        .padding(.horizontal, 10)
        .background(
            isLightAppearance ? Color.black.opacity(0.09) : Color.white.opacity(0.11),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}

private struct SheetToolbarCloseButton: View {
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var symbolEffectToken = UUID()

    private var isLightAppearance: Bool {
        colorScheme == .light
    }

    var body: some View {
        Button {
            if !reduceMotion {
                symbolEffectToken = UUID()
            }
            performImpactHaptic()
            action()
        } label: {
            iconView
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel("Close")
    }

    @ViewBuilder
    private var iconView: some View {
        let icon = Image(systemName: "xmark")
            .font(.system(size: 13, weight: .black))
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                isLightAppearance ? Color.black.opacity(0.93) : Color.white.opacity(0.94),
                Color.red.opacity(isLightAppearance ? 0.80 : 0.88),
                Color.orange.opacity(isLightAppearance ? 0.84 : 0.92)
            )

        if reduceMotion {
            icon
        } else if #available(iOS 18.0, macCatalyst 18.0, *) {
            icon.symbolEffect(.wiggle.byLayer, value: symbolEffectToken)
        } else {
            icon
        }
    }

    private func performImpactHaptic() {
#if canImport(UIKit) && !targetEnvironment(macCatalyst)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
#endif
    }
}

private struct DisplayTargetRow: View {
    let target: DisplayTarget
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(target.name)
                    .font(ChromaTypography.sheetRowTitle)
                Text(target.supportsFullscreen ? "Fullscreen capable" : "Windowed only")
                    .font(ChromaTypography.bodySecondary)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}

private struct ExportShareItem: Identifiable, Equatable {
    let url: URL

    var id: String {
        url.absoluteString
    }
}

private struct ExportSettingTileButton: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let isEnabled: Bool
    let tintColor: Color
    let isLightAppearance: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(title)
                    .font(ChromaTypography.metric)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .padding(.horizontal, 8)
            .exportSettingTileBackground(
                selected: isSelected,
                tintColor: tintColor,
                isLightAppearance: isLightAppearance
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

private struct GlassAppearanceToggleTile: View {
    let isLightAppearance: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var symbolEffectToken = UUID()

    var body: some View {
        Button {
            if !reduceMotion {
                symbolEffectToken = UUID()
            }
            performImpactHaptic()
            action()
        } label: {
            HStack(spacing: 12) {
                iconView

                VStack(alignment: .leading, spacing: 2) {
                    Text(isLightAppearance ? "Light Glass" : "Dark Glass")
                        .font(ChromaTypography.sheetRowTitle)
                    Text("Tap to switch chrome and ambient theme")
                        .font(ChromaTypography.bodySecondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(isLightAppearance ? "Light" : "Dark")
                    .font(ChromaTypography.metric.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .recorderGlassCardBackground(cornerRadius: 18, isLightAppearance: isLightAppearance)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var iconView: some View {
        let icon = Image(systemName: isLightAppearance ? "sun.max" : "moon.stars")
            .font(.system(size: 19, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                isLightAppearance ? Color.black.opacity(0.90) : Color.white,
                isLightAppearance ? Color.orange.opacity(0.86) : Color.indigo.opacity(0.86)
            )
            .frame(width: 38, height: 38)
            .background(
                isLightAppearance ? Color.black.opacity(0.09) : Color.white.opacity(0.11),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )

        if reduceMotion {
            icon
        } else if #available(iOS 18.0, macCatalyst 18.0, *) {
            icon.symbolEffect(.bounce, value: symbolEffectToken)
        } else {
            icon
        }
    }

    private func performImpactHaptic() {
#if canImport(UIKit) && !targetEnvironment(macCatalyst)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
#endif
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
                            color.opacity(0.46),
                            color.opacity(0.14),
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

#if canImport(UIKit)
private struct ChromaShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}
#endif

#if canImport(AVKit) && !targetEnvironment(macCatalyst)
private struct AirPlayRoutePickerRow: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView(frame: .zero)
        picker.activeTintColor = UIColor.white
        picker.tintColor = UIColor.systemBlue
        picker.prioritizesVideoDevices = true
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
    }
}
#endif

private extension View {
    @ViewBuilder
    func recorderGlassCardBackground(cornerRadius: CGFloat, isLightAppearance: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            self
                .background(
                    (isLightAppearance ? Color.white.opacity(0.40) : Color.white.opacity(0.11)),
                    in: shape
                )
                .glassEffect(
                    .regular
                        .tint(
                            isLightAppearance
                                ? Color.black.opacity(0.07)
                                : Color.white.opacity(0.09)
                        )
                        .interactive(),
                    in: shape
                )
                .overlay {
                    shape.stroke(
                        isLightAppearance ? Color.black.opacity(0.16) : Color.white.opacity(0.14),
                        lineWidth: 1
                    )
                }
        } else {
            self
                .background(
                    isLightAppearance
                        ? AnyShapeStyle(.ultraThinMaterial)
                        : AnyShapeStyle(.regularMaterial),
                    in: shape
                )
                .overlay {
                    shape.stroke(
                        isLightAppearance ? Color.black.opacity(0.16) : Color.white.opacity(0.14),
                        lineWidth: 1
                    )
                }
        }
    }

    @ViewBuilder
    func exportSettingTileBackground(selected: Bool, tintColor: Color, isLightAppearance: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            self
                .background(
                    (selected ? tintColor.opacity(isLightAppearance ? 0.30 : 0.24) : (isLightAppearance ? Color.white.opacity(0.34) : Color.white.opacity(0.08))),
                    in: shape
                )
                .glassEffect(
                    .regular
                        .tint(
                            selected
                                ? tintColor.opacity(isLightAppearance ? 0.44 : 0.35)
                                : (isLightAppearance ? Color.black.opacity(0.05) : Color.white.opacity(0.08))
                        )
                        .interactive(),
                    in: shape
                )
                .overlay {
                    shape.stroke(
                        selected
                            ? tintColor.opacity(isLightAppearance ? 0.62 : 0.48)
                            : (isLightAppearance ? Color.black.opacity(0.14) : Color.white.opacity(0.14)),
                        lineWidth: 1
                    )
                }
        } else {
            self
                .background(
                    selected
                        ? tintColor.opacity(isLightAppearance ? 0.28 : 0.22)
                        : (isLightAppearance ? Color.white.opacity(0.34) : Color.white.opacity(0.08)),
                    in: shape
                )
                .overlay {
                    shape.stroke(
                        selected
                            ? tintColor.opacity(isLightAppearance ? 0.54 : 0.44)
                            : (isLightAppearance ? Color.black.opacity(0.14) : Color.white.opacity(0.14)),
                        lineWidth: 1
                    )
                }
        }
    }

    @ViewBuilder
    func modePickerApplyButtonBackground(
        accentGradient: LinearGradient,
        borderColor: Color,
        isLightAppearance: Bool
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            self
                .background(accentGradient.opacity(isLightAppearance ? 0.30 : 0.24), in: shape)
                .glassEffect(
                    .regular
                        .tint(borderColor.opacity(isLightAppearance ? 0.40 : 0.32))
                        .interactive(),
                    in: shape
                )
                .overlay {
                    shape.stroke(
                        borderColor.opacity(isLightAppearance ? 0.62 : 0.56),
                        lineWidth: 1
                    )
                }
        } else {
            self
                .background(
                    accentGradient.opacity(isLightAppearance ? 0.26 : 0.22),
                    in: shape
                )
                .overlay {
                    shape.stroke(
                        borderColor.opacity(isLightAppearance ? 0.58 : 0.54),
                        lineWidth: 1
                    )
                }
        }
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
