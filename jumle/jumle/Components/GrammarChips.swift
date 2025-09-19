//
//  GrammarChips.swift
//  jumle
//
//  Created by Kai Kahar on 2025-08-22.
//
// File: Components/GrammarChips.swift
import SwiftUI

struct GrammarChips: View {
    let points: [String]
    let selected: String?
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(points, id: \.self) { p in
                    Button { onSelect(p) } label: {
                        Text(p)
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill((selected == p) ? Color.blue.opacity(0.25) : Color.blue.opacity(0.12))
                            )
                            .overlay(Capsule().stroke(Color.blue.opacity(0.35)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
