import Foundation

public protocol DiagnosticsService: AnyObject {
    func currentSnapshot(rendererSummary: RendererDiagnosticsSummary, audioStatus: String) -> DiagnosticsSnapshot
}

public final class PlaceholderDiagnosticsService: DiagnosticsService {
    public init() {
    }

    public func currentSnapshot(rendererSummary: RendererDiagnosticsSummary, audioStatus: String) -> DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            audioStatus: audioStatus,
            renderer: rendererSummary,
            lastUpdated: .now
        )
    }
}
