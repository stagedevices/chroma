import XCTest
@testable import Chroma

final class SessionPersistenceServiceTests: XCTestCase {
    func testDiskModeDefaultsServiceRoundTripsAndRemovesValues() throws {
        let baseURL = temporaryDirectoryURL()
        let fileURL = baseURL.appendingPathComponent("mode-defaults.json", isDirectory: false)
        let service = DiskModeDefaultsService(fileManager: .default, fileURL: fileURL)

        let values: [ScopedParameterValue] = [
            ScopedParameterValue(
                parameterID: "mode.colorShift.hueResponse",
                scope: .mode(.colorShift),
                value: .scalar(0.27)
            ),
            ScopedParameterValue(
                parameterID: "response.inputGain",
                scope: .global,
                value: .scalar(0.93)
            ),
        ]

        try service.saveDefaults(values, for: .colorShift)
        let loaded = service.defaults(for: .colorShift)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 2)
        XCTAssertTrue(
            loaded?.contains(where: {
                $0.parameterID == "response.inputGain" && $0.scope == .global
            }) ?? false
        )
        XCTAssertTrue(
            loaded?.contains(where: {
                $0.parameterID == "mode.colorShift.hueResponse" && $0.scope == .mode(.colorShift)
            }) ?? false
        )

        try service.removeDefaults(for: .colorShift)
        XCTAssertNil(service.defaults(for: .colorShift))
    }

    func testDiskSessionRecoveryServiceRoundTripsAndClearsSnapshot() throws {
        let baseURL = temporaryDirectoryURL()
        let fileURL = baseURL.appendingPathComponent("session-recovery.json", isDirectory: false)
        let service = DiskSessionRecoveryService(fileManager: .default, fileURL: fileURL)

        var session = ChromaSession.initial()
        session.activeModeID = .prismField
        let snapshot = SessionRecoverySnapshot(
            session: session,
            parameterAssignments: [
                ScopedParameterValue(
                    parameterID: "mode.prismField.facetDensity",
                    scope: .mode(.prismField),
                    value: .scalar(0.74)
                ),
                ScopedParameterValue(
                    parameterID: "response.inputGain",
                    scope: .global,
                    value: .scalar(0.88)
                ),
            ],
            savedAt: Date(timeIntervalSince1970: 1234)
        )

        try service.saveSnapshot(snapshot)
        guard let loaded = service.loadSnapshot() else {
            XCTFail("Expected persisted session recovery snapshot")
            return
        }
        XCTAssertEqual(loaded.session.activeModeID, .prismField)
        XCTAssertEqual(loaded.parameterAssignments.count, 2)
        XCTAssertEqual(loaded.savedAt.timeIntervalSince1970, 1234, accuracy: 0.0001)

        try service.clearSnapshot()
        XCTAssertNil(service.loadSnapshot())
    }

    func testSessionRecoverySnapshotSortingIsDeterministic() {
        let snapshot = SessionRecoverySnapshot(
            session: ChromaSession.initial(),
            parameterAssignments: [
                ScopedParameterValue(
                    parameterID: "mode.colorShift.hueResponse",
                    scope: .mode(.colorShift),
                    value: .scalar(0.22)
                ),
                ScopedParameterValue(
                    parameterID: "response.inputGain",
                    scope: .global,
                    value: .scalar(0.81)
                ),
                ScopedParameterValue(
                    parameterID: "mode.colorShift.hueRange",
                    scope: .mode(.colorShift),
                    value: .hueRange(min: 0.2, max: 0.7, outside: false)
                ),
            ]
        )

        XCTAssertEqual(snapshot.parameterAssignments.map(\.parameterID), [
            "response.inputGain",
            "mode.colorShift.hueRange",
            "mode.colorShift.hueResponse",
        ])
    }

    private func temporaryDirectoryURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chroma-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
