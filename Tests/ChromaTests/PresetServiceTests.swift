import XCTest
@testable import Chroma

final class PresetServiceTests: XCTestCase {
    func testDiskPresetServiceSeedsOnlyWhenStoreMissing() throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fileURL = tempDirectory.appendingPathComponent("presets.json")
        let seed = Preset(name: "Stage Color", modeID: .colorShift, values: [])
        let service = DiskPresetService(fileURL: fileURL, seedPresets: [seed])

        let firstLoad = service.loadPresets()
        XCTAssertEqual(firstLoad.map(\.name), ["Stage Color"])

        let secondLoad = service.loadPresets()
        XCTAssertEqual(secondLoad.map(\.name), ["Stage Color"])
    }

    func testDiskPresetServiceRoundTripsAcrossInstances() throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fileURL = tempDirectory.appendingPathComponent("presets.json")
        let writer = DiskPresetService(fileURL: fileURL, seedPresets: [])
        let preset = Preset(name: "Prism One", modeID: .prismField, values: [])
        try writer.save(preset: preset)

        let reader = DiskPresetService(fileURL: fileURL, seedPresets: [])
        let loaded = reader.loadPresets()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, preset.id)
        XCTAssertEqual(loaded.first?.name, "Prism One")
    }

    func testDiskPresetServiceUpsertDeleteAndDeterministicSort() throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fileURL = tempDirectory.appendingPathComponent("presets.json")
        let service = DiskPresetService(fileURL: fileURL, seedPresets: [])

        let cPreset = Preset(name: "Zeta", modeID: .riemannCorridor, values: [])
        let aPreset = Preset(name: "Alpha", modeID: .colorShift, values: [])
        let bPreset = Preset(name: "Beta", modeID: .colorShift, values: [])

        try service.save(preset: cPreset)
        try service.save(preset: bPreset)
        try service.save(preset: aPreset)

        var loaded = service.loadPresets()
        XCTAssertEqual(loaded.map(\.name), ["Alpha", "Beta", "Zeta"])

        var renamed = bPreset
        renamed.name = "Aardvark"
        try service.save(preset: renamed)
        loaded = service.loadPresets()
        XCTAssertEqual(loaded.map(\.name), ["Aardvark", "Alpha", "Zeta"])

        try service.deletePreset(id: renamed.id)
        loaded = service.loadPresets()
        XCTAssertEqual(loaded.map(\.name), ["Alpha", "Zeta"])
    }

    func testDiskPresetServiceBackfillsMissingModeSeedsIntoExistingStore() throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fileURL = tempDirectory.appendingPathComponent("presets.json")
        let existing = Preset(name: "Stage Color", modeID: .colorShift, values: [])
        let writer = DiskPresetService(fileURL: fileURL, seedPresets: [])
        try writer.save(preset: existing)

        let seeds = [
            Preset(name: "Stage Color", modeID: .colorShift, values: []),
            Preset(name: "Prism Nocturne", modeID: .prismField, values: []),
            Preset(name: "Tunnel Drive", modeID: .tunnelCels, values: []),
            Preset(name: "Fractal Aurora", modeID: .fractalCaustics, values: []),
            Preset(name: "Mandelbrot Boundary Run", modeID: .riemannCorridor, values: []),
        ]
        let reader = DiskPresetService(fileURL: fileURL, seedPresets: seeds)
        let firstLoad = reader.loadPresets()
        XCTAssertEqual(firstLoad.count, 5)
        XCTAssertEqual(Set(firstLoad.map(\.modeID)), Set(VisualModeID.allCases))
        XCTAssertTrue(firstLoad.contains(where: { $0.id == existing.id }))

        let secondLoad = reader.loadPresets()
        XCTAssertEqual(secondLoad.count, 5)
        XCTAssertEqual(Set(secondLoad.map(\.modeID)), Set(VisualModeID.allCases))
    }

    private func makeTemporaryDirectory() -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ChromaPresetServiceTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
