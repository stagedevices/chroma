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
}
