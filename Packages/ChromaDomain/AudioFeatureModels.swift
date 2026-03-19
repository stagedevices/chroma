import Foundation

public struct AudioAnalysisTuning: Codable, Equatable, Sendable {
    public var attackThresholdDB: Double
    public var attackHysteresisDB: Double
    public var attackCooldownMS: Double
    public var inputGainDB: Double

    public init(
        attackThresholdDB: Double = 8,
        attackHysteresisDB: Double = 2,
        attackCooldownMS: Double = 70,
        inputGainDB: Double = 0
    ) {
        self.attackThresholdDB = attackThresholdDB
        self.attackHysteresisDB = attackHysteresisDB
        self.attackCooldownMS = attackCooldownMS
        self.inputGainDB = inputGainDB
    }

    public static let `default` = AudioAnalysisTuning()

    public var attackCooldownSeconds: Double {
        attackCooldownMS / 1_000
    }

    public func clamped() -> AudioAnalysisTuning {
        AudioAnalysisTuning(
            attackThresholdDB: attackThresholdDB.clamped(to: 2 ... 24),
            attackHysteresisDB: attackHysteresisDB.clamped(to: 0.5 ... 8),
            attackCooldownMS: attackCooldownMS.clamped(to: 20 ... 500),
            inputGainDB: inputGainDB.clamped(to: -18 ... 18)
        )
    }
}

public struct AudioFeatureFrame: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var amplitude: Double
    public var lowBandEnergy: Double
    public var midBandEnergy: Double
    public var highBandEnergy: Double
    public var transientStrength: Double
    public var pitchHz: Double?
    public var pitchConfidence: Double
    public var stablePitchClass: Int?
    public var stablePitchCents: Double
    public var isAttack: Bool
    public var attackStrength: Double
    public var attackID: UInt64
    public var attackDbOverFloor: Double

    public init(
        timestamp: Date,
        amplitude: Double,
        lowBandEnergy: Double,
        midBandEnergy: Double,
        highBandEnergy: Double,
        transientStrength: Double,
        pitchHz: Double? = nil,
        pitchConfidence: Double = 0,
        stablePitchClass: Int? = nil,
        stablePitchCents: Double = 0,
        isAttack: Bool = false,
        attackStrength: Double = 0,
        attackID: UInt64 = 0,
        attackDbOverFloor: Double = 0
    ) {
        self.timestamp = timestamp
        self.amplitude = amplitude
        self.lowBandEnergy = lowBandEnergy
        self.midBandEnergy = midBandEnergy
        self.highBandEnergy = highBandEnergy
        self.transientStrength = transientStrength
        self.pitchHz = pitchHz
        self.pitchConfidence = pitchConfidence
        self.stablePitchClass = stablePitchClass
        self.stablePitchCents = stablePitchCents
        self.isAttack = isAttack
        self.attackStrength = attackStrength
        self.attackID = attackID
        self.attackDbOverFloor = attackDbOverFloor
    }

    public static let silent = AudioFeatureFrame(
        timestamp: .distantPast,
        amplitude: 0,
        lowBandEnergy: 0,
        midBandEnergy: 0,
        highBandEnergy: 0,
        transientStrength: 0,
        pitchHz: nil,
        pitchConfidence: 0,
        stablePitchClass: nil,
        stablePitchCents: 0,
        isAttack: false,
        attackStrength: 0,
        attackID: 0,
        attackDbOverFloor: 0
    )
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
