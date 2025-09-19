//
//  LessonView.swift
//  jumle
//
//  Created by Kai Kahar on 2025-09-04.
//

import SwiftUI

struct LessonView: View {
    let lesson: CustomLesson
    @EnvironmentObject private var lessonCoordinator: LessonCoordinator

    @State private var tabIndex: Int = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(lesson.title)
                        .font(.title.bold())

                    if !lesson.description.isEmpty {
                        Text(lesson.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // lesson.estimatedDuration is a non-optional Int
                    if lesson.estimatedDuration > 0 {
                        Text("~\(lesson.estimatedDuration) min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top)

                // Pager for sections + quiz
                TabView(selection: $tabIndex) {
                    ForEach(Array(lesson.sections.enumerated()), id: \.offset) { idx, section in
                        LessonSectionView(section: section)
                            .tag(idx)
                    }

                    // lesson.quiz is non-optional; show it only if it has questions
                    if !lesson.quiz.questions.isEmpty {
                        LessonQuizView(quiz: lesson.quiz) {
                            // Quiz finished
                            lessonCoordinator.closeLessonView()
                        }
                        .tag(lesson.sections.count) // quiz tab
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }
            .navigationTitle("AI Lesson")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { lessonCoordinator.closeLessonView() }
                }
            }
        }
    }
}
