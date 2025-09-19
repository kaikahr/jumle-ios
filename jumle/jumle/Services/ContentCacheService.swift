//
//  ContentCacheService.swift
//  jumle
//
//  Smart caching system for sentences, themes, and grammar content
//

import Foundation
import Combine

// MARK: - Cache Models
struct CacheEntry<T> {
    let data: T
    let timestamp: Date
    let accessCount: Int
    let lastAccessed: Date
    
    var age: TimeInterval {
        Date().timeIntervalSince(timestamp)
    }
    
    var isStale: Bool {
        age > 300 // 5 minutes
    }
    
    func accessed() -> CacheEntry<T> {
        CacheEntry(
            data: data,
            timestamp: timestamp,
            accessCount: accessCount + 1,
            lastAccessed: Date()
        )
    }
}

struct FilteredResult {
    let sentences: [Sentence]
    let searchText: String
    let selectedTopic: String?
    let selectedGrammar: String?
    let timestamp: Date
    
    func matches(search: String, topic: String?, grammar: String?) -> Bool {
        return searchText == search &&
               selectedTopic == topic &&
               selectedGrammar == grammar &&
               Date().timeIntervalSince(timestamp) < 30 // 30 seconds
    }
}

// MARK: - Content Cache Service
@MainActor
final class ContentCacheService: ObservableObject {
    static let shared = ContentCacheService()
    
    // MARK: - Cache Storage
    private var sentenceCache: [String: CacheEntry<[Sentence]>] = [:]
    private var grammarCache: [String: CacheEntry<[Sentence]>] = [:]
    private var filteredCache: [String: FilteredResult] = [:]
    
    // MARK: - Configuration
    private let maxCacheSize = 20 // Max entries per cache type
    private let backgroundQueue = DispatchQueue(label: "content.cache", qos: .utility)
    private let session = URLSession.shared
    
    // MARK: - Loading States
    @Published private(set) var loadingStates: [String: Bool] = [:]
    @Published private(set) var loadingProgress: [String: Double] = [:]
    
    private init() {
        startPeriodicCleanup()
    }
    
    // MARK: - Public API
    
    /// Load sentences for a theme with smart caching
    func loadTheme(_ themeRawValue: String) async -> Result<[Sentence], Error> {
        let key = "theme_\(themeRawValue)"
        
        // Check cache first
        if let entry = sentenceCache[key], !entry.isStale {
            sentenceCache[key] = entry.accessed()
            return .success(entry.data)
        }
        
        // Set loading state
        setLoading(key: key, isLoading: true)
        
        do {
            let sentences = try await loadThemeFromNetwork(themeRawValue)
            
            // Cache the result
            let entry = CacheEntry(
                data: sentences,
                timestamp: Date(),
                accessCount: 1,
                lastAccessed: Date()
            )
            sentenceCache[key] = entry
            
            // Manage cache size
            await cleanupCache("sentence")
            
            setLoading(key: key, isLoading: false)
            return .success(sentences)
            
        } catch {
            setLoading(key: key, isLoading: false)
            return .failure(error)
        }
    }
    
    /// Load grammar sentences with caching
    func loadGrammar(_ grammarPoint: String) async -> Result<[Sentence], Error> {
        let key = "grammar_\(grammarPoint)"
        
        // Check cache first
        if let entry = grammarCache[key], !entry.isStale {
            grammarCache[key] = entry.accessed()
            return .success(entry.data)
        }
        
        setLoading(key: key, isLoading: true)
        
        do {
            let sentences = try await loadGrammarFromNetwork(grammarPoint)
            
            let entry = CacheEntry(
                data: sentences,
                timestamp: Date(),
                accessCount: 1,
                lastAccessed: Date()
            )
            grammarCache[key] = entry
            
            await cleanupCache("grammar")
            
            setLoading(key: key, isLoading: false)
            return .success(sentences)
            
        } catch {
            setLoading(key: key, isLoading: false)
            return .failure(error)
        }
    }
    
    /// Get cached filtered results or compute them
    func getFilteredSentences(
        from sentences: [Sentence],
        searchText: String,
        selectedTopic: String?,
        selectedGrammar: String?
    ) async -> [Sentence] {
        let key = "\(searchText)_\(selectedTopic ?? "")_\(selectedGrammar ?? "")"
        
        // Check filtered cache
        if let cached = filteredCache[key],
           cached.matches(search: searchText, topic: selectedTopic, grammar: selectedGrammar) {
            return cached.sentences
        }
        
        // Compute in background
        return await withTaskGroup(of: [Sentence].self) { group in
            group.addTask {
                await self.filterSentences(
                    sentences: sentences,
                    searchText: searchText,
                    selectedTopic: selectedTopic,
                    selectedGrammar: selectedGrammar
                )
            }
            
            let filtered = await group.next() ?? []
            
            // Cache the result
            let result = FilteredResult(
                sentences: filtered,
                searchText: searchText,
                selectedTopic: selectedTopic,
                selectedGrammar: selectedGrammar,
                timestamp: Date()
            )
            
            await MainActor.run {
                self.filteredCache[key] = result
                self.cleanupFilteredCache()
            }
            
            return filtered
        }
    }
    
    /// Prefetch popular content in background
    func prefetchPopularContent() {
        Task {
            // Prefetch most common themes
            let popularThemes = ["daily_life", "travel", "work"]
            
            await withTaskGroup(of: Void.self) { group in
                for theme in popularThemes {
                    group.addTask {
                        _ = await self.loadTheme(theme)
                    }
                }
            }
        }
    }
    
    /// Check if content is loading
    func isLoading(for key: String) -> Bool {
        loadingStates[key] ?? false
    }
    
    /// Get loading progress
    func getProgress(for key: String) -> Double {
        loadingProgress[key] ?? 0.0
    }
    
    /// Clear all caches
    func clearAllCaches() {
        sentenceCache.removeAll()
        grammarCache.removeAll()
        filteredCache.removeAll()
        loadingStates.removeAll()
        loadingProgress.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func setLoading(key: String, isLoading: Bool, progress: Double = 0.0) {
        loadingStates[key] = isLoading
        if isLoading {
            loadingProgress[key] = progress
        } else {
            loadingProgress.removeValue(forKey: key)
        }
    }
    
    private func loadThemeFromNetwork(_ themeRawValue: String) async throws -> [Sentence] {
        let urlString = "https://d3bk01zimbieoh.cloudfront.net/text/themes/\(themeRawValue).json"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await session.data(from: url)
        
        // Simulate progress for better UX
        setLoading(key: "theme_\(themeRawValue)", isLoading: true, progress: 0.7)
        
        let sentences = try JSONDecoder().decode([Sentence].self, from: data)
        
        setLoading(key: "theme_\(themeRawValue)", isLoading: true, progress: 1.0)
        
        return sentences
    }
    
    private func loadGrammarFromNetwork(_ grammarPoint: String) async throws -> [Sentence] {
        guard let urlString = GrammarCatalog.urlString(for: grammarPoint),
              let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await session.data(from: url)
        
        setLoading(key: "grammar_\(grammarPoint)", isLoading: true, progress: 0.7)
        
        let sentences = try JSONDecoder().decode([Sentence].self, from: data)
        
        setLoading(key: "grammar_\(grammarPoint)", isLoading: true, progress: 1.0)
        
        return sentences
    }
    
    private func filterSentences(
        sentences: [Sentence],
        searchText: String,
        selectedTopic: String?,
        selectedGrammar: String?
    ) async -> [Sentence] {
        return await Task.detached(priority: .userInitiated) {
            var filtered = sentences
            
            // Apply search filter
            if !searchText.isEmpty {
                filtered = filtered.filter { $0.matches(searchText) }
            }
            
            // Apply topic filter
            if let topic = selectedTopic {
                filtered = filtered.filter { $0.topicMatches(topic) }
            }
            
            // Grammar filtering would happen here if needed
            // (currently handled by loading different grammar files)
            
            return filtered
        }.value
    }
    
    private func cleanupCache(_ cacheType: String) async {
        // Simplified cleanup without inout parameters
        switch cacheType {
        case "sentence":
            if sentenceCache.count > maxCacheSize {
                let sortedKeys = sentenceCache.keys.sorted { keyA, keyB in
                    let entryA = sentenceCache[keyA]!
                    let entryB = sentenceCache[keyB]!
                    return entryA.accessCount > entryB.accessCount
                }
                let keysToKeep = Set(sortedKeys.prefix(maxCacheSize - 2))
                sentenceCache = sentenceCache.filter { keysToKeep.contains($0.key) }
            }
        case "grammar":
            if grammarCache.count > maxCacheSize {
                let sortedKeys = grammarCache.keys.sorted { keyA, keyB in
                    let entryA = grammarCache[keyA]!
                    let entryB = grammarCache[keyB]!
                    return entryA.accessCount > entryB.accessCount
                }
                let keysToKeep = Set(sortedKeys.prefix(maxCacheSize - 2))
                grammarCache = grammarCache.filter { keysToKeep.contains($0.key) }
            }
        default:
            break
        }
    }
    
    private func cleanupFilteredCache() {
        // Keep only recent filtered results (last 50)
        if filteredCache.count > 50 {
            let sortedKeys = filteredCache.keys.sorted {
                filteredCache[$0]!.timestamp > filteredCache[$1]!.timestamp
            }
            let keysToKeep = Set(sortedKeys.prefix(30))
            filteredCache = filteredCache.filter { keysToKeep.contains($0.key) }
        }
    }
    
    private func startPeriodicCleanup() {
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in
                await self.cleanupCache("sentence")
                await self.cleanupCache("grammar")
                self.cleanupFilteredCache()
            }
        }
    }
}

// MARK: - Theme Extension (Remove this since Theme is now in AppState)
// Extension removed - Theme enum is now defined in AppState
