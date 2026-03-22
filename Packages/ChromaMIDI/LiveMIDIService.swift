import Foundation
import Combine
import CoreMIDI

public final class LiveMIDIService: MIDIService {
    public private(set) var isActive: Bool = false
    public private(set) var connectedDevices: [MIDIDeviceDescriptor] = []

    private let eventSubject = PassthroughSubject<MIDIEvent, Never>()
    public var eventPublisher: AnyPublisher<MIDIEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    private var clientRef: MIDIClientRef = 0
    private var inputPortRef: MIDIPortRef = 0
    private var connectedSourceRefs: Set<MIDIEndpointRef> = []

    // Tempo tracking for MIDI clock
    private var clockTimestamps: [UInt64] = []
    private let clockSampleCount = 24 // one beat at 24 ppqn

    public init() {}

    public func start() {
        guard !isActive else { return }

        let status = MIDIClientCreateWithBlock("com.chroma.midi" as CFString, &clientRef) { [weak self] notification in
            self?.handleMIDINotification(notification)
        }
        guard status == noErr else { return }

        let portStatus = MIDIInputPortCreateWithProtocol(
            clientRef,
            "com.chroma.midi.input" as CFString,
            ._1_0,
            &inputPortRef
        ) { [weak self] eventList, _ in
            self?.handleEventList(eventList)
        }
        guard portStatus == noErr else {
            MIDIClientDispose(clientRef)
            return
        }

        isActive = true
        connectAllSources()
        refreshDeviceList()
    }

    public func stop() {
        guard isActive else { return }
        disconnectAllSources()
        MIDIPortDispose(inputPortRef)
        MIDIClientDispose(clientRef)
        inputPortRef = 0
        clientRef = 0
        connectedSourceRefs = []
        connectedDevices = []
        isActive = false
    }

    // MARK: - Source management

    private func connectAllSources() {
        let sourceCount = MIDIGetNumberOfSources()
        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            if !connectedSourceRefs.contains(source) {
                let status = MIDIPortConnectSource(inputPortRef, source, nil)
                if status == noErr {
                    connectedSourceRefs.insert(source)
                }
            }
        }
    }

    private func disconnectAllSources() {
        for source in connectedSourceRefs {
            MIDIPortDisconnectSource(inputPortRef, source)
        }
        connectedSourceRefs = []
    }

    private func refreshDeviceList() {
        var devices: [MIDIDeviceDescriptor] = []
        let sourceCount = MIDIGetNumberOfSources()
        for i in 0..<sourceCount {
            let endpoint = MIDIGetSource(i)
            let name = Self.stringProperty(endpoint, kMIDIPropertyDisplayName) ?? "Unknown"
            let manufacturer = Self.stringProperty(endpoint, kMIDIPropertyManufacturer) ?? ""
            var uniqueID: MIDIUniqueID = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)
            devices.append(MIDIDeviceDescriptor(
                id: String(uniqueID),
                name: name,
                manufacturer: manufacturer
            ))
        }
        connectedDevices = devices
    }

    // MARK: - MIDI notification

    private func handleMIDINotification(_ notification: UnsafePointer<MIDINotification>) {
        switch notification.pointee.messageID {
        case .msgSetupChanged:
            connectAllSources()
            refreshDeviceList()
        default:
            break
        }
    }

    // MARK: - Event parsing (MIDI 1.0 Universal Packets)

    private func handleEventList(_ eventList: UnsafePointer<MIDIEventList>) {
        let list = eventList.pointee
        var packet = list.packet
        for _ in 0..<list.numPackets {
            parseMIDI1Packet(packet)
            var current = packet
            withUnsafePointer(to: &current) { ptr in
                packet = MIDIEventPacketNext(ptr).pointee
            }
        }
    }

    private func parseMIDI1Packet(_ packet: MIDIEventPacket) {
        let words = packet.words
        let word = words.0
        // MIDI 1.0 Channel Voice in UMP: message type 0x2
        let messageType = (word >> 28) & 0xF
        let now = Date()

        if messageType == 0x2 {
            let statusByte = UInt8((word >> 16) & 0xFF)
            let statusNibble = statusByte & 0xF0
            let channel = statusByte & 0x0F
            let data1 = UInt8((word >> 8) & 0xFF)
            let data2 = UInt8(word & 0xFF)

            switch statusNibble {
            case 0x90: // Note On
                if data2 == 0 {
                    eventSubject.send(MIDIEvent(kind: .noteOff(note: data1, channel: channel), timestamp: now))
                } else {
                    eventSubject.send(MIDIEvent(kind: .noteOn(note: data1, velocity: data2, channel: channel), timestamp: now))
                }
            case 0x80: // Note Off
                eventSubject.send(MIDIEvent(kind: .noteOff(note: data1, channel: channel), timestamp: now))
            case 0xB0: // Control Change
                eventSubject.send(MIDIEvent(kind: .controlChange(cc: data1, value: data2, channel: channel), timestamp: now))
            default:
                break
            }
        } else if messageType == 0x1 {
            // MIDI 1.0 System Common / Realtime in UMP
            let statusByte = UInt8((word >> 16) & 0xFF)
            switch statusByte {
            case 0xF8:
                trackClock()
                eventSubject.send(MIDIEvent(kind: .clock, timestamp: now))
            case 0xFA:
                clockTimestamps.removeAll()
                eventSubject.send(MIDIEvent(kind: .start, timestamp: now))
            case 0xFC:
                eventSubject.send(MIDIEvent(kind: .stop, timestamp: now))
            case 0xFB:
                eventSubject.send(MIDIEvent(kind: .continue, timestamp: now))
            default:
                break
            }
        }
    }

    // MARK: - Clock tempo tracking

    private func trackClock() {
        let now = mach_absolute_time()
        clockTimestamps.append(now)
        if clockTimestamps.count > clockSampleCount + 1 {
            clockTimestamps.removeFirst(clockTimestamps.count - clockSampleCount - 1)
        }
    }

    /// Estimated BPM from recent MIDI clock messages, or nil if insufficient data.
    public var estimatedBPM: Double? {
        guard clockTimestamps.count >= 7 else { return nil } // need a few ticks
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let tickToNs = Double(info.numer) / Double(info.denom)
        let first = clockTimestamps.first!
        let last = clockTimestamps.last!
        let intervals = clockTimestamps.count - 1
        let totalNs = Double(last - first) * tickToNs
        let avgTickNs = totalNs / Double(intervals)
        // 24 ticks per beat
        let beatNs = avgTickNs * 24.0
        let beatSec = beatNs / 1_000_000_000.0
        guard beatSec > 0 else { return nil }
        return 60.0 / beatSec
    }

    // MARK: - Helpers

    private static func stringProperty(_ endpoint: MIDIEndpointRef, _ property: CFString) -> String? {
        var str: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, property, &str)
        guard status == noErr, let cfStr = str else { return nil }
        return cfStr.takeRetainedValue() as String
    }
}
