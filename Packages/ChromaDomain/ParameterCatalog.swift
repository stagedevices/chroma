import Foundation

public enum ParameterCatalog {
    public static let modes: [VisualModeDescriptor] = [
        VisualModeDescriptor(
            id: .colorShift,
            name: VisualModeID.colorShift.displayName,
            summary: "Flat stage backfill; weighted live input drives hue changes only.",
            supportsMorphing: true
        ),
        VisualModeDescriptor(
            id: .prismField,
            name: VisualModeID.prismField.displayName,
            summary: "Refracted ribbons and split-spectrum spread.",
            supportsMorphing: true
        ),
        VisualModeDescriptor(
            id: .tunnelCels,
            name: VisualModeID.tunnelCels.displayName,
            summary: "Attack-spawned cel forms in an infinite stage tunnel.",
            supportsMorphing: true
        ),
        VisualModeDescriptor(
            id: .fractalCaustics,
            name: VisualModeID.fractalCaustics.displayName,
            summary: "Orbit-trap caustics with flow plus attack pulses.",
            supportsMorphing: true
        ),
        VisualModeDescriptor(
            id: .riemannCorridor,
            name: VisualModeID.riemannCorridor.displayName,
            summary: "Mandelbrot flight map with contour layers and attack traces.",
            supportsMorphing: true
        ),
    ]

    public static let descriptors: [ParameterDescriptor] = [
        ParameterDescriptor(
            id: "response.inputGain",
            title: "Input Gain",
            summary: "Global front-end gain trim for live response.",
            group: .input,
            tier: .basic,
            scope: .global,
            controlStyle: .slider,
            defaultValue: .scalar(0.72),
            minimumValue: 0.0,
            maximumValue: 1.5
        ),
        ParameterDescriptor(
            id: "response.smoothing",
            title: "Smoothing",
            summary: "Global response damping for envelope stability.",
            group: .response,
            tier: .basic,
            scope: .global,
            controlStyle: .slider,
            defaultValue: .scalar(0.38),
            minimumValue: 0.0,
            maximumValue: 1.0
        ),
        ParameterDescriptor(
            id: "mode.colorShift.hueResponse",
            title: "Hue Response",
            summary: "How strongly live input and motion weighting push hue movement.",
            group: .response,
            tier: .basic,
            scope: .mode(.colorShift),
            controlStyle: .slider,
            defaultValue: .scalar(0.66),
            minimumValue: 0.0,
            maximumValue: 1.0
        ),
        ParameterDescriptor(
            id: "mode.colorShift.hueRange",
            title: "Hue Range",
            summary: "Two-point hue clamp with inside/outside selection for Color Shift targeting.",
            group: .color,
            tier: .basic,
            scope: .mode(.colorShift),
            controlStyle: .hueRange,
            defaultValue: .hueRange(min: 0.13, max: 0.87, outside: false),
            minimumValue: 0.0,
            maximumValue: 1.0
        ),
        ParameterDescriptor(
            id: "mode.colorShift.hueCenterTrim",
            title: "Hue Center Trim",
            summary: "Internal hue-center offset for Color Shift range retuning.",
            group: .color,
            tier: .advanced,
            scope: .mode(.colorShift),
            controlStyle: .slider,
            defaultValue: .scalar(0.0),
            minimumValue: 0.0,
            maximumValue: 1.0
        ),
        ParameterDescriptor(
            id: "mode.colorShift.excitementMode",
            title: "Excitement Mode",
            summary: "Directional cue source for Color Shift hue-side selection.",
            group: .response,
            tier: .advanced,
            scope: .mode(.colorShift),
            controlStyle: .slider,
            defaultValue: .scalar(0.0),
            minimumValue: 0.0,
            maximumValue: 2.0
        ),
        ParameterDescriptor(
            id: "mode.prismField.facetDensity",
            title: "Facet Density",
            summary: "Prism facet complexity and caustic cell frequency.",
            group: .geometry,
            tier: .basic,
            scope: .mode(.prismField),
            controlStyle: .slider,
            defaultValue: .scalar(0.58),
            minimumValue: 0.0,
            maximumValue: 1.0
        ),
        ParameterDescriptor(
            id: "mode.prismField.dispersion",
            title: "Dispersion",
            summary: "Chromatic split strength and refractive sharpness.",
            group: .color,
            tier: .basic,
            scope: .mode(.prismField),
            controlStyle: .slider,
            defaultValue: .scalar(0.62),
            minimumValue: 0.0,
            maximumValue: 1.0
        ),
        ParameterDescriptor(
            id: "mode.tunnelCels.shapeScale",
            title: "Shape Scale",
            summary: "Overall cel object footprint within tunnel perspective.",
            group: .geometry,
            tier: .basic,
            scope: .mode(.tunnelCels),
            controlStyle: .slider,
            defaultValue: .scalar(0.56),
            minimumValue: 0.0,
            maximumValue: 1.0
        ),
        ParameterDescriptor(
            id: "mode.tunnelCels.depthSpeed",
            title: "Depth Speed",
            summary: "Forward tunnel travel speed and parallax progression.",
            group: .response,
            tier: .basic,
            scope: .mode(.tunnelCels),
            controlStyle: .slider,
            defaultValue: .scalar(0.62),
            minimumValue: 0.0,
            maximumValue: 1.0
        ),
        ParameterDescriptor(
            id: "mode.tunnelCels.releaseTail",
            title: "Release Tail",
            summary: "Release duration for attack-spawned shape envelopes.",
            group: .response,
            tier: .basic,
            scope: .mode(.tunnelCels),
            controlStyle: .slider,
            defaultValue: .scalar(0.58),
            minimumValue: 0.0,
            maximumValue: 1.0
        ),
        ParameterDescriptor(
            id: "mode.tunnelCels.variant",
            title: "Variant",
            summary: "Style selector: cel cards, prism shards, or glyph slabs.",
            group: .geometry,
            tier: .advanced,
            scope: .mode(.tunnelCels),
            controlStyle: .slider,
            defaultValue: .scalar(0.0),
            minimumValue: 0.0,
            maximumValue: 2.0
        ),
        ParameterDescriptor(
            id: "mode.fractalCaustics.detail",
            title: "Detail",
            summary: "Julia orbit-trap detail and field complexity.",
            group: .geometry,
            tier: .basic,
            scope: .mode(.fractalCaustics),
            controlStyle: .slider,
            defaultValue: .scalar(0.60),
            minimumValue: 0.0,
            maximumValue: 1.0
        ),
        ParameterDescriptor(
            id: "mode.fractalCaustics.flowRate",
            title: "Flow Rate",
            summary: "Continuous fractal flow speed and breathing rate.",
            group: .response,
            tier: .basic,
            scope: .mode(.fractalCaustics),
            controlStyle: .slider,
            defaultValue: .scalar(0.56),
            minimumValue: 0.0,
            maximumValue: 1.0
        ),
        ParameterDescriptor(
            id: "mode.fractalCaustics.attackBloom",
            title: "Attack Bloom",
            summary: "Attack pulse intensity and release behavior.",
            group: .response,
            tier: .basic,
            scope: .mode(.fractalCaustics),
            controlStyle: .slider,
            defaultValue: .scalar(0.62),
            minimumValue: 0.0,
            maximumValue: 1.0
        ),
        ParameterDescriptor(
            id: "mode.fractalCaustics.paletteVariant",
            title: "Palette",
            summary: "Curated gradient bank selection for fractal mapping.",
            group: .color,
            tier: .advanced,
            scope: .mode(.fractalCaustics),
            controlStyle: .slider,
            defaultValue: .scalar(0.0),
            minimumValue: 0.0,
            maximumValue: 7.0
        ),
        ParameterDescriptor(
            id: "mode.riemannCorridor.detail",
            title: "Detail",
            summary: "Mandelbrot iteration/detail budget and boundary complexity.",
            group: .geometry,
            tier: .basic,
            scope: .mode(.riemannCorridor),
            controlStyle: .slider,
            defaultValue: .scalar(0.60),
            minimumValue: 0.0,
            maximumValue: 1.0
        ),
        ParameterDescriptor(
            id: "mode.riemannCorridor.flowRate",
            title: "Flow Rate",
            summary: "Audio-driven navigation and warp speed through the fractal field.",
            group: .response,
            tier: .basic,
            scope: .mode(.riemannCorridor),
            controlStyle: .slider,
            defaultValue: .scalar(0.56),
            minimumValue: 0.0,
            maximumValue: 1.0
        ),
        ParameterDescriptor(
            id: "mode.riemannCorridor.zeroBloom",
            title: "Zero Bloom",
            summary: "Attack trace intensity and release behavior.",
            group: .response,
            tier: .basic,
            scope: .mode(.riemannCorridor),
            controlStyle: .slider,
            defaultValue: .scalar(0.62),
            minimumValue: 0.0,
            maximumValue: 1.0
        ),
        ParameterDescriptor(
            id: "mode.riemannCorridor.navigationMode",
            title: "Navigation Mode",
            summary: "Guided zoom handoff vs free-flight steering.",
            group: .geometry,
            tier: .advanced,
            scope: .mode(.riemannCorridor),
            controlStyle: .slider,
            defaultValue: .scalar(0.0),
            minimumValue: 0.0,
            maximumValue: 1.0
        ),
        ParameterDescriptor(
            id: "mode.riemannCorridor.steeringStrength",
            title: "Steering Strength",
            summary: "Anti-jitter steering damping and heading stability.",
            group: .response,
            tier: .advanced,
            scope: .mode(.riemannCorridor),
            controlStyle: .slider,
            defaultValue: .scalar(0.62),
            minimumValue: 0.0,
            maximumValue: 1.0
        ),
        ParameterDescriptor(
            id: "mode.riemannCorridor.paletteVariant",
            title: "Palette",
            summary: "Curated gradient bank selection for Mandelbrot domain coloring.",
            group: .color,
            tier: .advanced,
            scope: .mode(.riemannCorridor),
            controlStyle: .slider,
            defaultValue: .scalar(0.0),
            minimumValue: 0.0,
            maximumValue: 7.0
        ),
        ParameterDescriptor(
            id: "output.blackFloor",
            title: "Black Floor",
            summary: "Output floor to preserve darkness between events.",
            group: .output,
            tier: .basic,
            scope: .global,
            controlStyle: .slider,
            defaultValue: .scalar(0.86),
            minimumValue: 0.0,
            maximumValue: 1.0
        ),
        ParameterDescriptor(
            id: "output.noImageInSilence",
            title: "No Image In Silence",
            summary: "Drops output to black when live energy falls below threshold.",
            group: .output,
            tier: .advanced,
            scope: .global,
            controlStyle: .toggle,
            defaultValue: .toggle(false)
        ),
    ]

    public static let defaultDisplayTargets: [DisplayTarget] = [
        DisplayTarget(id: "device", name: "Device Screen", kind: .deviceScreen, isAvailable: true, supportsFullscreen: true),
        DisplayTarget(id: "external", name: "External Display", kind: .externalDisplay, isAvailable: false, supportsFullscreen: true),
    ]

    public static let exportProfiles: [ExportProfile] = [
        ExportProfile(id: "capture-1080p", name: "Capture 1080p", resolutionLabel: "1920x1080", frameRate: 60, codec: "HEVC"),
        ExportProfile(id: "rehearsal-prores", name: "Rehearsal ProRes", resolutionLabel: "1920x1080", frameRate: 30, codec: "ProRes 422"),
    ]

    public static func modeDescriptor(for modeID: VisualModeID) -> VisualModeDescriptor {
        modes.first(where: { $0.id == modeID }) ?? modes[0]
    }

    public static func quickControlParameterIDs(for modeID: VisualModeID) -> [String] {
        switch modeID {
        case .colorShift:
            return [
                "response.inputGain",
                "response.smoothing",
                "mode.colorShift.hueResponse",
                "mode.colorShift.hueRange",
            ]
        case .prismField:
            return [
                "response.inputGain",
                "response.smoothing",
                "mode.prismField.facetDensity",
                "mode.prismField.dispersion",
                "output.blackFloor",
            ]
        case .tunnelCels:
            return [
                "response.inputGain",
                "response.smoothing",
                "mode.tunnelCels.shapeScale",
                "mode.tunnelCels.depthSpeed",
                "mode.tunnelCels.releaseTail",
                "output.blackFloor",
            ]
        case .fractalCaustics:
            return [
                "response.inputGain",
                "response.smoothing",
                "mode.fractalCaustics.detail",
                "mode.fractalCaustics.flowRate",
                "mode.fractalCaustics.attackBloom",
                "output.blackFloor",
            ]
        case .riemannCorridor:
            return [
                "response.inputGain",
                "response.smoothing",
                "mode.riemannCorridor.detail",
                "mode.riemannCorridor.flowRate",
                "mode.riemannCorridor.zeroBloom",
                "output.blackFloor",
            ]
        }
    }

    public static func surfaceControlParameterIDs(for modeID: VisualModeID) -> [String] {
        switch modeID {
        case .colorShift:
            return [
                "response.inputGain",
                "mode.colorShift.hueResponse",
                "mode.colorShift.hueRange",
                "mode.colorShift.excitementMode",
            ]
        case .prismField:
            return [
                "response.inputGain",
                "response.smoothing",
                "mode.prismField.facetDensity",
                "mode.prismField.dispersion",
                "output.blackFloor",
            ]
        case .tunnelCels:
            return [
                "response.inputGain",
                "response.smoothing",
                "mode.tunnelCels.shapeScale",
                "mode.tunnelCels.depthSpeed",
                "mode.tunnelCels.releaseTail",
                "output.blackFloor",
            ]
        case .fractalCaustics:
            return [
                "response.inputGain",
                "response.smoothing",
                "mode.fractalCaustics.detail",
                "mode.fractalCaustics.flowRate",
                "mode.fractalCaustics.attackBloom",
                "output.blackFloor",
            ]
        case .riemannCorridor:
            return [
                "response.inputGain",
                "response.smoothing",
                "mode.riemannCorridor.detail",
                "mode.riemannCorridor.flowRate",
                "mode.riemannCorridor.zeroBloom",
                "output.blackFloor",
            ]
        }
    }
}
