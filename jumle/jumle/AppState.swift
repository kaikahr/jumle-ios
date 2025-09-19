import SwiftUI
import Combine

enum Theme: String, CaseIterable, Identifiable {
    case emotions, food, greetings, health, hobbies, housing
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
    
    // ✅ Persistent cache of ALL sentences ever loaded (for SavedView)
    @AppStorage("sentenceCache") private var sentenceCacheData: Data = Data()
    private var persistentSentenceCache: [Int: Sentence] = [:]
    
    // Explain/Context transient UI state (per active request)
    @Published var aiIsWorking: Bool = false
    @Published var aiError: String? = nil
    
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
    
    // MARK: - Save Management - Language-Specific Saves
    
    // Legacy saved data (for migration)
    @AppStorage("savedSentences") private var legacySavedData: Data = Data()
    
    // NEW: Language-specific saves
    @AppStorage("savedByLanguage") private var savedByLanguageData: Data = Data()
    @Published private var savedByLanguage: [AppLanguage: Set<Int>] = [:] {
        didSet { saveSavedByLanguage() }
    }
    
    // Computed property that maintains compatibility with existing code
    @Published var saved: Set<Int> = [] {
        didSet { savedByLanguage[learningLanguage] = saved }
    }
    
    // MARK: - Loading States
    @Published var loadingState: LoadingState = .idle
    @Published var filteringState: LoadingState = .idle
    @Published var loadingProgress: Double = 0.0
    
    // MARK: - Computed Properties
    var filtered: [Sentence] { _filtered }
    var isLoading: Bool { loadingState.isLoading || filteringState.isLoading }
    var errorMessage: String? {
        if case .error(let message) = loadingState { return message }
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
    
    // MARK: - Languages
    @AppStorage("knownLanguage") var knownLanguage: AppLanguage = .English {
        didSet { objectWillChange.send() }
    }
    @AppStorage("learningLanguage") var learningLanguage: AppLanguage = .French {
        didSet {
            if knownLanguage == learningLanguage {
                knownLanguage = learningLanguage == .English ? .French : .English
            }
            updateSavedForCurrentLanguage()
            objectWillChange.send()
        }
    }
    
    init() {
        loadSavedFromStorage()
        loadPersistentCacheFromStorage()
        loadSavedByLanguage()
        migrateIfNeeded()
        updateSavedForCurrentLanguage()
        setupFilteringPipeline()
    }
    
    // MARK: - Language-Specific Save Methods
    
    private func updateSavedForCurrentLanguage() {
        saved = savedByLanguage[learningLanguage] ?? []
    }
    
    // Load saved sentences from persistent storage (legacy)
    private func loadSavedFromStorage() {
        _ = try? JSONDecoder().decode([Int].self, from: legacySavedData)
    }
    
    // Load language-specific saves
    private func loadSavedByLanguage() {
        guard !savedByLanguageData.isEmpty else {
            savedByLanguage = [:]
            return
        }
        do {
            let payload = try JSONDecoder().decode([String: [Int]].self, from: savedByLanguageData)
            var result: [AppLanguage: Set<Int>] = [:]
            for (langString, ids) in payload {
                if let language = AppLanguage(rawValue: langString) {
                    result[language] = Set(ids)
                }
            }
            savedByLanguage = result
            print("✅ Loaded language-specific saves: \(result.mapValues { $0.count })")
        } catch {
            print("Failed to load saved by language: \(error)")
            savedByLanguage = [:]
        }
    }
    
    private func saveSavedByLanguage() {
        do {
            var entries: [String: [Int]] = [:]
            for (language, ids) in savedByLanguage {
                entries[language.rawValue] = Array(ids)
            }
            savedByLanguageData = try JSONEncoder().encode(entries)
            print("💾 Saved language-specific saves: \(savedByLanguage.mapValues { $0.count })")
        } catch {
            print("Failed to save saved by language: \(error)")
        }
    }
    
    // Migration from legacy system
    private func migrateIfNeeded() {
        if !legacySavedData.isEmpty && savedByLanguage.isEmpty {
            if let decoded = try? JSONDecoder().decode([Int].self, from: legacySavedData) {
                let legacySaved = Set(decoded)
                print("🔄 Migrating \(legacySaved.count) legacy saves to \(learningLanguage.displayName)")
                savedByLanguage[learningLanguage] = legacySaved
                legacySavedData = Data()
                print("✅ Migration completed")
            }
        }
    }
    
    // Helper methods for language-specific save management
    func getSavedCount(for language: AppLanguage) -> Int {
        return savedByLanguage[language]?.count ?? 0
    }
    
    var languagesWithSaves: [AppLanguage] {
        return Array(savedByLanguage.keys).filter {
            (savedByLanguage[$0]?.count ?? 0) > 0
        }.sorted { $0.displayName < $1.displayName }
    }
    
    func isSavedInAnyLanguage(_ sentence: Sentence) -> Bool {
        return savedByLanguage.values.contains { $0.contains(sentence.id) }
    }
    
    func getLanguagesSavedIn(for sentence: Sentence) -> [AppLanguage] {
        return savedByLanguage.compactMap { (language, ids) in
            ids.contains(sentence.id) ? language : nil
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
        if newCount >= goal && !streaks.hasGoalToday() {
            Task { await streaks.recordDailyGoalReached(count: newCount, goal: goal) }
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
                urlString = "https://d3bk01zimbieoh.cloudfront.net/text/themes/\(theme.rawValue).json"
            } else if let grammar = selectedGrammar {
                guard let grammarURL = GrammarCatalog.urlString(for: grammar) else {
                    throw URLError(.badURL)
                }
                urlString = grammarURL
            } else {
                urlString = "https://d3bk01zimbieoh.cloudfront.net/text/themes/general.json"
            }
            
            let newSentences = try await DataService.fetchSentences(from: urlString)
            sentences = newSentences
            
            globalIndex.removeAll()
            for sentence in newSentences {
                globalIndex[sentence.id] = sentence
                persistentSentenceCache[sentence.id] = sentence
            }
            savePersistentCacheToStorage()
            
            loadingState = .loaded
            loadingProgress = 1.0
            await applyCurrentFilters()
        } catch {
            loadingState = .error(error.localizedDescription)
            loadingProgress = 0.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.loadingProgress = 0.0
        }
    }
    
    // ✅ Preload saved sentences that might be missing from cache
    func ensureSavedSentencesLoaded() async {
        let missingSentenceIds = saved.filter { id in
            persistentSentenceCache[id] == nil && globalIndex[id] == nil
        }
        guard !missingSentenceIds.isEmpty else { return }
        
        for theme in Theme.allCases {
            let urlString = "https://d3bk01zimbieoh.cloudfront.net/text/themes/\(theme.rawValue).json"
            do {
                let sentences = try await DataService.fetchSentences(from: urlString)
                var foundAny = false
                for sentence in sentences where missingSentenceIds.contains(sentence.id) {
                    persistentSentenceCache[sentence.id] = sentence
                    foundAny = true
                }
                if foundAny { savePersistentCacheToStorage() }
                let stillMissing = missingSentenceIds.filter { persistentSentenceCache[$0] == nil }
                if stillMissing.isEmpty { break }
            } catch { continue }
        }
    }
    
    // MARK: - Selection Methods
    func selectTheme(_ theme: Theme) {
        if selectedTheme == theme { selectedTheme = nil } else {
            selectedTheme = theme; selectedGrammar = nil
        }
        Task { await loadContent() }
    }
    
    func selectGrammar(_ grammar: String) {
        if selectedGrammar == grammar { selectedGrammar = nil } else {
            selectedGrammar = grammar; selectedTheme = nil
        }
        Task { await loadContent() }
    }
    
    // MARK: - Filtering Pipeline
    private func setupFilteringPipeline() {
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { _ in Task { await self.applyCurrentFilters() } }
            .store(in: &cancellables)
        
        $selectedTopic
            .removeDuplicates()
            .sink { _ in Task { await self.applyCurrentFilters() } }
            .store(in: &cancellables)
        
        $saved
            .sink { _ in Task { await self.applyCurrentFilters() } }
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
        let savedIds = saved
        return await Task.detached(priority: .userInitiated) {
            var filtered = sentences
            filtered = filtered.filter { !savedIds.contains($0.id) }
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
                guard self.loadingState.isLoading else { timer.invalidate(); return }
                if self.loadingProgress < 0.9 { self.loadingProgress += 0.05 }
            }
        }
    }
    
    func lookup(id: Int) -> Sentence? {
        globalIndex[id]
    }
    
    // MARK: - Save Management (subscription-aware)
    /// Toggle saved state for the current learning language.
    /// - Parameter subscriptionManager: Optional. If provided, the free plan limit is enforced and paywall may be shown.
    func toggleSave(_ sentence: Sentence, subscriptionManager: SubscriptionManager? = nil) {
        // Only allow saving if the sentence has text in the current learning language
        guard sentence.text(for: learningLanguage) != nil else {
            print("⚠️ Cannot save sentence \(sentence.id) - no text in \(learningLanguage.displayName)")
            return
        }
        
        if saved.contains(sentence.id) {
            // Unsaving is always allowed
            saved.remove(sentence.id)
            print("📤 Unsaved sentence \(sentence.id) from \(learningLanguage.displayName)")
            return
        }
        
        // About to save
        if let manager = subscriptionManager {
            // Enforce free-plan daily limit when manager is present
            guard manager.canSaveSentence() else {
                // Free limit hit → show paywall and abort
                manager.showPaywallForFeature("save")
                return
            }
        }
        
        // Perform save
        saved.insert(sentence.id)
        print("📥 Saved sentence \(sentence.id) in \(learningLanguage.displayName)")
        
        // Ensure cached
        persistentSentenceCache[sentence.id] = sentence
        savePersistentCacheToStorage()
        
        // Record usage (whether free or premium—useful for UI)
        subscriptionManager?.recordSentenceSaved()
    }
    
    // Helper to get saved sentences for SavedView - language aware
    var savedSentences: [Sentence] {
        return saved.compactMap { id in
            let sentence = globalIndex[id] ?? persistentSentenceCache[id]
            if let sentence = sentence, sentence.text(for: learningLanguage) != nil {
                return sentence
            }
            return nil
        }.sorted { $0.id < $1.id }
    }
    
    // Reliable Sentence Lookup for SavedView
    func findSentence(by id: Int) -> Sentence? {
        if let sentence = globalIndex[id] { return sentence }
        return persistentSentenceCache[id]
    }
    
    // MARK: - Audio
    func audioURL(for sentence: Sentence, language: AppLanguage? = nil) -> URL? {
        let targetLanguage = language ?? learningLanguage
        guard sentence.text(for: targetLanguage) != nil else { return nil }
        
        let baseURL = "https://d3bk01zimbieoh.cloudfront.net/audio"
        let audioFolder = targetLanguage.audioFolder
        let audioPrefix = targetLanguage.audioPrefix
        let audioFileName = "\(audioPrefix)-\(sentence.id).mp3"
        let fullURL = "\(baseURL)/\(audioFolder)/\(audioFileName)"
        return URL(string: fullURL)
    }
    
    // MARK: - AI: Explain & Context (text responses)
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
            return try await OpenAIService.shared.completeTextCached(
                key: key, system: system, user: user, maxTokens: 350, temperature: 0.2
            )
        } catch {
            aiError = (error as NSError).localizedDescription
            return "Sorry—couldn't generate an explanation."
        }
    }
    
    func contextualize(sentence: Sentence) async -> String {
        aiIsWorking = true
        aiError = nil
        defer { aiIsWorking = false }
        
        let main = sentence.text(for: learningLanguage) ?? ""
        let known = knownLanguage.displayName
        
        let system = """
        You write short, vivid contexts (dialogues or mini-paragraphs) that make a target sentence feel natural. Keep it beginner-friendly and use simple vocabulary. Provide the output in the user's LEARNING language with translation provided in the user's KNOWN language.
        """
        let user = """
        Known language: \(known)
        Target sentence (keep exactly as-is when used): \(main)

        Task: Create a short dialogues or mini-paragraphs that naturally includes the target sentence once. The dialogue or mini-paragraph should be in the same language as \(main), then present the translation in \(known), the aim is to provide usage guide and familiarize the learner with the sentence.).
        """
        let key = "context:v1:\(known):\(main.hashValue)"
        do {
            return try await OpenAIService.shared.completeTextCached(
                key: key, system: system, user: user, maxTokens: 420, temperature: 0.4
            )
        } catch {
            aiError = (error as NSError).localizedDescription
            return "Sorry—couldn't generate context."
        }
    }
}
