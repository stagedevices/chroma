//
//  ChromaProBadge.swift
//  Chroma
//
//  Created by Sebastian Suarez-Solis on 3/21/26.
//


import SwiftUI

public struct ChromaProBadge: View {
    public enum Style: Equatable {
        case locked
        case status(ProAccessVisualState)
    }

    public let style: Style

    public init(style: Style) {
        self.style = style
    }

    public var body: some View {
        Label {
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.4)
        } icon: {
            Image(systemName: iconName)
                .font(.system(size: 9, weight: .bold))
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(.white.opacity(0.96))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(backgroundColor, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
    }

    private var iconName: String {
        switch style {
        case .locked:
            return "lock.fill"
        case .status:
            return "sparkles"
        }
    }

    private var text: String {
        switch style {
        case .locked:
            return "PRO"
        case .status(let state):
            return state.badgeText
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .locked:
            return Color(red: 47 / 255, green: 125 / 255, blue: 110 / 255)
        case .status(let state):
            switch state {
            case .active:
                return Color(red: 42 / 255, green: 126 / 255, blue: 116 / 255)
            case .trial:
                return Color(red: 88 / 255, green: 103 / 255, blue: 168 / 255)
            case .renewal:
                return Color(red: 156 / 255, green: 115 / 255, blue: 50 / 255)
            case .inactive:
                return Color(red: 104 / 255, green: 115 / 255, blue: 132 / 255)
            }
        }
    }
}