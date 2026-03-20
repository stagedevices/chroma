import Foundation
import Combine

public protocol RecorderService: AnyObject {
    var supportedVideoCodecs: Set<ExportVideoCodec> { get }
    var captureState: RecorderCaptureState { get }
    var captureStatePublisher: AnyPublisher<RecorderCaptureState, Never> { get }
    var statusMessage: String? { get }
    var statusMessagePublisher: AnyPublisher<String?, Never> { get }
    func startCapture(request: RecorderCaptureRequest) async throws
    func stopCapture() async
}

public struct RecorderCaptureRequest: Equatable, Sendable {
    public var settings: ExportCaptureSettings
    public var includeMicAudio: Bool

    public init(settings: ExportCaptureSettings, includeMicAudio: Bool) {
        self.settings = settings
        self.includeMicAudio = includeMicAudio
    }
}

public enum RecorderCaptureState: Equatable, Sendable {
    case idle
    case starting
    case recording
    case finalizing
    case completed(URL)
    case failed(String)
}

public enum RecorderError: LocalizedError {
    case alreadyRecording
    case writerUnavailable

    public var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Capture is already in progress."
        case .writerUnavailable:
            return "Recorder writer is unavailable."
        }
    }
}

public final class PlaceholderRecorderService: RecorderService {
    public let supportedVideoCodecs: Set<ExportVideoCodec>
    public private(set) var captureState: RecorderCaptureState
    public var captureStatePublisher: AnyPublisher<RecorderCaptureState, Never> {
        captureStateSubject.eraseToAnyPublisher()
    }
    public private(set) var statusMessage: String?
    public var statusMessagePublisher: AnyPublisher<String?, Never> {
        statusMessageSubject.eraseToAnyPublisher()
    }

    private let captureStateSubject: CurrentValueSubject<RecorderCaptureState, Never>
    private let statusMessageSubject: CurrentValueSubject<String?, Never>

    public init(supportedVideoCodecs: Set<ExportVideoCodec> = Set(ExportVideoCodec.allCases)) {
        self.supportedVideoCodecs = supportedVideoCodecs
        self.captureState = .idle
        captureStateSubject = CurrentValueSubject(.idle)
        self.statusMessage = nil
        statusMessageSubject = CurrentValueSubject(nil)
    }

    public func startCapture(request: RecorderCaptureRequest) async throws {
        guard captureState == .idle else {
            throw RecorderError.alreadyRecording
        }
        setCaptureState(.starting)
        setCaptureState(.recording)
    }

    public func stopCapture() async {
        guard case .recording = captureState else {
            return
        }
        setCaptureState(.finalizing)
        setCaptureState(.completed(URL(fileURLWithPath: "/tmp/chroma-placeholder-export.mov")))
    }

    private func setCaptureState(_ state: RecorderCaptureState) {
        captureState = state
        captureStateSubject.send(state)
    }
}
