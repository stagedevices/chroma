import Foundation

public protocol PresetService: AnyObject {
    func loadPresets() -> [Preset]
    func save(preset: Preset) throws
}

public final class PlaceholderPresetService: PresetService {
    private var storedPresets: [Preset]

    public init(storedPresets: [Preset] = []) {
        self.storedPresets = storedPresets
    }

    public func loadPresets() -> [Preset] {
        storedPresets
    }

    public func save(preset: Preset) throws {
        storedPresets.removeAll(where: { $0.id == preset.id })
        storedPresets.append(preset)
    }
}
