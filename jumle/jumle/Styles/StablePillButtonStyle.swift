//
//  StablePillButtonStyle.swift
//  jumle
//
//  Created by Kai Kahar on 2025-08-07.
//

// File: Styles/StablePillButtonStyle.swift
import SwiftUI

struct StablePillButtonStyle: ButtonStyle {
    var fill: Color = Color(.secondarySystemBackground)
    var stroke: Color = .secondary.opacity(0.35)
    var cornerRadius: CGFloat = 12
    var height: CGFloat = 40

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill.opacity(configuration.isPressed ? 0.9 : 1.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
            .animation(.none, value: configuration.isPressed)
    }
}
