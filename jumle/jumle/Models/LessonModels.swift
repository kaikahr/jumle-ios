//
//  LessonModels.swift
//  jumle
//
//  Created by Kai Kahar on 2025-09-02.
// Models/LessonModels.swift
import Foundation

// MARK: - Main Lesson Structure
struct CustomLesson: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let sentences: [Int] // IDs of sentences used
    let sections: [LessonSection]
    let quiz: CustomLessonQuiz  // Changed name to avoid conflict
    let estimatedDuration: Int // minutes
    let createdAt: Date
    let language: AppLanguage
    
    var dayKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: createdAt)
    }
}

// MARK: - Lesson Sections
struct LessonSection: Codable, Identifiable {
    let id: String
    let type: LessonSectionType
    let title: String
    let content: LessonContent
}

enum LessonSectionType: String, Codable, CaseIterable {
    case introduction = "introduction"
    case grammarExplanation = "grammar_explanation"
    case vocabularyBreakdown = "vocabulary_breakdown"
    case usageExamples = "usage_examples"
    case culturalContext = "cultural_context"
    case practiceExercises = "practice_exercises"
}

struct LessonContent: Codable {
    let text: String
    let examples: [LessonExample]?
    let grammarPoints: [GrammarPoint]?
    let vocabularyItems: [VocabularyItem]?
    let exercises: [PracticeExercise]?
}

// MARK: - Supporting Structures
struct LessonExample: Codable, Identifiable {
    let id: String
    let sentence: String
    let translation: String
    let explanation: String
    let audioAvailable: Bool
}

struct GrammarPoint: Codable, Identifiable {
    let id: String
    let concept: String
    let explanation: String
    let pattern: String
    let examples: [String]
    let difficulty: GrammarDifficulty
}

enum GrammarDifficulty: String, Codable {
    case beginner, intermediate, advanced
}

struct VocabularyItem: Codable, Identifiable {
    let id: String
    let word: String
    let definition: String
    let partOfSpeech: String
    let pronunciationGuide: String?
    let synonyms: [String]
    let usageNotes: String?
}

struct PracticeExercise: Codable, Identifiable {
    let id: String
    let type: ExerciseType
    let question: String
    let options: [String]?
    let correctAnswer: String
    let explanation: String
}

enum ExerciseType: String, Codable {
    case multipleChoice = "multiple_choice"
    case fillInTheBlank = "fill_blank"
    case translation = "translation"
    case ordering = "sentence_ordering"
}

// MARK: - Quiz Structure (Renamed to avoid conflicts)
struct CustomLessonQuiz: Codable, Identifiable {
    let id: String
    let title: String
    let questions: [LessonQuizQuestion]  // Changed name
    let passingScore: Int // percentage
}

struct LessonQuizQuestion: Codable, Identifiable {
    let id: String
    let type: LessonQuizQuestionType  // Changed name
    let question: String
    let options: [String]?
    let correctAnswer: String
    let explanation: String
    let points: Int
    let difficulty: QuizDifficulty
}

enum LessonQuizQuestionType: String, Codable {
    case multipleChoice = "multiple_choice"
    case trueFalse = "true_false"
    case fillInTheBlank = "fill_blank"
    case shortAnswer = "short_answer"
}

enum QuizDifficulty: String, Codable {
    case easy, medium, hard
}

// MARK: - API Response Structure
struct LessonGenerationResponse: Codable {
    let lesson: CustomLesson
    let processingTime: Double
    let tokensUsed: Int
}
