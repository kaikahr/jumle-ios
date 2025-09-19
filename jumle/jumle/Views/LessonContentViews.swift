//
//  LessonContentViews.swift
//  jumle
//
//  Created by Kai Kahar on 2025-09-02.
//
// Views/LessonContentViews.swift - Fixed version
import SwiftUI

// MARK: - Lesson Section View
struct LessonSectionView: View {
    let section: LessonSection
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Section header
                VStack(spacing: 8) {
                    Text(section.title)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    
                    Divider()
                        .frame(width: 60)
                        .background(Color.blue)
                }
                .padding(.top, 20)
                
                // Section content based on type
                switch section.type {
                case .introduction:
                    IntroductionSectionView(content: section.content)
                case .grammarExplanation:
                    GrammarSectionView(content: section.content)
                case .vocabularyBreakdown:
                    VocabularySectionView(content: section.content)
                case .usageExamples:
                    UsageExamplesSectionView(content: section.content)
                case .culturalContext:
                    CulturalContextSectionView(content: section.content)
                case .practiceExercises:
                    PracticeExercisesSectionView(content: section.content)
                }
                
                Spacer(minLength: 100) // Space for navigation
            }
            .padding()
        }
    }
}

// MARK: - Introduction Section
struct IntroductionSectionView: View {
    let content: LessonContent
    
    var body: some View {
        VStack(spacing: 16) {
            Text(content.text)
                .font(.body)
                .lineLimit(nil)
            
            if let examples = content.examples, !examples.isEmpty {
                VStack(spacing: 12) {
                    Text("What you'll learn:")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    ForEach(examples.prefix(3)) { example in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(example.explanation)
                                .font(.subheadline)
                            Spacer()
                        }
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - Grammar Section
struct GrammarSectionView: View {
    let content: LessonContent
    
    var body: some View {
        VStack(spacing: 20) {
            Text(content.text)
                .font(.body)
                .lineLimit(nil)
            
            if let grammarPoints = content.grammarPoints {
                ForEach(grammarPoints) { point in
                    GrammarPointCard(point: point)
                }
            }
        }
    }
}

struct GrammarPointCard: View {
    let point: GrammarPoint
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(point.concept)
                        .font(.headline)
                    Text(point.pattern)
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                }
                
                Spacer()
                
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
            }
            
            // Expandable content
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(point.explanation)
                        .font(.subheadline)
                    
                    if !point.examples.isEmpty {
                        Text("Examples:")
                            .font(.subheadline.weight(.medium))
                            .padding(.top, 8)
                        
                        ForEach(point.examples, id: \.self) { example in
                            HStack {
                                Text("•")
                                    .foregroundStyle(.blue)
                                Text(example)
                                    .font(.subheadline)
                                    .italic()
                                Spacer()
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Vocabulary Section
struct VocabularySectionView: View {
    let content: LessonContent
    
    var body: some View {
        VStack(spacing: 16) {
            Text(content.text)
                .font(.body)
                .lineLimit(nil)
            
            if let vocabularyItems = content.vocabularyItems {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(vocabularyItems) { item in
                        VocabularyCard(item: item)
                    }
                }
            }
        }
    }
}

struct VocabularyCard: View {
    let item: VocabularyItem
    @State private var showingDefinition = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Word and part of speech
            HStack {
                Text(item.word)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text(item.partOfSpeech)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .clipShape(Capsule())
                    .foregroundStyle(.blue)
            }
            
            // Pronunciation guide if available
            if let pronunciation = item.pronunciationGuide {
                Text("[\(pronunciation)]")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Definition
            Text(item.definition)
                .font(.subheadline)
                .lineLimit(showingDefinition ? nil : 2)
                .animation(.easeInOut(duration: 0.2), value: showingDefinition)
            
            // Synonyms if available
            if !item.synonyms.isEmpty {
                Text("Similar: \(item.synonyms.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
        .onTapGesture {
            showingDefinition.toggle()
        }
    }
}

// MARK: - Usage Examples Section
struct UsageExamplesSectionView: View {
    let content: LessonContent
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var audio: AudioPlayerService
    
    var body: some View {
        VStack(spacing: 16) {
            Text(content.text)
                .font(.body)
                .lineLimit(nil)
            
            if let examples = content.examples {
                ForEach(examples) { example in
                    ExampleCard(example: example)
                        .environmentObject(audio)
                }
            }
        }
    }
}

struct ExampleCard: View {
    let example: LessonExample
    @EnvironmentObject private var audio: AudioPlayerService
    @State private var showTranslation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main sentence
            Text(example.sentence)
                .font(.body.weight(.medium))
                .padding(.horizontal)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Controls
            HStack {
                // Audio button if available
                if example.audioAvailable {
                    Button {
                        // Play audio (would need actual audio URL)
                        print("Playing audio for: \(example.sentence)")
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                }
                
                // Translation toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showTranslation.toggle()
                    }
                } label: {
                    Text(showTranslation ? "Hide Translation" : "Show Translation")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
                
                Spacer()
            }
            
            // Translation and explanation
            if showTranslation {
                VStack(alignment: .leading, spacing: 8) {
                    Text(example.translation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    
                    if !example.explanation.isEmpty {
                        Text(example.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
}

// MARK: - Cultural Context Section
struct CulturalContextSectionView: View {
    let content: LessonContent
    
    var body: some View {
        VStack(spacing: 16) {
            // Cultural context icon and intro
            HStack {
                Image(systemName: "globe.asia.australia.fill")
                    .font(.title)
                    .foregroundStyle(.orange)
                
                VStack(alignment: .leading) {
                    Text("Cultural Insights")
                        .font(.headline)
                    Text("Understanding real-world usage")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Text(content.text)
                .font(.body)
                .lineLimit(nil)
            
            if let examples = content.examples {
                ForEach(examples) { example in
                    CulturalContextCard(example: example)
                }
            }
        }
    }
}

struct CulturalContextCard: View {
    let example: LessonExample
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(example.sentence)
                .font(.subheadline.weight(.medium))
            
            Text(example.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.orange.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Practice Exercises Section
struct PracticeExercisesSectionView: View {
    let content: LessonContent
    
    var body: some View {
        VStack(spacing: 20) {
            Text(content.text)
                .font(.body)
                .lineLimit(nil)
            
            if let exercises = content.exercises {
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                    PracticeExerciseCard(
                        exercise: exercise,
                        exerciseNumber: index + 1
                    )
                }
            }
        }
    }
}

struct PracticeExerciseCard: View {
    let exercise: PracticeExercise
    let exerciseNumber: Int
    
    @State private var selectedAnswer: String?
    @State private var showResult = false
    @State private var isCorrect = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Exercise header
            HStack {
                Text("Exercise \(exerciseNumber)")
                    .font(.headline)
                    .foregroundStyle(.purple)
                
                Spacer()
                
                Text(exercise.type.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.2))
                    .clipShape(Capsule())
                    .foregroundStyle(.purple)
            }
            
            // Question
            Text(exercise.question)
                .font(.body)
            
            // Answer options
            if let options = exercise.options {
                VStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            selectedAnswer = option
                            checkAnswer()
                        } label: {
                            HStack {
                                Text(option)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                
                                if showResult && option == selectedAnswer {
                                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(isCorrect ? .green : .red)
                                } else if showResult && option == exercise.correctAnswer && !isCorrect {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(getBackgroundColor(for: option))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(getBorderColor(for: option), lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(showResult)
                    }
                }
            }
            
            // Result explanation
            if showResult {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(isCorrect ? .green : .red)
                        Text(isCorrect ? "Correct!" : "Incorrect")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(isCorrect ? .green : .red)
                    }
                    
                    Text(exercise.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
    
    private func checkAnswer() {
        isCorrect = selectedAnswer == exercise.correctAnswer
        withAnimation(.easeInOut(duration: 0.3)) {
            showResult = true
        }
    }
    
    private func getBackgroundColor(for option: String) -> Color {
        if !showResult {
            return selectedAnswer == option ? Color.blue.opacity(0.1) : Color.clear
        }
        
        if option == exercise.correctAnswer {
            return Color.green.opacity(0.1)
        } else if option == selectedAnswer && !isCorrect {
            return Color.red.opacity(0.1)
        }
        
        return Color.clear
    }
    
    private func getBorderColor(for option: String) -> Color {
        if !showResult {
            return selectedAnswer == option ? Color.blue : Color(.systemGray4)
        }
        
        if option == exercise.correctAnswer {
            return Color.green
        } else if option == selectedAnswer && !isCorrect {
            return Color.red
        }
        
        return Color(.systemGray4)
    }
}

// MARK: - Lesson Quiz View (Fixed)
struct LessonQuizView: View {
    let quiz: CustomLessonQuiz  // ✅ Fixed: was LessonQuiz
    let onComplete: () -> Void
    
    @State private var currentQuestionIndex = 0
    @State private var selectedAnswers: [String: String] = [:] // questionId -> selectedAnswer
    @State private var showResults = false
    @State private var score = 0
    
    var currentQuestion: LessonQuizQuestion? {  // ✅ Fixed: was QuizQuestion
        guard currentQuestionIndex < quiz.questions.count else { return nil }
        return quiz.questions[currentQuestionIndex]
    }
    
    var totalScore: Int {
        quiz.questions.reduce(0) { $0 + $1.points }
    }
    
    var percentage: Int {
        guard totalScore > 0 else { return 0 }
        return Int(Double(score) / Double(totalScore) * 100)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if showResults {
                // Results view
                quizResultsView
            } else {
                // Quiz view
                VStack(spacing: 20) {
                    // Progress header
                    quizProgressHeader
                    
                    // Current question
                    if let question = currentQuestion {
                        QuizQuestionView(
                            question: question,
                            selectedAnswer: selectedAnswers[question.id],
                            onAnswerSelected: { answer in
                                selectedAnswers[question.id] = answer
                            }
                        )
                    }
                    
                    Spacer()
                    
                    // Navigation
                    quizNavigationControls
                }
                .padding()
            }
        }
    }
    
    private var quizProgressHeader: some View {
        VStack(spacing: 8) {
            Text(quiz.title)
                .font(.title2.weight(.bold))
            
            HStack {
                Text("Question \(currentQuestionIndex + 1) of \(quiz.questions.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("Score to Pass: \(quiz.passingScore)%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            ProgressView(value: Double(currentQuestionIndex + 1), total: Double(quiz.questions.count))
                .progressViewStyle(LinearProgressViewStyle(tint: .purple))
        }
    }
    
    private var quizNavigationControls: some View {
        HStack {
            // Previous button
            Button {
                if currentQuestionIndex > 0 {
                    currentQuestionIndex -= 1
                }
            } label: {
                Text("Previous")
                    .foregroundStyle(.blue)
            }
            .disabled(currentQuestionIndex == 0)
            
            Spacer()
            
            // Next/Finish button
            Button {
                if currentQuestionIndex < quiz.questions.count - 1 {
                    currentQuestionIndex += 1
                } else {
                    finishQuiz()
                }
            } label: {
                Text(currentQuestionIndex == quiz.questions.count - 1 ? "Finish Quiz" : "Next")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.purple)
                    .clipShape(Capsule())
            }
            .disabled(currentQuestion != nil && selectedAnswers[currentQuestion!.id] == nil)
        }
    }
    
    private var quizResultsView: some View {
        VStack(spacing: 24) {
            // Score display
            VStack(spacing: 16) {
                Image(systemName: percentage >= quiz.passingScore ? "star.fill" : "star")
                    .font(.system(size: 60))
                    .foregroundStyle(percentage >= quiz.passingScore ? .yellow : .gray)
                
                Text("Quiz Complete!")
                    .font(.title.weight(.bold))
                
                Text("\(score) / \(totalScore) points")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                
                Text("\(percentage)%")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(percentage >= quiz.passingScore ? .green : .orange)
            }
            
            // Pass/fail message
            Group {
                if percentage >= quiz.passingScore {
                    Text("🎉 Congratulations! You passed!")
                        .foregroundStyle(.green)
                } else {
                    Text("Keep studying! You'll improve with practice.")
                        .foregroundStyle(.orange)
                }
            }
            .font(.headline)
            .multilineTextAlignment(.center)
            
            // Complete button
            Button {
                onComplete()
            } label: {
                Text("Continue")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding()
    }
    
    private func finishQuiz() {
        // Calculate score
        score = 0
        for question in quiz.questions {
            if let selectedAnswer = selectedAnswers[question.id],
               selectedAnswer == question.correctAnswer {
                score += question.points
            }
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            showResults = true
        }
    }
}

// MARK: - Quiz Question View (Fixed)
struct QuizQuestionView: View {
    let question: LessonQuizQuestion  // ✅ Fixed: was QuizQuestion
    let selectedAnswer: String?
    let onAnswerSelected: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Question
            VStack(alignment: .leading, spacing: 8) {
                Text(question.question)
                    .font(.body)
                    .lineLimit(nil)
                
                HStack {
                    Text("\(question.points) points")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text(question.difficulty.rawValue.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(difficultyColor.opacity(0.2))
                        .clipShape(Capsule())
                        .foregroundStyle(difficultyColor)
                }
            }
            
            // Answer options
            if let options = question.options {
                VStack(spacing: 12) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            onAnswerSelected(option)
                        } label: {
                            HStack {
                                Text(option)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                
                                Spacer()
                                
                                if selectedAnswer == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.purple)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedAnswer == option ? Color.purple.opacity(0.1) : Color(.systemGray6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedAnswer == option ? Color.purple : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var difficultyColor: Color {
        switch question.difficulty {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        }
    }
}

// MARK: - Extensions
extension ExerciseType {
    var displayName: String {
        switch self {
        case .multipleChoice: return "Multiple Choice"
        case .fillInTheBlank: return "Fill in the Blank"
        case .translation: return "Translation"
        case .ordering: return "Word Order"
        }
    }
}
