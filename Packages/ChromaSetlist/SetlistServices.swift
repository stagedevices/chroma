import Foundation

public protocol SetlistService: AnyObject {
    func loadSets() -> [PerformanceSet]
    func saveSet(_ set: PerformanceSet) throws
    func deleteSet(id: UUID) throws
}

public final class PlaceholderSetlistService: SetlistService {
    private var sets: [PerformanceSet]

    public init(sets: [PerformanceSet] = []) {
        self.sets = SetlistServiceSorting.sorted(sets)
    }

    public func loadSets() -> [PerformanceSet] {
        sets
    }

    public func saveSet(_ set: PerformanceSet) throws {
        sets.removeAll(where: { $0.id == set.id })
        sets.append(set)
        sets = SetlistServiceSorting.sorted(sets)
    }

    public func deleteSet(id: UUID) throws {
        sets.removeAll(where: { $0.id == id })
    }
}

public final class DiskSetlistService: SetlistService {
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
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder = JSONDecoder()
    }

    public convenience init(
        fileManager: FileManager = .default,
        appDirectoryName: String = "Chroma",
        fileName: String = "setlists.json"
    ) {
        let baseDirectory = DiskSetlistService.resolveBaseDirectory(fileManager: fileManager)
        let appDirectory = baseDirectory.appendingPathComponent(appDirectoryName, isDirectory: true)
        let fileURL = appDirectory.appendingPathComponent(fileName, isDirectory: false)
        self.init(fileManager: fileManager, fileURL: fileURL)
    }

    public func loadSets() -> [PerformanceSet] {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([PerformanceSet].self, from: data)
        else {
            return []
        }
        return SetlistServiceSorting.sorted(decoded)
    }

    public func saveSet(_ set: PerformanceSet) throws {
        var sets = loadSets()
        sets.removeAll(where: { $0.id == set.id })
        sets.append(set)
        try persist(sets)
    }

    public func deleteSet(id: UUID) throws {
        var sets = loadSets()
        sets.removeAll(where: { $0.id == id })
        try persist(sets)
    }

    private func persist(_ sets: [PerformanceSet]) throws {
        let sorted = SetlistServiceSorting.sorted(sets)
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(sorted)
        try data.write(to: fileURL, options: [.atomic])
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

private enum SetlistServiceSorting {
    static func sorted(_ sets: [PerformanceSet]) -> [PerformanceSet] {
        sets.sorted { lhs, rhs in
            let nameCompare = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameCompare != .orderedSame {
                return nameCompare == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
