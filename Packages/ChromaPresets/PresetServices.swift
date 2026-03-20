import Foundation

public protocol PresetService: AnyObject {
    func loadPresets() -> [Preset]
    func save(preset: Preset) throws
    func deletePreset(id: UUID) throws
}

public final class PlaceholderPresetService: PresetService {
    private var storedPresets: [Preset]

    public init(storedPresets: [Preset] = []) {
        self.storedPresets = PresetServiceSorting.sorted(storedPresets)
    }

    public func loadPresets() -> [Preset] {
        storedPresets
    }

    public func save(preset: Preset) throws {
        storedPresets.removeAll(where: { $0.id == preset.id })
        storedPresets.append(preset)
        storedPresets = PresetServiceSorting.sorted(storedPresets)
    }

    public func deletePreset(id: UUID) throws {
        storedPresets.removeAll(where: { $0.id == id })
    }
}

public final class DiskPresetService: PresetService {
    private let fileManager: FileManager
    private let fileURL: URL
    private let seedPresets: [Preset]
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileManager: FileManager = .default,
        fileURL: URL,
        seedPresets: [Preset] = []
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL
        self.seedPresets = PresetServiceSorting.sorted(seedPresets)
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder = JSONDecoder()
    }

    public convenience init(
        fileManager: FileManager = .default,
        appDirectoryName: String = "Chroma",
        fileName: String = "presets.json",
        seedPresets: [Preset] = []
    ) {
        let baseDirectory = DiskPresetService.resolveBaseDirectory(fileManager: fileManager)
        let appDirectory = baseDirectory.appendingPathComponent(appDirectoryName, isDirectory: true)
        let fileURL = appDirectory.appendingPathComponent(fileName, isDirectory: false)
        self.init(fileManager: fileManager, fileURL: fileURL, seedPresets: seedPresets)
    }

    public func loadPresets() -> [Preset] {
        if !fileManager.fileExists(atPath: fileURL.path) {
            if !seedPresets.isEmpty {
                try? persist(seedPresets)
                return seedPresets
            }
            return []
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }

        guard let decoded = try? decoder.decode([Preset].self, from: data) else {
            return []
        }

        let sortedDecoded = PresetServiceSorting.sorted(decoded)
        let backfilled = backfillMissingModeSeeds(into: sortedDecoded)
        if backfilled.count != sortedDecoded.count {
            try? persist(backfilled)
        }
        return backfilled
    }

    public func save(preset: Preset) throws {
        var presets = loadPresets()
        presets.removeAll(where: { $0.id == preset.id })
        presets.append(preset)
        try persist(presets)
    }

    public func deletePreset(id: UUID) throws {
        var presets = loadPresets()
        presets.removeAll(where: { $0.id == id })
        try persist(presets)
    }

    private func persist(_ presets: [Preset]) throws {
        let sortedPresets = PresetServiceSorting.sorted(presets)
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(sortedPresets)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func backfillMissingModeSeeds(into presets: [Preset]) -> [Preset] {
        guard !seedPresets.isEmpty else { return presets }
        var existingModeIDs = Set(presets.map(\.modeID))
        var additions: [Preset] = []
        for seed in seedPresets {
            guard !existingModeIDs.contains(seed.modeID) else { continue }
            additions.append(seed)
            existingModeIDs.insert(seed.modeID)
        }
        guard !additions.isEmpty else { return presets }
        return PresetServiceSorting.sorted(presets + additions)
    }

    private static func resolveBaseDirectory(fileManager: FileManager) -> URL {
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
}

private enum PresetServiceSorting {
    static func sorted(_ presets: [Preset]) -> [Preset] {
        presets.sorted { lhs, rhs in
            if lhs.modeID.rawValue != rhs.modeID.rawValue {
                return lhs.modeID.rawValue < rhs.modeID.rawValue
            }
            let nameCompare = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameCompare != .orderedSame {
                return nameCompare == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
