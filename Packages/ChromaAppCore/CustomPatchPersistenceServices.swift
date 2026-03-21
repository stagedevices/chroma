import Foundation

public protocol CustomPatchService: AnyObject {
    func loadLibrary() -> CustomPatchLibrary
    func saveLibrary(_ library: CustomPatchLibrary) throws
}

public final class PlaceholderCustomPatchService: CustomPatchService {
    private var library: CustomPatchLibrary

    public init(library: CustomPatchLibrary = .seededDefault()) {
        self.library = CustomPatchSorting.normalized(library)
    }

    public func loadLibrary() -> CustomPatchLibrary {
        library
    }

    public func saveLibrary(_ library: CustomPatchLibrary) throws {
        self.library = CustomPatchSorting.normalized(library)
    }
}

public final class DiskCustomPatchService: CustomPatchService {
    private let fileManager: FileManager
    private let fileURL: URL
    private let seedLibrary: CustomPatchLibrary
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileManager: FileManager = .default,
        fileURL: URL,
        seedLibrary: CustomPatchLibrary = .seededDefault()
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL
        self.seedLibrary = CustomPatchSorting.normalized(seedLibrary)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    public convenience init(
        fileManager: FileManager = .default,
        appDirectoryName: String = "Chroma",
        fileName: String = "custom-patches.json",
        seedLibrary: CustomPatchLibrary = .seededDefault()
    ) {
        let baseDirectory = resolveCustomPatchBaseDirectory(fileManager: fileManager)
        let appDirectory = baseDirectory.appendingPathComponent(appDirectoryName, isDirectory: true)
        let fileURL = appDirectory.appendingPathComponent(fileName, isDirectory: false)
        self.init(fileManager: fileManager, fileURL: fileURL, seedLibrary: seedLibrary)
    }

    public func loadLibrary() -> CustomPatchLibrary {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            try? persist(seedLibrary)
            return seedLibrary
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            return seedLibrary
        }
        guard let decoded = try? decoder.decode(CustomPatchLibrary.self, from: data) else {
            return seedLibrary
        }
        let normalized = CustomPatchSorting.normalized(decoded)
        if normalized != decoded {
            try? persist(normalized)
        }
        return normalized
    }

    public func saveLibrary(_ library: CustomPatchLibrary) throws {
        try persist(CustomPatchSorting.normalized(library))
    }

    private func persist(_ library: CustomPatchLibrary) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(library)
        try data.write(to: fileURL, options: [.atomic])
    }
}

private enum CustomPatchSorting {
    static func normalized(_ library: CustomPatchLibrary) -> CustomPatchLibrary {
        let normalizedPatches = library.patches.map(normalizedPatch).sorted { lhs, rhs in
            let nameCompare = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameCompare != .orderedSame {
                return nameCompare == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let activePatchID: UUID? = {
            guard let requested = library.activePatchID else {
                return normalizedPatches.first?.id
            }
            return normalizedPatches.contains(where: { $0.id == requested })
                ? requested
                : normalizedPatches.first?.id
        }()
        return CustomPatchLibrary(activePatchID: activePatchID, patches: normalizedPatches)
    }

    private static func normalizedPatch(_ patch: CustomPatch) -> CustomPatch {
        let sortedNodes = patch.nodes.sorted { lhs, rhs in
            if lhs.title != rhs.title {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let sortedConnections = patch.connections.sorted { lhs, rhs in
            if lhs.fromNodeID != rhs.fromNodeID {
                return lhs.fromNodeID.uuidString < rhs.fromNodeID.uuidString
            }
            if lhs.fromPort != rhs.fromPort {
                return lhs.fromPort < rhs.fromPort
            }
            if lhs.toNodeID != rhs.toNodeID {
                return lhs.toNodeID.uuidString < rhs.toNodeID.uuidString
            }
            if lhs.toPort != rhs.toPort {
                return lhs.toPort < rhs.toPort
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let sortedGroups = patch.groups.sorted { $0.id.uuidString < $1.id.uuidString }
        return CustomPatch(
            id: patch.id,
            name: patch.name,
            nodes: sortedNodes,
            connections: sortedConnections,
            groups: sortedGroups,
            viewport: patch.viewport,
            createdAt: patch.createdAt,
            updatedAt: patch.updatedAt
        )
    }
}

private func resolveCustomPatchBaseDirectory(fileManager: FileManager) -> URL {
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
