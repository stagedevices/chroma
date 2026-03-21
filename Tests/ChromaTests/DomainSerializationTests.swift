import XCTest
@testable import Chroma

final class DomainSerializationTests: XCTestCase {
    func testSessionRoundTripsThroughCodable() throws {
        let session = ChromaSession.initial()
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(ChromaSession.self, from: data)
        XCTAssertEqual(decoded, session)
    }

    func testPresetRoundTripsThroughCodable() throws {
        let preset = Preset(
            name: "Stage Color",
            modeID: .colorShift,
            values: [
                ScopedParameterValue(parameterID: "response.inputGain", scope: .global, value: .scalar(0.8)),
                ScopedParameterValue(parameterID: "output.noImageInSilence", scope: .global, value: .toggle(true)),
                ScopedParameterValue(
                    parameterID: "mode.colorShift.hueRange",
                    scope: .mode(.colorShift),
                    value: .hueRange(min: 0.2, max: 0.7, outside: true)
                ),
            ]
        )
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(Preset.self, from: data)
        XCTAssertEqual(decoded, preset)
    }

    func testLegacySessionExportProfileDecodesIntoExportSettings() throws {
        let legacyJSON = """
        {
          "activeModeID": "colorShift",
          "activePresetName": "Unsaved Session",
          "morphState": {
            "progress": 0
          },
          "outputState": {
            "selectedDisplayTargetID": "device",
            "isMirrorEnabled": false,
            "hidesOperatorChrome": false,
            "noImageInSilence": false,
            "blackFloor": 0.86,
            "isColorFeedbackEnabled": false
          },
          "availableDisplayTargets": [
            {
              "id": "device",
              "name": "Device Screen",
              "kind": "deviceScreen",
              "isAvailable": true,
              "supportsFullscreen": true
            }
          ],
          "activeExportProfileID": "rehearsal-prores"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ChromaSession.self, from: legacyJSON)
        XCTAssertEqual(decoded.exportCaptureSettings.resolutionPreset, .p1080)
        XCTAssertEqual(decoded.exportCaptureSettings.frameRate, .fps30)
        XCTAssertEqual(decoded.exportCaptureSettings.codec, .proRes422)
        XCTAssertEqual(decoded.outputState.glassAppearanceStyle, .dark)
    }

    func testLegacySessionWithoutNewSettingsDecodesWithSafeDefaults() throws {
        let legacyJSON = """
        {
          "activeModeID": "colorShift",
          "activePresetName": "Unsaved Session",
          "morphState": {
            "progress": 0
          },
          "outputState": {
            "selectedDisplayTargetID": "device",
            "isMirrorEnabled": false,
            "hidesOperatorChrome": false,
            "noImageInSilence": false,
            "blackFloor": 0.86,
            "isColorFeedbackEnabled": false
          },
          "availableDisplayTargets": [
            {
              "id": "device",
              "name": "Device Screen",
              "kind": "deviceScreen",
              "isAvailable": true,
              "supportsFullscreen": true
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ChromaSession.self, from: legacyJSON)
        XCTAssertEqual(decoded.performanceSettings.mode, .auto)
        XCTAssertTrue(decoded.performanceSettings.thermalAwareFallbackEnabled)
        XCTAssertEqual(decoded.audioCalibrationSettings.attackThresholdDB, 8, accuracy: 0.0001)
        XCTAssertEqual(decoded.audioCalibrationSettings.silenceGateThreshold, 0.03, accuracy: 0.0001)
        XCTAssertTrue(decoded.sessionRecoverySettings.autoSaveEnabled)
        XCTAssertTrue(decoded.sessionRecoverySettings.restoreOnLaunchEnabled)
    }

    func testCustomPatchLibraryRoundTripsThroughCodable() throws {
        let library = CustomPatchLibrary.seededDefault()
        let data = try JSONEncoder().encode(library)
        let decoded = try JSONDecoder().decode(CustomPatchLibrary.self, from: data)
        XCTAssertEqual(decoded, library)
        XCTAssertEqual(decoded.patches.count, 3)
        XCTAssertEqual(decoded.activePatchID, library.activePatchID)
    }

    func testCustomPatchLibraryDecodesWithoutExplicitActivePatchID() throws {
        let json = """
        {
          "patches": [
            {
              "id": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
              "name": "Legacy Patch",
              "nodes": [],
              "connections": [],
              "viewport": {
                "zoom": 1,
                "offsetX": 0,
                "offsetY": 0
              },
              "createdAt": "2026-01-01T00:00:00Z",
              "updatedAt": "2026-01-01T00:00:00Z"
            }
          ]
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CustomPatchLibrary.self, from: json)
        XCTAssertNil(decoded.activePatchID)
        XCTAssertEqual(decoded.patches.count, 1)
        XCTAssertEqual(decoded.patches[0].name, "Legacy Patch")
    }
}
