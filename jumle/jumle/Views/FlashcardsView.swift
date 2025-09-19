// File: Views/FlashcardsView.swift - Complete Rebuild
import SwiftUI
import AVFoundation

// MARK: - Enhanced Models

enum QuizQuestionType: String, CaseIterable {
    case sentenceToTranslationPuzzle = "sentence_to_translation"
    case translationToSentencePuzzle = "translation_to_sentence"
    case fillInTheBlank = "fill_blank"
    case audioToSentence = "audio_to_sentence"
    
    var displayName: String {
        switch self {
        case .sentenceToTranslationPuzzle: return "Sentence → Translation"
        case .translationToSentencePuzzle: return "Translation → Sentence"
        case .fillInTheBlank: return "Fill in the Blank"
        case .audioToSentence: return "Audio Recognition"
        }
    }
}

struct QuizQuestion: Identifiable {
    let id = UUID()
    let type: QuizQuestionType
    let sentence: Sentence
    let prompt: String
    let correctAnswer: String
    let puzzlePieces: [String]? // For puzzle questions
    let multipleChoiceOptions: [String]? // For fill-in-blank and audio questions
    let correctChoiceIndex: Int? // Index of correct answer in multiple choice
    let blankWord: String? // The missing word for fill-in-blank
    let audioURL: URL? // For audio questions
}

struct FlashcardEntry {
    let sentenceId: Int
    var interval: Int // in hours
    var nextReview: Date
    var difficulty: Int // 0 = easy, 1 = medium, 2 = hard
    
    static let intervals = [1, 4, 12, 24, 48, 168, 336, 720] // hours: 1h, 4h, 12h, 1d, 2d, 1w, 2w, 1m
}

// MARK: - Quiz Engine

class QuizEngine {
    func generateQuiz(from sentences: [Sentence], savedIds: Set<Int>, recentSavedIds: Set<Int>, learningLang: AppLanguage, knownLang: AppLanguage) -> [QuizQuestion] {
        
        // Filter to sentences with both languages
        let availableSentences = sentences.filter { sentence in
            savedIds.contains(sentence.id) &&
            sentence.text(for: learningLang) != nil &&
            sentence.text(for: knownLang) != nil
        }
        
        guard !availableSentences.isEmpty else { return [] }
        
        var questions: [QuizQuestion] = []
        let totalQuestions = 15
        let recentQuestionCount = min(totalQuestions / 2, recentSavedIds.count)
        
        // Get recent sentences (last week)
        let recentSentences = availableSentences.filter { recentSavedIds.contains($0.id) }
        let otherSentences = availableSentences.filter { !recentSavedIds.contains($0.id) }
        
        // Select sentences for quiz
        var selectedSentences: [Sentence] = []
        selectedSentences.append(contentsOf: Array(recentSentences.shuffled().prefix(recentQuestionCount)))
        
        let remainingCount = totalQuestions - selectedSentences.count
        selectedSentences.append(contentsOf: Array(otherSentences.shuffled().prefix(remainingCount)))
        
        // Ensure we have enough sentences
        while selectedSentences.count < totalQuestions && selectedSentences.count < availableSentences.count {
            let remaining = availableSentences.filter { sentence in
                !selectedSentences.contains { $0.id == sentence.id }
            }
            if let additional = remaining.randomElement() {
                selectedSentences.append(additional)
            } else {
                break
            }
        }
        
        // Generate questions
        for sentence in selectedSentences.prefix(totalQuestions) {
            if let question = generateQuestion(for: sentence, allSentences: sentences, learningLang: learningLang, knownLang: knownLang) {
                questions.append(question)
            }
        }
        
        return questions.shuffled()
    }
    
    private func generateQuestion(for sentence: Sentence, allSentences: [Sentence], learningLang: AppLanguage, knownLang: AppLanguage) -> QuizQuestion? {
        
        guard let originalText = sentence.text(for: learningLang),
              let translationText = sentence.text(for: knownLang) else {
            return nil
        }
        
        let questionType = QuizQuestionType.allCases.randomElement() ?? .sentenceToTranslationPuzzle
        
        switch questionType {
        case .sentenceToTranslationPuzzle:
            // UPDATED: pass allSentences so we can add extra pieces from other translations
            return createSentenceToTranslationPuzzle(
                sentence: sentence,
                translationText: translationText,
                allSentences: allSentences,
                knownLang: knownLang
            )
            
        case .translationToSentencePuzzle:
            return createTranslationToSentencePuzzle(sentence: sentence, originalText: originalText, translationText: translationText, learningLang: learningLang, knownLang: knownLang)
            
        case .fillInTheBlank:
            return createFillInTheBlank(sentence: sentence, originalText: originalText, allSentences: allSentences, learningLang: learningLang)
            
        case .audioToSentence:
            return createAudioToSentence(sentence: sentence, originalText: originalText, allSentences: allSentences, learningLang: learningLang, knownLang: knownLang)
        }
    }
    
    // UPDATED: Inject extra (distractor) pieces from other sentences' translations
        private func createSentenceToTranslationPuzzle(
            sentence: Sentence,
            translationText: String,
            allSentences: [Sentence],
            knownLang: AppLanguage
        ) -> QuizQuestion {
            // Base pieces from the correct translation
            var pieces = createPuzzlePieces(from: translationText)
            
            // Build a pool of candidate distractor tokens from OTHER sentences' translations
            var distractorPool: [String] = []
            let targetLen = translationText.count
            
            for other in allSentences.shuffled() {
                guard other.id != sentence.id, let t = other.text(for: knownLang) else { continue }
                // Prefer similar-length sentences (±30%)
                if t.count > Int(Double(targetLen) * 0.7) && t.count < Int(Double(targetLen) * 1.3) {
                    let toks = createPuzzlePieces(from: t)
                        .filter { tok in
                            // Avoid pure punctuation-only tokens
                            !(tok.count == 1 && (tok.first?.isPunctuation == true))
                        }
                    distractorPool.append(contentsOf: toks)
                }
                if distractorPool.count >= 200 { break } // cap pool size
            }
            
            // Remove tokens that are exactly the same as trailing punctuation-only pieces like ".", ","
            // (We already filtered punctuation-only above for distractors.)
            
            // Decide how many extra tokens to add: 50% of correct piece count, between 4 and 10
            let minExtra = 4
            let maxExtra = 10
            let desiredExtra = min(max(pieces.count / 2, minExtra), maxExtra)
            
            if !distractorPool.isEmpty {
                // Favor unique distractors not already in the answer to increase confusion
                var uniquePool = Array(Set(distractorPool))
                // Remove obvious duplicates of entire answer tokens only a little to keep some noise
                let answerSet = Set(pieces)
                uniquePool.removeAll(where: { answerSet.contains($0) })
                
                let chosenFromUnique = Array(uniquePool.shuffled().prefix(desiredExtra))
                var extras = chosenFromUnique
                
                // If we still need more, allow some duplicates/noise from the raw pool
                if extras.count < desiredExtra {
                    let remaining = desiredExtra - extras.count
                    extras.append(contentsOf: Array(distractorPool.shuffled().prefix(remaining)))
                }
                
                pieces.append(contentsOf: extras)
            }
            
            return QuizQuestion(
                        type: .sentenceToTranslationPuzzle,
                        sentence: sentence,
                        prompt: "Arrange the pieces to form the correct translation:",
                        correctAnswer: translationText,
                        puzzlePieces: pieces.shuffled(),
                        multipleChoiceOptions: nil,
                        correctChoiceIndex: nil,
                        blankWord: nil,
                        audioURL: nil
                    )
                }
    
    private func createTranslationToSentencePuzzle(sentence: Sentence, originalText: String, translationText: String, learningLang: AppLanguage, knownLang: AppLanguage) -> QuizQuestion {
        
        let pieces = createPuzzlePieces(from: originalText)
        
        return QuizQuestion(
            type: .translationToSentencePuzzle,
            sentence: sentence,
            prompt: "Arrange the pieces to form the correct sentence:",
            correctAnswer: originalText,
            puzzlePieces: pieces.shuffled(),
            multipleChoiceOptions: nil,
            correctChoiceIndex: nil,
            blankWord: nil,
            audioURL: nil
        )
    }
    
    private func createFillInTheBlank(sentence: Sentence, originalText: String, allSentences: [Sentence], learningLang: AppLanguage) -> QuizQuestion? {
        
        let words = originalText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard words.count > 2 else { return nil }
        
        // Pick a content word (longer than 3 characters)
        let contentWords = words.filter { $0.count > 3 }
        guard let blankWord = contentWords.randomElement() else {
            guard let blankWord = words.randomElement() else { return nil }
            return createFillQuestion(sentence: sentence, originalText: originalText, blankWord: blankWord, allSentences: allSentences, learningLang: learningLang)
        }
        
        return createFillQuestion(sentence: sentence, originalText: originalText, blankWord: blankWord, allSentences: allSentences, learningLang: learningLang)
    }
    
    private func createFillQuestion(sentence: Sentence, originalText: String, blankWord: String, allSentences: [Sentence], learningLang: AppLanguage) -> QuizQuestion {
        
        let sentenceWithBlank = originalText.replacingOccurrences(of: blankWord, with: "_____")
        
        // Get distractors
        var distractors = Set<String>()
        for sentence in allSentences.shuffled() {
            if let text = sentence.text(for: learningLang) {
                let words = text.components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty &&
                             $0.count >= blankWord.count - 1 &&
                             $0.count <= blankWord.count + 2 }
                distractors.formUnion(words)
            }
            if distractors.count >= 10 { break }
        }
        
        distractors.remove(blankWord)
        let selectedDistractors = Array(distractors.shuffled().prefix(2))
        
        var options = selectedDistractors + [blankWord]
        options.shuffle()
        
        let correctIndex = options.firstIndex(of: blankWord) ?? 0
        
        return QuizQuestion(
            type: .fillInTheBlank,
            sentence: sentence,
            prompt: sentenceWithBlank,
            correctAnswer: blankWord,
            puzzlePieces: nil,
            multipleChoiceOptions: options,
            correctChoiceIndex: correctIndex,
            blankWord: blankWord,
            audioURL: nil
        )
    }
    
    private func createAudioToSentence(sentence: Sentence, originalText: String, allSentences: [Sentence], learningLang: AppLanguage, knownLang: AppLanguage) -> QuizQuestion? {
        
        // Get audio URL
        let baseURL = "https://d3bk01zimbieoh.cloudfront.net/audio"
        let audioFolder = learningLang.audioFolder
        let audioPrefix = learningLang.audioPrefix
        let audioFileName = "\(audioPrefix)-\(sentence.id).mp3"
        let fullURL = "\(baseURL)/\(audioFolder)/\(audioFileName)"
        
        guard let audioURL = URL(string: fullURL) else { return nil }
        
        // Get distractors
        var distractors: [String] = []
        for distractor in allSentences.shuffled() {
            if distractor.id != sentence.id,
               let text = distractor.text(for: learningLang),
               text.count > Int(Double(originalText.count) * 0.7) && text.count < Int(Double(originalText.count) * 1.3) {
                distractors.append(text)
            }
            if distractors.count >= 3 { break }
        }
        
        // Ensure we have enough options
        while distractors.count < 3 {
            if let randomSentence = allSentences.randomElement(),
               let text = randomSentence.text(for: learningLang),
               text != originalText && !distractors.contains(text) {
                distractors.append(text)
            }
        }
        
        var options = Array(distractors.prefix(3)) + [originalText]
        options.shuffle()
        
        let correctIndex = options.firstIndex(of: originalText) ?? 0
        
        return QuizQuestion(
            type: .audioToSentence,
            sentence: sentence,
            prompt: "Listen to the audio and select the correct sentence:",
            correctAnswer: originalText,
            puzzlePieces: nil,
            multipleChoiceOptions: options,
            correctChoiceIndex: correctIndex,
            blankWord: nil,
            audioURL: audioURL
        )
    }
    
    private func createPuzzlePieces(from text: String) -> [String] {
        // Handle Japanese text differently since it doesn't use spaces
        if containsJapanese(text) {
            return createJapanesePuzzlePieces(from: text)
        }
        
        // For other languages, split by spaces
        let words = text.components(separatedBy: " ").filter { !$0.isEmpty }
        var pieces: [String] = []
        
        for word in words {
            // Check if word has punctuation at the end
            if word.count > 1 && (word.last?.isPunctuation == true) {
                let wordPart = String(word.dropLast())
                let punctPart = String(word.last!)
                if !wordPart.isEmpty {
                    pieces.append(wordPart)
                }
                pieces.append(punctPart)
            } else {
                pieces.append(word)
            }
        }
        
        return pieces
    }
    
    // MARK: - Japanese Text Processing for Quiz Engine
    
    private func containsJapanese(_ text: String) -> Bool {
        for char in text {
            let scalar = char.unicodeScalars.first?.value ?? 0
            // Check for Hiragana, Katakana, and CJK Unified Ideographs ranges
            if (scalar >= 0x3040 && scalar <= 0x309F) ||  // Hiragana
               (scalar >= 0x30A0 && scalar <= 0x30FF) ||  // Katakana
               (scalar >= 0x4E00 && scalar <= 0x9FAF) {   // CJK Unified Ideographs (Kanji)
                return true
            }
        }
        return false
    }
    
    private func createJapanesePuzzlePieces(from text: String) -> [String] {
        var pieces: [String] = []
        var currentPiece = ""
        var i = text.startIndex
        
        while i < text.endIndex {
            let char = text[i]
            let scalar = char.unicodeScalars.first?.value ?? 0
            
            // Determine character type
            let charType = getJapaneseCharType(scalar)
            
            if !currentPiece.isEmpty {
                let lastScalar = currentPiece.last?.unicodeScalars.first?.value ?? 0
                let lastCharType = getJapaneseCharType(lastScalar)
                
                // Split when character type changes, except for some special cases
                if shouldSplitJapanese(from: lastCharType, to: charType, currentChar: char) {
                    pieces.append(currentPiece)
                    currentPiece = String(char)
                } else {
                    currentPiece.append(char)
                }
            } else {
                currentPiece.append(char)
            }
            
            i = text.index(after: i)
        }
        
        if !currentPiece.isEmpty {
            pieces.append(currentPiece)
        }
        
        // Post-process to create reasonable chunks (2-4 characters each)
        return optimizeJapanesePieces(pieces)
    }
    
    private enum JapaneseCharType {
        case hiragana, katakana, kanji, punctuation, ascii, other
    }
    
    private func getJapaneseCharType(_ scalar: UInt32) -> JapaneseCharType {
        switch scalar {
        case 0x3040...0x309F: return .hiragana
        case 0x30A0...0x30FF: return .katakana
        case 0x4E00...0x9FAF: return .kanji
        case 0x3000...0x303F: return .punctuation  // CJK punctuation
        case 0x0020...0x007F: return .ascii
        default: return .other
        }
    }
    
    private func shouldSplitJapanese(from lastType: JapaneseCharType, to currentType: JapaneseCharType, currentChar: Character) -> Bool {
        // Always split on punctuation
        if currentType == .punctuation {
            return true
        }
        
        // Split when transitioning between different script types
        switch (lastType, currentType) {
        case (.kanji, .hiragana): return true    // Kanji to Hiragana (often word boundary)
        case (.hiragana, .kanji): return true    // Hiragana to Kanji
        case (.katakana, .hiragana): return true // Katakana to Hiragana
        case (.hiragana, .katakana): return true // Hiragana to Katakana
        case (.kanji, .katakana): return true    // Kanji to Katakana
        case (.katakana, .kanji): return true    // Katakana to Kanji
        case (.ascii, _): return true            // ASCII to Japanese
        case (_, .ascii): return true            // Japanese to ASCII
        default: return false
        }
    }
    
    private func optimizeJapanesePieces(_ pieces: [String]) -> [String] {
        var optimized: [String] = []
        var i = 0
        
        while i < pieces.count {
            var currentChunk = pieces[i]
            
            // Try to combine very short pieces (single characters) with adjacent pieces
            if currentChunk.count == 1 && i + 1 < pieces.count {
                let nextPiece = pieces[i + 1]
                
                // Combine if it creates a reasonable chunk (2-3 characters)
                if currentChunk.count + nextPiece.count <= 3 {
                    currentChunk += nextPiece
                    i += 1 // Skip the next piece since we combined it
                }
            }
            
            optimized.append(currentChunk)
            i += 1
        }
        
        // Ensure we have at least 3 pieces for a good puzzle
        if optimized.count < 3 && !pieces.isEmpty {
            // Fall back to splitting into individual characters for very short sentences
            let text = pieces.joined()
            if text.count >= 3 {
                return text.map { String($0) }.filter { !$0.isEmpty }
            }
        }
        
        return optimized
    }
}
    
    private func createJapanesePuzzlePieces(from text: String) -> [String] {
        var pieces: [String] = []
        var currentPiece = ""
        var i = text.startIndex
        
        while i < text.endIndex {
            let char = text[i]
            let scalar = char.unicodeScalars.first?.value ?? 0
            
            // Determine character type
            let charType = getJapaneseCharType(scalar)
            
            if !currentPiece.isEmpty {
                let lastScalar = currentPiece.last?.unicodeScalars.first?.value ?? 0
                let lastCharType = getJapaneseCharType(lastScalar)
                
                // Split when character type changes, except for some special cases
                if shouldSplitJapanese(from: lastCharType, to: charType, currentChar: char) {
                    pieces.append(currentPiece)
                    currentPiece = String(char)
                } else {
                    currentPiece.append(char)
                }
            } else {
                currentPiece.append(char)
            }
            
            i = text.index(after: i)
        }
        
        if !currentPiece.isEmpty {
            pieces.append(currentPiece)
        }
        
        // Post-process to create reasonable chunks (2-4 characters each)
        return optimizeJapanesePieces(pieces)
    }
    
    private enum JapaneseCharType {
        case hiragana, katakana, kanji, punctuation, ascii, other
    }
    
    private func getJapaneseCharType(_ scalar: UInt32) -> JapaneseCharType {
        switch scalar {
        case 0x3040...0x309F: return .hiragana
        case 0x30A0...0x30FF: return .katakana
        case 0x4E00...0x9FAF: return .kanji
        case 0x3000...0x303F: return .punctuation  // CJK punctuation
        case 0x0020...0x007F: return .ascii
        default: return .other
        }
    }
    
    private func shouldSplitJapanese(from lastType: JapaneseCharType, to currentType: JapaneseCharType, currentChar: Character) -> Bool {
        // Always split on punctuation
        if currentType == .punctuation {
            return true
        }
        
        // Split when transitioning between different script types
        switch (lastType, currentType) {
        case (.kanji, .hiragana): return true    // Kanji to Hiragana (often word boundary)
        case (.hiragana, .kanji): return true    // Hiragana to Kanji
        case (.katakana, .hiragana): return true // Katakana to Hiragana
        case (.hiragana, .katakana): return true // Hiragana to Katakana
        case (.kanji, .katakana): return true    // Kanji to Katakana
        case (.katakana, .kanji): return true    // Katakana to Kanji
        case (.ascii, _): return true            // ASCII to Japanese
        case (_, .ascii): return true            // Japanese to ASCII
        default: return false
        }
    }
    
    private func optimizeJapanesePieces(_ pieces: [String]) -> [String] {
        var optimized: [String] = []
        var i = 0
        
        while i < pieces.count {
            var currentChunk = pieces[i]
            
            // Try to combine very short pieces (single characters) with adjacent pieces
            if currentChunk.count == 1 && i + 1 < pieces.count {
                let nextPiece = pieces[i + 1]
                
                // Combine if it creates a reasonable chunk (2-3 characters)
                if currentChunk.count + nextPiece.count <= 3 {
                    currentChunk += nextPiece
                    i += 1 // Skip the next piece since we combined it
                }
            }
            
            optimized.append(currentChunk)
            i += 1
        }
        
        // Ensure we have at least 3 pieces for a good puzzle
        if optimized.count < 3 && !pieces.isEmpty {
            // Fall back to splitting into individual characters for very short sentences
            let text = pieces.joined()
            if text.count >= 3 {
                return text.map { String($0) }.filter { !$0.isEmpty }
            }
        }
        
        return optimized
    }


// MARK: - Spaced Repetition Manager

@MainActor
class SpacedRepetitionManager: ObservableObject {
    @Published private(set) var flashcards: [Int: FlashcardEntry] = [:]
    private let userDefaults = UserDefaults.standard
    
    private var storageKey: String {
        "flashcards_v2" // v2 to reset old data
    }
    
    init() {
        loadFlashcards()
    }
    
    func loadFlashcards() {
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Int: FlashcardEntry].self, from: data) {
            flashcards = decoded
        }
    }
    
    func saveFlashcards() {
        if let encoded = try? JSONEncoder().encode(flashcards) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }
    
    func getDueFlashcards(from sentences: [Sentence], savedIds: Set<Int>) -> [Sentence] {
        let now = Date()
        var dueIds: [Int] = []
        
        for sentenceId in savedIds {
            if let entry = flashcards[sentenceId] {
                if entry.nextReview <= now {
                    dueIds.append(sentenceId)
                }
            } else {
                // New card, immediately due
                dueIds.append(sentenceId)
            }
        }
        
        // Sort by next review time (earliest first)
        dueIds.sort { id1, id2 in
            let time1 = flashcards[id1]?.nextReview ?? Date.distantPast
            let time2 = flashcards[id2]?.nextReview ?? Date.distantPast
            return time1 < time2
        }
        
        return sentences.filter { dueIds.contains($0.id) }
    }
    
    func markCardKnown(_ sentenceId: Int) {
        let now = Date()
        
        if var entry = flashcards[sentenceId] {
            // Increase interval
            let currentIntervalIndex = FlashcardEntry.intervals.firstIndex(of: entry.interval) ?? 0
            let nextIntervalIndex = min(currentIntervalIndex + 1, FlashcardEntry.intervals.count - 1)
            entry.interval = FlashcardEntry.intervals[nextIntervalIndex]
            entry.nextReview = Calendar.current.date(byAdding: .hour, value: entry.interval, to: now) ?? now
            entry.difficulty = max(0, entry.difficulty - 1)
            flashcards[sentenceId] = entry
        } else {
            // New card marked as known
            let entry = FlashcardEntry(
                sentenceId: sentenceId,
                interval: FlashcardEntry.intervals[1], // Start with 4 hours
                nextReview: Calendar.current.date(byAdding: .hour, value: FlashcardEntry.intervals[1], to: now) ?? now,
                difficulty: 0
            )
            flashcards[sentenceId] = entry
        }
        
        saveFlashcards()
    }
    
    func markCardUnknown(_ sentenceId: Int) {
        let now = Date()
        
        // Reset to 1 hour interval
        let entry = FlashcardEntry(
            sentenceId: sentenceId,
            interval: FlashcardEntry.intervals[0], // 1 hour
            nextReview: Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now,
            difficulty: min(2, (flashcards[sentenceId]?.difficulty ?? 0) + 1)
        )
        flashcards[sentenceId] = entry
        saveFlashcards()
    }
    
    func getNextReviewTime(for sentenceId: Int) -> Date? {
        return flashcards[sentenceId]?.nextReview
    }
}

// MARK: - Main FlashcardsView

struct FlashcardsView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var audio: AudioPlayerService
    @State private var selectedTab: Int = 0
    
    private let tabs = ["Quiz", "Flashcards"]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Fixed position tab selector
                VStack(spacing: 0) {
                    Picker("Mode", selection: $selectedTab) {
                        ForEach(0..<tabs.count, id: \.self) { index in
                            Text(tabs[index]).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    
                    Divider()
                }
                .background(.ultraThinMaterial)
                
                // Content area
                if selectedTab == 0 {
                    QuizContentView()
                        .environmentObject(app)
                        .environmentObject(audio)
                } else {
                    FlashcardContentView()
                        .environmentObject(app)
                        .environmentObject(audio)
                }
            }
            .navigationTitle("Study")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - Quiz Content View

struct QuizContentView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var audio: AudioPlayerService
    @EnvironmentObject private var streaks: StreakService  // Add this line
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    
    @State private var questions: [QuizQuestion] = []
    @State private var currentQuestionIndex = 0
    @State private var score = 0
    @State private var showFeedback = false
    @State private var isCorrect = false
    @State private var isQuizComplete = false
    @State private var userAnswer = ""
    @State private var selectedPieces: [String] = []
    @State private var availablePieces: [String] = []
    @State private var selectedChoiceIndex: Int? = nil
    @State private var feedbackMessage = ""
    
    var body: some View {
        VStack(spacing: 0) {
            if !subscriptionManager.isPremium {
                            usageIndicator
                        }
            if questions.isEmpty {
                generateQuizView
            } else if isQuizComplete {
                quizResultsView
            } else {
                VStack(spacing: 16) {
                    // Progress indicator
                    progressView
                    
                    // Question content
                    ScrollView {
                        VStack(spacing: 20) {
                            questionView
                            
                            if showFeedback {
                                feedbackView
                            }
                        }
                        .padding()
                    }
                }
            }
        }
    }
    
    private var usageIndicator: some View {
           HStack {
               Image(systemName: "brain.head.profile")
                   .foregroundStyle(.blue)
               
               Text(subscriptionManager.getUsageStatus(for: "quiz"))
                   .font(.caption)
                   .foregroundStyle(.secondary)
               
               Spacer()
               
               if !subscriptionManager.canTakeQuiz() {
                   Button("Upgrade") {
                       subscriptionManager.showPaywallForFeature("quiz")
                   }
                   .font(.caption)
                   .buttonStyle(.borderedProminent)
                   .controlSize(.mini)
               }
           }
           .padding(.horizontal, 16)
           .padding(.vertical, 8)
           .background(.ultraThinMaterial)
       }
    
    private var generateQuizView: some View {
        VStack(spacing: 24) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundStyle(.blue.gradient)
            
            Text("Ready for a Quiz?")
                .font(.title2.weight(.semibold))
            
            Text("Test your knowledge with 15 questions based on your saved sentences.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Generate Quiz") {
                   guard subscriptionManager.canTakeQuiz() else {
                       subscriptionManager.showPaywallForFeature("quiz")
                       return
                   }
                   generateQuiz()
               }
               .buttonStyle(StablePillButtonStyle(fill: Color.blue, height: 50))
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $subscriptionManager.showPaywall) {
                    SubscriptionPaywallView()
                        .environmentObject(subscriptionManager)
                }
    }
    
    private var progressView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Question \(currentQuestionIndex + 1) of \(questions.count)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("Score: \(score)/\(currentQuestionIndex + (showFeedback ? 1 : 0))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            
            ProgressView(value: Double(currentQuestionIndex + (showFeedback ? 1 : 0)), total: Double(questions.count))
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    @ViewBuilder
    private var questionView: some View {
        if currentQuestionIndex < questions.count {
            let question = questions[currentQuestionIndex]
            
            VStack(spacing: 20) {
                // Question type indicator
                Text(question.type.displayName)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
                
                // Question content based on type
                switch question.type {
                case .sentenceToTranslationPuzzle:
                    sentenceToTranslationView(question: question)
                case .translationToSentencePuzzle:
                    translationToSentenceView(question: question)
                case .fillInTheBlank:
                    fillInTheBlankView(question: question)
                case .audioToSentence:
                    audioToSentenceView(question: question)
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
    
    private func sentenceToTranslationView(question: QuizQuestion) -> some View {
        VStack(spacing: 16) {
            // Show original sentence
            VStack(spacing: 12) {
                if let originalText = question.sentence.text(for: app.learningLanguage) {
                    Text(originalText)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                
                // Audio button
                Button {
                    playAudio(for: question.sentence)
                } label: {
                    Label("Play Audio", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(StablePillButtonStyle(fill: Color.green.opacity(0.1), height: 40))
            }
            
            Text(question.prompt)
                .font(.headline)
            
            puzzleView(question: question)
        }
    }
    
    private func translationToSentenceView(question: QuizQuestion) -> some View {
        VStack(spacing: 16) {
            // Show translation
            VStack(spacing: 12) {
                if let translation = question.sentence.text(for: app.knownLanguage) {
                    Text(translation)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                
                // Audio button
                Button {
                    playAudio(for: question.sentence)
                } label: {
                    Label("Play Audio", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(StablePillButtonStyle(fill: Color.green.opacity(0.1), height: 40))
            }
            
            Text(question.prompt)
                .font(.headline)
            
            puzzleView(question: question)
        }
    }
    
    private func fillInTheBlankView(question: QuizQuestion) -> some View {
        VStack(spacing: 16) {
            Text(question.prompt)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            
            Text("Choose the correct word:")
                .font(.headline)
            
            if let options = question.multipleChoiceOptions {
                VStack(spacing: 10) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Button {
                            selectChoice(index: index, for: question)
                        } label: {
                            HStack {
                                Text(option)
                                    .font(.body)
                                Spacer()
                                if selectedChoiceIndex == index {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedChoiceIndex == index ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedChoiceIndex == index ? Color.blue : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(showFeedback)
                    }
                }
            }
            
            if selectedChoiceIndex != nil && !showFeedback {
                Button("Submit Answer") {
                    checkAnswer(for: question)
                }
                .buttonStyle(StablePillButtonStyle(fill: Color.blue, height: 44))
            }
        }
    }
    
    private func audioToSentenceView(question: QuizQuestion) -> some View {
        VStack(spacing: 16) {
            // Audio player
            VStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue.gradient)
                
                Button {
                    if let audioURL = question.audioURL {
                        playAudioFromURL(audioURL)
                    }
                } label: {
                    Label("Play Audio", systemImage: "play.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(StablePillButtonStyle(fill: Color.blue.opacity(0.1), height: 50))
            }
            
            Text(question.prompt)
                .font(.headline)
            
            if let options = question.multipleChoiceOptions {
                VStack(spacing: 10) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Button {
                            selectChoice(index: index, for: question)
                        } label: {
                            HStack {
                                Text(option)
                                    .font(.body)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                if selectedChoiceIndex == index {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedChoiceIndex == index ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedChoiceIndex == index ? Color.blue : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(showFeedback)
                    }
                }
            }
            
            if selectedChoiceIndex != nil && !showFeedback {
                Button("Submit Answer") {
                    checkAnswer(for: question)
                }
                .buttonStyle(StablePillButtonStyle(fill: Color.blue, height: 44))
            }
        }
    }
    
    private func puzzleView(question: QuizQuestion) -> some View {
        VStack(spacing: 16) {
            // Selected pieces area
            VStack(spacing: 8) {
                Text("Your Answer:")
                    .font(.subheadline.weight(.medium))
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(selectedPieces.enumerated()), id: \.offset) { index, piece in
                            PuzzlePiece(text: piece, isSelected: true) {
                                removePiece(at: index)
                            }
                        }
                        
                        if selectedPieces.isEmpty {
                            Text("Tap pieces below to build your answer")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(minHeight: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.tertiarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.separator), lineWidth: 1)
                        )
                )
            }
            
            // Available pieces
            VStack(spacing: 8) {
                Text("Available Pieces:")
                    .font(.subheadline.weight(.medium))
                
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 80), spacing: 8)
                ], spacing: 8) {
                    ForEach(availablePieces, id: \.self) { piece in
                        PuzzlePiece(text: piece, isSelected: false) {
                            addPiece(piece)
                        }
                    }
                }
            }
            
            // Submit button
            if !selectedPieces.isEmpty && !showFeedback {
                Button("Submit Answer") {
                    checkPuzzleAnswer(for: question)
                }
                .buttonStyle(StablePillButtonStyle(fill: Color.blue, height: 44))
            }
        }
    }
    
    private var feedbackView: some View {
        VStack(spacing: 16) {
            // Feedback message
            HStack {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isCorrect ? .green : .red)
                
                Text(feedbackMessage)
                    .font(.headline)
                    .foregroundStyle(isCorrect ? .green : .red)
            }
            
            // Show correct answer if wrong
            if !isCorrect {
                Text("Correct answer: \(questions[currentQuestionIndex].correctAnswer)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Next button
            Button(currentQuestionIndex < questions.count - 1 ? "Next Question" : "Finish Quiz") {
                nextQuestion()
            }
            .buttonStyle(StablePillButtonStyle(fill: Color.blue, height: 44))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isCorrect ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        )
    }
    
    private var quizResultsView: some View {
        VStack(spacing: 24) {
            // Score display
            VStack(spacing: 16) {
                Image(systemName: score >= Int(Double(questions.count) * 0.8) ? "trophy.fill" : "target")
                    .font(.system(size: 60))
                    .foregroundStyle(score >= Int(Double(questions.count) * 0.8) ? .yellow : .blue)
                
                Text("Quiz Complete!")
                    .font(.title.weight(.bold))
                
                Text("\(score) out of \(questions.count) correct")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                
                Text("\(Int(Double(score) / Double(questions.count) * 100))%")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(score >= Int(Double(questions.count) * 0.8) ? .green : .blue)
            }
            
            // Performance message
            Group {
                if score == questions.count {
                    Text("Perfect! Outstanding work! 🎉")
                } else if score >= Int(Double(questions.count) * 0.8) {
                    Text("Excellent! Great job! 👏")
                } else if score >= Int(Double(questions.count) * 0.6) {
                    Text("Good work! Keep practicing! 💪")
                } else {
                    Text("Keep studying! You'll improve! 📚")
                }
            }
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .onAppear {
                print("🧠 Quiz completed! Recording to streaks...")
                Task {
                    subscriptionManager.recordQuizTaken()
                    await streaks.recordQuizCompleted()
                    print("🧠 Quiz recording completed")
                    
                    // Wait a moment for the state to update, then debug
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                    await MainActor.run {
                        streaks.debugTodayStats()
                    }
                }
                Task {
                    await streaks.recordQuizCompleted()
                    await MainActor.run {
                        streaks.debugTodayStats()
                    }
                }
            }
            // Action buttons
            VStack(spacing: 12) {
                if subscriptionManager.canTakeQuiz() {
                    Button("Try New Quiz") {
                        resetQuiz()
                        generateQuiz()
                    }
                    .buttonStyle(StablePillButtonStyle(fill: Color.blue, height: 50))
                } else {
                    Button("Upgrade for More Quizzes") {
                        subscriptionManager.showPaywallForFeature("quiz")
                    }
                    .buttonStyle(StablePillButtonStyle(fill: Color.orange, height: 50))
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Quiz Logic
    
    private func generateQuiz() {
        let engine = QuizEngine()
        let recentSavedIds = getRecentlySavedIds()
        
        questions = engine.generateQuiz(
            from: app.sentences,
            savedIds: app.saved,
            recentSavedIds: recentSavedIds,
            learningLang: app.learningLanguage,
            knownLang: app.knownLanguage
        )
        
        resetQuizState()
    }
    
    private func getRecentlySavedIds() -> Set<Int> {
        // This is a simplified implementation
        // In a real app, you'd track when sentences were saved
        let recentCount = min(app.saved.count / 2, 8)
        return Set(Array(app.saved).prefix(recentCount))
    }
    
    private func resetQuiz() {
        questions = []
        resetQuizState()
    }
    
    private func resetQuizState() {
        currentQuestionIndex = 0
        score = 0
        showFeedback = false
        isQuizComplete = false
        resetAnswerState()
    }
    
    private func resetAnswerState() {
        userAnswer = ""
        selectedPieces = []
        availablePieces = []
        selectedChoiceIndex = nil
        feedbackMessage = ""
        
        // Setup puzzle pieces for current question
        if currentQuestionIndex < questions.count {
            let question = questions[currentQuestionIndex]
            if let pieces = question.puzzlePieces {
                availablePieces = pieces
                selectedPieces = []
            }
        }
    }
    
    private func selectChoice(index: Int, for question: QuizQuestion) {
        selectedChoiceIndex = index
    }
    
    private func addPiece(_ piece: String) {
        guard !showFeedback else { return }
        
        if let index = availablePieces.firstIndex(of: piece) {
            selectedPieces.append(piece)
            availablePieces.remove(at: index)
        }
    }
    
    private func removePiece(at index: Int) {
        guard !showFeedback, index < selectedPieces.count else { return }
        
        let piece = selectedPieces.remove(at: index)
        availablePieces.append(piece)
    }
    
    private func checkAnswer(for question: QuizQuestion) {
        guard let selectedIndex = selectedChoiceIndex,
              let options = question.multipleChoiceOptions,
              selectedIndex < options.count else { return }
        
        let selectedAnswer = options[selectedIndex]
        isCorrect = selectedAnswer == question.correctAnswer
        
        if isCorrect {
            score += 1
            feedbackMessage = "Correct!"
        } else {
            feedbackMessage = "Incorrect"
        }
        
        showFeedback = true
    }
    
    private func checkPuzzleAnswer(for question: QuizQuestion) {
        let userSentence = reconstructSentenceFromPieces(selectedPieces)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let correctAnswer = question.correctAnswer
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Normalize both strings for comparison (handle extra spaces, punctuation)
        let normalizedUser = normalizeForComparison(userSentence)
        let normalizedCorrect = normalizeForComparison(correctAnswer)
        
        isCorrect = normalizedUser == normalizedCorrect
        
        if isCorrect {
            score += 1
            feedbackMessage = "Perfect!"
        } else {
            feedbackMessage = "Not quite right"
            print("DEBUG: User answer: '\(userSentence)'")
            print("DEBUG: Correct answer: '\(correctAnswer)'")
            print("DEBUG: User normalized: '\(normalizedUser)'")
            print("DEBUG: Correct normalized: '\(normalizedCorrect)'")
        }
        
        showFeedback = true
    }
    
    private func reconstructSentenceFromPieces(_ pieces: [String]) -> String {
        // Check if this is Japanese text
        let hasJapanese = pieces.contains { containsJapanese($0) }
        
        if hasJapanese {
            // For Japanese, concatenate without spaces, except around ASCII/punctuation
            return reconstructJapaneseSentence(pieces)
        }
        
        // For other languages, use space-based reconstruction
        var result = ""
        
        for (index, piece) in pieces.enumerated() {
            if index == 0 {
                // First piece - just add it
                result += piece
            } else if piece.count == 1 && (piece.first?.isPunctuation == true) {
                // Punctuation - attach directly to previous word (no space)
                result += piece
            } else {
                // Regular word - add space then the word
                result += " " + piece
            }
        }
        
        return result
    }
    
    private func reconstructJapaneseSentence(_ pieces: [String]) -> String {
        var result = ""
        
        for (index, piece) in pieces.enumerated() {
            if index == 0 {
                result += piece
            } else {
                let prevPiece = pieces[index - 1]
                let prevIsAscii = prevPiece.allSatisfy { $0.isASCII }
                let currentIsAscii = piece.allSatisfy { $0.isASCII }
                
                // Add space only between ASCII words, or before/after ASCII in Japanese
                if (prevIsAscii && currentIsAscii) ||
                   (prevIsAscii && !containsJapanese(piece)) ||
                   (!containsJapanese(prevPiece) && currentIsAscii) {
                    result += " " + piece
                } else {
                    // No space for Japanese characters
                    result += piece
                }
            }
        }
        
        return result
    }
    
    // MARK: - Japanese Text Processing Helpers
    
    private func containsJapanese(_ text: String) -> Bool {
        for char in text {
            let scalar = char.unicodeScalars.first?.value ?? 0
            // Check for Hiragana, Katakana, and CJK Unified Ideographs ranges
            if (scalar >= 0x3040 && scalar <= 0x309F) ||  // Hiragana
               (scalar >= 0x30A0 && scalar <= 0x30FF) ||  // Katakana
               (scalar >= 0x4E00 && scalar <= 0x9FAF) {   // CJK Unified Ideographs (Kanji)
                return true
            }
        }
        return false
    }
    
    private func normalizeForComparison(_ text: String) -> String {
        // Remove extra spaces and normalize punctuation spacing
        let normalized = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Fix punctuation spacing - remove spaces before punctuation
        return normalized
            .replacingOccurrences(of: " ?", with: "?")
            .replacingOccurrences(of: " !", with: "!")
            .replacingOccurrences(of: " .", with: ".")
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " ;", with: ";")
            .replacingOccurrences(of: " :", with: ":")
    }
    
    private func nextQuestion() {
        if currentQuestionIndex < questions.count - 1 {
            currentQuestionIndex += 1
            showFeedback = false
            resetAnswerState()
        } else {
            isQuizComplete = true
        }
    }
    
    private func playAudio(for sentence: Sentence) {
        guard let audioURL = app.audioURL(for: sentence, language: app.learningLanguage) else { return }
        audio.loadAndPlay(urlString: audioURL.absoluteString, rate: 1.0)
    }
    
    private func playAudioFromURL(_ url: URL) {
        audio.loadAndPlay(urlString: url.absoluteString, rate: 1.0)
    }
}

// MARK: - Puzzle Piece Component

struct PuzzlePiece: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
                )
                .foregroundStyle(isSelected ? .blue : .primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.blue : Color(.separator), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flashcard Content View

struct FlashcardContentView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var audio: AudioPlayerService
    @StateObject private var srManager = SpacedRepetitionManager()
    
    @State private var dueFlashcards: [Sentence] = []
    @State private var currentCardIndex = 0
    @State private var showTranslation = false
    @State private var cardOffset: CGSize = .zero
    @State private var cardRotation: Double = 0
    
    var body: some View {
        VStack(spacing: 0) {
            if dueFlashcards.isEmpty {
                emptyFlashcardsView
            } else {
                VStack(spacing: 16) {
                    // Progress and stats
                    flashcardProgressView
                    
                    // Main flashcard
                    flashcardView
                    
                    // Control buttons
                    flashcardControlsView
                }
                .padding()
            }
        }
        .onAppear {
            loadDueFlashcards()
        }
        .onChange(of: app.saved) { _, _ in
            loadDueFlashcards()
        }
    }
    
    private var emptyFlashcardsView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.badge.questionmark")
                .font(.system(size: 60))
                .foregroundStyle(.green.gradient)
            
            Text("All Caught Up!")
                .font(.title2.weight(.semibold))
            
            Text("No flashcards are due right now. Great work on staying consistent!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            if !app.saved.isEmpty {
                Text("Next review in: \(nextReviewTimeText())")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var flashcardProgressView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Flashcard \(currentCardIndex + 1) of \(dueFlashcards.count)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("Due Now")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            }
            
            ProgressView(value: Double(currentCardIndex), total: Double(max(dueFlashcards.count - 1, 1)))
                .progressViewStyle(LinearProgressViewStyle(tint: .green))
        }
    }
    
    private var flashcardView: some View {
        let currentCard = dueFlashcards[min(currentCardIndex, dueFlashcards.count - 1)]
        
        return VStack(spacing: 20) {
            // Card content
            VStack(spacing: 16) {
                // Learning language text
                if let learningText = currentCard.text(for: app.learningLanguage) {
                    Text(learningText)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                }
                
                // Audio button
                Button {
                    playAudio(for: currentCard)
                } label: {
                    Label("Play Audio", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(StablePillButtonStyle(fill: Color.blue.opacity(0.1), height: 40))
                
                Divider()
                
                // Translation (show/hide)
                if showTranslation {
                    if let knownText = currentCard.text(for: app.knownLanguage) {
                        Text(knownText)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .transition(.opacity.combined(with: .scale))
                    }
                } else {
                    Button("Show Translation") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showTranslation = true
                        }
                    }
                    .buttonStyle(StablePillButtonStyle(fill: Color.secondary.opacity(0.1), height: 36))
                }
                
                // Topic display
                if !currentCard.topics.isEmpty {
                    HStack {
                        ForEach(currentCard.topics, id: \.self) { topic in
                            Text(topic)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.1))
                                .foregroundStyle(.purple)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 300)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(.separator), lineWidth: 1)
            )
            .offset(cardOffset)
            .rotationEffect(.degrees(cardRotation))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        cardOffset = value.translation
                        cardRotation = Double(value.translation.width / 20)
                    }
                    .onEnded { value in
                        handleSwipe(translation: value.translation)
                    }
            )
        }
    }
    
    private var flashcardControlsView: some View {
        HStack(spacing: 20) {
            // Don't know button
            Button {
                markCardUnknown()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.left.circle.fill")
                        .font(.title2)
                    Text("Don't Know")
                        .font(.caption)
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 12)
            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            
            // Know button
            Button {
                markCardKnown()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                    Text("I Know This")
                        .font(.caption)
                }
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 12)
            .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Flashcard Logic
    
    private func loadDueFlashcards() {
        dueFlashcards = srManager.getDueFlashcards(from: app.sentences, savedIds: app.saved)
        currentCardIndex = 0
        showTranslation = false
    }
    
    private func handleSwipe(translation: CGSize) {
        let threshold: CGFloat = 100
        
        if translation.width > threshold {
            // Swipe right - know it
            markCardKnown()
        } else if translation.width < -threshold {
            // Swipe left - don't know
            markCardUnknown()
        } else {
            // Snap back to center
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                cardOffset = .zero
                cardRotation = 0
            }
        }
    }
    
    private func markCardKnown() {
        let currentCard = dueFlashcards[currentCardIndex]
        srManager.markCardKnown(currentCard.id)
        advanceToNextCard()
    }
    
    private func markCardUnknown() {
        let currentCard = dueFlashcards[currentCardIndex]
        srManager.markCardUnknown(currentCard.id)
        advanceToNextCard()
    }
    
    private func advanceToNextCard() {
        withAnimation(.easeInOut(duration: 0.3)) {
            cardOffset = .zero
            cardRotation = 0
            showTranslation = false
        }
        
        // Remove current card from due list and move to next
        if !dueFlashcards.isEmpty {
            dueFlashcards.remove(at: currentCardIndex)
            
            if dueFlashcards.isEmpty {
                currentCardIndex = 0
            } else if currentCardIndex >= dueFlashcards.count {
                currentCardIndex = 0
            }
        }
    }
    
    private func nextReviewTimeText() -> String {
        var nextReview = Date.distantFuture
        
        for sentenceId in app.saved {
            if let reviewTime = srManager.getNextReviewTime(for: sentenceId) {
                if reviewTime < nextReview {
                    nextReview = reviewTime
                }
            }
        }
        
        if nextReview == Date.distantFuture {
            return "No scheduled reviews"
        }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: nextReview, relativeTo: Date())
    }
    
    private func playAudio(for sentence: Sentence) {
        guard let audioURL = app.audioURL(for: sentence, language: app.learningLanguage) else { return }
        audio.loadAndPlay(urlString: audioURL.absoluteString, rate: 1.0)
    }
}

// MARK: - FlashcardEntry Codable Extension

extension FlashcardEntry: Codable {
    enum CodingKeys: String, CodingKey {
        case sentenceId, interval, nextReview, difficulty
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sentenceId = try container.decode(Int.self, forKey: .sentenceId)
        interval = try container.decode(Int.self, forKey: .interval)
        nextReview = try container.decode(Date.self, forKey: .nextReview)
        difficulty = try container.decode(Int.self, forKey: .difficulty)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sentenceId, forKey: .sentenceId)
        try container.encode(interval, forKey: .interval)
        try container.encode(nextReview, forKey: .nextReview)
        try container.encode(difficulty, forKey: .difficulty)
    }
}

