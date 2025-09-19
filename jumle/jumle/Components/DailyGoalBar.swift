//
//  DailyGoalBar.swift
//  jumle
//
//  Created by Kai Kahar on 2025-08-20.
//
// Components/DailyGoalBar.swift
import SwiftUI

struct DailyGoalBar: View {
    let learnedCount: Int
    let quizCount: Int
    let flashcardCount: Int
    let goal: Int

    @State private var animate = false
    
    var totalProgress: Int {
            learnedCount + quizCount + flashcardCount
        }

    var body: some View {
        let progress = max(0, Double(totalProgress)) / Double(max(goal, 1))
        let clamped = min(progress, 1.0)

        VStack(spacing: 8) {
            HStack {
                Label("Today", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(totalProgress) / \(goal)")
                    .font(.subheadline.monospacedDigit())
            }

            // Show breakdown
            HStack(spacing: 12) {
                if learnedCount > 0 {
                    Label("\(learnedCount)", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                if quizCount > 0 {
                    Label("\(quizCount)", systemImage: "brain.head.profile")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                if flashcardCount > 0 {
                    Label("\(flashcardCount)", systemImage: "rectangle.on.rectangle")
                        .font(.caption)
                        .foregroundStyle(.purple)
                }
                Spacer()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(gradient(for: clamped))
                        .frame(width: CGFloat(clamped) * geo.size.width)
                        .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: clamped)
                }
            }
            .frame(height: 14)

            if learnedCount >= goal {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("Congrats! Daily goal reached.")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(.orange)
                .transition(.scale.combined(with: .opacity))
                .id("congrats")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear { animate = true }
    }

    private func gradient(for p: Double) -> LinearGradient {
        // blue → purple → pink → red as progress warms up
        let start = Color(hue: 0.60, saturation: 0.85, brightness: 0.95) // blue
        let mid   = Color(hue: 0.82, saturation: 0.80, brightness: 0.95) // purple
        let end   = Color(hue: 0.02, saturation: 0.90, brightness: 0.95) // red
        return LinearGradient(colors: p < 0.5 ? [start, mid] : [mid, end],
                              startPoint: .leading, endPoint: .trailing)
    }
}
