import Foundation
import Combine
import AVFoundation
import CoreImage
import CoreVideo
import Metal

public final class LiveRecorderService: RecorderService, RendererFrameCaptureSink {
    public let supportedVideoCodecs: Set<ExportVideoCodec>
    public private(set) var captureState: RecorderCaptureState
    public var captureStatePublisher: AnyPublisher<RecorderCaptureState, Never> {
        captureStateSubject.eraseToAnyPublisher()
    }

    public private(set) var statusMessage: String?
    public var statusMessagePublisher: AnyPublisher<String?, Never> {
        statusMessageSubject.eraseToAnyPublisher()
    }

    private let fileManager: FileManager
    private let exportDirectoryURL: URL
    private let maxCachedExports: Int
    private let maxExportAge: TimeInterval
    private let audioSamplePublisher: AnyPublisher<AudioSampleFrame, Never>?
    private let processingQueue = DispatchQueue(label: "chroma.recorder.processing", qos: .userInitiated)
    private let ciContext: CIContext?

    private let captureStateSubject: CurrentValueSubject<RecorderCaptureState, Never>
    private let statusMessageSubject: CurrentValueSubject<String?, Never>

    private var queueCaptureState: RecorderCaptureState
    private var queuedRequest: RecorderCaptureRequest?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var videoAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var audioInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var requestedIncludeMicAudio = true
    private var recordingStartHostTime: CFTimeInterval?
    private var lastVideoPresentationTime = CMTime.invalid
    private var captureFrameRate = ExportFrameRate.fps60.rawValue

    private var audioSubscription: AnyCancellable?
    private var audioSampleCursor: Int64 = 0
    private var audioSampleRate: Double = 48_000
    private var audioFormatDescription: CMAudioFormatDescription?
    private var pendingAudioFrames: [AudioSampleFrame] = []

    public init(
        supportedVideoCodecs: Set<ExportVideoCodec>? = nil,
        fileManager: FileManager = .default,
        exportDirectoryURL: URL? = nil,
        maxCachedExports: Int = 16,
        maxExportAge: TimeInterval = 60 * 60 * 24 * 7,
        audioSamplePublisher: AnyPublisher<AudioSampleFrame, Never>? = nil,
        metalDevice: MTLDevice? = MTLCreateSystemDefaultDevice()
    ) {
        self.supportedVideoCodecs = supportedVideoCodecs ?? Self.detectedSupportedCodecs()
        self.fileManager = fileManager
        self.maxCachedExports = maxCachedExports
        self.maxExportAge = maxExportAge
        self.audioSamplePublisher = audioSamplePublisher
        self.captureState = .idle
        self.captureStateSubject = CurrentValueSubject(.idle)
        self.statusMessage = nil
        self.statusMessageSubject = CurrentValueSubject(nil)
        self.queueCaptureState = .idle
        self.ciContext = metalDevice.map { CIContext(mtlDevice: $0) }

        if let exportDirectoryURL {
            self.exportDirectoryURL = exportDirectoryURL
        } else {
            self.exportDirectoryURL = Self.resolveDefaultExportDirectory(fileManager: fileManager)
                .appendingPathComponent("Chroma", isDirectory: true)
                .appendingPathComponent("Exports", isDirectory: true)
        }

        try? fileManager.createDirectory(at: self.exportDirectoryURL, withIntermediateDirectories: true)
        performExportCacheCleanup(now: Date())
    }

    deinit {
        audioSubscription?.cancel()
    }

    public func startCapture(request: RecorderCaptureRequest) async throws {
        try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
            guard let self else {
                continuation.resume(throwing: RecorderError.writerUnavailable)
                return
            }
            processingQueue.async {
                do {
                    try self.startCaptureOnQueue(request: request)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func stopCapture() async {
        await withCheckedContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume()
                return
            }
            processingQueue.async {
                self.stopCaptureOnQueue {
                    continuation.resume()
                }
            }
        }
    }

    public func consumeProgramFrame(texture: MTLTexture, hostTime: CFTimeInterval) {
        processingQueue.async { [weak self] in
            self?.appendVideoFrameOnQueue(texture: texture, hostTime: hostTime)
        }
    }

    private func startCaptureOnQueue(request: RecorderCaptureRequest) throws {
        switch queueCaptureState {
        case .starting, .recording, .finalizing:
            throw RecorderError.alreadyRecording
        case .idle, .completed, .failed:
            break
        }

        let outputURL = makeOutputURL()
        if fileManager.fileExists(atPath: outputURL.path) {
            try? fileManager.removeItem(at: outputURL)
        }

        queuedRequest = request
        requestedIncludeMicAudio = request.includeMicAudio
        self.outputURL = outputURL
        recordingStartHostTime = nil
        lastVideoPresentationTime = .invalid
        audioSampleCursor = 0
        audioSampleRate = 48_000
        audioFormatDescription = nil
        pendingAudioFrames.removeAll(keepingCapacity: true)
        captureFrameRate = request.settings.frameRate.rawValue

        audioSubscription?.cancel()
        audioSubscription = nil

        writer = nil
        videoInput = nil
        videoAdaptor = nil
        audioInput = nil

        publishCaptureState(.starting)
        setStatusMessage(nil)
    }

    private func stopCaptureOnQueue(completion: @escaping () -> Void) {
        switch queueCaptureState {
        case .recording:
            break
        case .starting:
            resetRuntimeState(clearQueuedRequest: true, clearOutputURL: false)
            publishCaptureState(.failed("No program frames were received before capture stopped."))
            completion()
            return
        case .idle, .finalizing, .completed, .failed:
            completion()
            return
        }

        publishCaptureState(.finalizing)
        audioSubscription?.cancel()
        audioSubscription = nil
        flushPendingAudioFramesOnQueue()

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        guard let writer else {
            publishCaptureState(.failed("Writer unavailable during finalize."))
            resetRuntimeState(clearQueuedRequest: true, clearOutputURL: true)
            completion()
            return
        }

        writer.finishWriting { [weak self] in
            guard let self else {
                completion()
                return
            }
            self.processingQueue.async {
                defer { completion() }

                let completedURL = self.outputURL
                self.resetRuntimeState(clearQueuedRequest: true, clearOutputURL: true)

                if writer.status == .completed, let completedURL {
                    self.publishCaptureState(.completed(completedURL))
                    self.performExportCacheCleanup(now: Date())
                } else {
                    let message = writer.error?.localizedDescription ?? "Failed to finalize capture."
                    self.publishCaptureState(.failed(message))
                }
            }
        }
    }

    private func appendVideoFrameOnQueue(texture: MTLTexture, hostTime: CFTimeInterval) {
        switch queueCaptureState {
        case .starting:
            do {
                try initializeWriterOnQueue(fromFirstFrame: texture)
            } catch {
                publishCaptureState(.failed(error.localizedDescription))
                resetRuntimeState(clearQueuedRequest: true, clearOutputURL: true)
                return
            }
        case .recording:
            break
        case .idle, .finalizing, .completed, .failed:
            return
        }

        guard case .recording = queueCaptureState else { return }
        guard let writer, writer.status == .writing else { return }
        guard let videoInput, videoInput.isReadyForMoreMediaData else { return }
        guard let adaptor = videoAdaptor, let pixelBufferPool = adaptor.pixelBufferPool else { return }

        if recordingStartHostTime == nil {
            recordingStartHostTime = hostTime
        }

        guard var presentationTime = presentationTimeForVideoFrame(hostTime: hostTime) else { return }
        if lastVideoPresentationTime.isValid, presentationTime <= lastVideoPresentationTime {
            let minStep = CMTime(value: 1, timescale: CMTimeScale(max(captureFrameRate, 24)))
            presentationTime = lastVideoPresentationTime + minStep
        }

        guard let pixelBuffer = makePixelBuffer(from: texture, pool: pixelBufferPool) else { return }
        if adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            lastVideoPresentationTime = presentationTime
        }
        flushPendingAudioFramesOnQueue()
    }

    private func initializeWriterOnQueue(fromFirstFrame texture: MTLTexture) throws {
        guard writer == nil else { return }
        guard let request = queuedRequest, let outputURL else {
            throw RecorderError.writerUnavailable
        }

        let sourceWidth = max(texture.width, 1)
        let sourceHeight = max(texture.height, 1)
        let targetSize = Self.targetDimensions(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            targetLongEdge: request.settings.resolutionPreset.longEdge
        )

        let writer = try AVAssetWriter(url: outputURL, fileType: .mov)

        let requestedCodec = request.settings.codec
        guard let selectedCodec = selectWritableCodec(
            requestedCodec: requestedCodec,
            writer: writer,
            targetWidth: targetSize.width,
            targetHeight: targetSize.height
        ) else {
            throw RecorderError.writerUnavailable
        }

        if selectedCodec != requestedCodec {
            setStatusMessage("Requested codec \(requestedCodec.label) is unavailable. Falling back to \(selectedCodec.label).")
        }

        let videoSettings = makeVideoSettings(
            codec: selectedCodec.avVideoCodecType,
            width: targetSize.width,
            height: targetSize.height
        )

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(videoInput) else {
            throw RecorderError.writerUnavailable
        }
        writer.add(videoInput)

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: targetSize.width,
            kCVPixelBufferHeightKey as String: targetSize.height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        var audioInput: AVAssetWriterInput?
        if request.includeMicAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000,
            ]

            let candidate = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            candidate.expectsMediaDataInRealTime = true
            if writer.canAdd(candidate) {
                writer.add(candidate)
                audioInput = candidate
            } else {
                setStatusMessage("Mic audio is unavailable for this configuration. Recording video-only.")
            }
        }

        guard writer.startWriting() else {
            throw RecorderError.writerUnavailable
        }

        writer.startSession(atSourceTime: .zero)

        self.writer = writer
        self.videoInput = videoInput
        self.videoAdaptor = adaptor
        self.audioInput = audioInput
        self.audioSampleCursor = 0
        self.audioSampleRate = 48_000
        self.audioFormatDescription = nil
        self.pendingAudioFrames.removeAll(keepingCapacity: true)
        self.captureFrameRate = request.settings.frameRate.rawValue
        self.lastVideoPresentationTime = .invalid
        self.recordingStartHostTime = nil

        if request.includeMicAudio {
            pendingAudioFrames.append(
                AudioSampleFrame(
                    timestamp: Date(),
                    sampleRate: 48_000,
                    monoSamples: Array(repeating: 0, count: 1_024)
                )
            )
        }

        bindAudioSamplesIfNeeded(includeMicAudio: request.includeMicAudio)
        publishCaptureState(.recording)
        performExportCacheCleanup(now: Date())
    }

    private func selectWritableCodec(
        requestedCodec: ExportVideoCodec,
        writer: AVAssetWriter,
        targetWidth: Int,
        targetHeight: Int
    ) -> ExportVideoCodec? {
        var candidates: [ExportVideoCodec] = [requestedCodec, .hevc, .h264, .proRes422]
        var seen = Set<ExportVideoCodec>()
        candidates = candidates.filter { seen.insert($0).inserted }

        for candidate in candidates {
            guard supportedVideoCodecs.contains(candidate) else { continue }
            let settings = makeVideoSettings(codec: candidate.avVideoCodecType, width: targetWidth, height: targetHeight)
            if writer.canApply(outputSettings: settings, forMediaType: .video) {
                return candidate
            }
        }
        return nil
    }

    private func bindAudioSamplesIfNeeded(includeMicAudio: Bool) {
        audioSubscription?.cancel()
        audioSubscription = nil

        guard includeMicAudio, audioInput != nil else { return }
        guard let audioSamplePublisher else { return }

        audioSubscription = audioSamplePublisher
            .sink { [weak self] frame in
                self?.processingQueue.async {
                    self?.appendAudioFrameOnQueue(frame)
                }
            }
    }

    private func appendAudioFrameOnQueue(_ frame: AudioSampleFrame) {
        guard case .recording = queueCaptureState else { return }
        guard let writer, writer.status == .writing else { return }
        guard requestedIncludeMicAudio else { return }
        guard let audioInput else { return }

        if audioInput.isReadyForMoreMediaData {
            guard let sampleBuffer = makeAudioSampleBuffer(from: frame) else { return }
            if !audioInput.append(sampleBuffer) {
                if pendingAudioFrames.count > 256 {
                    pendingAudioFrames.removeFirst(pendingAudioFrames.count - 256)
                }
                pendingAudioFrames.append(frame)
            }
            flushPendingAudioFramesOnQueue()
            return
        }

        if pendingAudioFrames.count > 256 {
            pendingAudioFrames.removeFirst(pendingAudioFrames.count - 256)
        }
        pendingAudioFrames.append(frame)
    }

    private func flushPendingAudioFramesOnQueue() {
        guard case .recording = queueCaptureState else { return }
        guard let writer, writer.status == .writing else { return }
        guard requestedIncludeMicAudio else { return }
        guard let audioInput else { return }

        while audioInput.isReadyForMoreMediaData, !pendingAudioFrames.isEmpty {
            let frame = pendingAudioFrames.removeFirst()
            guard let sampleBuffer = makeAudioSampleBuffer(from: frame) else { continue }
            if !audioInput.append(sampleBuffer) {
                pendingAudioFrames.insert(frame, at: 0)
                break
            }
        }
    }

    private func makePixelBuffer(from texture: MTLTexture, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else {
            return nil
        }

        let targetWidth = CVPixelBufferGetWidth(pixelBuffer)
        let targetHeight = CVPixelBufferGetHeight(pixelBuffer)

        if let ciContext,
           let ciImage = CIImage(mtlTexture: texture, options: [
               CIImageOption.colorSpace: CGColorSpaceCreateDeviceRGB(),
           ]) {
            let scaleX = CGFloat(targetWidth) / CGFloat(max(texture.width, 1))
            let scaleY = CGFloat(targetHeight) / CGFloat(max(texture.height, 1))
            let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            let bounds = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
            ciContext.render(
                scaledImage,
                to: pixelBuffer,
                bounds: bounds,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            return pixelBuffer
        }

        guard texture.width == targetWidth, texture.height == targetHeight else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let region = MTLRegionMake2D(0, 0, targetWidth, targetHeight)
        texture.getBytes(baseAddress, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        return pixelBuffer
    }

    private func makeAudioSampleBuffer(from frame: AudioSampleFrame) -> CMSampleBuffer? {
        guard !frame.monoSamples.isEmpty else { return nil }

        let sampleRate = max(8_000, min(frame.sampleRate, 96_000))
        let sampleRateInt = Int32(sampleRate.rounded())
        let sampleCount = frame.monoSamples.count
        let bytesPerSample = MemoryLayout<Int16>.size
        let dataLength = sampleCount * bytesPerSample

        if audioFormatDescription == nil || abs(audioSampleRate - sampleRate) > 0.5 {
            audioSampleRate = sampleRate
            audioSampleCursor = 0
            audioFormatDescription = makeAudioFormatDescription(sampleRate: Float64(sampleRateInt))
        }

        guard let audioFormatDescription else { return nil }

        var blockBuffer: CMBlockBuffer?
        let createStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataLength,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataLength,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard createStatus == kCMBlockBufferNoErr, let blockBuffer else {
            return nil
        }

        var samples = frame.monoSamples.map { sample -> Int16 in
            let clamped = max(-1.0, min(1.0, sample))
            return Int16((clamped * Float(Int16.max)).rounded())
        }
        let replaceStatus: OSStatus
        if let baseAddress = samples.withUnsafeMutableBytes({ $0.baseAddress }) {
            replaceStatus = CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: dataLength
            )
        } else {
            replaceStatus = -1
        }

        guard replaceStatus == kCMBlockBufferNoErr else {
            return nil
        }

        let timescale = CMTimeScale(max(sampleRateInt, 1))
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: timescale),
            presentationTimeStamp: CMTime(value: audioSampleCursor, timescale: timescale),
            decodeTimeStamp: .invalid
        )
        var sampleSize = bytesPerSample
        var sampleBuffer: CMSampleBuffer?
        let sampleBufferStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: audioFormatDescription,
            sampleCount: sampleCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        guard sampleBufferStatus == noErr, let sampleBuffer else {
            return nil
        }

        audioSampleCursor += Int64(sampleCount)
        return sampleBuffer
    }

    private func makeAudioFormatDescription(sampleRate: Float64) -> CMAudioFormatDescription? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        var formatDescription: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )

        guard status == noErr else {
            return nil
        }
        return formatDescription
    }

    private func presentationTimeForVideoFrame(hostTime: CFTimeInterval) -> CMTime? {
        guard let recordingStartHostTime else { return nil }
        let elapsed = max(0, hostTime - recordingStartHostTime)
        return CMTime(seconds: elapsed, preferredTimescale: 600)
    }

    private func makeOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        return exportDirectoryURL.appendingPathComponent("chroma-export-\(stamp).mov", isDirectory: false)
    }

    private func makeVideoSettings(codec: AVVideoCodecType, width: Int, height: Int) -> [String: Any] {
        [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 6,
                AVVideoExpectedSourceFrameRateKey: captureFrameRate,
                AVVideoMaxKeyFrameIntervalKey: captureFrameRate,
            ],
        ]
    }

    private func publishCaptureState(_ state: RecorderCaptureState) {
        queueCaptureState = state
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            captureState = state
            captureStateSubject.send(state)
        }
    }

    private func setStatusMessage(_ message: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            statusMessage = message
            statusMessageSubject.send(message)
        }
    }

    private func resetRuntimeState(clearQueuedRequest: Bool, clearOutputURL: Bool) {
        audioSubscription?.cancel()
        audioSubscription = nil
        videoInput = nil
        videoAdaptor = nil
        audioInput = nil
        writer = nil
        recordingStartHostTime = nil
        lastVideoPresentationTime = .invalid
        audioFormatDescription = nil
        audioSampleCursor = 0
        pendingAudioFrames.removeAll(keepingCapacity: true)
        if clearQueuedRequest {
            queuedRequest = nil
        }
        if clearOutputURL {
            outputURL = nil
        }
    }

    private func performExportCacheCleanup(now: Date) {
        let urls = (try? fileManager.contentsOfDirectory(
            at: exportDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let sorted = urls
            .map { url -> (URL, Date) in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                let date = values?.contentModificationDate ?? .distantPast
                return (url, date)
            }
            .sorted { lhs, rhs in lhs.1 > rhs.1 }

        for (index, item) in sorted.enumerated() {
            let age = now.timeIntervalSince(item.1)
            if index >= maxCachedExports || age > maxExportAge {
                try? fileManager.removeItem(at: item.0)
            }
        }
    }

    private static func targetDimensions(sourceWidth: Int, sourceHeight: Int, targetLongEdge: Int) -> (width: Int, height: Int) {
        guard sourceWidth > 0, sourceHeight > 0, targetLongEdge > 0 else {
            return (width: 1920, height: 1080)
        }

        let sourceLong = max(sourceWidth, sourceHeight)
        let sourceShort = min(sourceWidth, sourceHeight)
        let scale = Double(targetLongEdge) / Double(sourceLong)
        let scaledShort = max(2, Int((Double(sourceShort) * scale).rounded()))
        let evenShort = scaledShort.isMultiple(of: 2) ? scaledShort : scaledShort + 1
        let evenLong = targetLongEdge.isMultiple(of: 2) ? targetLongEdge : targetLongEdge + 1

        if sourceWidth >= sourceHeight {
            return (width: evenLong, height: evenShort)
        }
        return (width: evenShort, height: evenLong)
    }

    private static func detectedSupportedCodecs() -> Set<ExportVideoCodec> {
        let probeURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("chroma-codec-probe-\(UUID().uuidString).mov", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: probeURL) }

        guard let probeWriter = try? AVAssetWriter(url: probeURL, fileType: .mov) else {
            return [.hevc, .h264]
        }

        let probeWidth = 1_280
        let probeHeight = 720
        var supported = Set<ExportVideoCodec>()
        for codec in ExportVideoCodec.allCases {
            let settings: [String: Any] = [
                AVVideoCodecKey: codec.avVideoCodecType,
                AVVideoWidthKey: probeWidth,
                AVVideoHeightKey: probeHeight,
            ]
            if probeWriter.canApply(outputSettings: settings, forMediaType: .video) {
                supported.insert(codec)
            }
        }

        return supported.isEmpty ? [.hevc, .h264] : supported
    }

    private static func resolveDefaultExportDirectory(fileManager: FileManager) -> URL {
        let cacheDirectory = (try? fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ))

        return cacheDirectory
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }
}

private extension ExportVideoCodec {
    var avVideoCodecType: AVVideoCodecType {
        switch self {
        case .hevc:
            return .hevc
        case .h264:
            return .h264
        case .proRes422:
            return .proRes422
        }
    }

    init?(avVideoCodec: AVVideoCodecType) {
        switch avVideoCodec {
        case .hevc:
            self = .hevc
        case .h264:
            self = .h264
        case .proRes422:
            self = .proRes422
        default:
            return nil
        }
    }
}
