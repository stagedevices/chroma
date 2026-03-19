import Foundation

public struct DiagnosticsSnapshot: Codable, Equatable {
    public var audioStatus: String
    public var renderer: RendererDiagnosticsSummary
    public var lastUpdated: Date

    public var rendererStatus: String {
        renderer.readinessStatus.displayName
    }

    public var droppedFrameCount: Int {
        renderer.droppedFrameCount
    }

    public var averageFrameTimeMS: Double {
        renderer.averageFrameTimeMS
    }

    public init(audioStatus: String, renderer: RendererDiagnosticsSummary, lastUpdated: Date) {
        self.audioStatus = audioStatus
        self.renderer = renderer
        self.lastUpdated = lastUpdated
    }

    public static func placeholder(now: Date = .now, modeID: VisualModeID = .colorShift) -> DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            audioStatus: "Awaiting live input service",
            renderer: RendererDiagnosticsSummary.placeholder(modeID: modeID),
            lastUpdated: now
        )
    }
}
