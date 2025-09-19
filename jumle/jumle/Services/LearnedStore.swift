import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class LearnedStore: ObservableObject {
    @Published private(set) var learnedByLang: [AppLanguage: Set<Int>] = [:]
    @Published private(set) var learnedIDs: Set<String> = []   // "<lang>-<id>"
    @Published private(set) var todayCount: Int = 0
    @Published var dailyGoal: Int = 5

    private let db = Firestore.firestore()
    private var userListener: ListenerRegistration?
    private var todayListener: ListenerRegistration?
    private var uid: String?

    // MARK: lifecycle
    func start(userId: String) {
        stop()
        uid = userId
        attachAll()
    }

    func stop() {
        userListener?.remove();  userListener = nil
        todayListener?.remove(); todayListener = nil
        uid = nil
        learnedByLang = [:]
        learnedIDs.removeAll()
        todayCount = 0
    }

    deinit {
        // deinit is nonisolated; do NOT touch @Published state here.
        userListener?.remove()
        todayListener?.remove()
    }

    // MARK: listeners
    private func attachAll() {
        guard let uid else { return }

        // All learned docs (for membership + Saved tab)
        userListener = db.collection("users").document(uid).collection("learned")
            .addSnapshotListener { [weak self] snap, error in
                guard let self else { return }
                if let error { print("learned listener error:", error.localizedDescription) }

                var byLang: [AppLanguage: Set<Int>] = [:]
                var ids = Set<String>()
                for d in snap?.documents ?? [] {
                    let data = d.data()
                    guard let langRaw = data["language"] as? String,
                          let lang = AppLanguage(rawValue: langRaw),
                          let sid = data["sentenceId"] as? Int else { continue }
                    byLang[lang, default: []].insert(sid)
                    ids.insert("\(langRaw)-\(sid)")
                }
                self.learnedByLang = byLang
                self.learnedIDs = ids
            }

        // Today’s count (for progress bar)
        let dk = Self.dayKey(Date())
        todayListener = db.collection("users").document(uid).collection("learned")
            .whereField("dayKey", isEqualTo: dk)
            .addSnapshotListener { [weak self] snap, _ in
                self?.todayCount = snap?.documents.count ?? 0
            }
    }

    // MARK: public API
    func isLearned(sentenceId: Int, language: AppLanguage) -> Bool {
        learnedByLang[language]?.contains(sentenceId) ?? false
    }

    @discardableResult
    func toggleLearned(sentence: Sentence, language: AppLanguage) async -> Bool {
        if isLearned(sentenceId: sentence.id, language: language) {
            await unmarkLearned(sentenceID: sentence.id, language: language)
            return false
        } else {
            await markLearned(sentence: sentence, language: language)
            return true
        }
    }

    func markLearned(sentence: Sentence, language: AppLanguage) async {
        guard let uid else { return }

        // optimistic
        learnedByLang[language, default: []].insert(sentence.id)
        learnedIDs.insert("\(language.rawValue)-\(sentence.id)")

        let ref = db.collection("users").document(uid).collection("learned")
            .document("\(language.rawValue)-\(sentence.id)")
        let data: [String: Any] = [
            "sentenceId": sentence.id,
            "language": language.rawValue,
            "dayKey": Self.dayKey(Date()),
            "learnedAt": FieldValue.serverTimestamp(),
            "topic": sentence.topics.first ?? "",
            "hasAudio": ((sentence.audioURL?.isEmpty == false))
        ]
        do { try await ref.setData(data, merge: true) }
        catch {
            // rollback on failure
            learnedByLang[language]?.remove(sentence.id)
            learnedIDs.remove("\(language.rawValue)-\(sentence.id)")
            print("markLearned error:", error.localizedDescription)
        }
    }

    func unmarkLearned(sentenceID: Int, language: AppLanguage) async {
        guard let uid else { return }

        // optimistic
        learnedByLang[language]?.remove(sentenceID)
        learnedIDs.remove("\(language.rawValue)-\(sentenceID)")

        let ref = db.collection("users").document(uid).collection("learned")
            .document("\(language.rawValue)-\(sentenceID)")
        do { try await ref.delete() }
        catch {
            // rollback on failure
            learnedByLang[language, default: []].insert(sentenceID)
            learnedIDs.insert("\(language.rawValue)-\(sentenceID)")
            print("unmarkLearned error:", error.localizedDescription)
        }
    }

    // MARK: helpers
    static func dayKey(_ date: Date) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}
