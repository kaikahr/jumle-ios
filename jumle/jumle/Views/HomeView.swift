// File: Views/HomeView.swift - Clean Version Without Compilation Errors
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var learned: LearnedStore
    @EnvironmentObject private var streaks: StreakService  // Add this line

    @State private var pageIndex: Int = 0
    @State private var showCongrats = false

    var body: some View {
        NavigationStack {
            LoadingStateWrapper(
                loadingState: app.loadingState,
                loadingMessage: "Loading content..."
            ) {
                VStack(spacing: 0) {
                    // THEME selector
                    themeSelector
                        .padding(.bottom, 8)
                    
                    // GRAMMAR selector
                    grammarSelector
                        .padding(.bottom, 12)
                    
                    // Daily goal bar - clean design
                    dailyGoalSection
                        .padding(.bottom, 8)
                    
                    // Main content area
                    contentArea
                }
            }
            .navigationTitle("Home")
        }
        .searchable(text: $app.searchText, placement: .navigationBarDrawer(displayMode: .always))
        .task {
            if app.sentences.isEmpty {
                await app.loadContent()
            }
        }
        .onChange(of: app.filtered) { _, new in
            if pageIndex >= new.count {
                pageIndex = max(0, new.count - 1)
            }
        }
        .onChange(of: app.searchText) { _, _ in pageIndex = 0 }
        .onChange(of: app.selectedTopic) { _, _ in pageIndex = 0 }
        .onChange(of: app.selectedTheme) { _, _ in pageIndex = 0 }
        // Enhanced celebration overlay
        .overlay(
            Group {
                if showCongrats {
                    DailyGoalCelebrationView {
                        withAnimation(.easeOut) {
                            showCongrats = false
                        }
                    }
                    .zIndex(999)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
        )
    }
    
    // MARK: - Components
    
    private var themeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Theme.allCases) { theme in
                        Button {
                            selectTheme(theme)
                        } label: {
                            HStack(spacing: 6) {
                                if app.selectedTheme == theme {
                                    Image(systemName: "xmark.circle.fill")
                                        .imageScale(.small)
                                }
                                Text(theme.display)
                                    .font(.subheadline.weight(.medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(
                                    app.selectedTheme == theme
                                    ? Color.blue.opacity(0.25)
                                    : Color.blue.opacity(0.12)
                                )
                            )
                            .foregroundStyle(.blue)
                            .overlay(Capsule().stroke(Color.blue.opacity(0.35)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    private var grammarSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(app.availableGrammar, id: \.self) { point in
                        Button {
                            selectGrammar(point)
                        } label: {
                            HStack(spacing: 6) {
                                if app.selectedGrammar == point {
                                    Image(systemName: "xmark.circle.fill")
                                        .imageScale(.small)
                                }
                                Text(point)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(
                                    app.selectedGrammar == point
                                    ? Color.blue.opacity(0.25)
                                    : Color.blue.opacity(0.12)
                                )
                            )
                            .foregroundStyle(.blue)
                            .overlay(Capsule().stroke(Color.blue.opacity(0.35)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    // MARK: - Daily Goal Section (Clean Design)
    
    private var dailyGoalSection: some View {
        DailyGoalBar(
            learnedCount: learned.todayCount,
            quizCount: getTodayQuizCount(),
            flashcardCount: getTodayFlashcardCount(),
            goal: learned.dailyGoal
        )
        .padding(.horizontal, 16)
        .onChange(of: learned.todayCount) { old, new in
            handleGoalProgress(old: old, new: new)
        }
    }

    // Add these helper methods
    private func getTodayQuizCount() -> Int {
        let today = formatDate(Date())
        return streaks.dailyEntries[today]?.quizzesCompleted ?? 0
    }

    private func getTodayFlashcardCount() -> Int {
        let today = formatDate(Date())
        return streaks.dailyEntries[today]?.flashcardsRemembered ?? 0
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    // MARK: - Content Area
    
    private var contentArea: some View {
        Group {
            if let error = app.errorMessage, app.sentences.isEmpty {
                errorView(error: error)
            } else if app.filtered.isEmpty && !app.isLoading {
                emptyView
            } else {
                sentenceView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    // MARK: - Content Views
    
    private func errorView(error: String) -> some View {
        VStack(spacing: 16) {
            ContentStateMessage(
                title: "Failed to Load",
                subtitle: error,
                systemImage: "exclamationmark.triangle"
            )
            
            Button("Retry") {
                Task { await app.loadContent() }
            }
            .buttonStyle(StablePillButtonStyle())
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyView: some View {
        VStack(spacing: 14) {
            ContentStateMessage(
                title: "No results",
                subtitle: "Try clearing search, topic, or grammar filters.",
                systemImage: "magnifyingglass"
            )
            
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Button("Clear Search") { app.searchText = "" }
                        .buttonStyle(StablePillButtonStyle())
                    Button("Clear Topic") { app.selectedTopic = nil }
                        .buttonStyle(StablePillButtonStyle())
                }
                
                HStack(spacing: 10) {
                    Button("Clear Grammar") {
                        app.selectedGrammar = nil
                        Task { await app.loadContent() }
                    }
                        .buttonStyle(StablePillButtonStyle())
                    Button("Reload") {
                        Task { await app.loadContent() }
                    }
                    .buttonStyle(StablePillButtonStyle())
                }
            }
        }
        .padding(.top, 20)
        .padding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    
    // MARK: - Sentence View (Improved Scrolling)
    
    private var sentenceView: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Main sentence content
                TabView(selection: $pageIndex) {
                    ForEach(Array(app.filtered.enumerated()), id: \.1.id) { idx, sentence in
                        // Each card gets full scrollable area
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack {
                                // Generous top spacing
                                Spacer()
                                    .frame(height: 40)
                                
                                SentenceCardView(sentence: sentence)
                                    .padding(.horizontal, 12)
                                
                                // Generous bottom spacing for page indicator
                                Spacer()
                                    .frame(height: 100)
                            }
                            .frame(minHeight: geometry.size.height) // Ensure full height is available
                        }
                        .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .modifier(ZeroTabViewMargins())
                
                // Page indicator - overlay at bottom
                pageIndicator
                    .background(.regularMaterial.opacity(0.8))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
    }
    
    private var pageIndicator: some View {
        HStack(spacing: 4) {
            Text("\(pageIndex + 1)")
                .font(.footnote.monospacedDigit().weight(.medium))
                .foregroundStyle(.primary)
            Text("of")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("\(max(app.filtered.count, 1))")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
    
    // MARK: - Actions
    
    private func selectTheme(_ theme: Theme) {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        
        app.selectTheme(theme)
        pageIndex = 0
    }
    
    private func selectGrammar(_ point: String) {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        
        app.selectGrammar(point)
        pageIndex = 0
    }
    
    // MARK: - Enhanced Goal Progress Handler
    
    private func handleGoalProgress(old: Int, new: Int) {
        // Check if daily goal was just reached
        if old < learned.dailyGoal && new >= learned.dailyGoal {
            // Success haptic feedback
            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.success)
            
            // Show enhanced celebration
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                showCongrats = true
            }
        }
    }
}

// iOS 17+ margin fix
private struct ZeroTabViewMargins: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.contentMargins(.vertical, 0)
        } else {
            content
        }
    }
}
