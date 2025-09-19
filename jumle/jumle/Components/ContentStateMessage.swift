//
//  ContentStateMessage.swift
//  jumle
//
//  Created by Kai Kahar on 2025-08-07.
//

// File: Components/ContentStateMessage.swift
import SwiftUI

struct ContentStateMessage: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
            Text(title).font(.headline)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
