import XCTest
@testable import Chroma

final class ParameterStoreTests: XCTestCase {
    func testGlobalValuesOverrideDefaults() {
        let store = ParameterStore(descriptors: ParameterCatalog.descriptors)
        store.setValue(.scalar(1.1), for: "response.inputGain", scope: .global)

        XCTAssertEqual(store.value(for: "response.inputGain", scope: .global), .scalar(1.1))
    }

    func testModeScopedValuesRemainIsolated() {
        let store = ParameterStore(descriptors: ParameterCatalog.descriptors)
        store.setValue(.scalar(0.7), for: "mode.colorShift.hueResponse", scope: .mode(.colorShift))

        XCTAssertEqual(store.value(for: "mode.colorShift.hueResponse", scope: .mode(.colorShift)), .scalar(0.7))
        XCTAssertNil(store.value(for: "mode.colorShift.hueResponse", scope: .mode(.prismField))?.scalarValue)
    }

    func testTierAndModeFilteringReturnsExpectedDescriptors() {
        let store = ParameterStore(descriptors: ParameterCatalog.descriptors)

        let basicColorShift = store.descriptors(tier: .basic, for: .colorShift)
        let advancedColorShift = store.descriptors(tier: .advanced, for: .colorShift)

        XCTAssertTrue(basicColorShift.contains(where: { $0.id == "mode.colorShift.hueResponse" }))
        XCTAssertTrue(basicColorShift.contains(where: { $0.id == "mode.colorShift.hueRange" }))
        XCTAssertTrue(basicColorShift.contains(where: { $0.id == "response.inputGain" }))
        XCTAssertTrue(advancedColorShift.contains(where: { $0.id == "output.noImageInSilence" }))
    }

    func testColorShiftParameterDescriptorsAreStable() {
        let store = ParameterStore(descriptors: ParameterCatalog.descriptors)
        let hueResponse = store.descriptor(for: "mode.colorShift.hueResponse")
        let hueRange = store.descriptor(for: "mode.colorShift.hueRange")

        XCTAssertNotNil(hueResponse)
        XCTAssertNotNil(hueRange)
        guard let hueResponse, let hueRange else {
            return XCTFail("Expected color shift parameter descriptors")
        }

        XCTAssertEqual(hueResponse.scope, .mode(.colorShift))
        XCTAssertEqual(hueRange.scope, .mode(.colorShift))

        XCTAssertEqual(hueResponse.minimumValue ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(hueResponse.maximumValue ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(hueRange.minimumValue ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(hueRange.maximumValue ?? -1, 1, accuracy: 0.0001)

        XCTAssertEqual(hueResponse.defaultValue.scalarValue ?? -1, 0.66, accuracy: 0.0001)
        XCTAssertEqual(hueRange.defaultValue.scalarValue ?? -1, 0.74, accuracy: 0.0001)
    }

    func testColorShiftControlListsExcludeBlackFloorButPrismKeepsIt() {
        let colorShiftQuick = ParameterCatalog.quickControlParameterIDs(for: .colorShift)
        let colorShiftSurface = ParameterCatalog.surfaceControlParameterIDs(for: .colorShift)
        let prismQuick = ParameterCatalog.quickControlParameterIDs(for: .prismField)
        let prismSurface = ParameterCatalog.surfaceControlParameterIDs(for: .prismField)

        XCTAssertFalse(colorShiftQuick.contains("output.blackFloor"))
        XCTAssertFalse(colorShiftSurface.contains("output.blackFloor"))
        XCTAssertTrue(prismQuick.contains("mode.prismField.facetDensity"))
        XCTAssertTrue(prismQuick.contains("mode.prismField.dispersion"))
        XCTAssertTrue(prismSurface.contains("mode.prismField.facetDensity"))
        XCTAssertTrue(prismSurface.contains("mode.prismField.dispersion"))
        XCTAssertTrue(prismQuick.contains("output.blackFloor"))
        XCTAssertTrue(prismSurface.contains("output.blackFloor"))
    }

    func testPrismFieldParameterDescriptorsAreStable() {
        let store = ParameterStore(descriptors: ParameterCatalog.descriptors)
        let facetDensity = store.descriptor(for: "mode.prismField.facetDensity")
        let dispersion = store.descriptor(for: "mode.prismField.dispersion")

        XCTAssertNotNil(facetDensity)
        XCTAssertNotNil(dispersion)
        guard let facetDensity, let dispersion else {
            return XCTFail("Expected prism parameter descriptors")
        }

        XCTAssertEqual(facetDensity.scope, .mode(.prismField))
        XCTAssertEqual(dispersion.scope, .mode(.prismField))
        XCTAssertEqual(facetDensity.minimumValue ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(facetDensity.maximumValue ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(dispersion.minimumValue ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(dispersion.maximumValue ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(facetDensity.defaultValue.scalarValue ?? -1, 0.58, accuracy: 0.0001)
        XCTAssertEqual(dispersion.defaultValue.scalarValue ?? -1, 0.62, accuracy: 0.0001)
    }
}
