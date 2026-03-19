//
//  PerformHelpers.swift
//  Chroma
//
//  Created by Sebastian Suarez-Solis on 10/17/25.
//

import Foundation
import SwiftUI

// Reusable native-glass card
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.12)))
    }
}

// Small, glass-confined preview (swap MetalView for DemoVisualCanvas if needed)
struct PerformPreviewCard: View {
    @ObservedObject var renderParams: RenderParams
    var body: some View {
        GlassCard {
            // Use your real renderer if Sprint 2 is in; else DemoVisualCanvas()
            MetalView(params: renderParams)
                .aspectRatio(16.0/9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.08)))
        }
    }
}


// Core controls in one compact card
struct ControlsSection: View {
    @Binding var exposure: Double
    @Binding var strobeGuard: Bool
    var onTapTempo: () -> Void
    var onPanic: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Controls").font(.headline)
            VStack(spacing: 10) {
                HStack {
                    Text("Exposure").frame(width: 90, alignment: .leading)
                    Slider(value: $exposure, in: 0.3...2.0, step: 0.01)
                    Text(String(format: "%.2f", exposure)).foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
                }
                Toggle("Strobe Guard", isOn: $strobeGuard)
                HStack(spacing: 10) {
                    Button("Tap Tempo", action: onTapTempo)
                        .buttonStyle(.borderedProminent)
                    Button("Panic") { onPanic() }
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
            }
        }
    }
}

// One-line status row, wraps gracefully on narrow phones
struct StatusRow: View {
    let linkHealth: LinkHealth
    let fps: Int
    let battery: Int
    let reacting: Bool

    var body: some View {
        HStack(spacing: 12) {
            Label(linkHealth == .ok ? "Link OK" : "No Link",
                  systemImage: "dot.radiowaves.left.and.right")
                .foregroundStyle(linkHealth == .ok ? .green : .secondary)
            Divider().opacity(0.2)
            Label("\(fps) FPS", systemImage: "gauge")
                .foregroundStyle(.secondary)
            Divider().opacity(0.2)
            Label("\(battery)%", systemImage: "battery.100")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Circle()
                .fill(reacting ? Color.accentColor : Color.clear)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color.accentColor.opacity(0.5)))
                .accessibilityLabel(reacting ? "Onset detected" : "Idle")
        }
        .font(.footnote)
    }
}
