
import SwiftUI
import Combine

enum Theme: String, CaseIterable, Identifiable {
    case education, emotions, entertainment, food, greetings, health, hobbies, housing
    case money, nature, opinions, politeness, relationships, routine, safety, social
    case study, tech, time, travel, work
    
    var id: String { rawValue }
    
    var display: String {
        rawValue.capitalized
    }
}

enum LoadingState {
    case idle
    case loading
    case loaded
    case error(String)
    
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

@MainActor
final class AppState: ObservableObject {
    // MARK: - Core Data
    @Published var sentences: [Sentence] = []
    @Published var globalIndex: [Int: Sentence] = [:]
    
    // ✅ Persistent cache of ALL sentences ever loaded (for SavedView) - now truly persistent
    @AppStorage("sentenceCache") private var sentenceCacheData: Data = Data()
    private var persistentSentenceCache: [Int: Sentence] = [:]
    
    // MARK: - Selection State
    @Published var selectedTheme: Theme?
    @Published var selectedTopic: String?
    @Published var selectedGrammar: String?
    @Published var availableGrammar: [String] = GrammarCatalog.allDisplayNames
    
    // MARK: - Computed Properties
    var currentSelection: String {
        if let theme = selectedTheme {
            return theme.rawValue
        } else if let grammar = selectedGrammar {
            return "grammar: \(grammar)"
        } else {
            return "general"
        }
    }
    
    // MARK: - Search & Filtering
    @Published var searchText: String = ""
    @Published private var _filtered: [Sentence] = []
    
    // ✅ FIX 1: Make saved persistent using AppStorage
    @AppStorage("savedSentences") private var savedData: Data = Data()
    @Published var saved: Set<Int> = [] {
        didSet {
            // Persist to UserDefaults whenever saved changes
            if let encoded = try? JSONEncoder().encode(Array(saved)) {
                savedData = encoded
            }
        }
    }
    
    // MARK: - Loading States
    @Published var loadingState: LoadingState = .idle
    @Published var filteringState: LoadingState = .idle
    @Published var loadingProgress: Double = 0.0
    
    // MARK: - Computed Properties
    var filtered: [Sentence] {
        _filtered
    }
    
    var isLoading: Bool {
        loadingState.isLoading || filteringState.isLoading
    }
    
    var errorMessage: String? {
        if case .error(let message) = loadingState {
            return message
        }
        return nil
    }
    
    var availableTopics: [String] {
        Array(Set(sentences.compactMap { $0.topics.first }))
            .filter { !$0.isEmpty }
            .sorted()
    }
    
    // MARK: - Services
    private let ai = OpenAIService.shared
    private var cancellables = Set<AnyCancellable>()
    private var filteringTask: Task<Void, Never>?
    
    // MARK: - AI State
    @Published var aiError: String?
    
    // MARK: - Languages
    @AppStorage("knownLanguage") var knownLanguage: AppLanguage = .English {
        didSet { objectWillChange.send() }
    }
    @AppStorage("learningLanguage") var learningLanguage: AppLanguage = .French {
        didSet {
            if knownLanguage == learningLanguage {
                knownLanguage = learningLanguage == .English ? .French : .English
            }
            objectWillChange.send()
        }
    }
    
    init() {
        // ✅ Load saved sentences from storage on init
        loadSavedFromStorage()
        // ✅ Load persistent sentence cache from storage
        loadPersistentCacheFromStorage()
        setupFilteringPipeline()
    }
    
    // ✅ Load saved sentences from persistent storage
    private func loadSavedFromStorage() {
        if let decoded = try? JSONDecoder().decode([Int].self, from: savedData) {
            saved = Set(decoded)
        }
    }
    
    // ✅ Load persistent sentence cache from storage
    private func loadPersistentCacheFromStorage() {
        if let decoded = try? JSONDecoder().decode([Int: Sentence].self, from: sentenceCacheData) {
            persistentSentenceCache = decoded
        }
    }
    
    // ✅ Persist sentence cache to storage
    private func savePersistentCacheToStorage() {
        if let encoded = try? JSONEncoder().encode(persistentSentenceCache) {
            sentenceCacheData = encoded
        }
    }
    
    // MARK: - Streak Integration
    func checkDailyGoalReached(newCount: Int, goal: Int, streaks: StreakService) {
        // Check if goal was just reached
        if newCount >= goal && !streaks.hasGoalToday() {
            Task {
                await streaks.recordDailyGoalReached(count: newCount, goal: goal)
            }
        }
    }
    
    // MARK: - Content Loading
    func loadContent() async {
        loadingState = .loading
        loadingProgress = 0.1
        
        startProgressAnimation()
        
        do {
            let urlString: String
            
            if let theme = selectedTheme {
                // Load theme file
                urlString = "https://d3bk01zimbieoh.cloudfront.net/text/themes/\(theme.rawValue).json"
            } else if let grammar = selectedGrammar {
                // Load grammar file
                guard let grammarURL = GrammarCatalog.urlString(for: grammar) else {
                    throw URLError(.badURL)
                }
                urlString = grammarURL
            } else {
                // Load general file (default)
                urlString = "https://d3bk01zimbieoh.cloudfront.net/text/themes/general.json"
            }
            
            let newSentences = try await DataService.fetchSentences(from: urlString)
            
            sentences = newSentences
            
            // Update global index for current sentences
            globalIndex.removeAll()
            for sentence in newSentences {
                globalIndex[sentence.id] = sentence
                // ✅ Also add to persistent cache AND save to storage
                persistentSentenceCache[sentence.id] = sentence
            }
            
            // ✅ Save persistent cache to storage after updating
            savePersistentCacheToStorage()
            
            loadingState = .loaded
            loadingProgress = 1.0
            
            // Apply current filters
            await applyCurrentFilters()
            
        } catch {
            loadingState = .error(error.localizedDescription)
            loadingProgress = 0.0
        }
        
        // Reset progress after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.loadingProgress = 0.0
        }
    }
    
    // ✅ Method to preload saved sentences that might be missing from cache
    func ensureSavedSentencesLoaded() async {
        let missingSentenceIds = saved.filter { id in
            persistentSentenceCache[id] == nil && globalIndex[id] == nil
        }
        
        guard !missingSentenceIds.isEmpty else { return }
        
        // Try to load missing sentences from different themes
        let themes = Theme.allCases
        
        for theme in themes {
            let urlString = "https://d3bk01zimbieoh.cloudfront.net/text/themes/\(theme.rawValue).json"
            
            do {
                let sentences = try await DataService.fetchSentences(from: urlString)
                var foundAny = false
                
                for sentence in sentences {
                    if missingSentenceIds.contains(sentence.id) {
                        persistentSentenceCache[sentence.id] = sentence
                        foundAny = true
                    }
                }
                
                if foundAny {
                    savePersistentCacheToStorage()
                }
                
                // If we found all missing sentences, no need to continue
                let stillMissing = missingSentenceIds.filter { id in
                    persistentSentenceCache[id] == nil
                }
                if stillMissing.isEmpty {
                    break
                }
                
            } catch {
                // Continue to next theme if this one fails
                continue
            }
        }
    }
    
    // MARK: - Selection Methods
    func selectTheme(_ theme: Theme) {
        if selectedTheme == theme {
            // Deselect current theme
            selectedTheme = nil
        } else {
            // Select new theme and clear grammar
            selectedTheme = theme
            selectedGrammar = nil
        }
        
        Task {
            await loadContent()
        }
    }
    
    func selectGrammar(_ grammar: String) {
        if selectedGrammar == grammar {
            // Deselect current grammar
            selectedGrammar = nil
        } else {
            // Select new grammar and clear theme
            selectedGrammar = grammar
            selectedTheme = nil
        }
        
        Task {
            await loadContent()
        }
    }
    
    // MARK: - Filtering Pipeline
    private func setupFilteringPipeline() {
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { _ in
                Task { await self.applyCurrentFilters() }
            }
            .store(in: &cancellables)
        
        $selectedTopic
            .removeDuplicates()
            .sink { _ in
                Task { await self.applyCurrentFilters() }
            }
            .store(in: &cancellables)
        
        // Re-filter when saved set changes
        $saved
            .sink { _ in
                Task { await self.applyCurrentFilters() }
            }
            .store(in: &cancellables)
    }
    
    private func applyCurrentFilters() async {
        filteringTask?.cancel()
        filteringState = .loading
        
        filteringTask = Task {
            let filtered = await filterSentences(
                sentences: sentences,
                searchText: searchText,
                selectedTopic: selectedTopic
            )
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                _filtered = filtered
                filteringState = .loaded
            }
        }
        
        await filteringTask?.value
    }
    
    private func filterSentences(
        sentences: [Sentence],
        searchText: String,
        selectedTopic: String?
    ) async -> [Sentence] {
        // Capture saved set on main actor before going to background
        let savedIds = saved
        
        return await Task.detached(priority: .userInitiated) {
            var filtered = sentences
            
            // FIRST: Filter out saved sentences from Home page
            filtered = filtered.filter { !savedIds.contains($0.id) }
            
            // THEN: Apply other filters
            if !searchText.isEmpty {
                filtered = filtered.filter { $0.matches(searchText) }
            }
            
            if let topic = selectedTopic {
                filtered = filtered.filter { $0.topicMatches(topic) }
            }
            
            return filtered
        }.value
    }
    
    // MARK: - Helpers
    private func startProgressAnimation() {
        loadingProgress = 0.1
        
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            Task { @MainActor in
                guard self.loadingState.isLoading else {
                    timer.invalidate()
                    return
                }
                if self.loadingProgress < 0.9 {
                    self.loadingProgress += 0.05
                }
            }
        }
    }
    
    func lookup(id: Int) -> Sentence? {
        globalIndex[id]
    }
    
    // MARK: - Save Management
    func toggleSave(_ sentence: Sentence) {
        if saved.contains(sentence.id) {
            saved.remove(sentence.id)
        } else {
            saved.insert(sentence.id)
            // ✅ Ensure sentence is in persistent cache when saved
            persistentSentenceCache[sentence.id] = sentence
            savePersistentCacheToStorage()
        }
    }
    
    // Helper to get saved sentences for SavedView
    var savedSentences: [Sentence] {
        return saved.compactMap { id in
            globalIndex[id] ?? persistentSentenceCache[id]
        }.sorted { $0.id < $1.id }
    }
    
    // MARK: - Reliable Sentence Lookup for SavedView
    // This method should work regardless of current theme/grammar selection
    func findSentence(by id: Int) -> Sentence? {
        // First check current global index
        if let sentence = globalIndex[id] {
            return sentence
        }
        
        // If not found, check persistent cache
        return persistentSentenceCache[id]
    }
    
    // MARK: - Audio
    func audioURL(for sentence: Sentence, language: AppLanguage? = nil) -> URL? {
        let targetLanguage = language ?? learningLanguage
        
        // Ensure the sentence has text in the target language
        guard sentence.text(for: targetLanguage) != nil else {
            return nil
        }
        
        let baseURL = "https://d3bk01zimbieoh.cloudfront.net/audio"
        let audioFolder = targetLanguage.audioFolder
        let audioPrefix = targetLanguage.audioPrefix
        let audioFileName = "\(audioPrefix)-\(sentence.id).mp3"
        let fullURL = "\(baseURL)/\(audioFolder)/\(audioFileName)"
        
        return URL(string: fullURL)
    }
    
    // MARK: - AI Features
    func explain(sentence: Sentence) async -> String? {
        guard let text = sentence.text(for: learningLanguage) else { return nil }
        
        aiError = nil
        let key = "explain_\(sentence.id)_\(learningLanguage.rawValue)"
        let system = "You are a helpful language teacher. Explain the grammar, vocabulary, and structure of sentences in a clear, educational way. Keep explanations concise but informative."
        let user = "Explain this \(learningLanguage.displayName) sentence: \"\(text)\""
        
        do {
            return try await ai.completeCached(key: key, system: system, user: user, maxTokens: 300)
        } catch {
            aiError = "Failed to get explanation: \(error.localizedDescription)"
            return nil
        }
    }
    
    func contextualize(sentence: Sentence) async -> String? {
        guard let text = sentence.text(for: learningLanguage) else { return nil }
        
        aiError = nil
        let key = "context_\(sentence.id)_\(learningLanguage.rawValue)"
        let system = "You are a helpful language teacher. Provide cultural context, usage situations, and practical examples for sentences. Focus on when and how native speakers would use these phrases."
        let user = "Provide context and usage examples for this \(learningLanguage.displayName) sentence: \"\(text)\""
        
        do {
            return try await ai.completeCached(key: key, system: system, user: user, maxTokens: 350)
        } catch {
            aiError = "Failed to get context: \(error.localizedDescription)"
            return nil
        }
    }
}
