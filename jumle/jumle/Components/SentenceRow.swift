//
//  SentenceCardView.swift
//  jumle
//
// File: Components/SentenceRow.swift
import SwiftUI

struct SentenceRow: View {
    @EnvironmentObject private var app: AppState
    let sentence: Sentence

    var body: some View {
        let main: String = sentence.text(for: app.learningLanguage) ?? "—"
        let trans: String? = sentence.text(for: app.knownLanguage)

        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(main)
                    .font(.body)

                if let trans, !trans.isEmpty {
                    Text(trans)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !sentence.topicDisplay.isEmpty {
                    Text(sentence.topicDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button { app.toggleSave(sentence) } label: {
                Image(systemName: app.saved.contains(sentence.id) ? "star.fill" : "star")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }
}
