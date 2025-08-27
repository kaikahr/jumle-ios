//
//  FlashcardsView.swift
//  jumle
//
//  Created by Kai Kahar on 2025-08-07.
//

//
//
//  FlashcardsView.swift
// =============================
// MARK: - Models/QuizQuestion.swift
// =============================
import Foundation

enum QuizKind: String, Codable, CaseIterable {
    case l1ToL2MCQ
    case l2ToL1MCQ
    case cloze
    case audioMCQ
    case typing
}

struct QuizOption: Identifiable, Hashable, Codable {
    let id = UUID()
    let text: String
    let isCorrect: Bool
}

struct QuizQuestion: Identifiable, Hashable, Codable {
    let id = UUID()
    let kind: QuizKind
    let prompt: String // What to show the user (L1 text, audio hint text, cloze text, etc.)
    let options: [QuizOption]? // present if MCQ-like
    let correctAnswer: String // canonical correct answer (for MCQ & typing)
    let sentenceID: Int // underlying sentence id
}

struct QuizResult: Codable {
    let total: Int
    let correct: Int
    let scorePercent: Int
    let date: Date
}

// =============================
// MARK: - Utils/Levenshtein.swift
// =============================
import Foundation

enum StringSimilarity {
    /// Case-insensitive Levenshtein distance
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a.lowercased())
        let bChars = Array(b.lowercased())
        let m = aChars.count
        let n = bChars.count
        if m == 0 { return n }
        if n == 0 { return m }
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        for i in 1...m {
            for j in 1...n {
                let cost = aChars[i-1] == bChars[j-1] ? 0 : 1
                dp[i][j] = min(
                    dp[i-1][j] + 1,
                    dp[i][j-1] + 1,
                    dp[i-1][j-1] + cost
                )
            }
        }
        return dp[m][n]
    }

    /// Accept minor typos up to a threshold based on length
    static func isFuzzyMatch(input: String, target: String) -> Bool {
        let d = levenshtein(input, target)
        let len = max(1, target.count)
        // len <= 8 -> allow 1; <= 16 -> 2; else 3
        let thresh = len <= 8 ? 1 : (len <= 16 ? 2 : 3)
        return d <= thresh
    }
}

// =============================
// MARK: - Services/SpacedRepetitionStore.swift
// =============================
import Foundation

final class SpacedRepetitionStore: ObservableObject {
    /// Stores Fibonacci index and next due date per sentence per language.
    /// Keyed by "srs_<learningLang>"
    struct Entry: Codable {
        var fibIndex: Int // 0-based. 0 means show any time (immediate)
        var nextDue: Date
    }

    @Published private(set) var entries: [Int: Entry] = [:]

    private let key: String
    private let fib: [Int] = [1, 2, 3, 5, 8, 13, 21, 34] // days

    init(learningLanguageKey: String) {
        self.key = "srs_\(learningLanguageKey)"
        load()
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Int: Entry].self, from: data) {
            self.entries = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func recordRight(for sentenceID: Int, now: Date = .now) {
        var e = entries[sentenceID] ?? Entry(fibIndex: -1, nextDue: now)
        e.fibIndex += 1
        let days = fib[min(e.fibIndex, fib.count - 1)]
        e.nextDue = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        entries[sentenceID] = e
        persist()
    }

    func recordLeft(for sentenceID: Int, now: Date = .now) {
        let e = Entry(fibIndex: -1, nextDue: now) // reset so it can show anytime
        entries[sentenceID] = e
        persist()
    }

    func isDue(_ sentenceID: Int, at date: Date = .now) -> Bool {
        guard let e = entries[sentenceID] else { return true }
        return e.nextDue <= date
    }
}

// =============================
// MARK: - Services/SavedHistoryStore.swift
// =============================
import Foundation

/// Tracks when a sentence was saved, to weight quiz questions toward recent saves
final class SavedHistoryStore {
    private let key: String
    init(learningLanguageKey: String) { key = "savedHistory_\(learningLanguageKey)" }

    func markSaved(id: Int) {
        var dict = (UserDefaults.standard.dictionary(forKey: key) as? [String: TimeInterval]) ?? [:]
        dict[String(id)] = Date().timeIntervalSince1970
        UserDefaults.standard.set(dict, forKey: key)
    }

    func timestamp(for id: Int) -> TimeInterval? {
        let dict = (UserDefaults.standard.dictionary(forKey: key) as? [String: TimeInterval]) ?? [:]
        return dict[String(id)]
    }
}

// =============================
// MARK: - Quiz/QuizEngine.swift
// =============================
import Foundation

final class QuizEngine {
    struct BuildInput {
        let sentences: [Sentence]
        let savedIDs: Set<Int>
        let learning: AppLanguage
        let known: AppLanguage
        let desiredCount: Int
        let history: SavedHistoryStore
    }

    func buildQuiz(_ input: BuildInput) -> [QuizQuestion] {
        // 1) Filter to saved & with text in both languages
        var pool = input.sentences.filter { s in
            input.savedIDs.contains(s.id) && s.text(for: input.learning) != nil && s.text(for: input.known) != nil
        }
        // 2) Weight recent saves higher using a simple softmax-style sort key
        pool.sort { a, b in
            let ta = input.history.timestamp(for: a.id) ?? 0
            let tb = input.history.timestamp(for: b.id) ?? 0
            return ta > tb
        }
        if pool.isEmpty { return [] }

        // 3) Pick top N * 1.3 for variety then sample
        let head = Array(pool.prefix(max(5, input.desiredCount * 13 / 10)))
        let picked = Array(head.prefix(input.desiredCount))

        // 4) For each, create a random question type
        var questions: [QuizQuestion] = []
        for s in picked {
            if let q = makeRandomQuestion(from: s, in: head, learning: input.learning, known: input.known) {
                questions.append(q)
            }
        }
        return questions.shuffled()
    }

    private func makeRandomQuestion(from s: Sentence, in pool: [Sentence], learning: AppLanguage, known: AppLanguage) -> QuizQuestion? {
        guard let l2 = s.text(for: learning), let l1 = s.text(for: known) else { return nil }
        let types: [QuizKind] = [.l1ToL2MCQ, .l2ToL1MCQ, .cloze, .audioMCQ, .typing]
        let kind = types.randomElement() ?? .l1ToL2MCQ
        switch kind {
        case .l1ToL2MCQ:
            let opts = distractors(for: l2, from: pool.compactMap { $0.text(for: learning) })
            return QuizQuestion(kind: .l1ToL2MCQ, prompt: l1, options: opts, correctAnswer: l2, sentenceID: s.id)
        case .l2ToL1MCQ:
            let opts = distractors(for: l1, from: pool.compactMap { $0.text(for: known) })
            return QuizQuestion(kind: .l2ToL1MCQ, prompt: l2, options: opts, correctAnswer: l1, sentenceID: s.id)
        case .cloze:
            let (clozePrompt, answer, opts) = makeCloze(source: l2, pool: pool.compactMap { $0.text(for: learning) })
            return QuizQuestion(kind: .cloze, prompt: clozePrompt, options: opts, correctAnswer: answer, sentenceID: s.id)
        case .audioMCQ:
            // We still store prompt as the L1 meaning for UI; the audio URL will be pulled by sentenceID in the view
            let opts = distractors(for: l2, from: pool.compactMap { $0.text(for: learning) })
            return QuizQuestion(kind: .audioMCQ, prompt: l1, options: opts, correctAnswer: l2, sentenceID: s.id)
        case .typing:
            return QuizQuestion(kind: .typing, prompt: l1, options: nil, correctAnswer: l2, sentenceID: s.id)
        }
    }

    private func distractors(for correct: String, from pool: [String]) -> [QuizOption] {
        let targetLen = correct.count
        let isQuestion = correct.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?")
        // Filter by length ±20% and punctuation profile
        let candidates = pool.filter { $0 != correct }.filter { s in
            let lenOK = abs(s.count - targetLen) <= Int(Double(targetLen) * 0.2)
            let punctOK = s.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?") == isQuestion
            let commonOK = commonWordScore(s, correct) >= 1 // share >=1 common token
            return lenOK && punctOK && commonOK
        }.shuffled()
        let wrongs = Array(candidates.prefix(3)).map { QuizOption(text: $0, isCorrect: false) }
        let correctOpt = QuizOption(text: correct, isCorrect: true)
        return (wrongs + [correctOpt]).shuffled()
    }

    private func commonWordScore(_ a: String, _ b: String) -> Int {
        let wa = Set(a.lowercased().split { !$0.isLetter && !$0.isNumber })
        let wb = Set(b.lowercased().split { !$0.isLetter && !$0.isNumber })
        return wa.intersection(wb).count
    }

    private func makeCloze(source: String, pool: [String]) -> (String, String, [QuizOption]) {
        // pick a content word (>3 letters)
        let tokens = source.split(separator: " ")
        let contentIdxs = tokens.enumerated().filter { $0.element.count > 3 }.map { $0.offset }
        let idx = contentIdxs.randomElement() ?? Int.random(in: 0..<max(tokens.count,1))
        var blanked = tokens
        let answer = String(tokens[min(idx, tokens.count-1)])
        if !blanked.isEmpty { blanked[min(idx, tokens.count-1)] = "_____" }
        let prompt = blanked.joined(separator: " ")
        // distractors: same-POS naive (length-based)
        let sameLength = pool.compactMap { s -> String? in
            let ws = s.split(separator: " ").filter { $0.count == answer.count }
            return ws.randomElement().map { String($0) }
        }.filter { $0.lowercased() != answer.lowercased() }
        let wrongs = Array(Set(sameLength)).prefix(3).map { QuizOption(text: $0, isCorrect: false) }
        let opts = (wrongs + [QuizOption(text: answer, isCorrect: true)]).shuffled()
        return (prompt, answer, Array(opts))
    }
}

// =============================
// MARK: - Views/QuizView.swift
// =============================
import SwiftUI
import AVFoundation

struct QuizView: View {
    @EnvironmentObject private var app: AppState

    @State private var questions: [QuizQuestion] = []
    @State private var index: Int = 0
    @State private var correctCount: Int = 0
    @State private var typingAnswer: String = ""
    @State private var showResult = false
    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 16) {
            if questions.isEmpty {
                ContentStateMessage(title: "No saved sentences", subtitle: "Save some sentences to generate a quiz.", systemImage: "questionmark.circle")
            } else if index < questions.count {
                let q = questions[index]
                Text("Question \(index + 1) / \(questions.count)")
                    .font(.subheadline).foregroundStyle(.secondary)
                questionCard(for: q)
                Spacer(minLength: 0)
            } else {
                // done
                let percent = Int((Double(correctCount) / Double(max(questions.count,1))) * 100)
                VStack(spacing: 12) {
                    Text("Score: \(correctCount)/\(questions.count) (\(percent)%)").font(.title3.bold())
                    Button("New Quiz") { buildQuiz() }.buttonStyle(StablePillButtonStyle())
                }
            }
        }
        .padding()
        .navigationTitle("Quiz")
        .onAppear { buildQuiz() } // refresh each visit
    }

    private func buildQuiz() {
        index = 0; correctCount = 0; typingAnswer = ""; player = nil
        let engine = QuizEngine()
        let history = SavedHistoryStore(learningLanguageKey: app.learningLanguage.rawValue)
        let savedIDs = app.saved
        let sentences = app.sentences
        let questions = engine.buildQuiz(.init(
            sentences: sentences,
            savedIDs: savedIDs,
            learning: app.learningLanguage,
            known: app.knownLanguage,
            desiredCount: min(12, max(6, savedIDs.count)),
            history: history
        ))
        self.questions = questions
    }

    @ViewBuilder private func questionCard(for q: QuizQuestion) -> some View {
        VStack(spacing: 14) {
            switch q.kind {
            case .l1ToL2MCQ, .l2ToL1MCQ, .cloze, .audioMCQ:
                if q.kind == .audioMCQ, let s = app.sentences.first(where: { $0.id == q.sentenceID }), let urlStr = s.audioURL, let url = URL(string: urlStr) {
                    Button { play(url: url) } label: { Label("Play", systemImage: "speaker.wave.2.fill") }
                        .buttonStyle(StablePillButtonStyle())
                }
                Text(q.prompt)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                if let opts = q.options {
                    VStack(spacing: 10) {
                        ForEach(opts) { opt in
                            Button(opt.text) { answer(opt.text) }
                                .buttonStyle(StablePillButtonStyle(height: 48))
                        }
                    }
                }
            case .typing:
                Text(q.prompt)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                TextField("Type here…", text: $typingAnswer)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit { answer(typingAnswer) }
                Button("Check") { answer(typingAnswer) }
                    .buttonStyle(StablePillButtonStyle())
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    private func play(url: URL) {
        player = AVPlayer(url: url)
        player?.play()
    }

    private func answer(_ user: String) {
        guard index < questions.count else { return }
        let q = questions[index]
        let isCorrect: Bool
        if q.kind == .typing {
            isCorrect = StringSimilarity.isFuzzyMatch(input: user, target: q.correctAnswer)
        } else {
            isCorrect = user == q.correctAnswer
        }
        if isCorrect { correctCount += 1 }
        withAnimation { index += 1; typingAnswer = "" }
        if index == questions.count { storeScore(correct: correctCount, total: questions.count) }
    }

    private func storeScore(correct: Int, total: Int) {
        let key = "quizScore_\(app.learningLanguage.rawValue)"
        let res = QuizResult(total: total, correct: correct, scorePercent: Int((Double(correct)/Double(max(total,1)))*100), date: Date())
        if let data = try? JSONEncoder().encode(res) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// =============================
// MARK: - Views/FlashcardDeckView.swift
// =============================
import SwiftUI

struct FlashcardDeckView: View {
    @EnvironmentObject private var app: AppState

    @State private var index: Int = 0
    @State private var offset: CGSize = .zero
    @State private var srs: SpacedRepetitionStore = SpacedRepetitionStore(learningLanguageKey: "")

    var body: some View {
        let _ = _setupSRS()
        let due = dueSentences
        VStack(spacing: 10) {
            if due.isEmpty {
                ContentStateMessage(title: "All caught up", subtitle: "No due cards. Come back later!", systemImage: "checkmark.circle")
            } else {
                let s = due[min(index, due.count-1)]
                card(for: s)
                    .offset(offset)
                    .rotationEffect(.degrees(Double(offset.width / 20)))
                    .gesture(
                        DragGesture()
                            .onChanged { offset = $0.translation }
                            .onEnded { endDrag(for: s, translation: $0.translation) }
                    )

                HStack(spacing: 12) {
                    Button { swipeLeft(s) } label: { Label("Again", systemImage: "arrow.uturn.left.circle") }
                        .buttonStyle(StablePillButtonStyle(height: 44))
                    Button { swipeRight(s) } label: { Label("Good", systemImage: "checkmark.circle") }
                        .buttonStyle(StablePillButtonStyle(height: 44))
                }
                Text("\(index + 1) / \(due.count) due today")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding()
        .navigationTitle("Flashcards")
    }

    private func _setupSRS() {
        if srs.entries.isEmpty { // cheap one-time swap per language
            srs = SpacedRepetitionStore(learningLanguageKey: app.learningLanguage.rawValue)
        }
    }

    private var dueSentences: [Sentence] {
        let candidates = app.sentences.filter { app.saved.contains($0.id) }
        return candidates.filter { srs.isDue($0.id) }
    }

    @ViewBuilder private func card(for s: Sentence) -> some View {
        VStack(spacing: 10) {
            Text(s.text(for: app.learningLanguage) ?? "—")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(s.text(for: app.knownLanguage) ?? "")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 240)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    private func endDrag(for s: Sentence, translation: CGSize) {
        let threshold: CGFloat = 80
        if translation.width > threshold { swipeRight(s) }
        else if translation.width < -threshold { swipeLeft(s) }
        else { withAnimation { offset = .zero } }
    }

    private func swipeRight(_ s: Sentence) {
        srs.recordRight(for: s.id)
        advance()
    }

    private func swipeLeft(_ s: Sentence) {
        srs.recordLeft(for: s.id)
        advance()
    }

    private func advance() {
        withAnimation { offset = .zero; index += 1 }
    }
}

// =============================
// MARK: - Views/FlashcardsView.swift (replace)
// =============================
import SwiftUI

struct FlashcardsView: View {
    @EnvironmentObject private var app: AppState
    @State private var tab: Int = 0 // 0 = Quiz, 1 = Flashcards

    private let tabs = ["Quiz", "Flashcards"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $tab) {
                    ForEach(0..<tabs.count, id: \.self) { i in
                        Text(tabs[i]).tag(i)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if tab == 0 {
                    QuizView().environmentObject(app)
                } else {
                    FlashcardDeckView().environmentObject(app)
                }
            }
            .navigationTitle("Study")
            .onChange(of: app.saved) { _, new in
                // Mark save timestamps for recency bias
                let history = SavedHistoryStore(learningLanguageKey: app.learningLanguage.rawValue)
                new.forEach { history.markSaved(id: $0) }
            }
        }
    }
}
