import Foundation

public protocol ModeDefaultsService: AnyObject {
    func defaults(for modeID: VisualModeID) -> [ScopedParameterValue]?
    func loadAllDefaults() -> [VisualModeID: [ScopedParameterValue]]
    func saveDefaults(_ values: [ScopedParameterValue], for modeID: VisualModeID) throws
    func removeDefaults(for modeID: VisualModeID) throws
}

public protocol SessionRecoveryService: AnyObject {
    func loadSnapshot() -> SessionRecoverySnapshot?
    func saveSnapshot(_ snapshot: SessionRecoverySnapshot) throws
    func clearSnapshot() throws
}

public struct SessionRecoverySnapshot: Codable, Equatable {
    public var session: ChromaSession
    public var parameterAssignments: [ScopedParameterValue]
    public var savedAt: Date

    public init(
        session: ChromaSession,
        parameterAssignments: [ScopedParameterValue],
        savedAt: Date = .now
    ) {
        self.session = session
        self.parameterAssignments = SessionPersistenceSorting.sorted(parameterAssignments)
        self.savedAt = savedAt
    }
}

public final class PlaceholderModeDefaultsService: ModeDefaultsService {
    private var storage: [VisualModeID: [ScopedParameterValue]]

    public init(storage: [VisualModeID: [ScopedParameterValue]] = [:]) {
        self.storage = storage.mapValues(SessionPersistenceSorting.sorted)
    }

    public func defaults(for modeID: VisualModeID) -> [ScopedParameterValue]? {
        storage[modeID]
    }

    public func loadAllDefaults() -> [VisualModeID: [ScopedParameterValue]] {
        storage
    }

    public func saveDefaults(_ values: [ScopedParameterValue], for modeID: VisualModeID) throws {
        storage[modeID] = SessionPersistenceSorting.sorted(values)
    }

    public func removeDefaults(for modeID: VisualModeID) throws {
        storage.removeValue(forKey: modeID)
    }
}

public final class PlaceholderSessionRecoveryService: SessionRecoveryService {
    private var snapshot: SessionRecoverySnapshot?

    public init(snapshot: SessionRecoverySnapshot? = nil) {
        self.snapshot = snapshot
    }

    public func loadSnapshot() -> SessionRecoverySnapshot? {
        snapshot
    }

    public func saveSnapshot(_ snapshot: SessionRecoverySnapshot) throws {
        self.snapshot = snapshot
    }

    public func clearSnapshot() throws {
        snapshot = nil
    }
}

public final class DiskModeDefaultsService: ModeDefaultsService {
    private let fileManager: FileManager
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileManager: FileManager = .default,
        fileURL: URL
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    public convenience init(
        fileManager: FileManager = .default,
        appDirectoryName: String = "Chroma",
        fileName: String = "mode-defaults.json"
    ) {
        let baseDirectory = resolveBaseDirectory(fileManager: fileManager)
        let appDirectory = baseDirectory.appendingPathComponent(appDirectoryName, isDirectory: true)
        let fileURL = appDirectory.appendingPathComponent(fileName, isDirectory: false)
        self.init(fileManager: fileManager, fileURL: fileURL)
    }

    public func defaults(for modeID: VisualModeID) -> [ScopedParameterValue]? {
        loadAllDefaults()[modeID]
    }

    public func loadAllDefaults() -> [VisualModeID: [ScopedParameterValue]] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return [:]
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            return [:]
        }
        guard let payload = try? decoder.decode(ModeDefaultsPayload.self, from: data) else {
            return [:]
        }

        var resolved: [VisualModeID: [ScopedParameterValue]] = [:]
        for (rawModeID, values) in payload.valuesByModeID {
            guard let modeID = VisualModeID(rawValue: rawModeID) else { continue }
            resolved[modeID] = SessionPersistenceSorting.sorted(values)
        }
        return resolved
    }

    public func saveDefaults(_ values: [ScopedParameterValue], for modeID: VisualModeID) throws {
        var all = loadAllDefaults()
        all[modeID] = SessionPersistenceSorting.sorted(values)
        try persist(all)
    }

    public func removeDefaults(for modeID: VisualModeID) throws {
        var all = loadAllDefaults()
        all.removeValue(forKey: modeID)
        try persist(all)
    }

    private func persist(_ valuesByModeID: [VisualModeID: [ScopedParameterValue]]) throws {
        let payload = ModeDefaultsPayload(
            valuesByModeID: Dictionary(
                uniqueKeysWithValues: valuesByModeID
                    .sorted { $0.key.rawValue < $1.key.rawValue }
                    .map { ($0.key.rawValue, SessionPersistenceSorting.sorted($0.value)) }
            )
        )
        try write(payload)
    }

    private func write(_ payload: ModeDefaultsPayload) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(payload)
        try data.write(to: fileURL, options: [.atomic])
    }
}

public final class DiskSessionRecoveryService: SessionRecoveryService {
    private let fileManager: FileManager
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileManager: FileManager = .default,
        fileURL: URL
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    public convenience init(
        fileManager: FileManager = .default,
        appDirectoryName: String = "Chroma",
        fileName: String = "session-recovery.json"
    ) {
        let baseDirectory = resolveBaseDirectory(fileManager: fileManager)
        let appDirectory = baseDirectory.appendingPathComponent(appDirectoryName, isDirectory: true)
        let fileURL = appDirectory.appendingPathComponent(fileName, isDirectory: false)
        self.init(fileManager: fileManager, fileURL: fileURL)
    }

    public func loadSnapshot() -> SessionRecoverySnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? decoder.decode(SessionRecoverySnapshot.self, from: data)
    }

    public func saveSnapshot(_ snapshot: SessionRecoverySnapshot) throws {
        let sortedSnapshot = SessionRecoverySnapshot(
            session: snapshot.session,
            parameterAssignments: SessionPersistenceSorting.sorted(snapshot.parameterAssignments),
            savedAt: snapshot.savedAt
        )
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(sortedSnapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func clearSnapshot() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}

private struct ModeDefaultsPayload: Codable {
    var valuesByModeID: [String: [ScopedParameterValue]]
}

private enum SessionPersistenceSorting {
    static func sorted(_ assignments: [ScopedParameterValue]) -> [ScopedParameterValue] {
        assignments.sorted { lhs, rhs in
            if lhs.scope.kind != rhs.scope.kind {
                return lhs.scope.kind.rawValue < rhs.scope.kind.rawValue
            }
            if lhs.scope.modeID?.rawValue != rhs.scope.modeID?.rawValue {
                return (lhs.scope.modeID?.rawValue ?? "") < (rhs.scope.modeID?.rawValue ?? "")
            }
            if lhs.parameterID != rhs.parameterID {
                return lhs.parameterID < rhs.parameterID
            }
            return String(describing: lhs.value) < String(describing: rhs.value)
        }
    }
}

private func resolveBaseDirectory(fileManager: FileManager) -> URL {
    let supportDirectory = (try? fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    ))

    return supportDirectory
        ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
}
