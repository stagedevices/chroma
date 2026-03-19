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
            ]
        )
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(Preset.self, from: data)
        XCTAssertEqual(decoded, preset)
    }
}
