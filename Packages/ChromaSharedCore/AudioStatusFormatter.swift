import Foundation

public struct AudioStatusFormatter {
    public init() {
    }

    public func liveStatus(meterFrame: AudioMeterFrame, featureFrame: AudioFeatureFrame) -> String {
        let rmsDB = meterFrame.rmsDBFS ?? decibels(fromLinear: meterFrame.rms)
        let peakDB = meterFrame.peakDBFS ?? decibels(fromLinear: meterFrame.peak)
        if let pitchHz = featureFrame.pitchHz {
            return String(
                format: "Live input • rms %.2f dBFS • peak %.2f dBFS • transient %.2f • pitch %.1f Hz • conf %.2f",
                rmsDB,
                peakDB,
                featureFrame.transientStrength,
                pitchHz,
                featureFrame.pitchConfidence
            )
        }
        return String(
            format: "Live input • rms %.2f dBFS • peak %.2f dBFS • transient %.2f",
            rmsDB,
            peakDB,
            featureFrame.transientStrength
        )
    }

    public func idleStatus() -> String {
        "Awaiting live input service"
    }

    private func decibels(fromLinear linear: Double) -> Double {
        guard linear > 0 else { return -80 }
        return max(-80, 20 * log10(linear))
    }
}
