//
//  QuickMapView.swift
//  Chroma
//
//  Created by Sebastian Suarez-Solis on 10/17/25.
//
// Stage Devices — Visuals App: SwiftUI Kit (Studio Rev C)
// Fixes: Combine import, simplified LabeledSlider (no generics), keeps geometry helpers local.
// Second pass: Studio views — Quick Map + Node Graph + Inspector + Curve Editor.
// Assumes SDTokens, GlassChip, etc. from Rev A are available in the target.

import SwiftUI
import Combine

// MARK: - Shared Models (Studio)
// Source domains
enum StudioSourceDomain: String, CaseIterable, Identifiable { case audio, time, gesture, midi, osc; var id: String { rawValue } }

// Audio feature types
enum AudioFeature: String, CaseIterable, Identifiable {
    case onset, beat, rms, spectralCentroid, lowBand, midBand, highBand
    var id: String { rawValue }
    var display: String {
        switch self {
        case .onset: return "Onset"
        case .beat: return "Beat"
        case .rms: return "RMS"
        case .spectralCentroid: return "Centroid"
        case .lowBand: return "Low"
        case .midBand: return "Mid"
        case .highBand: return "High"
        }
    }
    var symbol: String {
        switch self { case .onset: return "burst.fill"; case .beat: return "metronome.fill"; case .rms: return "waveform"; case .spectralCentroid: return "chart.line.uptrend.xyaxis"; case .lowBand: return "speaker.wave.2.fill"; case .midBand: return "speaker.wave.2"; case .highBand: return "speaker.wave.1" }
    }
}

// Studio targets (generator/post params)
struct StudioTargetParam: Identifiable, Hashable {
    enum ParamType { case float, int, bool, color }
    let id = UUID()
    var nodeID: UUID
    var name: String
    var type: ParamType
    var range: ClosedRange<Double> = 0...1
}

// Mapping model
struct MappingLink: Identifiable {
    let id = UUID()
    var source: MappingSource
    var target: StudioTargetParam
    var transform: CurveTransform = .linear
    var smoothing: Double = 0.0 // seconds
    var minOut: Double = 0
    var maxOut: Double = 1
    var isBypassed: Bool = false
    var isGate: Bool = false
}

enum MappingSource: Hashable {
    case audio(AudioFeature)
    case timeBarsBeats
    case gestureTiltX, gestureTiltY
    case midiCC(Int)
    case oscAddress(String)

    var label: String {
        switch self {
        case .audio(let f): return f.display
        case .timeBarsBeats: return "Bars:Beats"
        case .gestureTiltX: return "Tilt X"
        case .gestureTiltY: return "Tilt Y"
        case .midiCC(let n): return "MIDI CC \(n)"
        case .oscAddress(let a): return a
        }
    }
    var icon: String {
        switch self {
        case .audio(let f): return f.symbol
        case .timeBarsBeats: return "clock";
        case .gestureTiltX, .gestureTiltY: return "gyroscope"
        case .midiCC: return "pianokeys"
        case .oscAddress: return "dot.radiowaves.left.and.right"
        }
    }
}

// Curve / Transform
enum CurveTransform: String, CaseIterable, Identifiable { case linear, easeIn, easeOut, easeInOut, custom; var id: String { rawValue } }

// MARK: - Quick Map
struct QuickMapView: View {
    @State private var mappings: [MappingLink] = []
    // demo target params
    @State private var targets: [StudioTargetParam] = [
        .init(nodeID: UUID(), name: "Shader Gain", type: .float, range: 0...2),
        .init(nodeID: UUID(), name: "Hue Shift", type: .float, range: 0...1),
        .init(nodeID: UUID(), name: "Particle Rate", type: .float, range: 0...1),
        .init(nodeID: UUID(), name: "Bloom", type: .float, range: 0...1)
    ]

    @State private var showNewMapSheet = false
    @State private var editorTarget: MappingLink? = nil

    var body: some View {
        VStack(spacing: SDTokens.Spacing.l) {
            HStack {
                Text("Quick Map").font(.title2.weight(.bold))
                Spacer()
                Button { showNewMapSheet = true } label: { Label("New Mapping", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, SDTokens.Spacing.l)

            // Mappings list
            if mappings.isEmpty {
                EmptyPrompt(title: "No mappings yet", subtitle: "Map audio, time, MIDI or gestures to visual parameters.") {
                    showNewMapSheet = true
                }
                .padding()
            } else {
                List {
                    ForEach($mappings) { $map in
                        MappingRow(link: $map) {
                            editorTarget = map
                        }
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { idx in mappings.remove(atOffsets: idx) }
                }
                .listStyle(.insetGrouped)
            }
        }
        .sheet(isPresented: $showNewMapSheet) { NewMappingSheet(targets: targets) { newMap in
            mappings.append(newMap)
        } }
        .sheet(item: $editorTarget) { link in
            CurveEditorSheet(link: link) { updated in
                if let idx = mappings.firstIndex(where: { $0.id == updated.id }) { mappings[idx] = updated }
            }
        }
    }
}

// MARK: - Components (Quick Map)
struct EmptyPrompt: View {
    let title: String
    let subtitle: String
    var action: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "link.badge.plus").font(.largeTitle)
            Text(title).font(.headline)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            Button("Create a mapping", action: action).buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: 480)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12)))
    }
}

struct MappingRow: View {
    @Binding var link: MappingLink
    var onEditCurve: () -> Void

    var body: some View {
        HStack(spacing: SDTokens.Spacing.m) {
            // Source chip
            HStack(spacing: SDTokens.Spacing.s) {
                Image(systemName: link.source.icon).imageScale(.medium)
                Text(link.source.label).font(.footnote.weight(.semibold))
            }
            .sdGlassChip()

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            // Target chip
            HStack(spacing: SDTokens.Spacing.s) {
                Image(systemName: "slider.horizontal.3").imageScale(.medium)
                Text(link.target.name).font(.footnote.weight(.semibold))
            }
            .sdGlassChip()

            Spacer(minLength: 0)

            // Small curve preview
            CurvePreview(transform: link.transform)
                .frame(width: 72, height: 28)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.12)))
                .onTapGesture { onEditCurve() }
            Toggle(isOn: $link.isBypassed) { Text("Bypass").font(.caption) }
                .toggleStyle(.switch)
                .frame(width: 120)
        }
        .padding(.vertical, 6)
    }
}

struct CurvePreview: View {
    var transform: CurveTransform
    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let path = Path.curvePath(for: transform, in: CGRect(origin: .zero, size: size))
                ctx.stroke(path, with: .color(.accentColor), lineWidth: 2)
                // Grid
                let grid = Path { p in
                    p.addRect(CGRect(x: size.width*0.5, y: 0, width: 0.5, height: size.height))
                    p.addRect(CGRect(x: 0, y: size.height*0.5, width: size.width, height: 0.5))
                }
                ctx.stroke(grid, with: .color(.secondary.opacity(0.3)))
            }
        }
    }
}

extension Path {
    static func curvePath(for t: CurveTransform, in rect: CGRect) -> Path {
        func f(_ x: CGFloat) -> CGFloat {
            switch t {
            case .linear: return x
            case .easeIn: return x*x
            case .easeOut: return 1 - pow(1-x, 2)
            case .easeInOut: return x < 0.5 ? 2*x*x : 1 - pow(-2*x + 2, 2)/2
            case .custom: return x // custom handled in editor; preview as linear
            }
        }
        var p = Path()
        let steps = 64
        for i in 0...steps {
            let x = CGFloat(i) / CGFloat(steps)
            let y = f(x)
            let px = rect.minX + x * rect.width
            let py = rect.maxY - y * rect.height
            if i == 0 { p.move(to: CGPoint(x: px, y: py)) } else { p.addLine(to: CGPoint(x: px, y: py)) }
        }
        return p
    }
}

// New Mapping sheet
struct NewMappingSheet: View {
    let targets: [StudioTargetParam]
    var onCreate: (MappingLink) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSource: MappingSource = .audio(.beat)
    @State private var selectedTarget: StudioTargetParam?
    @State private var transform: CurveTransform = .linear

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    Picker("Type", selection: $selectedSource) {
                        ForEach(defaultSources, id: \.self) { src in
                            HStack { Image(systemName: src.icon); Text(src.label) }.tag(src)
                        }
                    }
                }
                Section("Target") {
                    Picker("Parameter", selection: Binding(get: { selectedTarget }, set: { selectedTarget = $0 })) {
                        ForEach(targets) { t in Text(t.name).tag(Optional(t)) }
                    }
                }
                Section("Transform") {
                    Picker("Curve", selection: $transform) {
                        ForEach(CurveTransform.allCases) { t in Text(t.rawValue.capitalized).tag(t) }
                    }
                }
            }
            .navigationTitle("New Mapping")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let target = selectedTarget {
                            onCreate(MappingLink(source: selectedSource, target: target, transform: transform))
                            dismiss()
                        }
                    }.disabled(selectedTarget == nil)
                }
            }
        }
    }
    private var defaultSources: [MappingSource] {
        [.audio(.beat), .audio(.rms), .audio(.spectralCentroid), .timeBarsBeats, .gestureTiltX, .gestureTiltY, .midiCC(1), .oscAddress("/your/param")]
    }
}

// Curve Editor Sheet
struct CurveEditorSheet: View {
    @State var link: MappingLink
    var onDone: (MappingLink) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var customPoints: [CGPoint] = [CGPoint(x: 0.2, y: 0.1), CGPoint(x: 0.8, y: 0.9)] // for custom bezier

    var body: some View {
        NavigationStack {
            VStack(spacing: SDTokens.Spacing.l) {
                CurvePicker(selected: $link.transform)
                CurveEditorView(transform: $link.transform, customPoints: $customPoints)
                    .frame(height: 240)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
                HStack {
                    LabeledSlider(label: "Smooth", value: $link.smoothing, range: 0...0.5, format: .number.precision(.fractionLength(2)))
                    LabeledSlider(label: "Min", value: $link.minOut, range: 0...1)
                    LabeledSlider(label: "Max", value: $link.maxOut, range: 0...1)
                }
                .padding(.horizontal)
                Toggle("Gate (trigger only)", isOn: $link.isGate)
                    .padding(.horizontal)
                Spacer()
            }
            .padding()
            .navigationTitle("Mapping Curve")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { onDone(link); dismiss() } }
            }
        }
    }
}

struct CurvePicker: View {
    @Binding var selected: CurveTransform
    var body: some View {
        HStack(spacing: SDTokens.Spacing.m) {
            ForEach(CurveTransform.allCases) { t in
                Button {
                    withAnimation(.snappy) { selected = t }
                } label: {
                    VStack(spacing: SDTokens.Spacing.s) {
                        CurvePreview(transform: t).frame(width: 80, height: 32)
                        Text(t.rawValue.capitalized).font(.caption)
                    }
                    .padding(SDTokens.Spacing.s)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected == t ? Color.accentColor.opacity(0.6) : .white.opacity(0.12), lineWidth: selected == t ? 2 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// Simplified (non-generic) LabeledSlider
struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var format: FloatingPointFormatStyle<Double> = .number
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(label): \(value, format: format)").font(.caption).foregroundStyle(.secondary)
            Slider(value: $value, in: range)
        }
        .frame(minWidth: 120)
    }
}

struct CurveEditorView: View {
    @Binding var transform: CurveTransform
    @Binding var customPoints: [CGPoint]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Grid
                GridBackdrop()
                // Curve
                Path.curvePath(for: transform, in: geo.frame(in: .local).insetBy(dx: 12, dy: 12))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                if transform == .custom {
                    // Custom Bezier with draggable points
                    CustomCurve(points: customPoints)
                        .stroke(Color.accentColor, lineWidth: 2)
                    ForEach(customPoints.indices, id: \.self) { i in
                        DraggableHandle(position: $customPoints[i], bounds: geo.frame(in: .local))
                    }
                }
            }
        }
    }
}

struct GridBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let grid = Path { p in
                    let step: CGFloat = 24
                    var x: CGFloat = 0
                    while x <= size.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); x += step }
                    var y: CGFloat = 0
                    while y <= size.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); y += step }
                }
                ctx.stroke(grid, with: .color(.white.opacity(0.08)))
                ctx.stroke(Path(CGRect(x: size.width/2, y: 0, width: 1, height: size.height)), with: .color(.white.opacity(0.18)))
                ctx.stroke(Path(CGRect(x: 0, y: size.height/2, width: size.width, height: 1)), with: .color(.white.opacity(0.18)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct CustomCurve: Shape {
    var points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.minX, y: rect.maxY)
        let end = CGPoint(x: rect.maxX, y: rect.minY)
        let p1 = CGPoint(x: rect.minX + points[0].x * rect.width, y: rect.maxY - points[0].y * rect.height)
        let p2 = CGPoint(x: rect.minX + points[1].x * rect.width, y: rect.maxY - points[1].y * rect.height)
        path.move(to: start)
        path.addCurve(to: end, control1: p1, control2: p2)
        return path
    }
}

struct DraggableHandle: View {
    @Binding var position: CGPoint // normalized 0..1 in both axes
    var bounds: CGRect
    var body: some View {
        let p = CGPoint(x: bounds.minX + position.x * bounds.width, y: bounds.maxY - position.y * bounds.height)
        Circle()
            .fill(.background)
            .frame(width: 18, height: 18)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .position(p)
            .gesture(DragGesture().onChanged { g in
                let nx = ((g.location.x - bounds.minX) / bounds.width).clamped(to: 0...1)
                let ny = (1 - (g.location.y - bounds.minY) / bounds.height).clamped(to: 0...1)
                position = CGPoint(x: nx, y: ny)
            })
    }
}

// MARK: - Node Graph
struct GraphNode: Identifiable, Hashable {
    enum Kind: String { case source, operatorNode, generator, compositor, output }
    let id: UUID
    var kind: Kind
    var title: String
    var position: CGPoint // in canvas coordinates
    var inputs: [GraphPort]
    var outputs: [GraphPort]
    var isBypassed: Bool = false

    init(id: UUID = UUID(), kind: Kind, title: String, position: CGPoint, inputs: [GraphPort] = [], outputs: [GraphPort] = []) {
        self.id = id; self.kind = kind; self.title = title; self.position = position; self.inputs = inputs; self.outputs = outputs
    }
}

struct GraphPort: Identifiable, Hashable { enum PortKind { case input, output }
    let id: UUID = UUID(); let name: String; let portKind: PortKind }

struct GraphConnection: Identifiable, Hashable { let id = UUID(); var fromNode: UUID; var fromPort: UUID; var toNode: UUID; var toPort: UUID }

final class GraphModel: ObservableObject {
    @Published var nodes: [GraphNode] = []
    @Published var connections: [GraphConnection] = []
    @Published var selectedNodeID: UUID? = nil
    @Published var scale: CGFloat = 1.0
    @Published var offset: CGSize = .zero

    func node(by id: UUID) -> GraphNode? { nodes.first { $0.id == id } }
}

struct NodeGraphView: View {
    @StateObject var model: GraphModel = GraphModel()
    @State private var pendingConnection: (fromNode: UUID, fromPort: UUID, current: CGPoint)? = nil

    var body: some View {
        ZStack {
            GraphBackdrop()
                .scaleEffect(model.scale)
                .offset(model.offset)
                .gesture(panGesture.simultaneously(with: zoomGesture))
                .onTapGesture { model.selectedNodeID = nil }

            ForEach(model.nodes) { node in
                NodeCard(node: node,
                         isSelected: node.id == model.selectedNodeID,
                         onDrag: { delta in move(node: node.id, by: delta) },
                         onStartWire: { port in
                            pendingConnection = (fromNode: node.id, fromPort: port.id, current: .zero)
                         },
                         onEndWireAt: { targetNode, targetPort in
                            if let from = pendingConnection { finalizeWire(from: from, toNode: targetNode.id, toPort: targetPort.id) }
                            pendingConnection = nil
                         },
                         onTap: { model.selectedNodeID = node.id }
                )
                .position(node.position.applying(CGAffineTransform(scaleX: model.scale, y: model.scale)).applying(CGAffineTransform(translationX: model.offset.width, y: model.offset.height)))
            }

            // Existing connections
            ConnectionsLayer(nodes: model.nodes, connections: model.connections, scale: model.scale, offset: model.offset)

            // Rubberband wire
            if let pending = pendingConnection, let fromNode = model.node(by: pending.fromNode) {
                RubberbandWire(from: screenPoint(for: fromNode.position), to: pending.current)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .background(Color.black.opacity(0.6))
        .onAppear { seedDemo() }
        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
            if pendingConnection != nil { pendingConnection?.current = g.location }
        })
    }

    private func screenPoint(for p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * model.scale + model.offset.width, y: p.y * model.scale + model.offset.height)
    }

    private var panGesture: some Gesture {
        DragGesture().onChanged { g in model.offset = CGSize(width: model.offset.width + g.translation.width, height: model.offset.height + g.translation.height) }
    }
    private var zoomGesture: some Gesture {
        MagnificationGesture().onChanged { m in model.scale = (model.scale * m).clamped(to: 0.5...2.0) }
    }

    private func move(node id: UUID, by delta: CGSize) { if let idx = model.nodes.firstIndex(where: { $0.id == id }) { model.nodes[idx].position = CGPoint(x: model.nodes[idx].position.x + delta.width, y: model.nodes[idx].position.y + delta.height) } }
    private func finalizeWire(from: (fromNode: UUID, fromPort: UUID, current: CGPoint), toNode: UUID, toPort: UUID) {
        model.connections.append(.init(fromNode: from.fromNode, fromPort: from.fromPort, toNode: toNode, toPort: toPort))
    }

    private func seedDemo() {
        if !model.nodes.isEmpty { return }
        let src = GraphNode(kind: .source, title: "Audio Features", position: CGPoint(x: 160, y: 160), inputs: [], outputs: [GraphPort(name: "Beat", portKind: .output), GraphPort(name: "RMS", portKind: .output)])
        let op = GraphNode(kind: .operatorNode, title: "Map+Lag", position: CGPoint(x: 420, y: 220), inputs: [GraphPort(name: "In", portKind: .input)], outputs: [GraphPort(name: "Out", portKind: .output)])
        let gen = GraphNode(kind: .generator, title: "Shader", position: CGPoint(x: 700, y: 200), inputs: [GraphPort(name: "Gain", portKind: .input), GraphPort(name: "Hue", portKind: .input)], outputs: [GraphPort(name: "Image", portKind: .output)])
        let out = GraphNode(kind: .output, title: "Output", position: CGPoint(x: 980, y: 200), inputs: [GraphPort(name: "Image", portKind: .input)], outputs: [])
        model.nodes = [src, op, gen, out]
        model.connections = []
    }
}

struct GraphBackdrop: View { var body: some View { GridBackdrop().opacity(0.9) } }

struct NodeCard: View {
    var node: GraphNode
    var isSelected: Bool
    var onDrag: (CGSize) -> Void
    var onStartWire: (GraphPort) -> Void
    var onEndWireAt: (GraphNode, GraphPort) -> Void
    var onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(node.title).font(.footnote.weight(.semibold))
                Spacer()
                if node.isBypassed { Text("Byp").font(.caption2).padding(4).background(.ultraThinMaterial, in: Capsule()) }
            }
            .padding(.bottom, 2)
            HStack(alignment: .top, spacing: 12) {
                // Inputs
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(node.inputs) { port in PortDot(label: port.name, kind: .input) }
                }
                Spacer(minLength: 0)
                // Outputs
                VStack(alignment: .trailing, spacing: 8) {
                    ForEach(node.outputs) { port in PortDot(label: port.name, kind: .output) }
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(isSelected ? Color.accentColor.opacity(0.6) : .white.opacity(0.12), lineWidth: isSelected ? 2 : 1))
        .gesture(DragGesture().onChanged { g in onDrag(g.translation) })
        .onTapGesture { onTap() }
        .overlay(alignment: .leading) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(node.inputs) { port in WireHandle(kind: .input) { onEndWireAt(node, port) } }
            }.padding(.leading, -14)
        }
        .overlay(alignment: .trailing) {
            VStack(alignment: .trailing, spacing: 8) {
                ForEach(node.outputs) { port in WireHandle(kind: .output) { onStartWire(port) } }
            }.padding(.trailing, -14)
        }
    }
}

struct PortDot: View { enum Kind { case input, output }
    let label: String; let kind: Kind
    var body: some View {
        HStack(spacing: 6) {
            if kind == .input { Circle().frame(width: 8, height: 8) }
            Text(label).font(.caption2)
            if kind == .output { Circle().frame(width: 8, height: 8) }
        }.foregroundStyle(.secondary)
    }
}

struct WireHandle: View {
    enum Kind { case input, output }
    let kind: Kind
    var action: () -> Void
    var body: some View {
        Circle()
            .fill(.background)
            .frame(width: 16, height: 16)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .onTapGesture { action() }
    }
}

struct ConnectionsLayer: View {
    let nodes: [GraphNode]
    let connections: [GraphConnection]
    let scale: CGFloat
    let offset: CGSize
    var body: some View {
        Canvas { ctx, size in
            for c in connections {
                if let fromNode = nodes.first(where: { $0.id == c.fromNode }), let toNode = nodes.first(where: { $0.id == c.toNode }) {
                    let p1 = CGPoint(x: fromNode.position.x * scale + offset.width, y: fromNode.position.y * scale + offset.height)
                    let p2 = CGPoint(x: toNode.position.x * scale + offset.width, y: toNode.position.y * scale + offset.height)
                    var path = Path()
                    path.move(to: p1)
                    let cp1 = CGPoint(x: p1.x + 80, y: p1.y)
                    let cp2 = CGPoint(x: p2.x - 80, y: p2.y)
                    path.addCurve(to: p2, control1: cp1, control2: cp2)
                    ctx.stroke(path, with: .color(.accentColor), lineWidth: 2)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct RubberbandWire: Shape {
    var from: CGPoint
    var to: CGPoint
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: from)
        let cp1 = CGPoint(x: from.x + 80, y: from.y)
        let cp2 = CGPoint(x: to.x - 80, y: to.y)
        p.addCurve(to: to, control1: cp1, control2: cp2)
        return p
    }
}

// MARK: - Inspector Pane (simplified)
struct InspectorPane: View {
    @ObservedObject var graph: GraphModel
    @State private var paramValue: Double = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: SDTokens.Spacing.m) {
            Text("Inspector").font(.headline)
            if let node = graph.nodes.first(where: { $0.id == graph.selectedNodeID }) {
                Text(node.title).font(.subheadline.weight(.semibold))
                Toggle("Bypass", isOn: Binding(get: { node.isBypassed }, set: { new in
                    if let idx = graph.nodes.firstIndex(where: { $0.id == node.id }) { graph.nodes[idx].isBypassed = new }
                }))
                Divider()
                if node.kind == .generator {
                    LabeledSlider(label: "Gain", value: $paramValue, range: 0...2)
                    LabeledSlider(label: "Hue", value: $paramValue, range: 0...1)
                } else if node.kind == .operatorNode {
                    LabeledSlider(label: "Lag (s)", value: $paramValue, range: 0...0.5)
                } else {
                    Text("No editable parameters").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Select a node to edit").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .frame(minWidth: 260)
        .background(.thinMaterial)
    }
}

// MARK: - Studio Shell (Tabs: Quick Map / Node Graph)
struct StudioView: View {
    @State private var tab: Int = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $tab) {
                Text("Quick Map").tag(0)
                Text("Node Graph").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if tab == 0 {
                QuickMapView().transition(.opacity)
            } else {
                HStack(spacing: 0) {
                    NodeGraphView()
                    Divider()
                    InspectorPane(graph: GraphModel()) // placeholder; wire shared model in app shell
                }
                .transition(.opacity)
            }
        }
    }
}

// MARK: - Demos
#Preview("Quick Map") { QuickMapView() }
#Preview("Node Graph") { NodeGraphView() }
#Preview("Studio Shell") { StudioView() }

// MARK: - Small geometry helpers
private extension CGPoint { static func + (lhs: CGPoint, rhs: CGSize) -> CGPoint { CGPoint(x: lhs.x + rhs.width, y: lhs.y + rhs.height) } }
private extension CGSize { static func + (lhs: CGSize, rhs: CGSize) -> CGSize { CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height) } }
