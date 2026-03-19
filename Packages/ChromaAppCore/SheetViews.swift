import SwiftUI

struct ModePickerSheet: View {
    @ObservedObject var sessionViewModel: SessionViewModel
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            List(sessionViewModel.availableModes) { mode in
                Button {
                    sessionViewModel.selectMode(mode.id)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(mode.name)
                            .font(ChromaTypography.sheetRowTitle)
                        Text(mode.summary)
                            .font(ChromaTypography.bodySecondary)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(ChromaTypography.body)
            .navigationTitle("MODES")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("CLOSE", action: dismiss)
                }
            }
        }
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("CLOSE", action: dismiss)
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

struct TunnelVariantPickerSheet: View {
    @ObservedObject var sessionViewModel: SessionViewModel
    let dismiss: () -> Void

    private let options: [(index: Int, title: String, summary: String)] = [
        (0, "Cel Cards", "Flat graphic cards with clean tunnel silhouettes."),
        (1, "Prism Shards", "Facet-driven shard silhouettes with angular edges."),
        (2, "Glyph Slabs", "Thicker slab silhouettes with bold panel feel."),
    ]

    var body: some View {
        NavigationStack {
            List(options, id: \.index) { option in
                Button {
                    sessionViewModel.setTunnelVariant(index: option.index)
                    dismiss()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(option.title)
                                .font(ChromaTypography.sheetRowTitle)
                            Text(option.summary)
                                .font(ChromaTypography.bodySecondary)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if option.title == sessionViewModel.tunnelVariantLabel {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .font(ChromaTypography.body)
            .navigationTitle("VARIANT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("CLOSE", action: dismiss)
                }
            }
        }
    }
}

struct FractalPalettePickerSheet: View {
    @ObservedObject var sessionViewModel: SessionViewModel
    let dismiss: () -> Void

    private let paletteNames = ["Aurora", "Solar", "Abyss", "Neon", "Infra", "Glass", "Mono", "Prism"]

    var body: some View {
        NavigationStack {
            List(Array(paletteNames.enumerated()), id: \.offset) { offset, name in
                Button {
                    sessionViewModel.setFractalPaletteVariant(index: offset)
                    dismiss()
                } label: {
                    HStack {
                        Text(name)
                            .font(ChromaTypography.sheetRowTitle)
                        Spacer()
                        if name == sessionViewModel.fractalPaletteLabel {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .font(ChromaTypography.body)
            .navigationTitle("PALETTE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("CLOSE", action: dismiss)
                }
            }
        }
    }
}

struct RiemannPalettePickerSheet: View {
    @ObservedObject var sessionViewModel: SessionViewModel
    let dismiss: () -> Void

    private let paletteNames = ["Aurora", "Solar", "Abyss", "Neon", "Infra", "Glass", "Mono", "Prism"]

    var body: some View {
        NavigationStack {
            List(Array(paletteNames.enumerated()), id: \.offset) { offset, name in
                Button {
                    sessionViewModel.setRiemannPaletteVariant(index: offset)
                    dismiss()
                } label: {
                    HStack {
                        Text(name)
                            .font(ChromaTypography.sheetRowTitle)
                        Spacer()
                        if name == sessionViewModel.riemannPaletteLabel {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .font(ChromaTypography.body)
            .navigationTitle("PALETTE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("CLOSE", action: dismiss)
                }
            }
        }
    }
}

struct PresetBrowserSheet: View {
    @ObservedObject var sessionViewModel: SessionViewModel
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if sessionViewModel.presets.isEmpty {
                    Text("No presets stored yet.")
                        .font(ChromaTypography.bodySecondary)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessionViewModel.presets) { preset in
                        Button {
                            sessionViewModel.applyPreset(preset)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(preset.name)
                                    .font(ChromaTypography.sheetRowTitle)
                                Text(ParameterCatalog.modeDescriptor(for: preset.modeID).summary)
                                    .font(ChromaTypography.bodySecondary)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .font(ChromaTypography.body)
            .navigationTitle("PRESETS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("CLOSE", action: dismiss)
                }
            }
        }
    }
}

struct RecorderExportSheet: View {
    @ObservedObject var sessionViewModel: SessionViewModel
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                profilesSection
                captureSection
            }
            .font(ChromaTypography.body)
            .navigationTitle("RECORDER / EXPORT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("CLOSE", action: dismiss)
                }
            }
        }
    }

    private var profilesSection: some View {
        Section {
            ForEach(sessionViewModel.exportProfiles, id: \.id) { profile in
                Button {
                    sessionViewModel.selectExportProfile(profile)
                } label: {
                    ExportProfileRow(
                        profile: profile,
                        isSelected: profile.id == sessionViewModel.session.activeExportProfileID
                    )
                }
            }
        } header: {
            sectionHeader("Profiles")
        }
    }

    private var captureSection: some View {
        Section {
            Text("Recorder/export remains scaffolded. Task 002 focuses on the live render surface and renderer lifecycle.")
                .font(ChromaTypography.bodySecondary)
                .foregroundStyle(.secondary)
        } header: {
            sectionHeader("Capture")
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(ChromaTypography.sheetSectionHeader)
            .tracking(1.4)
    }
}

struct SettingsDiagnosticsSheet: View {
    @ObservedObject var sessionViewModel: SessionViewModel
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                liveControlsSection
                audioInputSection
                outputSection
                diagnosticsSection
            }
            .font(ChromaTypography.body)
            .navigationTitle("SETTINGS / DIAGNOSTICS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("REFRESH") {
                        sessionViewModel.refreshDiagnostics()
                        sessionViewModel.refreshAudioInputs()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("CLOSE", action: dismiss)
                }
            }
        }
    }

    private var liveControlsSection: some View {
        Section {
            Text(sessionViewModel.activeModeDescriptor.name)
                .font(ChromaTypography.bodySecondary)
                .foregroundStyle(.secondary)

            ForEach(sessionViewModel.primarySurfaceControlDescriptors) { descriptor in
                SettingsSurfaceSliderRow(
                    descriptor: descriptor,
                    value: sessionViewModel.parameterValue(for: descriptor).scalarValue ?? 0,
                    onChange: { newValue in
                        sessionViewModel.updateParameter(descriptor, value: .scalar(newValue))
                    }
                )
            }
        } header: {
            sectionHeader("Live Controls")
        }
    }

    private var audioInputSection: some View {
        Section {
            LabeledContent("Authorization", value: sessionViewModel.audioAuthorizationStatus.rawValue)

            if sessionViewModel.availableAudioInputSources.isEmpty {
                Text("No input sources are currently available.")
                    .font(ChromaTypography.bodySecondary)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessionViewModel.availableAudioInputSources) { source in
                    Button {
                        sessionViewModel.selectAudioInputSource(id: source.id)
                        Task {
                            await sessionViewModel.restartRealtimeAudioPipeline()
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.name)
                                    .font(ChromaTypography.sheetRowTitle)
                                Text(source.transportSummary)
                                    .font(ChromaTypography.bodySecondary)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if source.id == sessionViewModel.selectedAudioInputSourceID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }

            Button("RESTART AUDIO INPUT") {
                Task {
                    await sessionViewModel.restartRealtimeAudioPipeline()
                }
            }
        } header: {
            sectionHeader("Audio Input")
        }
    }

    private var outputSection: some View {
        Section {
            ForEach(sessionViewModel.session.availableDisplayTargets, id: \.id) { target in
                Button {
                    sessionViewModel.selectDisplayTarget(id: target.id)
                } label: {
                    DisplayTargetRow(
                        target: target,
                        isSelected: target.id == sessionViewModel.session.outputState.selectedDisplayTargetID
                    )
                }
                .disabled(!target.isAvailable)
            }
        } header: {
            sectionHeader("Output")
        }
    }

    private var diagnosticsSection: some View {
        Section {
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
        } header: {
            sectionHeader("Diagnostics")
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(ChromaTypography.sheetSectionHeader)
            .tracking(1.4)
    }
}

private struct SettingsSurfaceSliderRow: View {
    let descriptor: ParameterDescriptor
    let value: Double
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
                        onChange(newValue)
                    }
                ),
                in: (descriptor.minimumValue ?? 0) ... (descriptor.maximumValue ?? 1)
            )
            .tint(.white)
        }
        .padding(.vertical, 4)
    }
}

private struct ExportProfileRow: View {
    let profile: ExportProfile
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(profile.name)
                    .font(ChromaTypography.sheetRowTitle)
                Text("\(profile.resolutionLabel) • \(profile.frameRate) fps • \(profile.codec)")
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
