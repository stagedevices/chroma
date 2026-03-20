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
                ToolbarItem(placement: .topBarTrailing) {
                    SheetToolbarCloseButton(action: dismiss)
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
                ToolbarItem(placement: .topBarTrailing) {
                    SheetToolbarCloseButton(action: dismiss)
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
                ToolbarItem(placement: .topBarTrailing) {
                    SheetToolbarCloseButton(action: dismiss)
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
                ToolbarItem(placement: .topBarTrailing) {
                    SheetToolbarCloseButton(action: dismiss)
                }
            }
        }
    }
}

struct PresetBrowserSheet: View {
    @ObservedObject var sessionViewModel: SessionViewModel
    let dismiss: () -> Void
    @State private var renamingPreset: Preset?
    @State private var renameDraft: String = ""
    @State private var deletingPreset: Preset?

    var body: some View {
        NavigationStack {
            List {
                if sessionViewModel.presetsForActiveMode.isEmpty {
                    Text("No presets for \(sessionViewModel.activeModeDescriptor.name) yet.")
                        .font(ChromaTypography.bodySecondary)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessionViewModel.presetsForActiveMode) { preset in
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Rename") {
                                renamingPreset = preset
                                renameDraft = preset.name
                            }
                            .tint(.blue)

                            Button("Delete", role: .destructive) {
                                deletingPreset = preset
                            }
                        }
                    }
                }
            }
            .font(ChromaTypography.body)
            .navigationTitle("PRESETS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetToolbarCloseButton(action: dismiss)
                }
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
                Text("“\(preset.name)” will be removed.")
            }
        }
    }
}

struct RecorderExportSheet: View {
    @ObservedObject var sessionViewModel: SessionViewModel
    let dismiss: () -> Void
    @State private var captureStartDate: Date?
    @State private var now = Date()
    @State private var shareItem: ExportShareItem?
    @State private var completedExportURL: URL?
    @State private var saveToPhotosStatusMessage: String?
    @State private var isSavingToPhotos = false

    private let elapsedTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

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
            subtitle: actionButtonSubtitle,
            systemImage: actionButtonIcon,
            accentColor: .red.opacity(0.88),
            isLightAppearance: sessionViewModel.isLightGlassAppearance,
            isEnabled: !actionButtonDisabled
        ) {
            Task {
                performImpactHaptic()
                if case .recording = sessionViewModel.recorderCaptureState {
                    await sessionViewModel.stopRecorderCapture()
                } else {
                    await sessionViewModel.startRecorderCapture()
                }
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
    @ObservedObject var sessionViewModel: SessionViewModel
    let dismiss: () -> Void
    @State private var inkTransitionProgress: CGFloat = 0.001
    @State private var inkTransitionOpacity: Double = 0
    @State private var diagnosticsExpanded = false

    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    audioInputSection
                    outputSection
                    appearanceSection
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

    private var outputSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(sessionViewModel.session.availableDisplayTargets, id: \.id) { target in
                        ExportSettingTileButton(
                            title: target.name,
                            subtitle: target.isAvailable ? "Ready" : "Unavailable",
                            isSelected: target.id == sessionViewModel.session.outputState.selectedDisplayTargetID,
                            isEnabled: target.isAvailable,
                            tintColor: exportSettingsTintColor,
                            isLightAppearance: sessionViewModel.isLightGlassAppearance
                        ) {
                            sessionViewModel.selectDisplayTarget(id: target.id)
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
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
