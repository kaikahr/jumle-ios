//
//  LessonAIService.swift
//  jumle
//
//  Fixed implementation with proper JSON handling and error management
//

import Foundation

@MainActor
final class LessonAIService: ObservableObject {
    static let shared = LessonAIService()
    
    @Published private(set) var isGenerating = false
    @Published private(set) var generationProgress: Double = 0.0
    @Published private(set) var currentStep = ""
    
    private let openAI = OpenAIService.shared
    private let rateLimiter = AIRateLimiter()
    
    private init() {}
    
    // MARK: - Main Generation Method
    func generateLesson(
        for sentences: [Sentence],
        learningLanguage: AppLanguage,
        knownLanguage: AppLanguage,
        dayKey: String
    ) async throws -> CustomLesson {
        
        guard !sentences.isEmpty else {
            throw LessonError.emptySentenceList
        }
        
        isGenerating = true
        generationProgress = 0.0
        currentStep = "Starting lesson generation..."
        
        defer {
            isGenerating = false
            generationProgress = 0.0
            currentStep = ""
        }
        
        do {
            // Check rate limits
            try await rateLimiter.checkRateLimit()
            
            // Step 1: Generate lesson content (simplified approach)
            currentStep = "Generating lesson content..."
            generationProgress = 0.3
            
            let lessonContent = try await generateLessonContent(
                sentences: sentences,
                learningLanguage: learningLanguage,
                knownLanguage: knownLanguage
            )
            
            currentStep = "Creating lesson structure..."
            generationProgress = 0.7
            
            // Step 2: Create lesson structure
            let lesson = createLessonFromContent(
                content: lessonContent,
                sentences: sentences,
                learningLanguage: learningLanguage,
                dayKey: dayKey
            )
            
            generationProgress = 1.0
            currentStep = "Complete!"
            
            // Brief delay to show completion
            try await Task.sleep(nanoseconds: 500_000_000)
            
            return lesson
            
        } catch {
            await rateLimiter.recordError()
            throw error
        }
    }
    
    // MARK: - Simplified Lesson Generation
    
    private func generateLessonContent(
        sentences: [Sentence],
        learningLanguage: AppLanguage,
        knownLanguage: AppLanguage
    ) async throws -> LessonContentData {
        
        let sentenceTexts = sentences.compactMap { $0.text(for: learningLanguage) }
        let translations = sentences.compactMap { $0.text(for: knownLanguage) }
        let languageSpecificGuidance = getLanguageSpecificGuidance(for: learningLanguage)
        
        guard !sentenceTexts.isEmpty else {
            throw LessonError.emptySentenceList
        }
        
        // Deterministic cache key based on inputs (day-agnostic)
        let cacheKeySeed = (sentenceTexts + translations + [learningLanguage.rawValue, knownLanguage.rawValue]).joined(separator: "|")
        let cacheKey = "lesson_content_" + String(cacheKeySeed.hashValue)
        
        let systemPrompt = """
        You are an expert language teacher specializing in \(learningLanguage.displayName) for \(knownLanguage.displayName) speakers, you will create a mini lesson and generate multiple quiz questions.

        \(languageSpecificGuidance)

        Create educational lesson content for \(learningLanguage.displayName) learners.

        STRICT OUTPUT REQUIREMENTS:
        - Return ONLY valid JSON (no markdown fences, no prose before/after).
        - Use EXACT keys and snake_case as shown below.
        - Ensure the JSON is syntactically valid and parseable.

        Required JSON schema (keys/shape, not literal values):
        {
          "title": "lesson title",
          "description": "what is in the lesson",
          "introduction": "engaging introduction text",
          "grammar_points": [
            {
              "concept": "grammar concept name",
              "explanation": "clear explanation in \(knownLanguage.displayName)",
              "examples": ["example1", "example2"]
            }
          ],
          "vocabulary": [
            {
              "word": "vocabulary word in \(learningLanguage.displayName)",
              "definition": "clear definition in \(knownLanguage.displayName)",
              "example": "usage example"
            }
          ],
          "use_cases": "context and usage notes",
          "quiz_questions": [
            {
              "question": "quiz question in \(knownLanguage.displayName)",
              "options": ["option1", "option2", "option3", "option4"],
              "correct_answer": "correct option",
              "explanation": "why this is correct in \(knownLanguage.displayName)"
            }
          ]
        }
        """
        
        let userPrompt = """
        Create a lesson based on these \(learningLanguage.displayName) sentences:

        \(sentenceTexts.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))

        Translations:
        \(translations.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))

        Focus on practical usage, grammar patterns, and use cases. Make it educational and engaging.
        """
        
        // NOTE: Using a deterministic cache key. Keep the call signature the same.
        // If your OpenAIService supports a responseFormat, enable JSON there.
        let response = try await openAI.completeCached(
            key: cacheKey,
            system: systemPrompt,
            user: userPrompt,
            maxTokens: 1100,
            temperature: 0.4
        )
        
        return try parseLessonContent(response)
    }
    
    // MARK: - Lesson Creation
    // Language-specific guidance
    private func getLanguageSpecificGuidance(for language: AppLanguage) -> String {
        switch language {
        case .Japanese:
            return "Focus on: Hiragana, Katakana, basic Kanji, particles (は,が,を,に,で), keigo levels, verb conjugations"
        case .French:
            return "Focus on: Gender agreement, verb conjugations, vous/tu, nasal sounds, French cultural context"
        case .German:
            return "Focus on: Case system (Nom/Akk/Dat/Gen), verb position, gender/plurals, modal verbs, compound words"
        case .Italian:
            return "Focus on: Gender agreement, verb conjugations, pronunciation/stress, regional variations, gestures"
        case .Russian:
            return "Focus on: Cyrillic script, case system, verb aspects, stress patterns, formality levels"
        case .Spanish:
            return "Focus on: Ser vs estar, subjunctive, regional differences, pronunciation, cultural context"
        case .Turkish:
            return "Focus on: Vowel harmony, agglutination, word order flexibility, formality levels, honorifics"
        case .Ukrainian:
            return "Focus on: Cyrillic variations, case system, pronunciation differences, cultural identity"
        case .English:
            return "Focus on: Irregular verbs, phrasal verbs, articles, idioms, formal/informal register"
        }
    }
    
    private func createLessonFromContent(
        content: LessonContentData,
        sentences: [Sentence],
        learningLanguage: AppLanguage,
        dayKey: String
    ) -> CustomLesson {
        
        // Create sections from content
        var sections: [LessonSection] = []
        
        // Introduction section
        sections.append(LessonSection(
            id: UUID().uuidString,
            type: .introduction,
            title: "Introduction",
            content: LessonContent(
                text: content.introduction,
                examples: nil,
                grammarPoints: nil,
                vocabularyItems: nil,
                exercises: nil
            )
        ))
        
        // Grammar section
        if !content.grammarPoints.isEmpty {
            let grammarItems = content.grammarPoints.map { point in
                GrammarPoint(
                    id: UUID().uuidString,
                    concept: point.concept,
                    explanation: point.explanation,
                    pattern: point.concept, // Simplified
                    examples: point.examples,
                    difficulty: .intermediate
                )
            }
            
            sections.append(LessonSection(
                id: UUID().uuidString,
                type: .grammarExplanation,
                title: "Grammar Points",
                content: LessonContent(
                    text: "Let's explore the key grammar concepts in these sentences.",
                    examples: nil,
                    grammarPoints: grammarItems,
                    vocabularyItems: nil,
                    exercises: nil
                )
            ))
        }
        
        // Vocabulary section
        if !content.vocabulary.isEmpty {
            let vocabItems = content.vocabulary.map { vocab in
                VocabularyItem(
                    id: UUID().uuidString,
                    word: vocab.word,
                    definition: vocab.definition,
                    partOfSpeech: "noun", // Simplified
                    pronunciationGuide: nil,
                    synonyms: [],
                    usageNotes: vocab.example
                )
            }
            
            sections.append(LessonSection(
                id: UUID().uuidString,
                type: .vocabularyBreakdown,
                title: "Key Vocabulary",
                content: LessonContent(
                    text: "Important words and phrases from the lesson.",
                    examples: nil,
                    grammarPoints: nil,
                    vocabularyItems: vocabItems,
                    exercises: nil
                )
            ))
        }
        
        // Cultural context section
        if !content.culturalNotes.isEmpty {
            sections.append(LessonSection(
                id: UUID().uuidString,
                type: .culturalContext,
                title: "Cultural Context",
                content: LessonContent(
                    text: content.culturalNotes,
                    examples: nil,
                    grammarPoints: nil,
                    vocabularyItems: nil,
                    exercises: nil
                )
            ))
        }
        
        // Create quiz
        let quizQuestions = content.quizQuestions.map { q in
            LessonQuizQuestion(
                id: UUID().uuidString,
                type: .multipleChoice,
                question: q.question,
                options: q.options,
                correctAnswer: q.correctAnswer,
                explanation: q.explanation,
                points: 10,
                difficulty: .medium
            )
        }
        
        let quiz = CustomLessonQuiz(
            id: UUID().uuidString,
            title: "Lesson Quiz",
            questions: quizQuestions,
            passingScore: 70
        )
        
        // Create final lesson
        return CustomLesson(
            id: UUID().uuidString,
            title: content.title,
            description: content.description,
            sentences: sentences.map { $0.id },
            sections: sections,
            quiz: quiz,
            estimatedDuration: calculateDuration(sections: sections, quiz: quiz),
            createdAt: Date(),
            language: learningLanguage
        )
    }
    
    private func calculateDuration(sections: [LessonSection], quiz: CustomLessonQuiz) -> Int {
        let sectionTime = sections.count * 3 // 3 minutes per section average
        let quizTime = quiz.questions.count * 2 // 2 minutes per question
        return max(sectionTime + quizTime, 10) // Minimum 10 minutes
    }
    
    // MARK: - JSON Parsing
    
    private func parseLessonContent(_ response: String) throws -> LessonContentData {
        let sanitized = sanitizeJSONResponse(response)
        guard let data = sanitized.data(using: .utf8) else {
            throw LessonError.invalidResponse
        }
        
        // 🔍 DEBUG: Print the actual JSON being parsed
        print("📝 AI Response JSON:")
        print(sanitized)
        print("📝 End of JSON")
        
        do {
            return try JSONDecoder().decode(LessonContentData.self, from: data)
        } catch {
            print("❌ JSON Parsing Error: \(error)")
            print("📄 Raw response: \(response)")
            print("🧹 Sanitized: \(sanitized)")
            throw LessonError.parsingFailed(error)
        }
    }
    
    /// Strips common wrappers (markdown fences, leading/trailing commentary) and returns the tightest JSON object or array substring if possible.
    private func sanitizeJSONResponse(_ text: String) -> String {
        // Quick path: if it already looks like clean JSON, return early.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            return trimmed
        }
        
        // Remove markdown fences if present
        var working = trimmed
        if working.hasPrefix("```") {
            // Strip the first fence line
            if let fenceEndRange = working.range(of: "\n") {
                working = String(working[fenceEndRange.upperBound...])
            }
            // Strip trailing fence
            if let lastFenceRange = working.range(of: "```", options: .backwards) {
                working = String(working[..<lastFenceRange.lowerBound])
            }
            working = working.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Extract the first full JSON object or array by matching outermost braces/brackets
        if let jsonRange = extractOutermostJSONRange(in: working) {
            return String(working[jsonRange])
        }
        
        // Fallback: return trimmed original to surface the parse error with more context
        return trimmed
    }
    
    /// Finds the range of the first top-level JSON object/array in the text.
    private func extractOutermostJSONRange(in s: String) -> Range<String.Index>? {
        guard let startIndex = s.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
        let openChar = s[startIndex]
        let closeChar: Character = (openChar == "{") ? "}" : "]"
        var depth = 0
        var idx = startIndex
        while idx < s.endIndex {
            let ch = s[idx]
            if ch == openChar { depth += 1 }
            else if ch == closeChar {
                depth -= 1
                if depth == 0 {
                    return startIndex..<s.index(after: idx)
                }
            }
            // Skip over strings to avoid counting braces inside quotes
            if ch == "\"" {
                idx = s.index(after: idx)
                while idx < s.endIndex {
                    let c = s[idx]
                    if c == "\\" { // skip escaped char
                        idx = s.index(idx, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex
                        continue
                    }
                    if c == "\"" { break }
                    idx = s.index(after: idx)
                }
            }
            idx = s.index(after: idx)
        }
        return nil
    }
}

// MARK: - Supporting Data Structures

struct LessonContentData: Codable {
    let title: String
    let description: String
    let introduction: String
    let grammarPoints: [GrammarPointData]
    let vocabulary: [VocabularyData]
    let culturalNotes: String
    let quizQuestions: [QuizQuestionData]
    
    private enum CodingKeys: String, CodingKey {
        case title, description, introduction
        case grammarPoints = "grammar_points"
        case vocabulary
        case culturalNotes = "cultural_notes"
        case quizQuestions = "quiz_questions"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Custom Lesson"
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? "A personalized lesson based on your saved sentences."
        introduction = try container.decodeIfPresent(String.self, forKey: .introduction) ?? "Let's explore these sentences together."
        grammarPoints = try container.decodeIfPresent([GrammarPointData].self, forKey: .grammarPoints) ?? []
        vocabulary = try container.decodeIfPresent([VocabularyData].self, forKey: .vocabulary) ?? []
        culturalNotes = try container.decodeIfPresent(String.self, forKey: .culturalNotes) ?? ""
        quizQuestions = try container.decodeIfPresent([QuizQuestionData].self, forKey: .quizQuestions) ?? []
    }
}

struct GrammarPointData: Codable {
    let concept: String
    let explanation: String
    let examples: [String]
}

struct VocabularyData: Codable {
    let word: String
    let definition: String
    let example: String
}

struct QuizQuestionData: Codable {
    let question: String
    let options: [String]
    let correctAnswer: String
    let explanation: String
    
    private enum CodingKeys: String, CodingKey {
        case question, options, explanation
        case correctAnswer = "correct_answer"
    }
}

// MARK: - Rate Limiter (Updated)
actor AIRateLimiter {
    private var requestCount = 0
    private var errorCount = 0
    private var lastReset = Date()
    private let maxRequestsPerMinute = 4500 // 90% of your 5000 RPM limit
    
    func checkRateLimit() async throws {
        let now = Date()
        
        // Reset counter every hour
        if now.timeIntervalSince(lastReset) > 3600 {
            requestCount = 0
            errorCount = 0
            lastReset = now
        }
        
        // Check if we're at the limit
        if requestCount >= maxRequestsPerMinute {
            throw LessonError.rateLimitExceeded
        }
        
        // Add exponential backoff for errors
        if errorCount > 0 {
            let backoffSeconds = min(pow(2.0, Double(errorCount)), 30.0)
            try await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
        }
        
        requestCount += 1
    }
    
    func recordError() {
        errorCount += 1
    }
}

// MARK: - Error Types (Updated)
enum LessonError: LocalizedError {
    case emptySentenceList
    case invalidResponse
    case parsingFailed(Error)
    case rateLimitExceeded
    case networkError(Error)
    case apiKeyMissing
    
    var errorDescription: String? {
        switch self {
        case .emptySentenceList:
            return "No sentences provided for lesson generation."
        case .invalidResponse:
            return "Invalid response from AI service."
        case .parsingFailed(let error):
            return "Failed to parse lesson content: \(error.localizedDescription)"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiKeyMissing:
            return "OpenAI API key is missing or invalid."
        }
    }
}
