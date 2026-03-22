//
//  ProEntitlement.swift
//  Chroma
//
//  Created by Sebastian Suarez-Solis on 3/21/26.
//


import Foundation

public enum ProFeature: Equatable {
    case mode(VisualModeID)
    case recording
    case externalDisplay
    case customBuilder
    case unlimitedPresets
    case modeMorphing
}

public enum ProEntitlement {
    public static func requiresPro(_ feature: ProFeature) -> Bool {
        switch feature {
        case .mode(let modeID):
            switch modeID {
            case .colorShift, .prismField:
                return false
            case .tunnelCels, .fractalCaustics, .riemannCorridor, .custom:
                return true
            }
        case .recording, .externalDisplay, .customBuilder, .unlimitedPresets, .modeMorphing:
            return true
        }
    }
}
