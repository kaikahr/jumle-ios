// File: AppState.swift
import SwiftUI
import Foundation
import Combine

// MARK: - Theme Enum
enum Theme: String, CaseIterable, Identifiable, Codable {
    case general
    case social
    case routine
    case emotions
    case entertainment
    case politeness
    case food
    case greetings
    case health
    case hobbies
    case housing
    case manifest
    case opinions
    case relationships
    case safety
    case study
    case education
    case money
    case tech
    case time
    case travel
    case nature
    case work

    var id: String { rawValue }
    var display: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
    var filename: String { "\(rawValue).json" }
}

@MainActor
final class AppState: ObservableObject {
    // Raw data and UI-ready filtered list
    @Published var sentences: [Sentence] = []
    @Published var filtered: [Sentence] = []

    // UI state
    @Published var saved: Set<Int> = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var searchText: String = ""
    @Published var selectedTopic: String? = nil

    // Theme selection (defaults to General)
    @Published var selectedTheme: Theme = .general
    // ✅ New: a cross-dataset cache so Saved tab is stable no matter what is loaded
    @Published private(set) var savedIndex: [Int: Sentence] = [:]
    @Published var globalIndex: [Int: Sentence] = [:]

    // Explain/Context transient UI state (per active request)
    @Published var aiIsWorking: Bool = false
    @Published var aiError: String? = nil

    // Persisted languages (by rawValue)
    @AppStorage("knownLanguage") private var knownLanguageRaw: String = AppLanguage.English.rawValue
    @AppStorage("learningLanguage") private var learningLanguageRaw: String = AppLanguage.French.rawValue

    var knownLanguage: AppLanguage {
        get { AppLanguage(rawValue: knownLanguageRaw) ?? .English }
        set {
            if newValue == learningLanguage,
               let alt = AppLanguage.allCases.first(where: { $0 != newValue }) {
                learningLanguageRaw = alt.rawValue
            }
            knownLanguageRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    var learningLanguage: AppLanguage {
        get { AppLanguage(rawValue: learningLanguageRaw) ?? .French }
        set {
            if newValue == knownLanguage,
               let alt = AppLanguage.allCases.first(where: { $0 != newValue }) {
                knownLanguageRaw = alt.rawValue
            }
            learningLanguageRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    // Topics
    let defaultTopics: [String] = [
        "General", "Directions", "Shopping", "Health", "Greetings",
        "Food", "Travel", "Work", "School", "Weather", "Hobbies", "Technology"
    ]

    var availableTopics: [String] {
        let fromData = Set(sentences.compactMap { $0.theme }.filter { !$0.isEmpty })
        return Array(fromData).sorted() + defaultTopics
    }

    // MARK: - Filtering (Combine)
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupFiltering()
    }

    private func setupFiltering() {
        Publishers.CombineLatest3(
            $sentences,
            $searchText
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .removeDuplicates()
                .debounce(for: .milliseconds(250), scheduler: RunLoop.main),
            $selectedTopic.removeDuplicates()
        )
        .receive(on: DispatchQueue.global(qos: .userInitiated))
        .map { sentences, rawQuery, topic -> [Sentence] in
            let q = rawQuery.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            return sentences.filter { s in
                let topicOK = (topic?.isEmpty ?? true) || s.topicMatches(topic!)
                let queryOK = q.isEmpty || s.matches(q)
                return topicOK && queryOK
            }
        }
        .receive(on: RunLoop.main)
        .assign(to: &$filtered)
    }

    // MARK: - Actions
    func toggleSave(_ sentence: Sentence) {
        if saved.contains(sentence.id) {
            saved.remove(sentence.id)
            savedIndex.removeValue(forKey: sentence.id)
        } else {
            saved.insert(sentence.id)
            savedIndex[sentence.id] = sentence  // keep a snapshot so UI can render anytime
        }
    }
    
    func index(_ sentences: [Sentence]) {
        for s in sentences {
            globalIndex[s.id] = s
        }
    }

    // Convenience resolver used by SavedView to get a Sentence by id
    func lookup(id: Int) -> Sentence? {
        // Prefer global; fall back to whatever is currently loaded
        globalIndex[id] ?? sentences.first(where: { $0.id == id })
    }

    // MARK: - Theme-based networking
    func loadTheme(_ theme: Theme) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let url = themeURL(for: theme) else {
            errorMessage = "Invalid URL."
            return
        }

        do {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw URLError(.badServerResponse)
            }

            var decoded = try JSONDecoder().decode([Sentence].self, from: data)
           // decoded.shuffle() // randomize order each load

            sentences = decoded
            selectedTopic = nil
            searchText = ""
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
            sentences = []
        }
    }

    private func themeURL(for theme: Theme) -> URL? {
        // Matches: https://d7hjupfdvrdpp.cloudfront.net/text/health.json
        return URL(string: "https://d7hjupfdvrdpp.cloudfront.net/text/\(theme.filename)")
    }

    // Legacy loader
    func loadSentences(from urlString: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid URL."
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode([Sentence].self, from: data)
            sentences = decoded
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }
    }
    
    // MARK: Grammar selection
    @Published var availableGrammar: [String] = GrammarCatalog.allDisplayNames
    @Published var selectedGrammar: String? = nil

    func selectGrammar(_ displayName: String?) {
        // Clear grammar → restore whatever your default dataset is
        guard let name = displayName, let url = GrammarCatalog.urlString(for: name) else {
            selectedGrammar = nil
            Task { @MainActor in
                // Reload your default dataset (or just keep current list if you prefer)
                // Example: await loadSentences(from: defaultURLString)
            }
            return
        }

        selectedGrammar = name
        // Optional: when picking grammar, clear the topic filter so results are obvious
        selectedTopic = nil

        Task { @MainActor in
            await loadSentences(from: url)
        }
    }
    
    

    
    // MARK: - Audio URL builder

    private let audioBaseURL = "https://d7hjupfdvrdpp.cloudfront.net/audio/"

    func audioURL(for sentence: Sentence) -> URL? {
        // If JSON already provides a full URL, prefer it.
        if let s = sentence.audioURL, let u = URL(string: s) {
            return u
        }
        // Build from learning language + id
        let folder = learningLanguage.audioFolder
        let prefix = learningLanguage.audioPrefix
        let path = "\(audioBaseURL)\(folder)/\(prefix)-\(sentence.id).mp3"
        return URL(string: path)
    }


    // MARK: - AI: Explain & Context (cached + throttled + retries)
    func explain(sentence: Sentence) async -> String {
        aiIsWorking = true
        aiError = nil
        defer { aiIsWorking = false }

        let main = sentence.text(for: learningLanguage) ?? ""
        let known = knownLanguage.displayName

        let system = """
        You are a concise language tutor. Explain sentences in the user's KNOWN language clearly and simply. Avoid overlong grammar lectures—focus on meaning, key grammar points, and any idioms. If the sentence is ambiguous, note the most common reading.
        """
        let user = """
        Known language: \(known)
        Target sentence: \(main)

        Task: Explain this sentence in \(known). Include:
        1) Natural translation
        2) Brief breakdown of tricky words/grammar
        3) One usage tip
        """

        let key = "explain:v1:\(known):\(main.hashValue)"
        do {
            return try await OpenAIService.shared.completeCached(key: key, system: system, user: user, maxTokens: 350, temperature: 0.2)
        } catch {
            aiError = (error as NSError).localizedDescription
            return "Sorry—couldn’t generate an explanation."
        }
    }

    func contextualize(sentence: Sentence) async -> String {
        aiIsWorking = true
        aiError = nil
        defer { aiIsWorking = false }

        let main = sentence.text(for: learningLanguage) ?? ""
        let known = knownLanguage.displayName

        let system = """
        You write short, vivid contexts (dialogues or mini-paragraphs) that make a target sentence feel natural. Keep it beginner-friendly and use simple vocabulary. Provide the output in the user's KNOWN language as narration with the TARGET sentence embedded in the original target language.
        """
        let user = """
        Known language: \(known)
        Target sentence (keep exactly as-is when used): \(main)

        Task: Create a short context (3–5 lines) that naturally includes the target sentence once. First give a single-sentence setup in \(known), then present the context (either a brief dialogue with speaker tags or a mini-paragraph in \(known), but keep the target sentence itself in the target language when it appears).
        """

        let key = "context:v1:\(known):\(main.hashValue)"
        do {
            return try await OpenAIService.shared.completeCached(key: key, system: system, user: user, maxTokens: 420, temperature: 0.4)
        } catch {
            aiError = (error as NSError).localizedDescription
            return "Sorry—couldn’t generate context."
        }
    }
}
