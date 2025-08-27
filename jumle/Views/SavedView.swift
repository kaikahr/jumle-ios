// File: Views/SavedView.swift
import SwiftUI

struct SavedView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var learned: LearnedStore

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedByLanguage, id: \.0) { (lang, items) in
                    Section(header: Text(lang.displayName)) {
                        ForEach(items) { s in
                            NavigationLink {
                                // Reuse the same card but pin displayLanguage
                                SentenceCardView(sentence: s, displayLanguage: lang)
                                    .padding()
                            } label: {
                                SavedRow(sentence: s, language: lang)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Saved")
            .overlay {
                if groupedByLanguage.isEmpty {
                    ContentStateMessage(
                        title: "Nothing learned yet",
                        subtitle: "Tap the ✓ on any sentence to mark it learned.",
                        systemImage: "checkmark.circle"
                    )
                }
            }
        }
    }

    // ✅ Stable: resolve IDs through AppState.globalIndex/lookup
    private var groupedByLanguage: [(AppLanguage, [Sentence])] {
        AppLanguage.allCases.compactMap { lang in
            let ids = Array(learned.learnedByLang[lang] ?? [])
            // Look up each id in the global index (falls back to current dataset if present)
            let items = ids.compactMap { app.lookup(id: $0) }
            return items.isEmpty ? nil : (lang, items.sorted { $0.id < $1.id })
        }
    }
}

// A small row that shows text in the specific saved language.
private struct SavedRow: View {
    let sentence: Sentence
    let language: AppLanguage
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sentence.text(for: language) ?? "—")
                .font(.body)
            if let t = sentence.text(for: otherLanguage(for: language)) {
                Text(t).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func otherLanguage(for lang: AppLanguage) -> AppLanguage {
        // fallback: show English as "translation" if the chosen profile language is not suitable
        return lang == .English ? .French : .English
    }
}
