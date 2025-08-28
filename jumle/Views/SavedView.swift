// File: Views/SavedView.swift - Fixed version with filtering
import SwiftUI

struct SavedView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var learned: LearnedStore
    
    @State private var selectedFilter: SavedFilter = .all
    @State private var availableThemes: Set<String> = []
    @State private var availableGrammar: Set<String> = []
    
    enum SavedFilter: Hashable {
        case all
        case theme(String)
        case grammar(String)
        
        var displayName: String {
            switch self {
            case .all:
                return "All"
            case .theme(let theme):
                return theme.capitalized
            case .grammar(let grammar):
                return grammar
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter selector at top
                if !app.savedSentences.isEmpty {
                    filterSelector
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                }
                
                // Main content
                List {
                    // Only show learned sentences from LearnedStore
                    ForEach(groupedByLanguage, id: \.0) { (lang, items) in
                        Section(header: Text("Learned - \(lang.displayName)")) {
                            ForEach(filteredLearned(items)) { sentence in
                                NavigationLink {
                                    SentenceCardView(sentence: sentence, displayLanguage: lang)
                                        .padding()
                                } label: {
                                    SavedRow(sentence: sentence, language: lang)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Saved")
            .overlay {
                if groupedByLanguage.isEmpty {
                    ContentStateMessage(
                        title: "Nothing saved yet",
                        subtitle: "Mark sentences as learned using the checkmark button.",
                        systemImage: "checkmark.circle"
                    )
                }
            }
        }
        .onAppear {
            updateAvailableFilters()
        }
        .onChange(of: app.savedSentences) { _, _ in
            updateAvailableFilters()
        }
    }
    
    // MARK: - Filter Selector
    
    private var filterSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Filter by")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // All filter
                    FilterChip(
                        title: "All",
                        isSelected: selectedFilter == .all,
                        action: { selectedFilter = .all }
                    )
                    
                    // Theme filters
                    ForEach(Array(availableThemes).sorted(), id: \.self) { theme in
                        FilterChip(
                            title: theme.capitalized,
                            isSelected: selectedFilter == .theme(theme),
                            action: { selectedFilter = .theme(theme) }
                        )
                    }
                    
                    // Grammar filters
                    ForEach(Array(availableGrammar).sorted(), id: \.self) { grammar in
                        FilterChip(
                            title: grammar,
                            isSelected: selectedFilter == .grammar(grammar),
                            action: { selectedFilter = .grammar(grammar) }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func updateAvailableFilters() {
        var themes = Set<String>()
        var grammar = Set<String>()
        
        for sentence in app.savedSentences {
            // Add themes from sentence topics
            for topic in sentence.topics {
                if !topic.isEmpty {
                    themes.insert(topic.lowercased())
                }
            }
            
            // Check if sentence exists in grammar files (simplified approach)
            // You might want to store grammar source info with sentences
        }
        
        availableThemes = themes
        // You can populate grammar from GrammarCatalog if needed
    }
    
    private func filteredLearned(_ sentences: [Sentence]) -> [Sentence] {
        switch selectedFilter {
        case .all:
            return sentences
        case .theme(let theme):
            return sentences.filter { sentence in
                sentence.topics.contains { $0.lowercased() == theme.lowercased() }
            }
        case .grammar(let grammar):
            // Filter by grammar if you have that info stored
            return sentences
        }
    }
    
    // Filter learned sentences to only show current learning language
    private var groupedByLanguage: [(AppLanguage, [Sentence])] {
        // Only show sentences for the current learning language
        let currentLang = app.learningLanguage
        
        if let ids = learned.learnedByLang[currentLang], !ids.isEmpty {
            let items = Array(ids).compactMap { id in
                app.findSentence(by: id)
            }
            
            return items.isEmpty ? [] : [(currentLang, items.sorted { $0.id < $1.id })]
        }
        
        return []
    }
}

// MARK: - Supporting Views

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(
                        isSelected
                        ? Color.accentColor.opacity(0.2)
                        : Color.secondary.opacity(0.1)
                    )
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .overlay(
                    Capsule().stroke(
                        isSelected ? Color.accentColor.opacity(0.3) : Color.clear,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }
}

// Keep existing SavedRow for learned sentences
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
            if !sentence.topicDisplay.isEmpty {
                Text(sentence.topicDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func otherLanguage(for lang: AppLanguage) -> AppLanguage {
        return lang == .English ? .French : .English
    }
}
