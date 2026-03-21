import XCTest
@testable import Chroma

final class PatchCompilerTests: XCTestCase {

    // MARK: - Valid Graph Compilation

    func testSeedScaffoldCompilesSuccessfully() {
        let patch = CustomPatch.seedScaffold()
        let result = PatchCompiler.compile(patch)
        XCTAssertTrue(result.isSuccess, "Seed scaffold should compile without errors: \(result.errors)")
        XCTAssertNotNil(result.program)
    }

    func testSeedScaffoldProducesCorrectStepCount() {
        let patch = CustomPatch.seedScaffold()
        let result = PatchCompiler.compile(patch)
        guard let program = result.program else { return XCTFail("Expected program") }
        XCTAssertEqual(program.steps.count, 5)
    }

    func testSeedScaffoldTopologicalOrder() {
        let patch = CustomPatch.seedScaffold()
        let result = PatchCompiler.compile(patch)
        guard let program = result.program else { return XCTFail("Expected program") }

        let kindOrder = program.steps.map(\.kind)
        let audioInIndex = kindOrder.firstIndex(of: .audioIn)!
        let spectrumIndex = kindOrder.firstIndex(of: .spectrum)!
        let oscillatorIndex = kindOrder.firstIndex(of: .oscillator)!
        let blendIndex = kindOrder.firstIndex(of: .blend)!
        let outputIndex = kindOrder.firstIndex(of: .output)!

        XCTAssertLessThan(audioInIndex, spectrumIndex, "AudioIn must come before Spectrum")
        XCTAssertLessThan(spectrumIndex, oscillatorIndex, "Spectrum must come before Oscillator")
        XCTAssertLessThan(oscillatorIndex, blendIndex, "Oscillator must come before Blend")
        XCTAssertLessThan(blendIndex, outputIndex, "Blend must come before Output")
    }

    func testSeedScaffoldSlotCounts() {
        let patch = CustomPatch.seedScaffold()
        let result = PatchCompiler.compile(patch)
        guard let program = result.program else { return XCTFail("Expected program") }

        // AudioIn: signal + trigger = 2 signal slots
        // Spectrum: low + mid + high = 3 signal slots
        // Total signal slots: 5
        XCTAssertEqual(program.signalSlotCount, 5)

        // Oscillator: field = 1 texture slot
        // Blend: color = 1 texture slot
        // Total texture slots: 2
        XCTAssertEqual(program.textureSlotCount, 2)
    }

    func testSeedScaffoldOutputTextureSlot() {
        let patch = CustomPatch.seedScaffold()
        let result = PatchCompiler.compile(patch)
        guard let program = result.program else { return XCTFail("Expected program") }

        // Output node reads from Blend's output texture
        XCTAssertGreaterThanOrEqual(program.outputTextureSlot, 0)
        XCTAssertLessThan(program.outputTextureSlot, program.textureSlotCount)
    }

    func testSeedScaffoldInputBindingsAreConnected() {
        let patch = CustomPatch.seedScaffold()
        let result = PatchCompiler.compile(patch)
        guard let program = result.program else { return XCTFail("Expected program") }

        let oscillatorStep = program.steps.first(where: { $0.kind == .oscillator })!
        let driveInput = oscillatorStep.inputs.first(where: { $0.portName == "drive" })!
        XCTAssertTrue(driveInput.isConnected, "Oscillator drive should be connected")
        XCTAssertEqual(driveInput.portType, .signal)
    }

    func testSeedScaffoldBlendUnconnectedInputs() {
        let patch = CustomPatch.seedScaffold()
        let result = PatchCompiler.compile(patch)
        guard let program = result.program else { return XCTFail("Expected program") }

        let blendStep = program.steps.first(where: { $0.kind == .blend })!
        let aInput = blendStep.inputs.first(where: { $0.portName == "a" })!
        let bInput = blendStep.inputs.first(where: { $0.portName == "b" })!
        let mixInput = blendStep.inputs.first(where: { $0.portName == "mix" })!
        XCTAssertTrue(aInput.isConnected, "Blend 'a' is connected from oscillator")
        XCTAssertFalse(bInput.isConnected, "Blend 'b' is unconnected")
        XCTAssertFalse(mixInput.isConnected, "Blend 'mix' is unconnected")
    }

    // MARK: - Minimal Valid Graph

    func testMinimalPatchCompiles() {
        let outputNode = CustomPatchNode(
            kind: .output,
            title: "Output",
            position: CustomPatchPoint(x: 0, y: 0)
        )
        let patch = CustomPatch(name: "Minimal", nodes: [outputNode], connections: [])
        let result = PatchCompiler.compile(patch)
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.program?.steps.count, 1)
        XCTAssertEqual(result.program?.outputTextureSlot, -1, "No connected field → -1")
    }

    // MARK: - Cycle Detection

    func testCycleDetected() {
        let blendA = CustomPatchNode(id: UUID(), kind: .blend, title: "Blend A", position: CustomPatchPoint(x: 0, y: 0))
        let blendB = CustomPatchNode(id: UUID(), kind: .blend, title: "Blend B", position: CustomPatchPoint(x: 100, y: 0))
        let output = CustomPatchNode(id: UUID(), kind: .output, title: "Out", position: CustomPatchPoint(x: 200, y: 0))
        // A.color → B.a and B.color → A.a (cycle with matching field types)
        let connections = [
            CustomPatchConnection(fromNodeID: blendA.id, fromPort: "color", toNodeID: blendB.id, toPort: "a"),
            CustomPatchConnection(fromNodeID: blendB.id, fromPort: "color", toNodeID: blendA.id, toPort: "a"),
        ]
        let patch = CustomPatch(name: "Cycle", nodes: [blendA, blendB, output], connections: connections)
        let result = PatchCompiler.compile(patch)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.errors.contains(.cycleDetected))
    }

    // MARK: - Validation Errors

    func testNoOutputNodeError() {
        let node = CustomPatchNode(kind: .audioIn, title: "Audio In", position: CustomPatchPoint(x: 0, y: 0))
        let patch = CustomPatch(name: "No Output", nodes: [node], connections: [])
        let result = PatchCompiler.compile(patch)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.errors.contains(.noOutputNode))
    }

    func testMultipleOutputNodesError() {
        let output1 = CustomPatchNode(kind: .output, title: "Out 1", position: CustomPatchPoint(x: 0, y: 0))
        let output2 = CustomPatchNode(kind: .output, title: "Out 2", position: CustomPatchPoint(x: 100, y: 0))
        let patch = CustomPatch(name: "Double Output", nodes: [output1, output2], connections: [])
        let result = PatchCompiler.compile(patch)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.errors.contains(.multipleOutputNodes))
    }

    func testTypeMismatchError() {
        let audioIn = CustomPatchNode(id: UUID(), kind: .audioIn, title: "Audio In", position: CustomPatchPoint(x: 0, y: 0))
        let output = CustomPatchNode(id: UUID(), kind: .output, title: "Output", position: CustomPatchPoint(x: 100, y: 0))
        // signal → field type mismatch
        let connection = CustomPatchConnection(fromNodeID: audioIn.id, fromPort: "signal", toNodeID: output.id, toPort: "color")
        let patch = CustomPatch(name: "Mismatch", nodes: [audioIn, output], connections: [connection])
        let result = PatchCompiler.compile(patch)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.errors.contains(where: {
            if case .typeMismatch(_, .signal, .field) = $0 { return true }
            return false
        }))
    }

    func testInvalidPortNameError() {
        let audioIn = CustomPatchNode(id: UUID(), kind: .audioIn, title: "Audio In", position: CustomPatchPoint(x: 0, y: 0))
        let output = CustomPatchNode(id: UUID(), kind: .output, title: "Output", position: CustomPatchPoint(x: 100, y: 0))
        let connection = CustomPatchConnection(fromNodeID: audioIn.id, fromPort: "nonexistent", toNodeID: output.id, toPort: "color")
        let patch = CustomPatch(name: "Bad Port", nodes: [audioIn, output], connections: [connection])
        let result = PatchCompiler.compile(patch)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.errors.contains(where: {
            if case .invalidPort(_, "nonexistent", "output") = $0 { return true }
            return false
        }))
    }

    func testDuplicateConnectionError() {
        let audioIn = CustomPatchNode(id: UUID(), kind: .audioIn, title: "Audio In", position: CustomPatchPoint(x: 0, y: 0))
        let spectrum = CustomPatchNode(id: UUID(), kind: .spectrum, title: "Spectrum", position: CustomPatchPoint(x: 100, y: 0))
        let output = CustomPatchNode(id: UUID(), kind: .output, title: "Output", position: CustomPatchPoint(x: 200, y: 0))
        let conn1 = CustomPatchConnection(fromNodeID: audioIn.id, fromPort: "signal", toNodeID: spectrum.id, toPort: "signal")
        let conn2 = CustomPatchConnection(fromNodeID: audioIn.id, fromPort: "signal", toNodeID: spectrum.id, toPort: "signal")
        let patch = CustomPatch(name: "Dup", nodes: [audioIn, spectrum, output], connections: [conn1, conn2])
        let result = PatchCompiler.compile(patch)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.errors.contains(where: {
            if case .duplicateConnection = $0 { return true }
            return false
        }))
    }

    func testUnknownNodeError() {
        let output = CustomPatchNode(id: UUID(), kind: .output, title: "Output", position: CustomPatchPoint(x: 0, y: 0))
        let connection = CustomPatchConnection(fromNodeID: UUID(), fromPort: "signal", toNodeID: output.id, toPort: "color")
        let patch = CustomPatch(name: "Unknown", nodes: [output], connections: [connection])
        let result = PatchCompiler.compile(patch)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.errors.contains(where: {
            if case .unknownNode = $0 { return true }
            return false
        }))
    }

    // MARK: - Port Type System

    func testAllNodeKindsHavePortDescriptors() {
        for kind in CustomPatchNodeKind.allCases {
            let inputs = kind.inputPortDescriptors
            let outputs = kind.outputPortDescriptors
            switch kind {
            case .audioIn:
                XCTAssertEqual(inputs.count, 0)
                XCTAssertEqual(outputs.count, 2)
            case .spectrum:
                XCTAssertEqual(inputs.count, 1)
                XCTAssertEqual(outputs.count, 3)
            case .oscillator:
                XCTAssertEqual(inputs.count, 1)
                XCTAssertEqual(outputs.count, 1)
                XCTAssertEqual(outputs[0].type, .field)
            case .transform:
                XCTAssertEqual(inputs.count, 2)
                XCTAssertEqual(outputs.count, 1)
            case .blend:
                XCTAssertEqual(inputs.count, 3)
                XCTAssertEqual(outputs.count, 1)
            case .output:
                XCTAssertEqual(inputs.count, 1)
                XCTAssertEqual(outputs.count, 0)
            case .pitch:
                XCTAssertEqual(inputs.count, 0)
                XCTAssertEqual(outputs.count, 2)
            case .lfo, .noise, .constant, .time:
                XCTAssertEqual(inputs.count, 0)
                XCTAssertEqual(outputs.count, 1)
            case .math, .mix:
                XCTAssertGreaterThanOrEqual(inputs.count, 2)
                XCTAssertEqual(outputs.count, 1)
            case .envelope:
                XCTAssertEqual(inputs.count, 1)
                XCTAssertEqual(outputs.count, 1)
            case .smooth, .threshold, .remap:
                XCTAssertEqual(inputs.count, 1)
                XCTAssertEqual(outputs.count, 1)
            case .sampleAndHold:
                XCTAssertEqual(inputs.count, 2)
                XCTAssertEqual(outputs.count, 1)
            case .solid:
                XCTAssertEqual(inputs.count, 3) // r, g, b
                XCTAssertEqual(outputs.count, 1)
                XCTAssertEqual(outputs[0].type, .field)
            case .gradient:
                XCTAssertEqual(inputs.count, 2)
                XCTAssertEqual(outputs.count, 1)
                XCTAssertEqual(outputs[0].type, .field)
            case .oscillator2D:
                XCTAssertEqual(inputs.count, 2)
                XCTAssertEqual(outputs.count, 1)
                XCTAssertEqual(outputs[0].type, .field)
            case .particles:
                XCTAssertEqual(inputs.count, 2)
                XCTAssertTrue(inputs.contains(where: { $0.type == .trigger }))
                XCTAssertEqual(outputs.count, 1)
                XCTAssertEqual(outputs[0].type, .field)
            case .hsvAdjust:
                XCTAssertTrue(inputs.contains(where: { $0.type == .field }))
                XCTAssertEqual(outputs.count, 1)
                XCTAssertEqual(outputs[0].type, .field)
            case .transform2D:
                XCTAssertTrue(inputs.contains(where: { $0.type == .field }))
                XCTAssertEqual(outputs.count, 1)
                XCTAssertEqual(outputs[0].type, .field)
            case .fractal:
                XCTAssertEqual(inputs.count, 2) // real, imag signals
                XCTAssertEqual(outputs.count, 1)
                XCTAssertEqual(outputs[0].type, .field)
            case .voronoi:
                XCTAssertEqual(inputs.count, 1) // drive signal
                XCTAssertEqual(outputs.count, 1)
                XCTAssertEqual(outputs[0].type, .field)
            case .feedback:
                XCTAssertEqual(inputs.count, 1)
                XCTAssertTrue(inputs.contains(where: { $0.type == .field }))
                XCTAssertEqual(outputs.count, 1)
                XCTAssertEqual(outputs[0].type, .field)
            case .blur:
                XCTAssertEqual(inputs.count, 2) // field, radius signal
                XCTAssertTrue(inputs.contains(where: { $0.type == .field }))
                XCTAssertEqual(outputs.count, 1)
                XCTAssertEqual(outputs[0].type, .field)
            case .displace:
                XCTAssertEqual(inputs.count, 3) // field, map field, amount signal
                XCTAssertEqual(inputs.filter({ $0.type == .field }).count, 2)
                XCTAssertEqual(outputs.count, 1)
                XCTAssertEqual(outputs[0].type, .field)
            case .mirror:
                XCTAssertEqual(inputs.count, 1)
                XCTAssertTrue(inputs.contains(where: { $0.type == .field }))
                XCTAssertEqual(outputs.count, 1)
                XCTAssertEqual(outputs[0].type, .field)
            case .tile:
                XCTAssertEqual(inputs.count, 2) // field, scale signal
                XCTAssertTrue(inputs.contains(where: { $0.type == .field }))
                XCTAssertEqual(outputs.count, 1)
                XCTAssertEqual(outputs[0].type, .field)
            case .cameraIn:
                XCTAssertEqual(inputs.count, 0)
                XCTAssertEqual(outputs.count, 1)
                XCTAssertEqual(outputs[0].type, .field)
            }
        }
    }

    func testAllNodeKindsHaveDefaultParameters() {
        for kind in CustomPatchNodeKind.allCases {
            let params = kind.defaultParameters
            XCTAssertFalse(params.isEmpty, "\(kind) should have at least one parameter")
            for param in params {
                XCTAssertGreaterThanOrEqual(param.value, param.min, "\(kind).\(param.name) value below min")
                XCTAssertLessThanOrEqual(param.value, param.max, "\(kind).\(param.name) value above max")
                XCTAssertGreaterThanOrEqual(param.defaultValue, param.min)
                XCTAssertLessThanOrEqual(param.defaultValue, param.max)
            }
        }
    }

    // MARK: - Domain Serialization

    func testCustomPatchNodeRoundTripsCodable() throws {
        let node = CustomPatchNode(
            kind: .oscillator,
            title: "Test Osc",
            position: CustomPatchPoint(x: 100, y: 200),
            parameters: [
                PatchNodeParameter(name: "rate", displayName: "Rate", value: 0.8, defaultValue: 0.56, min: 0, max: 4),
            ]
        )
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(CustomPatchNode.self, from: data)
        XCTAssertEqual(decoded.id, node.id)
        XCTAssertEqual(decoded.kind, .oscillator)
        XCTAssertEqual(decoded.parameters.count, 1)
        XCTAssertEqual(decoded.parameters[0].value, 0.8, accuracy: 0.001)
        XCTAssertEqual(decoded.inputPorts, ["drive"])
        XCTAssertEqual(decoded.outputPorts, ["field"])
    }

    func testCustomPatchNodeDecodesLegacyFormat() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "kind": "audioIn",
          "title": "Audio In",
          "position": {"x": 96, "y": 172},
          "inputPorts": [],
          "outputPorts": ["signal"],
          "inspectorHints": {"gain": 0.85}
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(CustomPatchNode.self, from: json)
        XCTAssertEqual(decoded.kind, .audioIn)
        XCTAssertEqual(decoded.parameters.count, 1)
        XCTAssertEqual(decoded.parameters[0].name, "gain")
        XCTAssertEqual(decoded.parameters[0].value, 0.85, accuracy: 0.001)
        XCTAssertEqual(decoded.inputPorts, [])
        XCTAssertEqual(decoded.outputPorts, ["signal", "attack"])
    }

    func testSeededDefaultLibraryRoundTripsCodable() throws {
        let library = CustomPatchLibrary.seededDefault()
        let data = try JSONEncoder().encode(library)
        let decoded = try JSONDecoder().decode(CustomPatchLibrary.self, from: data)
        XCTAssertEqual(decoded.patches.count, 3)
        XCTAssertEqual(decoded.patches[0].name, "Breathing Fractal")
        XCTAssertEqual(decoded.patches[0].nodes.count, 12)
        XCTAssertEqual(decoded.patches[0].connections.count, 13)
        XCTAssertEqual(decoded.activePatchID, library.activePatchID)
    }

    func testPatchProgramRoundTripsCodable() throws {
        let patch = CustomPatch.seedScaffold()
        let result = PatchCompiler.compile(patch)
        guard let program = result.program else { return XCTFail("Expected program") }
        let data = try JSONEncoder().encode(program)
        let decoded = try JSONDecoder().decode(PatchProgram.self, from: data)
        XCTAssertEqual(decoded, program)
    }

    // MARK: - Phase 2 Node Kind Coverage

    func testPhase2SourceNodePortSignatures() {
        // Pitch
        XCTAssertEqual(CustomPatchNodeKind.pitch.inputPortDescriptors.count, 0)
        XCTAssertEqual(CustomPatchNodeKind.pitch.outputPortDescriptors.count, 2)
        XCTAssertEqual(CustomPatchNodeKind.pitch.outputPortDescriptors[0].name, "confidence")
        XCTAssertEqual(CustomPatchNodeKind.pitch.outputPortDescriptors[1].name, "pitch")

        // LFO
        XCTAssertEqual(CustomPatchNodeKind.lfo.inputPortDescriptors.count, 0)
        XCTAssertEqual(CustomPatchNodeKind.lfo.outputPortDescriptors.count, 1)
        XCTAssertEqual(CustomPatchNodeKind.lfo.outputPortDescriptors[0].type, .signal)

        // Noise
        XCTAssertEqual(CustomPatchNodeKind.noise.outputPortDescriptors.count, 1)

        // Constant
        XCTAssertEqual(CustomPatchNodeKind.constant.outputPortDescriptors.count, 1)
        XCTAssertEqual(CustomPatchNodeKind.constant.defaultParameters[0].name, "value")

        // Time
        XCTAssertEqual(CustomPatchNodeKind.time.outputPortDescriptors.count, 1)
    }

    func testPhase2ProcessingNodePortSignatures() {
        // Math: 2 signal in → 1 signal out
        XCTAssertEqual(CustomPatchNodeKind.math.inputPortDescriptors.count, 2)
        XCTAssertEqual(CustomPatchNodeKind.math.outputPortDescriptors.count, 1)
        XCTAssertEqual(CustomPatchNodeKind.math.inputPortDescriptors[0].type, .signal)

        // Envelope: 1 trigger in → 1 signal out
        XCTAssertEqual(CustomPatchNodeKind.envelope.inputPortDescriptors.count, 1)
        XCTAssertEqual(CustomPatchNodeKind.envelope.inputPortDescriptors[0].type, .trigger)
        XCTAssertEqual(CustomPatchNodeKind.envelope.outputPortDescriptors[0].type, .signal)
        XCTAssertEqual(CustomPatchNodeKind.envelope.defaultParameters.count, 4) // ADSR

        // Smooth
        XCTAssertEqual(CustomPatchNodeKind.smooth.inputPortDescriptors.count, 1)
        XCTAssertEqual(CustomPatchNodeKind.smooth.outputPortDescriptors.count, 1)

        // Threshold: signal in → trigger out
        XCTAssertEqual(CustomPatchNodeKind.threshold.inputPortDescriptors[0].type, .signal)
        XCTAssertEqual(CustomPatchNodeKind.threshold.outputPortDescriptors[0].type, .trigger)

        // Sample & Hold: signal + trigger in → signal out
        XCTAssertEqual(CustomPatchNodeKind.sampleAndHold.inputPortDescriptors.count, 2)
        XCTAssertTrue(CustomPatchNodeKind.sampleAndHold.inputPortDescriptors.contains(where: { $0.type == .trigger }))

        // Mix: 3 signal in → 1 signal out
        XCTAssertEqual(CustomPatchNodeKind.mix.inputPortDescriptors.count, 3)
        XCTAssertEqual(CustomPatchNodeKind.mix.outputPortDescriptors.count, 1)

        // Remap: 1 signal in → 1 signal out, 5 params
        XCTAssertEqual(CustomPatchNodeKind.remap.inputPortDescriptors.count, 1)
        XCTAssertEqual(CustomPatchNodeKind.remap.defaultParameters.count, 5)
    }

    func testPhase2NodeKindsAreSignalOnly() {
        let phase2Kinds: [CustomPatchNodeKind] = [.pitch, .lfo, .noise, .constant, .time, .math, .envelope, .smooth, .threshold, .sampleAndHold, .mix, .remap]
        for kind in phase2Kinds {
            XCTAssertTrue(kind.isSignalOnly, "\(kind) should be signal-only")
            for port in kind.inputPortDescriptors {
                XCTAssertTrue(port.type == .signal || port.type == .trigger, "\(kind) input \(port.name) should be signal or trigger")
            }
            for port in kind.outputPortDescriptors {
                XCTAssertTrue(port.type == .signal || port.type == .trigger, "\(kind) output \(port.name) should be signal or trigger")
            }
        }
    }

    func testPhase2GraphWithLFOAndMathCompiles() {
        let lfo = CustomPatchNode(id: UUID(), kind: .lfo, title: "LFO", position: CustomPatchPoint(x: 0, y: 0))
        let constant = CustomPatchNode(id: UUID(), kind: .constant, title: "Const", position: CustomPatchPoint(x: 0, y: 100))
        let math = CustomPatchNode(id: UUID(), kind: .math, title: "Math", position: CustomPatchPoint(x: 200, y: 0))
        let osc = CustomPatchNode(id: UUID(), kind: .oscillator, title: "Osc", position: CustomPatchPoint(x: 400, y: 0))
        let output = CustomPatchNode(id: UUID(), kind: .output, title: "Out", position: CustomPatchPoint(x: 600, y: 0))

        let connections = [
            CustomPatchConnection(fromNodeID: lfo.id, fromPort: "signal", toNodeID: math.id, toPort: "a"),
            CustomPatchConnection(fromNodeID: constant.id, fromPort: "signal", toNodeID: math.id, toPort: "b"),
            CustomPatchConnection(fromNodeID: math.id, fromPort: "result", toNodeID: osc.id, toPort: "drive"),
            CustomPatchConnection(fromNodeID: osc.id, fromPort: "field", toNodeID: output.id, toPort: "color"),
        ]

        let patch = CustomPatch(name: "LFO+Math", nodes: [lfo, constant, math, osc, output], connections: connections)
        let result = PatchCompiler.compile(patch)
        XCTAssertTrue(result.isSuccess, "Errors: \(result.errors)")
        XCTAssertEqual(result.program?.steps.count, 5)
    }

    func testPhase2EnvelopeChainCompiles() {
        let audioIn = CustomPatchNode(id: UUID(), kind: .audioIn, title: "Audio", position: CustomPatchPoint(x: 0, y: 0))
        let threshold = CustomPatchNode(id: UUID(), kind: .threshold, title: "Thresh", position: CustomPatchPoint(x: 200, y: 0))
        let envelope = CustomPatchNode(id: UUID(), kind: .envelope, title: "Env", position: CustomPatchPoint(x: 400, y: 0))
        let smooth = CustomPatchNode(id: UUID(), kind: .smooth, title: "Smooth", position: CustomPatchPoint(x: 600, y: 0))
        let osc = CustomPatchNode(id: UUID(), kind: .oscillator, title: "Osc", position: CustomPatchPoint(x: 800, y: 0))
        let output = CustomPatchNode(id: UUID(), kind: .output, title: "Out", position: CustomPatchPoint(x: 1000, y: 0))

        let connections = [
            // audio amplitude → threshold → trigger → envelope → smooth → oscillator drive
            CustomPatchConnection(fromNodeID: audioIn.id, fromPort: "signal", toNodeID: threshold.id, toPort: "signal"),
            CustomPatchConnection(fromNodeID: threshold.id, fromPort: "trigger", toNodeID: envelope.id, toPort: "trigger"),
            CustomPatchConnection(fromNodeID: envelope.id, fromPort: "signal", toNodeID: smooth.id, toPort: "signal"),
            CustomPatchConnection(fromNodeID: smooth.id, fromPort: "signal", toNodeID: osc.id, toPort: "drive"),
            CustomPatchConnection(fromNodeID: osc.id, fromPort: "field", toNodeID: output.id, toPort: "color"),
        ]

        let patch = CustomPatch(name: "Envelope Chain", nodes: [audioIn, threshold, envelope, smooth, osc, output], connections: connections)
        let result = PatchCompiler.compile(patch)
        XCTAssertTrue(result.isSuccess, "Errors: \(result.errors)")
        guard let program = result.program else { return XCTFail("Expected program") }
        XCTAssertEqual(program.steps.count, 6)

        // Verify topological order: audioIn before threshold before envelope before smooth before osc before output
        let kindOrder = program.steps.map(\.kind)
        let audioIdx = kindOrder.firstIndex(of: .audioIn)!
        let threshIdx = kindOrder.firstIndex(of: .threshold)!
        let envIdx = kindOrder.firstIndex(of: .envelope)!
        let smoothIdx = kindOrder.firstIndex(of: .smooth)!
        let oscIdx = kindOrder.firstIndex(of: .oscillator)!
        XCTAssertLessThan(audioIdx, threshIdx)
        XCTAssertLessThan(threshIdx, envIdx)
        XCTAssertLessThan(envIdx, smoothIdx)
        XCTAssertLessThan(smoothIdx, oscIdx)
    }

    func testPhase2RemapNodeRoundTripsCodable() throws {
        let node = CustomPatchNode(
            kind: .remap,
            title: "Test Remap",
            position: CustomPatchPoint(x: 0, y: 0),
            parameters: [
                PatchNodeParameter(name: "inputMin", displayName: "In Min", value: 0.2, defaultValue: 0, min: 0, max: 1),
                PatchNodeParameter(name: "inputMax", displayName: "In Max", value: 0.8, defaultValue: 1, min: 0, max: 1),
                PatchNodeParameter(name: "outputMin", displayName: "Out Min", value: 0, defaultValue: 0, min: 0, max: 1),
                PatchNodeParameter(name: "outputMax", displayName: "Out Max", value: 1, defaultValue: 1, min: 0, max: 1),
                PatchNodeParameter(name: "curve", displayName: "Curve", value: 1, defaultValue: 0, min: 0, max: 3),
            ]
        )
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(CustomPatchNode.self, from: data)
        XCTAssertEqual(decoded.kind, .remap)
        XCTAssertEqual(decoded.parameters.count, 5)
        XCTAssertEqual(decoded.parameters.first(where: { $0.name == "inputMin" })!.value, 0.2, accuracy: 0.001)
    }

    func testPhase2SampleAndHoldWithMixCompiles() {
        let audio = CustomPatchNode(id: UUID(), kind: .audioIn, title: "Audio", position: CustomPatchPoint(x: 0, y: 0))
        let snh = CustomPatchNode(id: UUID(), kind: .sampleAndHold, title: "S&H", position: CustomPatchPoint(x: 200, y: 0))
        let lfo = CustomPatchNode(id: UUID(), kind: .lfo, title: "LFO", position: CustomPatchPoint(x: 200, y: 100))
        let mixNode = CustomPatchNode(id: UUID(), kind: .mix, title: "Mix", position: CustomPatchPoint(x: 400, y: 0))
        let osc = CustomPatchNode(id: UUID(), kind: .oscillator, title: "Osc", position: CustomPatchPoint(x: 600, y: 0))
        let output = CustomPatchNode(id: UUID(), kind: .output, title: "Out", position: CustomPatchPoint(x: 800, y: 0))

        let connections = [
            CustomPatchConnection(fromNodeID: audio.id, fromPort: "signal", toNodeID: snh.id, toPort: "signal"),
            CustomPatchConnection(fromNodeID: audio.id, fromPort: "attack", toNodeID: snh.id, toPort: "trigger"),
            CustomPatchConnection(fromNodeID: snh.id, fromPort: "signal", toNodeID: mixNode.id, toPort: "a"),
            CustomPatchConnection(fromNodeID: lfo.id, fromPort: "signal", toNodeID: mixNode.id, toPort: "b"),
            CustomPatchConnection(fromNodeID: mixNode.id, fromPort: "result", toNodeID: osc.id, toPort: "drive"),
            CustomPatchConnection(fromNodeID: osc.id, fromPort: "field", toNodeID: output.id, toPort: "color"),
        ]

        let patch = CustomPatch(name: "S&H+Mix", nodes: [audio, snh, lfo, mixNode, osc, output], connections: connections)
        let result = PatchCompiler.compile(patch)
        XCTAssertTrue(result.isSuccess, "Errors: \(result.errors)")
        XCTAssertEqual(result.program?.steps.count, 6)
    }

    func testTotalNodeKindCount() {
        // Phase 1: 6 core + Phase 2: 12 signal + Phase 3: 6 visual + Phase 5: 8 advanced = 32 total
        XCTAssertEqual(CustomPatchNodeKind.allCases.count, 32)
    }

    // MARK: - Phase 3 Visual Node Tests

    func testPhase3VisualNodesAreNotSignalOnly() {
        let phase3Kinds: [CustomPatchNodeKind] = [.solid, .gradient, .oscillator2D, .particles, .hsvAdjust, .transform2D]
        for kind in phase3Kinds {
            XCTAssertFalse(kind.isSignalOnly, "\(kind) should NOT be signal-only (produces fields)")
        }
    }

    func testPhase3VisualGeneratorGraphCompiles() {
        // Audio → Spectrum → LFO-driven Oscillator2D → HSV Adjust → Output
        let audio = CustomPatchNode(id: UUID(), kind: .audioIn, title: "Audio", position: CustomPatchPoint(x: 0, y: 0))
        let spectrum = CustomPatchNode(id: UUID(), kind: .spectrum, title: "Spectrum", position: CustomPatchPoint(x: 200, y: 0))
        let osc2d = CustomPatchNode(id: UUID(), kind: .oscillator2D, title: "Osc2D", position: CustomPatchPoint(x: 400, y: 0))
        let hsv = CustomPatchNode(id: UUID(), kind: .hsvAdjust, title: "HSV", position: CustomPatchPoint(x: 600, y: 0))
        let output = CustomPatchNode(id: UUID(), kind: .output, title: "Out", position: CustomPatchPoint(x: 800, y: 0))

        let connections = [
            CustomPatchConnection(fromNodeID: audio.id, fromPort: "signal", toNodeID: spectrum.id, toPort: "signal"),
            CustomPatchConnection(fromNodeID: spectrum.id, fromPort: "mid", toNodeID: osc2d.id, toPort: "drive"),
            CustomPatchConnection(fromNodeID: spectrum.id, fromPort: "high", toNodeID: osc2d.id, toPort: "speed"),
            CustomPatchConnection(fromNodeID: osc2d.id, fromPort: "field", toNodeID: hsv.id, toPort: "field"),
            CustomPatchConnection(fromNodeID: spectrum.id, fromPort: "low", toNodeID: hsv.id, toPort: "hue"),
            CustomPatchConnection(fromNodeID: hsv.id, fromPort: "field", toNodeID: output.id, toPort: "color"),
        ]

        let patch = CustomPatch(name: "Visual Gen", nodes: [audio, spectrum, osc2d, hsv, output], connections: connections)
        let result = PatchCompiler.compile(patch)
        XCTAssertTrue(result.isSuccess, "Errors: \(result.errors)")
        XCTAssertEqual(result.program?.steps.count, 5)
        XCTAssertGreaterThanOrEqual(result.program?.textureSlotCount ?? 0, 2, "Needs textures for osc2d + hsv")
    }

    func testPhase3ParticleWithBlendCompiles() {
        // Audio attack → Particles + Gradient → Blend → Output
        let audio = CustomPatchNode(id: UUID(), kind: .audioIn, title: "Audio", position: CustomPatchPoint(x: 0, y: 0))
        let grad = CustomPatchNode(id: UUID(), kind: .gradient, title: "Grad", position: CustomPatchPoint(x: 200, y: 100))
        let parts = CustomPatchNode(id: UUID(), kind: .particles, title: "Parts", position: CustomPatchPoint(x: 200, y: 0))
        let blend = CustomPatchNode(id: UUID(), kind: .blend, title: "Blend", position: CustomPatchPoint(x: 400, y: 0))
        let output = CustomPatchNode(id: UUID(), kind: .output, title: "Out", position: CustomPatchPoint(x: 600, y: 0))

        let connections = [
            CustomPatchConnection(fromNodeID: audio.id, fromPort: "attack", toNodeID: parts.id, toPort: "trigger"),
            CustomPatchConnection(fromNodeID: audio.id, fromPort: "signal", toNodeID: parts.id, toPort: "intensity"),
            CustomPatchConnection(fromNodeID: parts.id, fromPort: "field", toNodeID: blend.id, toPort: "a"),
            CustomPatchConnection(fromNodeID: grad.id, fromPort: "field", toNodeID: blend.id, toPort: "b"),
            CustomPatchConnection(fromNodeID: audio.id, fromPort: "signal", toNodeID: blend.id, toPort: "mix"),
            CustomPatchConnection(fromNodeID: blend.id, fromPort: "color", toNodeID: output.id, toPort: "color"),
        ]

        let patch = CustomPatch(name: "Particle Blend", nodes: [audio, grad, parts, blend, output], connections: connections)
        let result = PatchCompiler.compile(patch)
        XCTAssertTrue(result.isSuccess, "Errors: \(result.errors)")
        XCTAssertEqual(result.program?.steps.count, 5)
    }

    func testPhase3Transform2DChainCompiles() {
        // Solid → Transform2D → Transform2D → Output (rotation + scale chain)
        let solid = CustomPatchNode(id: UUID(), kind: .solid, title: "Solid", position: CustomPatchPoint(x: 0, y: 0))
        let lfo = CustomPatchNode(id: UUID(), kind: .lfo, title: "LFO", position: CustomPatchPoint(x: 0, y: 100))
        let t1 = CustomPatchNode(id: UUID(), kind: .transform2D, title: "Rotate", position: CustomPatchPoint(x: 200, y: 0))
        let t2 = CustomPatchNode(id: UUID(), kind: .transform2D, title: "Scale", position: CustomPatchPoint(x: 400, y: 0))
        let output = CustomPatchNode(id: UUID(), kind: .output, title: "Out", position: CustomPatchPoint(x: 600, y: 0))

        let connections = [
            CustomPatchConnection(fromNodeID: solid.id, fromPort: "field", toNodeID: t1.id, toPort: "field"),
            CustomPatchConnection(fromNodeID: lfo.id, fromPort: "signal", toNodeID: t1.id, toPort: "rotate"),
            CustomPatchConnection(fromNodeID: t1.id, fromPort: "field", toNodeID: t2.id, toPort: "field"),
            CustomPatchConnection(fromNodeID: lfo.id, fromPort: "signal", toNodeID: t2.id, toPort: "scale"),
            CustomPatchConnection(fromNodeID: t2.id, fromPort: "field", toNodeID: output.id, toPort: "color"),
        ]

        let patch = CustomPatch(name: "Transform Chain", nodes: [solid, lfo, t1, t2, output], connections: connections)
        let result = PatchCompiler.compile(patch)
        XCTAssertTrue(result.isSuccess, "Errors: \(result.errors)")
        XCTAssertEqual(result.program?.steps.count, 5)
        XCTAssertGreaterThanOrEqual(result.program?.textureSlotCount ?? 0, 3, "Needs textures for solid + t1 + t2")
    }

    // MARK: - Phase 5 Graph Compilation

    func testPhase5FractalWithAudioDriveCompiles() {
        // AudioIn → Spectrum → Fractal → Output
        let audioIn = CustomPatchNode(id: UUID(), kind: .audioIn, title: "Audio In", position: CustomPatchPoint(x: 0, y: 0))
        let spectrum = CustomPatchNode(id: UUID(), kind: .spectrum, title: "Spectrum", position: CustomPatchPoint(x: 200, y: 0))
        let fractal = CustomPatchNode(id: UUID(), kind: .fractal, title: "Fractal", position: CustomPatchPoint(x: 400, y: 0))
        let output = CustomPatchNode(id: UUID(), kind: .output, title: "Out", position: CustomPatchPoint(x: 600, y: 0))

        let connections = [
            CustomPatchConnection(fromNodeID: audioIn.id, fromPort: "signal", toNodeID: spectrum.id, toPort: "signal"),
            CustomPatchConnection(fromNodeID: spectrum.id, fromPort: "low", toNodeID: fractal.id, toPort: "real"),
            CustomPatchConnection(fromNodeID: spectrum.id, fromPort: "high", toNodeID: fractal.id, toPort: "imag"),
            CustomPatchConnection(fromNodeID: fractal.id, fromPort: "field", toNodeID: output.id, toPort: "color"),
        ]

        let patch = CustomPatch(name: "Fractal Audio", nodes: [audioIn, spectrum, fractal, output], connections: connections)
        let result = PatchCompiler.compile(patch)
        XCTAssertTrue(result.isSuccess, "Errors: \(result.errors)")
        XCTAssertEqual(result.program?.steps.count, 4)
    }

    func testPhase5VoronoiBlendCompiles() {
        // Voronoi + Fractal → Blend → Output
        let lfo = CustomPatchNode(id: UUID(), kind: .lfo, title: "LFO", position: CustomPatchPoint(x: 0, y: 0))
        let voronoi = CustomPatchNode(id: UUID(), kind: .voronoi, title: "Voronoi", position: CustomPatchPoint(x: 200, y: 0))
        let fractal = CustomPatchNode(id: UUID(), kind: .fractal, title: "Fractal", position: CustomPatchPoint(x: 200, y: 100))
        let blend = CustomPatchNode(id: UUID(), kind: .blend, title: "Blend", position: CustomPatchPoint(x: 400, y: 50))
        let output = CustomPatchNode(id: UUID(), kind: .output, title: "Out", position: CustomPatchPoint(x: 600, y: 50))

        let connections = [
            CustomPatchConnection(fromNodeID: lfo.id, fromPort: "signal", toNodeID: voronoi.id, toPort: "drive"),
            CustomPatchConnection(fromNodeID: voronoi.id, fromPort: "field", toNodeID: blend.id, toPort: "a"),
            CustomPatchConnection(fromNodeID: fractal.id, fromPort: "field", toNodeID: blend.id, toPort: "b"),
            CustomPatchConnection(fromNodeID: blend.id, fromPort: "color", toNodeID: output.id, toPort: "color"),
        ]

        let patch = CustomPatch(name: "Voronoi Blend", nodes: [lfo, voronoi, fractal, blend, output], connections: connections)
        let result = PatchCompiler.compile(patch)
        XCTAssertTrue(result.isSuccess, "Errors: \(result.errors)")
        XCTAssertEqual(result.program?.steps.count, 5)
    }

    func testPhase5FeedbackLoopCompiles() {
        // Oscillator → Feedback → Mirror → Output
        let osc = CustomPatchNode(id: UUID(), kind: .oscillator, title: "Osc", position: CustomPatchPoint(x: 0, y: 0))
        let feedback = CustomPatchNode(id: UUID(), kind: .feedback, title: "FB", position: CustomPatchPoint(x: 200, y: 0))
        let mirror = CustomPatchNode(id: UUID(), kind: .mirror, title: "Mirror", position: CustomPatchPoint(x: 400, y: 0))
        let output = CustomPatchNode(id: UUID(), kind: .output, title: "Out", position: CustomPatchPoint(x: 600, y: 0))

        let connections = [
            CustomPatchConnection(fromNodeID: osc.id, fromPort: "field", toNodeID: feedback.id, toPort: "field"),
            CustomPatchConnection(fromNodeID: feedback.id, fromPort: "field", toNodeID: mirror.id, toPort: "field"),
            CustomPatchConnection(fromNodeID: mirror.id, fromPort: "field", toNodeID: output.id, toPort: "color"),
        ]

        let patch = CustomPatch(name: "Feedback Loop", nodes: [osc, feedback, mirror, output], connections: connections)
        let result = PatchCompiler.compile(patch)
        XCTAssertTrue(result.isSuccess, "Errors: \(result.errors)")
        XCTAssertEqual(result.program?.steps.count, 4)
    }

    func testPhase5BlurDisplaceChainCompiles() {
        // Gradient → Blur → Displace(with Voronoi map) → Tile → Output
        let gradient = CustomPatchNode(id: UUID(), kind: .gradient, title: "Grad", position: CustomPatchPoint(x: 0, y: 0))
        let voronoi = CustomPatchNode(id: UUID(), kind: .voronoi, title: "Voronoi", position: CustomPatchPoint(x: 0, y: 100))
        let blur = CustomPatchNode(id: UUID(), kind: .blur, title: "Blur", position: CustomPatchPoint(x: 200, y: 0))
        let displace = CustomPatchNode(id: UUID(), kind: .displace, title: "Displace", position: CustomPatchPoint(x: 400, y: 0))
        let tile = CustomPatchNode(id: UUID(), kind: .tile, title: "Tile", position: CustomPatchPoint(x: 600, y: 0))
        let output = CustomPatchNode(id: UUID(), kind: .output, title: "Out", position: CustomPatchPoint(x: 800, y: 0))

        let connections = [
            CustomPatchConnection(fromNodeID: gradient.id, fromPort: "field", toNodeID: blur.id, toPort: "field"),
            CustomPatchConnection(fromNodeID: blur.id, fromPort: "field", toNodeID: displace.id, toPort: "field"),
            CustomPatchConnection(fromNodeID: voronoi.id, fromPort: "field", toNodeID: displace.id, toPort: "map"),
            CustomPatchConnection(fromNodeID: displace.id, fromPort: "field", toNodeID: tile.id, toPort: "field"),
            CustomPatchConnection(fromNodeID: tile.id, fromPort: "field", toNodeID: output.id, toPort: "color"),
        ]

        let patch = CustomPatch(name: "Blur Displace Chain", nodes: [gradient, voronoi, blur, displace, tile, output], connections: connections)
        let result = PatchCompiler.compile(patch)
        XCTAssertTrue(result.isSuccess, "Errors: \(result.errors)")
        XCTAssertEqual(result.program?.steps.count, 6)
    }

    func testPhase5CameraInCompiles() {
        // CameraIn → Mirror → Output
        let camera = CustomPatchNode(id: UUID(), kind: .cameraIn, title: "Camera", position: CustomPatchPoint(x: 0, y: 0))
        let mirror = CustomPatchNode(id: UUID(), kind: .mirror, title: "Mirror", position: CustomPatchPoint(x: 200, y: 0))
        let output = CustomPatchNode(id: UUID(), kind: .output, title: "Out", position: CustomPatchPoint(x: 400, y: 0))

        let connections = [
            CustomPatchConnection(fromNodeID: camera.id, fromPort: "field", toNodeID: mirror.id, toPort: "field"),
            CustomPatchConnection(fromNodeID: mirror.id, fromPort: "field", toNodeID: output.id, toPort: "color"),
        ]

        let patch = CustomPatch(name: "Camera Mirror", nodes: [camera, mirror, output], connections: connections)
        let result = PatchCompiler.compile(patch)
        XCTAssertTrue(result.isSuccess, "Errors: \(result.errors)")
        XCTAssertEqual(result.program?.steps.count, 3)
    }

    func testPhase5AllNewNodeKindsRoundTripCodable() throws {
        let phase5Kinds: [CustomPatchNodeKind] = [.fractal, .voronoi, .feedback, .blur, .displace, .mirror, .tile, .cameraIn]
        for kind in phase5Kinds {
            let node = CustomPatchNode(kind: kind, title: kind.displayName, position: CustomPatchPoint(x: 100, y: 200))
            let data = try JSONEncoder().encode(node)
            let decoded = try JSONDecoder().decode(CustomPatchNode.self, from: data)
            XCTAssertEqual(decoded.kind, kind)
            XCTAssertEqual(decoded.parameters.count, kind.defaultParameters.count, "\(kind) parameter count mismatch")
            XCTAssertEqual(decoded.inputPorts, kind.inputPortDescriptors.map(\.name))
            XCTAssertEqual(decoded.outputPorts, kind.outputPortDescriptors.map(\.name))
        }
    }

    // MARK: - Phase 6 Tests

    func testPhase6FeedbackCycleCompilesSuccessfully() {
        // Feedback cycle: osc → blend ← feedback, blend → feedback (cycle)
        let osc = CustomPatchNode(id: UUID(), kind: .oscillator, title: "Osc", position: CustomPatchPoint(x: 0, y: 0))
        let feedback = CustomPatchNode(id: UUID(), kind: .feedback, title: "FB", position: CustomPatchPoint(x: 200, y: 100))
        let blend = CustomPatchNode(id: UUID(), kind: .blend, title: "Blend", position: CustomPatchPoint(x: 200, y: 0))
        let output = CustomPatchNode(id: UUID(), kind: .output, title: "Out", position: CustomPatchPoint(x: 400, y: 0))

        let connections = [
            CustomPatchConnection(fromNodeID: osc.id, fromPort: "field", toNodeID: blend.id, toPort: "a"),
            CustomPatchConnection(fromNodeID: feedback.id, fromPort: "field", toNodeID: blend.id, toPort: "b"),
            CustomPatchConnection(fromNodeID: blend.id, fromPort: "color", toNodeID: feedback.id, toPort: "field"),
            CustomPatchConnection(fromNodeID: blend.id, fromPort: "color", toNodeID: output.id, toPort: "color"),
        ]

        let patch = CustomPatch(name: "Feedback Cycle", nodes: [osc, feedback, blend, output], connections: connections)
        let result = PatchCompiler.compile(patch)
        XCTAssertTrue(result.isSuccess, "Feedback cycle should compile: \(result.errors)")
        XCTAssertEqual(result.program?.steps.count, 4)

        // Feedback should execute before blend (no in-degree from DAG perspective)
        let steps = result.program!.steps
        let fbIndex = steps.firstIndex(where: { $0.kind == .feedback })!
        let blendIndex = steps.firstIndex(where: { $0.kind == .blend })!
        XCTAssertLessThan(fbIndex, blendIndex, "Feedback must execute before blend")

        // Second-pass resolution: feedback's "field" input binding must reference
        // blend's output texture slot (not -1), so swapFeedbackTextures can read it.
        let fbStep = steps[fbIndex]
        let fieldInput = fbStep.inputs.first(where: { $0.portName == "field" })!
        XCTAssertTrue(fieldInput.isConnected, "Feedback field input must be resolved to blend output")
        let blendStep = steps[blendIndex]
        let blendOutputSlot = blendStep.outputs.first(where: { $0.portName == "color" })!.slot
        XCTAssertEqual(fieldInput.sourceSlot, blendOutputSlot, "Feedback field must point to blend color slot")
    }

    func testPhase6FactoryPresetsAllCompile() {
        let presets = CustomPatch.factoryPresets()
        XCTAssertEqual(presets.count, 3)
        for preset in presets {
            let result = PatchCompiler.compile(preset)
            XCTAssertTrue(result.isSuccess, "\(preset.name) failed: \(result.errors)")
        }
    }

    func testPhase6GroupsRoundTripCodable() throws {
        let nodeA = CustomPatchNode(id: UUID(), kind: .oscillator, title: "A", position: CustomPatchPoint(x: 0, y: 0))
        let nodeB = CustomPatchNode(id: UUID(), kind: .blend, title: "B", position: CustomPatchPoint(x: 100, y: 0))
        let group = CustomPatchGroup(name: "My Group", nodeIDs: [nodeA.id, nodeB.id], colorIndex: 2)
        let patch = CustomPatch(name: "Grouped", nodes: [nodeA, nodeB], connections: [], groups: [group])

        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(CustomPatch.self, from: data)
        XCTAssertEqual(decoded.groups.count, 1)
        XCTAssertEqual(decoded.groups[0].name, "My Group")
        XCTAssertEqual(decoded.groups[0].nodeIDs, [nodeA.id, nodeB.id])
        XCTAssertEqual(decoded.groups[0].colorIndex, 2)
    }

    func testPhase6GroupsMissingInLegacyJSONDefaultsToEmpty() throws {
        let json = """
        {
          "id": "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
          "name": "Legacy",
          "nodes": [],
          "connections": [],
          "viewport": { "zoom": 1, "offsetX": 0, "offsetY": 0 },
          "createdAt": "2026-01-01T00:00:00Z",
          "updatedAt": "2026-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CustomPatch.self, from: json)
        XCTAssertEqual(decoded.groups, [])
        XCTAssertEqual(decoded.name, "Legacy")
    }

    func testPhase6ClipboardRoundTripsCodable() throws {
        let node = CustomPatchNode(id: UUID(), kind: .fractal, title: "Fractal", position: CustomPatchPoint(x: 50, y: 60))
        let clipboard = CustomPatchClipboard(nodes: [node], connections: [])
        let data = try JSONEncoder().encode(clipboard)
        let decoded = try JSONDecoder().decode(CustomPatchClipboard.self, from: data)
        XCTAssertEqual(decoded.nodes.count, 1)
        XCTAssertEqual(decoded.nodes[0].kind, .fractal)
    }
}
