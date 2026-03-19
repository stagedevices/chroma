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
        let tunnelQuick = ParameterCatalog.quickControlParameterIDs(for: .tunnelCels)
        let tunnelSurface = ParameterCatalog.surfaceControlParameterIDs(for: .tunnelCels)
        let fractalQuick = ParameterCatalog.quickControlParameterIDs(for: .fractalCaustics)
        let fractalSurface = ParameterCatalog.surfaceControlParameterIDs(for: .fractalCaustics)
        let riemannQuick = ParameterCatalog.quickControlParameterIDs(for: .riemannCorridor)
        let riemannSurface = ParameterCatalog.surfaceControlParameterIDs(for: .riemannCorridor)

        XCTAssertFalse(colorShiftQuick.contains("output.blackFloor"))
        XCTAssertFalse(colorShiftSurface.contains("output.blackFloor"))
        XCTAssertTrue(prismQuick.contains("mode.prismField.facetDensity"))
        XCTAssertTrue(prismQuick.contains("mode.prismField.dispersion"))
        XCTAssertTrue(prismSurface.contains("mode.prismField.facetDensity"))
        XCTAssertTrue(prismSurface.contains("mode.prismField.dispersion"))
        XCTAssertTrue(prismQuick.contains("output.blackFloor"))
        XCTAssertTrue(prismSurface.contains("output.blackFloor"))
        XCTAssertTrue(tunnelQuick.contains("mode.tunnelCels.shapeScale"))
        XCTAssertTrue(tunnelQuick.contains("mode.tunnelCels.depthSpeed"))
        XCTAssertTrue(tunnelQuick.contains("mode.tunnelCels.releaseTail"))
        XCTAssertTrue(tunnelQuick.contains("output.blackFloor"))
        XCTAssertTrue(tunnelSurface.contains("mode.tunnelCels.shapeScale"))
        XCTAssertTrue(tunnelSurface.contains("mode.tunnelCels.depthSpeed"))
        XCTAssertTrue(tunnelSurface.contains("mode.tunnelCels.releaseTail"))
        XCTAssertTrue(tunnelSurface.contains("output.blackFloor"))
        XCTAssertFalse(tunnelQuick.contains("mode.tunnelCels.variant"))
        XCTAssertFalse(tunnelSurface.contains("mode.tunnelCels.variant"))
        XCTAssertTrue(fractalQuick.contains("mode.fractalCaustics.detail"))
        XCTAssertTrue(fractalQuick.contains("mode.fractalCaustics.flowRate"))
        XCTAssertTrue(fractalQuick.contains("mode.fractalCaustics.attackBloom"))
        XCTAssertTrue(fractalQuick.contains("output.blackFloor"))
        XCTAssertTrue(fractalSurface.contains("mode.fractalCaustics.detail"))
        XCTAssertTrue(fractalSurface.contains("mode.fractalCaustics.flowRate"))
        XCTAssertTrue(fractalSurface.contains("mode.fractalCaustics.attackBloom"))
        XCTAssertTrue(fractalSurface.contains("output.blackFloor"))
        XCTAssertFalse(fractalQuick.contains("mode.fractalCaustics.paletteVariant"))
        XCTAssertFalse(fractalSurface.contains("mode.fractalCaustics.paletteVariant"))
        XCTAssertTrue(riemannQuick.contains("mode.riemannCorridor.detail"))
        XCTAssertTrue(riemannQuick.contains("mode.riemannCorridor.flowRate"))
        XCTAssertTrue(riemannQuick.contains("mode.riemannCorridor.zeroBloom"))
        XCTAssertTrue(riemannQuick.contains("output.blackFloor"))
        XCTAssertTrue(riemannSurface.contains("mode.riemannCorridor.detail"))
        XCTAssertTrue(riemannSurface.contains("mode.riemannCorridor.flowRate"))
        XCTAssertTrue(riemannSurface.contains("mode.riemannCorridor.zeroBloom"))
        XCTAssertTrue(riemannSurface.contains("output.blackFloor"))
        XCTAssertFalse(riemannQuick.contains("mode.riemannCorridor.paletteVariant"))
        XCTAssertFalse(riemannSurface.contains("mode.riemannCorridor.paletteVariant"))
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

    func testTunnelCelsParameterDescriptorsAreStable() {
        let store = ParameterStore(descriptors: ParameterCatalog.descriptors)
        let shapeScale = store.descriptor(for: "mode.tunnelCels.shapeScale")
        let depthSpeed = store.descriptor(for: "mode.tunnelCels.depthSpeed")
        let releaseTail = store.descriptor(for: "mode.tunnelCels.releaseTail")
        let variant = store.descriptor(for: "mode.tunnelCels.variant")

        XCTAssertNotNil(shapeScale)
        XCTAssertNotNil(depthSpeed)
        XCTAssertNotNil(releaseTail)
        XCTAssertNotNil(variant)
        guard let shapeScale, let depthSpeed, let releaseTail, let variant else {
            return XCTFail("Expected tunnel cels parameter descriptors")
        }

        XCTAssertEqual(shapeScale.scope, .mode(.tunnelCels))
        XCTAssertEqual(depthSpeed.scope, .mode(.tunnelCels))
        XCTAssertEqual(releaseTail.scope, .mode(.tunnelCels))
        XCTAssertEqual(variant.scope, .mode(.tunnelCels))
        XCTAssertEqual(shapeScale.defaultValue.scalarValue ?? -1, 0.56, accuracy: 0.0001)
        XCTAssertEqual(depthSpeed.defaultValue.scalarValue ?? -1, 0.62, accuracy: 0.0001)
        XCTAssertEqual(releaseTail.defaultValue.scalarValue ?? -1, 0.58, accuracy: 0.0001)
        XCTAssertEqual(variant.defaultValue.scalarValue ?? -1, 0.0, accuracy: 0.0001)
        XCTAssertEqual(variant.minimumValue ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(variant.maximumValue ?? -1, 2, accuracy: 0.0001)
    }

    func testFractalCausticsParameterDescriptorsAreStable() {
        let store = ParameterStore(descriptors: ParameterCatalog.descriptors)
        let detail = store.descriptor(for: "mode.fractalCaustics.detail")
        let flowRate = store.descriptor(for: "mode.fractalCaustics.flowRate")
        let attackBloom = store.descriptor(for: "mode.fractalCaustics.attackBloom")
        let palette = store.descriptor(for: "mode.fractalCaustics.paletteVariant")

        XCTAssertNotNil(detail)
        XCTAssertNotNil(flowRate)
        XCTAssertNotNil(attackBloom)
        XCTAssertNotNil(palette)
        guard let detail, let flowRate, let attackBloom, let palette else {
            return XCTFail("Expected fractal caustics parameter descriptors")
        }

        XCTAssertEqual(detail.scope, .mode(.fractalCaustics))
        XCTAssertEqual(flowRate.scope, .mode(.fractalCaustics))
        XCTAssertEqual(attackBloom.scope, .mode(.fractalCaustics))
        XCTAssertEqual(palette.scope, .mode(.fractalCaustics))
        XCTAssertEqual(detail.defaultValue.scalarValue ?? -1, 0.60, accuracy: 0.0001)
        XCTAssertEqual(flowRate.defaultValue.scalarValue ?? -1, 0.56, accuracy: 0.0001)
        XCTAssertEqual(attackBloom.defaultValue.scalarValue ?? -1, 0.62, accuracy: 0.0001)
        XCTAssertEqual(palette.defaultValue.scalarValue ?? -1, 0.0, accuracy: 0.0001)
        XCTAssertEqual(detail.minimumValue ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(detail.maximumValue ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(flowRate.minimumValue ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(flowRate.maximumValue ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(attackBloom.minimumValue ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(attackBloom.maximumValue ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(palette.minimumValue ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(palette.maximumValue ?? -1, 7, accuracy: 0.0001)
    }

    func testRiemannCorridorParameterDescriptorsAreStable() {
        let store = ParameterStore(descriptors: ParameterCatalog.descriptors)
        let detail = store.descriptor(for: "mode.riemannCorridor.detail")
        let flowRate = store.descriptor(for: "mode.riemannCorridor.flowRate")
        let zeroBloom = store.descriptor(for: "mode.riemannCorridor.zeroBloom")
        let palette = store.descriptor(for: "mode.riemannCorridor.paletteVariant")

        XCTAssertNotNil(detail)
        XCTAssertNotNil(flowRate)
        XCTAssertNotNil(zeroBloom)
        XCTAssertNotNil(palette)
        guard let detail, let flowRate, let zeroBloom, let palette else {
            return XCTFail("Expected riemann corridor parameter descriptors")
        }

        XCTAssertEqual(detail.scope, .mode(.riemannCorridor))
        XCTAssertEqual(flowRate.scope, .mode(.riemannCorridor))
        XCTAssertEqual(zeroBloom.scope, .mode(.riemannCorridor))
        XCTAssertEqual(palette.scope, .mode(.riemannCorridor))
        XCTAssertEqual(detail.defaultValue.scalarValue ?? -1, 0.60, accuracy: 0.0001)
        XCTAssertEqual(flowRate.defaultValue.scalarValue ?? -1, 0.56, accuracy: 0.0001)
        XCTAssertEqual(zeroBloom.defaultValue.scalarValue ?? -1, 0.62, accuracy: 0.0001)
        XCTAssertEqual(palette.defaultValue.scalarValue ?? -1, 0.0, accuracy: 0.0001)
        XCTAssertEqual(detail.minimumValue ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(detail.maximumValue ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(flowRate.minimumValue ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(flowRate.maximumValue ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(zeroBloom.minimumValue ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(zeroBloom.maximumValue ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(palette.minimumValue ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(palette.maximumValue ?? -1, 7, accuracy: 0.0001)
    }

    func testMandelbrotModeLabelKeepsStableID() {
        XCTAssertEqual(VisualModeID.riemannCorridor.rawValue, "riemannCorridor")
        XCTAssertEqual(VisualModeID.riemannCorridor.displayName, "Mandelbrot")

        let modeDescriptor = ParameterCatalog.modes.first { $0.id == .riemannCorridor }
        XCTAssertNotNil(modeDescriptor)
        XCTAssertEqual(modeDescriptor?.name, "Mandelbrot")
    }
}
