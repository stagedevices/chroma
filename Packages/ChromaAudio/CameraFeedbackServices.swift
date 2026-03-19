import Foundation
import Combine
@preconcurrency import AVFoundation
import CoreVideo
import CoreMedia

public enum CameraFeedbackAuthorizationStatus: String, Codable {
    case notDetermined
    case denied
    case authorized
    case unavailable
}

public enum CameraFeedbackError: LocalizedError {
    case notAuthorized
    case frontCameraUnavailable
    case captureOutputUnavailable
    case inputUnavailable

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Camera permission is required for feedback."
        case .frontCameraUnavailable:
            return "Front camera is unavailable on this device."
        case .captureOutputUnavailable:
            return "Unable to create camera output stream."
        case .inputUnavailable:
            return "Unable to configure front camera input."
        }
    }
}

public struct CameraFeedbackFrame {
    public var timestamp: Date
    public var pixelBuffer: CVPixelBuffer
    public var width: Int
    public var height: Int

    public init(timestamp: Date, pixelBuffer: CVPixelBuffer, width: Int, height: Int) {
        self.timestamp = timestamp
        self.pixelBuffer = pixelBuffer
        self.width = width
        self.height = height
    }
}

public protocol CameraFeedbackService: AnyObject {
    var authorizationStatus: CameraFeedbackAuthorizationStatus { get }
    var isRunning: Bool { get }
    var latestFrame: CameraFeedbackFrame? { get }
    var framePublisher: AnyPublisher<CameraFeedbackFrame?, Never> { get }
    func startFrontCapture() async throws
    func stopCapture()
}

public final class PlaceholderCameraFeedbackService: CameraFeedbackService {
    public private(set) var authorizationStatus: CameraFeedbackAuthorizationStatus
    public private(set) var isRunning: Bool
    public private(set) var latestFrame: CameraFeedbackFrame?
    public var framePublisher: AnyPublisher<CameraFeedbackFrame?, Never> {
        frameSubject.eraseToAnyPublisher()
    }
    public private(set) var startCallCount: Int
    public private(set) var stopCallCount: Int

    private let frameSubject: CurrentValueSubject<CameraFeedbackFrame?, Never>

    public init(
        authorizationStatus: CameraFeedbackAuthorizationStatus = .unavailable,
        isRunning: Bool = false,
        latestFrame: CameraFeedbackFrame? = nil
    ) {
        self.authorizationStatus = authorizationStatus
        self.isRunning = isRunning
        self.latestFrame = latestFrame
        self.startCallCount = 0
        self.stopCallCount = 0
        frameSubject = CurrentValueSubject(latestFrame)
    }

    public func startFrontCapture() async throws {
        startCallCount += 1
        guard authorizationStatus == .authorized else {
            throw CameraFeedbackError.notAuthorized
        }
        isRunning = true
    }

    public func stopCapture() {
        stopCallCount += 1
        isRunning = false
    }

    public func setAuthorizationStatusForTesting(_ status: CameraFeedbackAuthorizationStatus) {
        authorizationStatus = status
    }

    public func publishFrameForTesting(_ frame: CameraFeedbackFrame?) {
        latestFrame = frame
        frameSubject.send(frame)
    }
}

public final class LiveCameraFeedbackService: NSObject, CameraFeedbackService {
    public private(set) var authorizationStatus: CameraFeedbackAuthorizationStatus
    public private(set) var isRunning: Bool
    public private(set) var latestFrame: CameraFeedbackFrame?
    public var framePublisher: AnyPublisher<CameraFeedbackFrame?, Never> {
        frameSubject.eraseToAnyPublisher()
    }

    private let captureSession: AVCaptureSession
    private let videoOutput: AVCaptureVideoDataOutput
    private let sessionQueue: DispatchQueue
    private let sampleQueue: DispatchQueue
    private let frameSubject: CurrentValueSubject<CameraFeedbackFrame?, Never>
    private var isConfigured: Bool

    public override init() {
        captureSession = AVCaptureSession()
        videoOutput = AVCaptureVideoDataOutput()
        sessionQueue = DispatchQueue(label: "chroma.camera.feedback.session", qos: .userInitiated)
        sampleQueue = DispatchQueue(label: "chroma.camera.feedback.sample", qos: .userInitiated)
        frameSubject = CurrentValueSubject(nil)
        isConfigured = false
        isRunning = false
        latestFrame = nil
        authorizationStatus = Self.currentAuthorizationStatus()
        super.init()
    }

    public func startFrontCapture() async throws {
        authorizationStatus = Self.currentAuthorizationStatus()
        if authorizationStatus == .notDetermined {
            let granted = await Self.requestVideoAccessIfNeeded()
            authorizationStatus = granted ? .authorized : .denied
        }

        guard authorizationStatus == .authorized else {
            throw CameraFeedbackError.notAuthorized
        }
        guard !isRunning else { return }

        try await configureSessionIfNeeded()
        let captureSession = self.captureSession
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if !captureSession.isRunning {
                    captureSession.startRunning()
                }
                continuation.resume()
            }
        }
        isRunning = true
    }

    public func stopCapture() {
        guard isRunning else { return }
        isRunning = false
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }

    private func configureSessionIfNeeded() async throws {
        guard !isConfigured else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraFeedbackError.captureOutputUnavailable)
                    return
                }

                do {
                    if #available(iOS 15.0, macCatalyst 15.0, *) {
                        self.captureSession.automaticallyConfiguresApplicationAudioSession = false
                    }

                    self.captureSession.beginConfiguration()
                    defer { self.captureSession.commitConfiguration() }

                    if self.captureSession.canSetSessionPreset(.hd1280x720) {
                        self.captureSession.sessionPreset = .hd1280x720
                    }

                    for input in self.captureSession.inputs {
                        self.captureSession.removeInput(input)
                    }
                    for output in self.captureSession.outputs {
                        self.captureSession.removeOutput(output)
                    }

                    guard
                        let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                            ?? AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
                    else {
                        throw CameraFeedbackError.frontCameraUnavailable
                    }

                    let input = try AVCaptureDeviceInput(device: frontCamera)
                    guard self.captureSession.canAddInput(input) else {
                        throw CameraFeedbackError.inputUnavailable
                    }
                    self.captureSession.addInput(input)

                    self.videoOutput.alwaysDiscardsLateVideoFrames = true
                    self.videoOutput.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                    ]
                    self.videoOutput.setSampleBufferDelegate(self, queue: self.sampleQueue)
                    guard self.captureSession.canAddOutput(self.videoOutput) else {
                        throw CameraFeedbackError.captureOutputUnavailable
                    }
                    self.captureSession.addOutput(self.videoOutput)

                    if let connection = self.videoOutput.connection(with: .video) {
                        if connection.isVideoMirroringSupported {
                            connection.isVideoMirrored = true
                        }
                        if #available(iOS 17.0, macCatalyst 17.0, *) {
                            if connection.isVideoRotationAngleSupported(0) {
                                connection.videoRotationAngle = 0
                            }
                        } else if connection.isVideoOrientationSupported {
                            connection.videoOrientation = .portrait
                        }
                    }

                    try frontCamera.lockForConfiguration()
                    let targetDuration = CMTime(value: 1, timescale: 30)
                    frontCamera.activeVideoMinFrameDuration = targetDuration
                    frontCamera.activeVideoMaxFrameDuration = targetDuration
                    frontCamera.unlockForConfiguration()

                    self.isConfigured = true
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func currentAuthorizationStatus() -> CameraFeedbackAuthorizationStatus {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .unavailable
        }
        #else
        return .unavailable
        #endif
    }

    private static func requestVideoAccessIfNeeded() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

extension LiveCameraFeedbackService: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let timestamp = Date()
        let frame = CameraFeedbackFrame(
            timestamp: timestamp,
            pixelBuffer: pixelBuffer,
            width: width,
            height: height
        )
        latestFrame = frame
        frameSubject.send(frame)
    }
}
