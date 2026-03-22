import Foundation
import Combine

// MARK: - Protocol

public protocol MIDIService: AnyObject {
    var isActive: Bool { get }
    var connectedDevices: [MIDIDeviceDescriptor] { get }
    var eventPublisher: AnyPublisher<MIDIEvent, Never> { get }
    func start()
    func stop()
}

// MARK: - Placeholder

public final class PlaceholderMIDIService: MIDIService {
    public private(set) var isActive: Bool = false
    public private(set) var connectedDevices: [MIDIDeviceDescriptor] = []

    private let eventSubject = PassthroughSubject<MIDIEvent, Never>()
    public var eventPublisher: AnyPublisher<MIDIEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    public init() {}

    public func start() { isActive = true }
    public func stop() { isActive = false }

    /// Inject a synthetic event for testing.
    public func injectEvent(_ event: MIDIEvent) {
        eventSubject.send(event)
    }

    /// Inject a synthetic device for testing.
    public func injectDevice(_ device: MIDIDeviceDescriptor) {
        connectedDevices.append(device)
    }
}
