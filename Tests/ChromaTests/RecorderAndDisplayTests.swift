import XCTest
import Combine
import AVFoundation
import Metal
@testable import Chroma

@MainActor
final class RecorderAndDisplayTests: XCTestCase {
    func testPlaceholderRecorderTransitionsToCompleted() async throws {
        let service = PlaceholderRecorderService()

        try await service.startCapture(
            request: RecorderCaptureRequest(settings: .default, includeMicAudio: true)
        )
        XCTAssertEqual(service.captureState, .recording)

        await service.stopCapture()

        guard case .completed(let url) = service.captureState else {
            return XCTFail("Expected completed recorder state")
        }
        XCTAssertEqual(url.path, "/tmp/chroma-placeholder-export.mov")
    }

    func testLiveRecorderProducesVideoOnlyFileWithoutAudioTrack() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable in test environment")
        }

        let exportDirectory = makeTemporaryExportDirectory()
        defer { try? FileManager.default.removeItem(at: exportDirectory) }

        let service = LiveRecorderService(
            fileManager: .default,
            exportDirectoryURL: exportDirectory,
            maxCachedExports: 10,
            maxExportAge: 60,
            audioSamplePublisher: nil,
            metalDevice: device
        )

        try await service.startCapture(
            request: RecorderCaptureRequest(
                settings: ExportCaptureSettings(resolutionPreset: .p720, frameRate: .fps30, codec: .hevc),
                includeMicAudio: false
            )
        )

        let texture = makeSolidTexture(device: device, width: 320, height: 180, rgba: (0, 192, 255, 255))
        let baseTime: CFTimeInterval = 1.0
        for index in 0 ..< 12 {
            service.consumeProgramFrame(texture: texture, hostTime: baseTime + (Double(index) / 30.0))
        }

        try await Task.sleep(nanoseconds: 80_000_000)
        await service.stopCapture()

        guard case .completed(let url) = service.captureState else {
            return XCTFail("Expected completed recorder state")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let asset = AVURLAsset(url: url)
        XCTAssertFalse(asset.tracks(withMediaType: .video).isEmpty)
        XCTAssertTrue(asset.tracks(withMediaType: .audio).isEmpty)
    }

    func testLiveRecorderProducesAudioTrackWhenMicEnabled() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable in test environment")
        }

        let exportDirectory = makeTemporaryExportDirectory()
        defer { try? FileManager.default.removeItem(at: exportDirectory) }

        let sampleSubject = PassthroughSubject<AudioSampleFrame, Never>()

        let service = LiveRecorderService(
            fileManager: .default,
            exportDirectoryURL: exportDirectory,
            maxCachedExports: 10,
            maxExportAge: 60,
            audioSamplePublisher: sampleSubject.eraseToAnyPublisher(),
            metalDevice: device
        )

        try await service.startCapture(
            request: RecorderCaptureRequest(
                settings: ExportCaptureSettings(resolutionPreset: .p720, frameRate: .fps30, codec: .hevc),
                includeMicAudio: true
            )
        )

        let texture = makeSolidTexture(device: device, width: 320, height: 180, rgba: (255, 160, 32, 255))
        let baseTime: CFTimeInterval = 2.0
        service.consumeProgramFrame(texture: texture, hostTime: baseTime)
        for index in 0 ..< 20 {
            let samples = makeSineSamples(count: 1024, phaseOffset: Float(index) * 0.12)
            sampleSubject.send(
                AudioSampleFrame(
                    timestamp: Date(),
                    sampleRate: 48_000,
                    monoSamples: samples
                )
            )
            service.consumeProgramFrame(texture: texture, hostTime: baseTime + (Double(index + 1) / 30.0))
        }

        try await Task.sleep(nanoseconds: 120_000_000)
        await service.stopCapture()

        guard case .completed(let url) = service.captureState else {
            return XCTFail("Expected completed recorder state")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let asset = AVURLAsset(url: url)
        XCTAssertFalse(asset.tracks(withMediaType: .video).isEmpty)
        XCTAssertFalse(asset.tracks(withMediaType: .audio).isEmpty)
    }

    func testLiveRecorderKeepsPortraitOrientationForPortraitProgramFeed() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable in test environment")
        }

        let exportDirectory = makeTemporaryExportDirectory()
        defer { try? FileManager.default.removeItem(at: exportDirectory) }

        let service = LiveRecorderService(
            fileManager: .default,
            exportDirectoryURL: exportDirectory,
            maxCachedExports: 10,
            maxExportAge: 60,
            audioSamplePublisher: nil,
            metalDevice: device
        )

        try await service.startCapture(
            request: RecorderCaptureRequest(
                settings: ExportCaptureSettings(resolutionPreset: .p720, frameRate: .fps30, codec: .hevc),
                includeMicAudio: false
            )
        )

        let texture = makeSolidTexture(device: device, width: 180, height: 320, rgba: (40, 210, 160, 255))
        for index in 0 ..< 12 {
            service.consumeProgramFrame(texture: texture, hostTime: 3.0 + (Double(index) / 30.0))
        }

        try await Task.sleep(nanoseconds: 80_000_000)
        await service.stopCapture()

        guard case .completed(let url) = service.captureState else {
            return XCTFail("Expected completed recorder state")
        }

        let asset = AVURLAsset(url: url)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            return XCTFail("Expected video track")
        }

        XCTAssertGreaterThan(videoTrack.naturalSize.height, videoTrack.naturalSize.width)
        XCTAssertEqual(Int(videoTrack.naturalSize.width.rounded()), 720)
        XCTAssertEqual(Int(videoTrack.naturalSize.height.rounded()), 1280)
    }

    func testLiveRecorderKeepsLandscapeOrientationForLandscapeProgramFeed() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable in test environment")
        }

        let exportDirectory = makeTemporaryExportDirectory()
        defer { try? FileManager.default.removeItem(at: exportDirectory) }

        let service = LiveRecorderService(
            fileManager: .default,
            exportDirectoryURL: exportDirectory,
            maxCachedExports: 10,
            maxExportAge: 60,
            audioSamplePublisher: nil,
            metalDevice: device
        )

        try await service.startCapture(
            request: RecorderCaptureRequest(
                settings: ExportCaptureSettings(resolutionPreset: .p720, frameRate: .fps30, codec: .hevc),
                includeMicAudio: false
            )
        )

        let texture = makeSolidTexture(device: device, width: 320, height: 180, rgba: (128, 64, 255, 255))
        for index in 0 ..< 12 {
            service.consumeProgramFrame(texture: texture, hostTime: 4.0 + (Double(index) / 30.0))
        }

        try await Task.sleep(nanoseconds: 80_000_000)
        await service.stopCapture()

        guard case .completed(let url) = service.captureState else {
            return XCTFail("Expected completed recorder state")
        }

        let asset = AVURLAsset(url: url)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            return XCTFail("Expected video track")
        }

        XCTAssertGreaterThan(videoTrack.naturalSize.width, videoTrack.naturalSize.height)
        XCTAssertEqual(Int(videoTrack.naturalSize.width.rounded()), 1280)
        XCTAssertEqual(Int(videoTrack.naturalSize.height.rounded()), 720)
    }

#if canImport(UIKit) && !targetEnvironment(macCatalyst)
    func testLiveExternalDisplayCoordinatorReconcilesSelectionOnDisconnect() {
        var hasExternal = false
        let coordinator = LiveExternalDisplayCoordinator(
            notificationCenter: NotificationCenter(),
            externalScreenProvider: { hasExternal },
            selectedTargetID: "device"
        )

        XCTAssertFalse(coordinator.targets.first(where: { $0.id == "external" })?.isAvailable ?? true)
        XCTAssertEqual(coordinator.selectedTargetID, "device")

        hasExternal = true
        coordinator.refreshTargetAvailabilityForTesting()
        XCTAssertTrue(coordinator.targets.first(where: { $0.id == "external" })?.isAvailable ?? false)

        coordinator.selectDisplayTarget(id: "external")
        XCTAssertEqual(coordinator.selectedTargetID, "external")

        hasExternal = false
        coordinator.refreshTargetAvailabilityForTesting()
        XCTAssertFalse(coordinator.targets.first(where: { $0.id == "external" })?.isAvailable ?? true)
        XCTAssertEqual(coordinator.selectedTargetID, "device")
    }
#endif

    private func makeTemporaryExportDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("chroma-recorder-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSolidTexture(
        device: MTLDevice,
        width: Int,
        height: Int,
        rgba: (UInt8, UInt8, UInt8, UInt8)
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("Unable to create test texture")
        }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            bytes[index + 0] = rgba.2
            bytes[index + 1] = rgba.1
            bytes[index + 2] = rgba.0
            bytes[index + 3] = rgba.3
        }

        let region = MTLRegionMake2D(0, 0, width, height)
        bytes.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            texture.replace(region: region, mipmapLevel: 0, withBytes: baseAddress, bytesPerRow: width * 4)
        }

        return texture
    }

    private func makeSineSamples(count: Int, phaseOffset: Float) -> [Float] {
        guard count > 0 else { return [] }
        return (0 ..< count).map { index in
            let phase = (Float(index) / Float(count)) * Float.pi * 2 + phaseOffset
            return sin(phase) * 0.35
        }
    }
}
