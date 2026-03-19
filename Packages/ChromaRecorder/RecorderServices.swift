import Foundation

public protocol RecorderService: AnyObject {
    var availableExportProfiles: [ExportProfile] { get }
    func beginCapture(profileID: String) async throws
    func stopCapture() async
}

public final class PlaceholderRecorderService: RecorderService {
    public let availableExportProfiles: [ExportProfile]

    public init(availableExportProfiles: [ExportProfile] = ParameterCatalog.exportProfiles) {
        self.availableExportProfiles = availableExportProfiles
    }

    public func beginCapture(profileID: String) async throws {
    }

    public func stopCapture() async {
    }
}
