//
//  AppRoot.swift
//  Chroma
//
//  Created by Sebastian Suarez-Solis on 10/17/25.
//
// Stage Devices — Visuals App: App Target (Rev 0)
// Wire the existing SwiftUI kits (Perform + Studio) into a runnable app shell.
// Requires: "SwiftUI Kit (Rev A)" and "SwiftUI Kit (Studio Rev B)" files in target.
// Deployment: iOS 17+

import SwiftUI
import Combine

// MARK: - App Entry
@main
struct AURAApp: App {
    @StateObject private var appState = AppState()
    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environmentObject(appState)
        }
    }
}


final class AppState: ObservableObject {
    @Published var linkHealth: LinkHealth = .ok
    @Published var fps: Int = 60
    @Published var battery: Int = 92

    // Audio + transport
    @Published var audioFeatures: AudioFeatures = .empty
    @Published var transport: TransportState = TransportState()

    let audioEngine = SystemAudioEngine()
    private var bag = Set<AnyCancellable>()

    init() {
        audioEngine.featuresPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] f in
                self?.audioFeatures = f
                self?.transport.update(with: f)
            }
            .store(in: &bag)
        audioEngine.start()
    }
}



// MARK: - Root Shell (Tabs)
struct AppRoot: View {
    @EnvironmentObject private var app: AppState
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            PerformScreen()
                .tabItem { Label("Perform", systemImage: "sparkles") }
                .tag(0)
            StudioScreen()
                .tabItem { Label("Studio", systemImage: "slider.horizontal.3") }
                .tag(1)
            LibraryScreen()
                .tabItem { Label("Library", systemImage: "square.stack.3d.up") }
                .tag(2)
            CuesScreen()
                .tabItem { Label("Cues", systemImage: "timeline.selection") }
                .tag(3)
            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(4)
        }
    }
}

// MARK: - Perform
// MARK: - Perform (glassy, compact, HIG-clean)
struct PerformScreen: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.horizontalSizeClass) private var hSize

    // UI state
    @State private var sensitivity: Double = 0.55
    @State private var exposure: Double = 1.0
    @State private var strobeGuard: Bool = true
    @State private var selectedPresetIndex: Int = 0

    #if canImport(Combine)
    @StateObject private var renderParams = RenderParams()
    #endif

    private let presets: [Preset] = [
        .init(name: "Beat Pulse",      color: .pink),
        .init(name: "Spectrum Waves",  color: .blue),
        .init(name: "Particle Burst",  color: .purple),
        .init(name: "Geo Kaleido",     color: .teal),
        .init(name: "CRT Glitch",      color: .indigo)
    ]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Perform")
                .navigationBarTitleDisplayMode(.large)
        }
        .safeAreaInset(edge: .bottom) { bottomActionBar }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            #if canImport(Combine)
            renderParams.exposure = Float(exposure)
            renderParams.strobeGuard = strobeGuard
            #endif
        }
        .onChange(of: exposure) { newValue in
            #if canImport(Combine)
            renderParams.exposure = Float(newValue)
            #endif
        }
        .onChange(of: strobeGuard) { newValue in
            #if canImport(Combine)
            renderParams.strobeGuard = newValue
            #endif
        }
    }

    @ViewBuilder
    private var content: some View {
        // Responsive: single column on compact; split on regular width
        if hSize == .regular {
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        previewCard
                        statusRow
                    }
                    .frame(maxWidth: 560)
                    VStack(spacing: 16) {
                        sceneStrip
                        controlsCard
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 92)
            }
        } else {
            ScrollView(.vertical) {
                VStack(spacing: 16) {
                    previewCard
                    statusRow
                    sceneStrip
                    controlsCard
                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 92)
            }
        }
    }

    // MARK: Sections

    private var previewCard: some View {
        GlassPreviewCard(title: "Program Preview") {
            Group {
                #if canImport(MetalKit)
                MetalView(params: renderParams)
                #else
                DemoVisualCanvas()
                #endif
            }
            .accessibilityHidden(true)
        }
        .frame(maxWidth: previewMaxWidth)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            StatusChip(systemName: "dot.radiowaves.left.and.right",
                       label: app.linkHealth == .ok ? "Link OK" : "Link…",
                       tint: app.linkHealth == .ok ? .green : .orange)
            StatusChip(systemName: "speedometer", label: "\(app.fps) FPS", tint: .blue)
            StatusChip(systemName: "battery.100", label: "\(app.battery)%", tint: .yellow)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    private var sceneStrip: some View {
        PresetStrip(presets: presets, selectedIndex: $selectedPresetIndex) {
            // TODO: switch live scene here
        }
    }

    private var controlsCard: some View {
        ControlsCard {
            VStack(spacing: 12) {
                LabeledSliderSimple(label: "Exposure",
                                    value: $exposure,
                                    range: 0.25...2.0)
                LabeledSliderSimple(label: "Sensitivity",
                                    value: $sensitivity,
                                    range: 0...1.0)
                Toggle("Strobe Guard", isOn: $strobeGuard)
            }
        }
    }

    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            Button {
                NotificationCenter.default.post(name: .tapTempo, object: nil)
            } label: { Label("Tap Tempo", systemImage: "metronome.fill") }
            .buttonStyle(.borderedProminent)

            Button(role: .destructive) {
                #if canImport(Combine)
                let current = exposure
                // "Panic": quick blackout, auto-restore
                renderParams.exposure = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    renderParams.exposure = Float(current)
                }
                #endif
            } label: { Label("Panic", systemImage: "bolt.slash.fill") }
            .buttonStyle(.bordered)

            Spacer()

            Button { /* lock UI, optional */ } label: {
                Label("Lock", systemImage: "lock.fill")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    // MARK: Layout helpers
    private var previewMaxWidth: CGFloat {
        if hSize == .regular { return 560 }
        // Compact → scale by device
        let w = UIScreen.main.bounds.width
        if w <= 340 { return 320 }     // SE
        if w <= 390 { return 360 }     // iPhone 14/15
        return 420                     // Plus/Max in portrait
    }
}

// MARK: - Glass preview container
struct GlassPreviewCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1))
                content()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .aspectRatio(16/9, contentMode: .fit)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - Status chip
struct StatusChip: View {
    let systemName: String
    let label: String
    let tint: Color
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemName).imageScale(.small)
            Text(label).font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .foregroundStyle(tint)
        .contentShape(Rectangle()) // bigger hit area horizontally
    }
}

// MARK: - Preset strip
struct PresetStrip: View {
    let presets: [Preset]
    @Binding var selectedIndex: Int
    var onSelect: (() -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(presets.enumerated()), id: \.0) { i, p in
                    Button {
                        selectedIndex = i
                        onSelect?()
                    } label: {
                        HStack(spacing: 8) {
                            Circle().fill(p.color.gradient).frame(width: 22, height: 22)
                            Text(p.name).font(.footnote.weight(.semibold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                        .overlay(
                            Capsule().stroke(
                                i == selectedIndex ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.12),
                                lineWidth: i == selectedIndex ? 2 : 1
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Duplicate") { /* TODO */ }
                        Button("Rename") { /* TODO */ }
                        Button("Fade-in: 2.0s") { /* TODO */ }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - Controls card + simple slider
struct ControlsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Controls").font(.headline)
            content()
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

struct LabeledSliderSimple: View {
    let label: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .accessibilityLabel(Text(label))
        }
    }
}




// MARK: - Studio
struct StudioScreen: View {
    @State private var mode: Int = 0
    @StateObject private var graph = GraphModel()
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    Text("Quick Map").tag(0)
                    Text("Node Graph").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if mode == 0 {
                    QuickMapView().transition(.opacity)
                } else {
                    NodeGraphWorkbench(graph: graph)
                        .transition(.opacity)
                }
            }
            .navigationTitle("Studio")
        }
    }
}

// Bridge that shares one GraphModel between graph canvas and inspector
struct NodeGraphWorkbench: View {
    @ObservedObject var graph: GraphModel
    var body: some View {
        HStack(spacing: 0) {
            NodeGraphViewShared(graph: graph)
                .frame(minWidth: 400)
            Divider()
            InspectorPane(graph: graph)
                .frame(width: 300)
        }
    }
}

// A shared‑model version of NodeGraphView (non‑conflicting name)
struct NodeGraphViewShared: View {
    @ObservedObject var graph: GraphModel
    @State private var pendingConnection: (fromNode: UUID, fromPort: UUID, current: CGPoint)? = nil
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    var body: some View {
        ZStack {
            GraphBackdrop()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(panGesture.simultaneously(with: zoomGesture))
                .onTapGesture { graph.selectedNodeID = nil }

            ForEach(graph.nodes) { node in
                NodeCard(node: node,
                         isSelected: node.id == graph.selectedNodeID,
                         onDrag: { delta in move(node: node.id, by: delta) },
                         onStartWire: { port in pendingConnection = (node.id, port.id, .zero) },
                         onEndWireAt: { targetNode, targetPort in
                            if let from = pendingConnection { finalizeWire(from: from, toNode: targetNode.id, toPort: targetPort.id) }
                            pendingConnection = nil
                         },
                         onTap: { graph.selectedNodeID = node.id }
                )
                .position(screenPoint(for: node.position))
            }

            ConnectionsLayer(nodes: graph.nodes, connections: graph.connections, scale: scale, offset: offset)

            if let pending = pendingConnection, let fromNode = graph.node(by: pending.fromNode) {
                RubberbandWire(from: screenPoint(for: fromNode.position), to: pending.current)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .background(Color.black.opacity(0.6))
        .onAppear { seedDemoIfNeeded() }
        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
            if pendingConnection != nil { pendingConnection?.current = g.location }
        })
    }

    private func screenPoint(for p: CGPoint) -> CGPoint { CGPoint(x: p.x * scale + offset.width, y: p.y * scale + offset.height) }
    private var panGesture: some Gesture { DragGesture().onChanged { g in offset = CGSize(width: offset.width + g.translation.width, height: offset.height + g.translation.height) } }
    private var zoomGesture: some Gesture { MagnificationGesture().onChanged { m in scale = (scale * m).clamped(to: 0.5...2.0) } }
    private func move(node id: UUID, by delta: CGSize) { if let idx = graph.nodes.firstIndex(where: { $0.id == id }) { graph.nodes[idx].position = CGPoint(x: graph.nodes[idx].position.x + delta.width, y: graph.nodes[idx].position.y + delta.height) } }
    private func finalizeWire(from: (fromNode: UUID, fromPort: UUID, current: CGPoint), toNode: UUID, toPort: UUID) { graph.connections.append(.init(fromNode: from.fromNode, fromPort: from.fromPort, toNode: toNode, toPort: toPort)) }
    private func seedDemoIfNeeded() {
        guard graph.nodes.isEmpty else { return }
        let src = GraphNode(kind: .source, title: "Audio Features", position: CGPoint(x: 160, y: 160), inputs: [], outputs: [GraphPort(name: "Beat", portKind: .output), GraphPort(name: "RMS", portKind: .output)])
        let op = GraphNode(kind: .operatorNode, title: "Map+Lag", position: CGPoint(x: 420, y: 220), inputs: [GraphPort(name: "In", portKind: .input)], outputs: [GraphPort(name: "Out", portKind: .output)])
        let gen = GraphNode(kind: .generator, title: "Shader", position: CGPoint(x: 700, y: 200), inputs: [GraphPort(name: "Gain", portKind: .input), GraphPort(name: "Hue", portKind: .input)], outputs: [GraphPort(name: "Image", portKind: .output)])
        let out = GraphNode(kind: .output, title: "Output", position: CGPoint(x: 980, y: 200), inputs: [GraphPort(name: "Image", portKind: .input)], outputs: [])
        graph.nodes = [src, op, gen, out]
    }
}

// MARK: - Library
struct LibraryScreen: View {
    @State private var search = ""
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section("My Scenes") {
                        ForEach(0..<6, id: \.self) { i in
                            HStack { RoundedRectangle(cornerRadius: 8).fill(.quaternary).frame(width: 56, height: 36); Text("Scene \(i+1)") }
                        }
                    }
                    Section("Packs") {
                        ForEach(["Starter Pack","Glitch Pack","Geo Pack"], id: \.self) { name in Text(name) }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Library")
            .searchable(text: $search)
        }
    }
}

// MARK: - Cues (SyncTimer Link placeholder)
struct CuesScreen: View {
    @EnvironmentObject private var app: AppState
    @State private var connected = true
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                StatusPill(systemImage: "dot.radiowaves.left.and.right", label: connected ? "SyncTimer Linked" : "Not Linked", tint: connected ? .green : .red)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Timeline").font(.headline)
                    HStack { Text("Marker:").foregroundStyle(.secondary); Text("Verse A → Chorus") }
                    HStack { Text("Next Cue:").foregroundStyle(.secondary); Text("Load ‘Spectrum Waves’ • +2.0s fade") }
                    HStack { Text("Latency:").foregroundStyle(.secondary); Text("±8 ms") }
                }
                .padding()
                .frame(maxWidth: 520)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
                Spacer()
            }
            .padding()
            .navigationTitle("Cues")
        }
    }
}

// MARK: - Settings
struct SettingsScreen: View {
    @EnvironmentObject private var app: AppState
    @State private var hdr = true
    @State private var fpsCap = 60.0
    @State private var strobeGuard = true
    @State private var ndiOn = true
    var body: some View {
        NavigationStack {
            Form {
                Section("Output") {
                    Toggle("HDR", isOn: $hdr)
                    HStack { Text("FPS Cap"); Spacer(); Text("\(Int(fpsCap))") }
                    Slider(value: $fpsCap, in: 30...120, step: 30)
                    Toggle("NDI Stream", isOn: $ndiOn)
                }
                Section("Audio") {
                    Picker("Latency Mode", selection: .constant(1)) {
                        Text("Ultra‑low").tag(0)
                        Text("Balanced").tag(1)
                        Text("Eco").tag(2)
                    }
                }
                Section("Safety") {
                    Toggle("Strobe Guard", isOn: $strobeGuard)
                    Stepper("Max Brightness 85%", value: .constant(85), in: 10...100)
                }
                Section("About") {
                    HStack { Text("Version"); Spacer(); Text("0.1 (Rev 0)").foregroundStyle(.secondary) }
                    Link("Discord / Support", destination: URL(string: "https://example.com")!)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Previews
#Preview("App Root") { AppRoot().environmentObject(AppState()) }
