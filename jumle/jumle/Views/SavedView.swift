// Views/SavedView.swift - Fixed to show all theme categories
import SwiftUI

struct SavedView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var session: SessionViewModel
    @EnvironmentObject private var lessonCoordinator: LessonCoordinator
    
    @State private var selectedFilter: SavedFilter = .all
    @State private var availableThemes: Set<String> = []
    @State private var availableGrammar: Set<String> = []
    
    // Persist per-sentence "date saved" locally
    @AppStorage("savedDates") private var savedDatesData: Data = Data()
    @State private var savedDates: [Int: Date] = [:] // [sentenceID: dateSaved]
    
    // Track which dates (day buckets) are expanded
    @State private var expandedDayKeys: Set<String> = []
    
    enum SavedFilter: Hashable {
        case all
        case theme(String)
        case grammar(String)
        
        var displayName: String {
            switch self {
            case .all:
                return "All"
            case .theme(let theme):
                return theme.capitalized
            case .grammar(let grammar):
                return grammar
            }
        }
    }
    
    // MARK: - Date Helpers
    
    private static let dayKeyFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
    
    private static let dayTitleFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = .current
        df.timeZone = .current
        df.dateStyle = .full
        df.timeStyle = .none
        return df
    }()
    
    private func dayKey(for date: Date) -> String {
        Self.dayKeyFormatter.string(from: date)
    }
    
    private func dayTitle(forKey key: String) -> String {
        if let date = Self.dayKeyFormatter.date(from: key) {
            return Self.dayTitleFormatter.string(from: date)
        }
        return key
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    // Filter selector at top - Always show when we have any themes to display
                    if !availableThemes.isEmpty {
                        filterSelector
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                    }
                    
                    // Main content
                    List {
                        // Group by saved date (day), recent first
                        let sortedGroups = groupedByDay.sorted(by: { $0.key > $1.key })
                        ForEach(sortedGroups, id: \.key) { dayKey, sentences in
                            Section {
                                DisclosureGroup(
                                    isExpanded: Binding(
                                        get: { expandedDayKeys.contains(dayKey) },
                                        set: { newVal in
                                            if newVal {
                                                expandedDayKeys.insert(dayKey)
                                            } else {
                                                expandedDayKeys.remove(dayKey)
                                            }
                                        }
                                    ),
                                    content: {
                                        // AI Lesson Generation Button
                                        if sentences.count >= 2 { // Need at least 2 sentences for a lesson
                                            LessonGenerationButton(
                                                sentences: filteredByChip(sentences),
                                                dayKey: dayKey
                                            )
                                            .padding(.vertical, 8)
                                        }
                                        
                                        // Sentence list
                                        let filteredSentences = filteredByChip(sentences)
                                        ForEach(filteredSentences) { sentence in
                                            NavigationLink {
                                                SentenceCardView(
                                                    sentence: sentence,
                                                    displayLanguage: app.learningLanguage
                                                )
                                                .padding()
                                            } label: {
                                                SavedRow(
                                                    sentence: sentence,
                                                    language: app.learningLanguage
                                                )
                                            }
                                        }
                                    },
                                    label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(dayTitle(forKey: dayKey))
                                                    .font(.headline)
                                                
                                                let filteredCount = filteredByChip(sentences).count
                                                let totalCount = sentences.count
                                                
                                                if selectedFilter == .all {
                                                    Text("\(totalCount) sentences")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                } else {
                                                    Text("\(filteredCount) of \(totalCount) sentences")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            // AI lesson indicator
                                            let sentenceIds = sentences.map { $0.id }
                                            let hasExistingLesson = lessonCoordinator.hasExistingLesson(
                                                for: dayKey,
                                                sentences: sentenceIds,
                                                language: app.learningLanguage
                                            )
                                            
                                            if sentences.count >= 2 && hasExistingLesson {
                                                Image(systemName: "brain.head.profile.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(.blue)
                                                    .padding(4)
                                                    .background(Color.blue.opacity(0.1), in: Circle())
                                            }
                                        }
                                    }
                                )
                            }
                        }
                    }
                    .listStyle(.plain)
                }
                
                // Loading overlay for lesson generation
                if lessonCoordinator.isGenerating {
                    LessonGenerationLoadingView()
                }
            }
            .navigationTitle("Saved")
            .overlay {
                if baseSavedForCurrentLanguage.isEmpty {
                    ContentStateMessage(
                        title: "Nothing saved yet",
                        subtitle: "Mark sentences as learned using the checkmark button.",
                        systemImage: "checkmark.circle"
                    )
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { lessonCoordinator.showLessonView },
                    set: { if !$0 { lessonCoordinator.closeLessonView() } }
                )
            ) {
                if let lesson = lessonCoordinator.currentLesson {
                    LessonView(lesson: lesson)
                        .environmentObject(lessonCoordinator)
                } else {
                    Text("No lesson available").padding()
                }
            }

            .alert("Lesson Generation Error", isPresented: .constant(lessonCoordinator.error != nil)) {
                Button("OK") {
                    lessonCoordinator.clearError()
                }
            } message: {
                Text(lessonCoordinator.error ?? "")
            }
        }
        .onAppear {
            loadSavedDates()
            reconcileSavedDatesWithApp()
            updateAvailableFilters()
            setupLessonCoordinator()
            
            // Expand today's section by default if present
            let todayKey = dayKey(for: Date())
            if groupedByDay.keys.contains(todayKey) {
                expandedDayKeys.insert(todayKey)
            }
        }
        .onChange(of: app.saved) { _, _ in
            reconcileSavedDatesWithApp()
        }
        .onChange(of: app.learningLanguage) { _, _ in
            updateAvailableFilters()
        }
        .onChange(of: app.savedSentences) { _, _ in
            updateAvailableFilters()
        }
        .onChange(of: session.currentUser?.uid) { _, newUID in
            setupLessonCoordinator()
        }
    }
    
    // MARK: - Setup Methods
    
    private func setupLessonCoordinator() {
        lessonCoordinator.setupServices(userId: session.currentUser?.uid)
    }
    
    // MARK: - Filter Selector
    
    private var filterSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Filter by")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // All filter
                    FilterChip(
                        title: "All",
                        isSelected: selectedFilter == .all,
                        count: baseSavedForCurrentLanguage.count,
                        action: { selectedFilter = .all }
                    )
                    
                    // Theme filters - now shows all available themes
                    let sortedThemes = Array(availableThemes).sorted()
                    ForEach(sortedThemes, id: \.self) { theme in
                        let themeCount = baseSavedForCurrentLanguage.filter { sentence in
                            sentence.topics.contains { $0.lowercased() == theme.lowercased() }
                        }.count
                        
                        FilterChip(
                            title: theme.capitalized,
                            isSelected: selectedFilter == .theme(theme),
                            count: themeCount,
                            action: { selectedFilter = .theme(theme) }
                        )
                    }
                    
                    // Grammar filters
                    let sortedGrammar = Array(availableGrammar).sorted()
                    ForEach(sortedGrammar, id: \.self) { grammar in
                        FilterChip(
                            title: grammar,
                            isSelected: selectedFilter == .grammar(grammar),
                            count: 0, // Grammar filtering not implemented yet
                            action: { selectedFilter = .grammar(grammar) }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    // MARK: - Derived Collections
    
    private var baseSavedForCurrentLanguage: [Sentence] {
        let lang = app.learningLanguage
        return app.savedSentences.filter { $0.text(for: lang) != nil }
    }
    
    private var groupedByDay: [String: [Sentence]] {
        var groups: [String: [Sentence]] = [:]
        for s in baseSavedForCurrentLanguage {
            guard let date = savedDates[s.id] else { continue }
            let key = dayKey(for: date)
            groups[key, default: []].append(s)
        }
        
        // Sort each day's list by time saved (most recent first)
        for (k, v) in groups {
            groups[k] = v.sorted { (lhs, rhs) in
                let dl = savedDates[lhs.id] ?? .distantPast
                let dr = savedDates[rhs.id] ?? .distantPast
                return dl > dr
            }
        }
        return groups
    }
    
    // MARK: - Filtering
    
    private func filteredByChip(_ sentences: [Sentence]) -> [Sentence] {
        switch selectedFilter {
        case .all:
            return sentences
        case .theme(let theme):
            return sentences.filter { s in
                s.topics.contains { $0.lowercased() == theme.lowercased() }
            }
        case .grammar(_):
            return sentences
        }
    }
    
    // MARK: - ✅ FIXED: Show all theme categories by default
    private func updateAvailableFilters() {
        // Always show all available theme categories from the Theme enum
        // This ensures users can see all categories even if they don't have sentences saved in them
        let allThemeCategories = Set(Theme.allCases.map { $0.rawValue.lowercased() })
        
        // Also include any additional themes found in saved sentences that might not be in the enum
        var savedThemes = Set<String>()
        for sentence in baseSavedForCurrentLanguage {
            for topic in sentence.topics where !topic.isEmpty {
                savedThemes.insert(topic.lowercased())
            }
        }
        
        // Combine both sets - this ensures all standard categories are shown plus any custom ones
        availableThemes = allThemeCategories.union(savedThemes)
        
        // Grammar points (keep existing logic)
        var grammar = Set<String>()
        for sentence in baseSavedForCurrentLanguage {
            // Add any grammar-related logic here if needed
        }
        availableGrammar = grammar
    }
    
    // MARK: - Saved Date Persistence
    
    private struct SavedDatesCodable: Codable {
        let entries: [Int: Date]
    }
    
    private func loadSavedDates() {
        guard !savedDatesData.isEmpty else {
            savedDates = [:]
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(SavedDatesCodable.self, from: savedDatesData)
            savedDates = payload.entries
        } catch {
            savedDates = [:]
        }
    }
    
    private func saveSavedDates() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let payload = SavedDatesCodable(entries: savedDates)
            savedDatesData = try encoder.encode(payload)
        } catch {
            // Best-effort; ignore write errors silently
        }
    }
    
    private func reconcileSavedDatesWithApp() {
        let savedIDs = app.saved
        let now = Date()
        
        // Add missing dates for newly-saved sentences
        for id in savedIDs {
            if savedDates[id] == nil {
                savedDates[id] = now
            }
        }
        
        // Remove dates for unsaved sentences
        let toRemove = savedDates.keys.filter { !savedIDs.contains($0) }
        for id in toRemove {
            savedDates.removeValue(forKey: id)
        }
        
        saveSavedDates()
    }
}

// MARK: - Updated FilterChip with count display

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                
                // Show count if greater than 0 or if this filter is selected
                if count > 0 || isSelected {
                    Text("(\(count))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(
                    isSelected
                    ? Color.accentColor.opacity(0.2)
                    : Color.secondary.opacity(0.1)
                )
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .overlay(
                Capsule().stroke(
                    isSelected ? Color.accentColor.opacity(0.3) : Color.clear,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Supporting Views (unchanged)

struct LessonGenerationButton: View {
    let sentences: [Sentence]
    let dayKey: String
    
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var session: SessionViewModel
    @EnvironmentObject private var lessonCoordinator: LessonCoordinator
    
    var body: some View {
        VStack(spacing: 12) {
            // Check if lesson already exists - ADD language parameter
            let sentenceIds = sentences.map { $0.id }
            let hasExistingLesson = lessonCoordinator.hasExistingLesson(
                for: dayKey,
                sentences: sentenceIds,
                language: app.learningLanguage  // ADD this line
            )
            
            if hasExistingLesson {
                // Show existing lesson - ADD language parameter
                Button {
                    if let existingLesson = lessonCoordinator.getExistingLesson(
                        for: dayKey,
                        language: app.learningLanguage  // ADD this line
                    ) {
                        lessonCoordinator.currentLesson = existingLesson
                        lessonCoordinator.showLessonView = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "brain.head.profile.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("View \(app.learningLanguage.displayName) Lesson")  // CHANGE: Show language
                                .font(.subheadline.weight(.semibold))
                            Text("Custom lesson ready")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                
            } else {
                // Generate new lesson - Already has correct parameters
                Button {
                    guard session.ensureSignedIn() else { return }
                    
                    Task {
                        await lessonCoordinator.generateOrRetrieveLesson(
                            for: sentences,
                            dayKey: dayKey,
                            learningLanguage: app.learningLanguage,
                            knownLanguage: app.knownLanguage
                        )
                    }
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Generate \(app.learningLanguage.displayName) Lesson")  // CHANGE: Show language
                                .font(.subheadline.weight(.semibold))
                            Text("Create custom lesson from \(sentences.count) sentences")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.orange)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(lessonCoordinator.isGenerating)
            }
        }
    }
}

struct LessonGenerationLoadingView: View {
    @EnvironmentObject private var lessonCoordinator: LessonCoordinator
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            // Loading content
            VStack(spacing: 24) {
                // Animated AI brain icon
                ZStack {
                    Circle()
                        .stroke(Color.blue.opacity(0.2), lineWidth: 4)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .trim(from: 0.0, to: 0.7)
                        .stroke(
                            Color.blue,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 2.0).repeatForever(autoreverses: false), value: lessonCoordinator.isGenerating)
                    
                    Image(systemName: "brain.head.profile.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue)
                }
                
                VStack(spacing: 12) {
                    Text("Generating Your Lesson")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.primary)
                    
                    Text(lessonCoordinator.currentStep)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    // Progress bar
                    ProgressView(value: lessonCoordinator.generationProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .frame(width: 200)
                    
                    Text("\(Int(lessonCoordinator.generationProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(40)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}

private struct SavedRow: View {
    let sentence: Sentence
    let language: AppLanguage
    
    @EnvironmentObject private var app: AppState  // ✅ Access to app state
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sentence.text(for: language) ?? "—")
                .font(.body)
            
            // ✅ FIXED: Use app.knownLanguage instead of hardcoded logic
            if let translation = sentence.text(for: app.knownLanguage) {
                Text(translation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            if !sentence.topicDisplay.isEmpty {
                Text(sentence.topicDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
    
    // ✅ Remove the hardcoded otherLanguage function entirely
}
