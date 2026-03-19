//
//  GlassChip.swift
//  Chroma
//
//  Created by Sebastian Suarez-Solis on 10/17/25.
//

import Foundation
// Stage Devices — Visuals App: SwiftUI Kit (Rev A)
// SwiftUI components for the new generative‑visuals app, on‑brand with SyncTimer/Tenney.
// iOS 17+ (Swift 5.9). Self‑contained demo scaffolding included at bottom.

import SwiftUI
import Combine

// MARK: - Design Tokens
struct SDTokens {
    struct Radii {
        static let chip: CGFloat = 14
        static let card: CGFloat = 20
        static let circle: CGFloat = 28
    }
    struct Spacing {
        static let xs: CGFloat = 6
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
    }
    struct Size {
        static let chipHeight: CGFloat = 40
        static let circleButton: CGFloat = 56
        static let icon: CGFloat = 20
    }
}

// MARK: - Utilities
extension View {
    func sdGlassChip() -> some View {
        self
            .padding(.horizontal, SDTokens.Spacing.m)
            .frame(height: SDTokens.Size.chipHeight)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: SDTokens.Radii.chip, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SDTokens.Radii.chip, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
    }
    func sdGlassCircle() -> some View {
        self
            .frame(width: SDTokens.Size.circleButton, height: SDTokens.Size.circleButton)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SDTokens.Radii.circle, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SDTokens.Radii.circle, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
    }
}

// MARK: - Status Pill
enum LinkHealth: String { case ok, degraded, offline }
struct StatusPill: View {
    let systemImage: String
    let label: String
    var tint: Color = .secondary
    var body: some View {
        HStack(spacing: SDTokens.Spacing.xs) {
            Image(systemName: systemImage).imageScale(.small)
            Text(label).font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, SDTokens.Spacing.m)
        .frame(height: SDTokens.Size.chipHeight)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12)))
        .foregroundStyle(tint)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - GlassChip
struct GlassChip: View {
    let title: String
    var systemImage: String? = nil
    var isOn: Bool = false
    var valueBadge: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: SDTokens.Spacing.s) {
                if let systemImage { Image(systemName: systemImage).imageScale(.medium) }
                Text(title).font(.footnote.weight(.semibold))
                if let valueBadge { Spacer(minLength: SDTokens.Spacing.s); Text(valueBadge).font(.footnote.monospacedDigit()) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .sdGlassChip()
        .overlay(
            RoundedRectangle(cornerRadius: SDTokens.Radii.chip, style: .continuous)
                .fill(Color.accentColor.opacity(isOn ? 0.10 : 0.0))
        )
        .accessibilityLabel(Text(title + (isOn ? ", on" : ", off")))
    }
}

// MARK: - GlassCircleButton
struct GlassCircleButton: View {
    let systemImage: String
    var onLongPress: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil

    // ⬇️ was @State; must be @GestureState for `.updating`
    @GestureState private var isPressed: Bool = false

    var body: some View {
        let tap = TapGesture().onEnded { onTap?() }
        let long = LongPressGesture(minimumDuration: 0.7)
            .updating($isPressed) { current, state, _ in
                state = current   // current is Bool for LongPressGesture
            }
            .onEnded { _ in onLongPress?() }

        return ZStack {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.primary, .secondary)
        }
        .sdGlassCircle()
        .overlay(
            RoundedRectangle(cornerRadius: SDTokens.Radii.circle, style: .continuous)
                .stroke(isPressed ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .gesture(long.simultaneously(with: tap))
        .accessibilityAddTraits(.isButton)
    }
}


// MARK: - Knob (Sensitivity)
struct Knob: View {
    @Binding var value: Double // 0…1
    var label: String = "Sensitivity"
    var body: some View {
        VStack(spacing: SDTokens.Spacing.s) {
            ZStack {
                Circle().stroke(.secondary.opacity(0.2), lineWidth: 10)
                Circle()
                    .trim(from: 0.0, to: value)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(Int(value * 100), format: .number)
                    .font(.footnote.monospacedDigit().weight(.semibold))
            }
            .frame(width: 72, height: 72)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                // Simple vertical drag mapping
                let delta = -Double(g.translation.height) / 200.0
                value = (value + delta).clamped(to: 0...1)
            })
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(SDTokens.Spacing.m)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SDTokens.Radii.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SDTokens.Radii.card, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text("\(Int(value*100)) percent"))
    }
}

// MARK: - Top Status Strip
struct StatusStrip: View {
    var sceneName: String
    var fps: Int
    var linkHealth: LinkHealth = .ok
    var ndiOn: Bool = false
    var battery: Int = 100
    var body: some View {
        HStack(spacing: SDTokens.Spacing.m) {
            Label(sceneName, systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            StatusPill(systemImage: "gauge.medium", label: "\(fps) FPS", tint: .primary)
            let linkTint: Color = (linkHealth == .ok ? .green : (linkHealth == .degraded ? .yellow : .red))
            StatusPill(systemImage: "dot.radiowaves.left.and.right", label: linkHealthLabel, tint: linkTint)
            if ndiOn { StatusPill(systemImage: "antenna.radiowaves.left.and.right", label: "NDI", tint: .blue) }
            StatusPill(systemImage: "battery.100", label: "\(battery)%", tint: .secondary)
        }
        .padding(.horizontal, SDTokens.Spacing.l)
        .padding(.vertical, SDTokens.Spacing.s)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
    private var linkHealthLabel: String {
        switch linkHealth { case .ok: return "Link OK"; case .degraded: return "Link ⚠︎"; case .offline: return "Link Off" }
    }
}

// MARK: - Preset Carousel (snap)
struct Preset: Identifiable, Equatable { let id = UUID(); let name: String; let color: Color }
struct PresetCarousel: View {
    let items: [Preset]
    @Binding var selected: Preset
    var onSelect: (Preset) -> Void = { _ in }
    @State private var scrollID: UUID = .init()
    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: SDTokens.Spacing.m) {
                ForEach(items) { p in
                    Button {
                        withAnimation(.snappy) { selected = p; onSelect(p) }
                    } label: {
                        VStack(spacing: SDTokens.Spacing.s) {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(p.color.gradient)
                                .frame(width: 96, height: 64)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(.white.opacity(0.18), lineWidth: 1)
                                )
                            Text(p.name).font(.caption.weight(.semibold)).lineLimit(1)
                        }
                        .padding(SDTokens.Spacing.s)
                        .frame(width: 110)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(selected == p ? Color.accentColor.opacity(0.6) : .white.opacity(0.12), lineWidth: selected == p ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, SDTokens.Spacing.l)
            .padding(.vertical, SDTokens.Spacing.s)
        }
        .scrollIndicators(.never)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SDTokens.Radii.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SDTokens.Radii.card, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Presets")
    }
}

// MARK: - Bottom Transport
struct BottomTransport: View {
    var beat: Int
    var bar: Int
    var linkHealth: LinkHealth
    var onTapTempo: () -> Void
    var onPanic: () -> Void
    @State private var pulse = false
    var body: some View {
        HStack(spacing: SDTokens.Spacing.l) {
            HStack(spacing: SDTokens.Spacing.s) {
                Circle().frame(width: 10, height: 10).foregroundStyle(pulse ? Color.accentColor : .secondary).animation(.easeOut(duration: 0.12), value: pulse)
                Text("Bar \(bar) • Beat \(beat)").font(.footnote.monospacedDigit().weight(.semibold))
            }
            Spacer()
            Button(action: onTapTempo) { Label("Tap", systemImage: "hand.tap") }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button(role: .destructive, action: onPanic) { Label("Panic", systemImage: "power") }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, SDTokens.Spacing.l)
        .padding(.vertical, SDTokens.Spacing.s)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SDTokens.Radii.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SDTokens.Radii.card).stroke(.white.opacity(0.12)))
        .onAppear { startPulse() }
    }
    private func startPulse() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            pulse.toggle()
        }
    }
}

// MARK: - Performance Lock Overlay
struct PerformanceLockOverlay: View {
    @Binding var isLocked: Bool
    var unlockAction: () -> Void = {}
    var body: some View {
        ZStack {
            if isLocked {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.orange.opacity(0.8), lineWidth: 3)
                    .blendMode(.plusLighter)
                    .padding(2)
                VStack(spacing: SDTokens.Spacing.m) {
                    Image(systemName: "lock.fill").font(.title2)
                    Text("Performance Lock").font(.headline.weight(.semibold))
                    Text("Press and hold to unlock").font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
                .gesture(LongPressGesture(minimumDuration: 1.0).onEnded { _ in withAnimation { isLocked = false; unlockAction() } })
                .accessibilityElement(children: .combine)
                .accessibilityHint("Long‑press to unlock")
            }
        }
        .allowsHitTesting(isLocked)
        .animation(.snappy, value: isLocked)
    }
}

// MARK: - Metrics Overlay
struct MetricsOverlay: View {
    var cpu: Int
    var gpu: Int
    var latencyMs: Int
    var body: some View {
        HStack(spacing: SDTokens.Spacing.l) {
            Label("CPU \(cpu)%", systemImage: "cpu")
            Label("GPU \(gpu)%", systemImage: "display")
            Label("\(latencyMs) ms", systemImage: "timer")
        }
        .font(.footnote.monospacedDigit().weight(.semibold))
        .padding(.horizontal, SDTokens.Spacing.l)
        .padding(.vertical, SDTokens.Spacing.s)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12)))
    }
}

// MARK: - Quick Controls Column (left)
struct QuickControlsColumn: View {
    @Binding var reacting: Bool
    @Binding var sensitivity: Double
    @Binding var paletteName: String
    @Binding var exposure: Double
    @Binding var strobeGuard: Bool
    var body: some View {
        VStack(spacing: SDTokens.Spacing.m) {
            GlassChip(title: reacting ? "Reacting" : "Idle", systemImage: reacting ? "waveform" : "pause.fill", isOn: reacting) { reacting.toggle() }
            Knob(value: $sensitivity, label: "Sensitivity")
            GlassChip(title: "Palette: \(paletteName)", systemImage: "swatchpalette.fill", isOn: true) { }
            GlassChip(title: "Exposure: \(String(format: "%.1f", exposure))", systemImage: "sun.max.fill", isOn: true) { exposure = min(exposure + 0.1, 2.0) }
            GlassChip(title: "Strobe Guard", systemImage: "bolt.slash.fill", isOn: strobeGuard) { strobeGuard.toggle() }
            Spacer()
        }
        .frame(width: 180)
    }
}

// MARK: - Perform HUD Shell
struct PerformHUD: View {
    @Binding var showHUD: Bool
    @Binding var linkHealth: LinkHealth
    @Binding var reacting: Bool
    @Binding var sensitivity: Double
    @Binding var paletteName: String
    @Binding var exposure: Double
    @Binding var strobeGuard: Bool
    @Binding var selectedPreset: Preset
    let presets: [Preset]
    var fps: Int = 60
    var ndiOn: Bool = false
    var battery: Int = 100
    var bar: Int = 1
    var beat: Int = 1
    var onTapTempo: () -> Void = {}
    var onPanic: () -> Void = {}
    var onSelectPreset: (Preset) -> Void = { _ in }

    @State private var isLocked = false
    @State private var showMetrics = false

    var body: some View {
        ZStack(alignment: .top) {
            // Top strip
            if showHUD {
                HStack {
                    StatusStrip(sceneName: selectedPreset.name, fps: fps, linkHealth: linkHealth, ndiOn: ndiOn, battery: battery)
                        .padding(.top, SDTokens.Spacing.l)
                        .padding(.horizontal, SDTokens.Spacing.l)
                    Spacer(minLength: 0)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Left controls & Right presets
            if showHUD {
                HStack(alignment: .center, spacing: SDTokens.Spacing.l) {
                    QuickControlsColumn(reacting: $reacting, sensitivity: $sensitivity, paletteName: $paletteName, exposure: $exposure, strobeGuard: $strobeGuard)
                        .padding(.leading, SDTokens.Spacing.l)

                    Spacer(minLength: 0)

                    VStack { // Right dock
                        PresetCarousel(items: presets, selected: $selectedPreset, onSelect: onSelectPreset)
                    }
                    .frame(width: 360)
                    .padding(.trailing, SDTokens.Spacing.l)
                }
                .padding(.top, 100)
                .transition(.opacity)
            }

            // Bottom transport
            VStack { Spacer()
                if showHUD {
                    BottomTransport(beat: beat, bar: bar, linkHealth: linkHealth, onTapTempo: onTapTempo, onPanic: onPanic)
                        .padding([.horizontal, .bottom], SDTokens.Spacing.l)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            // Lock & Metrics overlays
            PerformanceLockOverlay(isLocked: $isLocked)
                .padding(6)
                .allowsHitTesting(true)
            if showMetrics {
                MetricsOverlay(cpu: 23, gpu: 41, latencyMs: 7)
                    .padding(.top, 80)
                    .transition(.opacity)
            }
        }
        .onTapGesture(count: 1) { withAnimation(.snappy) { showHUD.toggle() } }
        .onTapGesture(count: 3) { withAnimation(.snappy) { showMetrics.toggle() } }
      //  .simultaneousGesture(DragGesture(minimumDistance: 0).modifiers(.command)) // placeholder for future gesture map
        .overlay(alignment: .topLeading) {
            if showHUD {
                GlassCircleButton(systemImage: isLocked ? "lock.fill" : "lock.open") {
                    // long press unlock/lock
                    withAnimation { isLocked.toggle() }
                } onTap: {
                    withAnimation { isLocked.toggle() }
                }
                .padding(.top, SDTokens.Spacing.l)
                .padding(.leading, SDTokens.Spacing.l)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Demo Canvas & Previews
struct DemoVisualCanvas: View {
    // Placeholder generative background to visualize HUD overlay
    @State private var phase: CGFloat = 0
    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { context, size in
                phase += 0.008
                let rows = 16
                let cols = 12
                let cellW = size.width / CGFloat(cols)
                let cellH = size.height / CGFloat(rows)
                for r in 0..<rows {
                    for c in 0..<cols {
                        let x = CGFloat(c) * cellW
                        let y = CGFloat(r) * cellH
                        let t = sin(phase + CGFloat(r) * 0.35 + CGFloat(c) * 0.25)
                        let color = Color(hue: Double(0.6 + 0.2 * t), saturation: 0.7, brightness: 0.9)
                        context.fill(Path(CGRect(x: x+1, y: y+1, width: cellW-2, height: cellH-2)), with: .color(color.opacity(0.35 + 0.35*Double(abs(t)))))
                    }
                }
            }
            .ignoresSafeArea()
        }
    }
}

struct PerformHUDDemo: View {
    @State private var showHUD = true
    @State private var linkHealth: LinkHealth = .ok
    @State private var reacting = true
    @State private var sensitivity: Double = 0.55
    @State private var paletteName: String = "Aurora"
    @State private var exposure: Double = 1.0
    @State private var strobeGuard: Bool = true

    private let demoPresets: [Preset] = [
        .init(name: "Beat Pulse", color: .pink),
        .init(name: "Spectrum Waves", color: .blue),
        .init(name: "Particle Burst", color: .purple),
        .init(name: "Geo Kaleido", color: .teal),
        .init(name: "CRT Glitch", color: .indigo)
    ]
    @State private var selected: Preset = .init(name: "Beat Pulse", color: .pink)

    var body: some View {
        ZStack {
            DemoVisualCanvas()
            PerformHUD(
                showHUD: $showHUD,
                linkHealth: $linkHealth,
                reacting: $reacting,
                sensitivity: $sensitivity,
                paletteName: $paletteName,
                exposure: $exposure,
                strobeGuard: $strobeGuard,
                selectedPreset: $selected,
                presets: demoPresets,
                fps: 60,
                ndiOn: true,
                battery: 87,
                bar: 3,
                beat: 2,
                onTapTempo: { /* wire to tap tempo */ },
                onPanic: { /* fade to black */ },
                onSelectPreset: { _ in }
            )
        }
    }
}

#Preview("Perform HUD Demo") {
    PerformHUDDemo()
}

// MARK: - Helpers
extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self { min(max(self, limits.lowerBound), limits.upperBound) }
}
