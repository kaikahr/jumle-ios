//
//  LessonCoordinator.swift
//  jumle
//
//  Created by Kai Kahar on 2025-09-02.
//
import SwiftUI

@MainActor
final class LessonCoordinator: ObservableObject {
    static let shared = LessonCoordinator()
    
    @Published var isGenerating = false
    @Published var generationProgress: Double = 0.0
    @Published var currentStep = ""
    @Published var error: String?
    
    // Current lesson being viewed
    @Published var currentLesson: CustomLesson?
    @Published var showLessonView = false
    
    private let aiService = LessonAIService.shared
    private let firebaseService = LessonFirebaseService.shared
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Main method to generate or retrieve a lesson
    func generateOrRetrieveLesson(
        for sentences: [Sentence],
        dayKey: String,
        learningLanguage: AppLanguage,
        knownLanguage: AppLanguage
    ) async {
        
        error = nil
        let sentenceIds = sentences.map { $0.id }
        
        // First check if we already have this lesson cached
        if firebaseService.hasLesson(for: dayKey, sentences: sentenceIds, language: learningLanguage) {
            // Load from cache
            currentStep = "Loading cached lesson..."
            if let cachedLesson = firebaseService.getLesson(for: dayKey, language: learningLanguage) {
                currentLesson = cachedLesson
                showLessonView = true
                return
            }
        }
        
        // Generate new lesson
        isGenerating = true
        currentStep = "Starting lesson generation..."
        generationProgress = 0.0
        
        defer {
            isGenerating = false
            generationProgress = 0.0
            currentStep = ""
        }
        
        do {
            // Monitor AI service progress
            startProgressMonitoring()
            
            let lesson = try await aiService.generateLesson(
                for: sentences,
                learningLanguage: learningLanguage,
                knownLanguage: knownLanguage,
                dayKey: dayKey
            )
            
            // Save to Firebase for future use
            currentStep = "Saving lesson..."
            generationProgress = 0.95
            
            try await firebaseService.saveLesson(lesson, language: learningLanguage)
            
            // Show the lesson
            currentLesson = lesson
            showLessonView = true
            
            generationProgress = 1.0
            currentStep = "Complete!"
            
            // Brief delay to show completion
            try await Task.sleep(nanoseconds: 500_000_000)
            
        } catch {
            if let urlErr = error as? URLError {
                self.error = "Network error (\(urlErr.code.rawValue)): \(urlErr.localizedDescription)"
            } else {
                self.error = error.localizedDescription
            }
            print("Lesson generation failed: \(error)")
        }
    }
    
    /// Start monitoring AI service progress
    private func startProgressMonitoring() {
        Task {
            while isGenerating {
                generationProgress = aiService.generationProgress
                currentStep = aiService.currentStep.isEmpty ? currentStep : aiService.currentStep
                
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
        }
    }
    
    /// Check if a lesson exists for given parameters
    func hasExistingLesson(for dayKey: String, sentences: [Int], language: AppLanguage) -> Bool {
        return firebaseService.hasLesson(for: dayKey, sentences: sentences, language: language)
    }
    
    /// Get existing lesson without generating
    func getExistingLesson(for dayKey: String, language: AppLanguage) -> CustomLesson? {
        return firebaseService.getLesson(for: dayKey, language: language)
    }
    
    /// Delete a lesson
    func deleteLesson(for dayKey: String, language: AppLanguage) async {
        do {
            try await firebaseService.deleteLesson(for: dayKey, language: language)
            if currentLesson?.dayKey == dayKey {
                currentLesson = nil
                showLessonView = false
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    /// Clear current lesson and close view
    func closeLessonView() {
        currentLesson = nil
        showLessonView = false
    }
    
    /// Setup services when user changes
    func setupServices(userId: String?) {
        if let userId = userId {
            firebaseService.start(userId: userId)
        } else {
            firebaseService.stop()
        }
    }
    
    /// Clear any errors
    func clearError() {
        error = nil
    }
}

// MARK: - Lesson Generation State
enum LessonGenerationState {
    case idle
    case checking
    case generating
    case saving
    case complete
    case error(String)
    
    var isActive: Bool {
        switch self {
        case .idle, .complete, .error:
            return false
        default:
            return true
        }
    }
    
    var progressValue: Double {
        switch self {
        case .idle:
            return 0.0
        case .checking:
            return 0.1
        case .generating:
            return 0.8
        case .saving:
            return 0.95
        case .complete:
            return 1.0
        case .error:
            return 0.0
        }
    }
}
