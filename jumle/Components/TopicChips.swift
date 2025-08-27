//
//  TopicChips.swift
//  jumle
//
//  Created by Kai Kahar on 2025-08-07.
//

// File: Components/TopicChips.swift
import SwiftUI

struct TopicChips: View {
    let topics: [String]
    let selected: String?
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(topics, id: \.self) { topic in
                    Button { onSelect(topic) } label: {
                        Text(topic)
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill((selected == topic) ? Color.purple.opacity(0.25) : Color.purple.opacity(0.12))
                            )
                            .overlay(Capsule().stroke(Color.purple.opacity(0.35)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
