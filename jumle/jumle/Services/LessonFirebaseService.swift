//
//  LessonFirebaseService.swift
//  jumle
//
//  Created by Kai Kahar on 2025-09-02.
//
import FirebaseFirestore
import FirebaseAuth

enum LessonFirebaseError: LocalizedError {
    case notAuthenticated
    case saveFailed(Error)
    case deleteFailed(Error)
    case fetchFailed(Error)
    case encodingFailed
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated."
        case .saveFailed(let error):
            return "Failed to save lesson: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete lesson: \(error.localizedDescription)"
        case .fetchFailed(let error):
            return "Failed to fetch lessons: \(error.localizedDescription)"
        case .encodingFailed:
            return "Failed to encode lesson data."
        }
    }
}

@MainActor
final class LessonFirebaseService: ObservableObject {
    static let shared = LessonFirebaseService()
    
    @Published private(set) var cachedLessons: [String: CustomLesson] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    
    private let db = Firestore.firestore()
    private var lessonsListener: ListenerRegistration?
    private var currentUserId: String?
    
    private init() {}
    
    // Language-specific lesson key creation
    private func createLessonKey(dayKey: String, language: AppLanguage) -> String {
        return "\(dayKey)_\(language.rawValue)"
    }
    
    func start(userId: String) {
        stop()
        currentUserId = userId
        attachLessonsListener()
    }
    
    func stop() {
        lessonsListener?.remove()
        lessonsListener = nil
        currentUserId = nil
        cachedLessons.removeAll()
    }
    
    // Updated to include language parameter
    func hasLesson(for dayKey: String, sentences: [Int], language: AppLanguage) -> Bool {
        let lessonKey = createLessonKey(dayKey: dayKey, language: language)
        guard let lesson = cachedLessons[lessonKey] else { return false }
        return Set(lesson.sentences) == Set(sentences)
    }
    
    // Updated to include language parameter
    func getLesson(for dayKey: String, language: AppLanguage) -> CustomLesson? {
        let lessonKey = createLessonKey(dayKey: dayKey, language: language)
        return cachedLessons[lessonKey]
    }
    
    // Updated to include language parameter and use language-specific document ID
    func saveLesson(_ lesson: CustomLesson, language: AppLanguage) async throws {
        guard let userId = currentUserId else {
            throw LessonFirebaseError.notAuthenticated
        }
        
        isLoading = true
        error = nil
        
        defer {
            isLoading = false
        }
        
        do {
            let lessonData = try encodeLessonForFirebase(lesson)
            
            // Use language-specific document ID
            let lessonKey = createLessonKey(dayKey: lesson.dayKey, language: language)
            let docRef = db.collection("users")
                .document(userId)
                .collection("lessons")
                .document(lessonKey)
            
            try await docRef.setData(lessonData)
            
            // Update local cache with language-specific key
            cachedLessons[lessonKey] = lesson
            
        } catch {
            self.error = "Failed to save lesson: \(error.localizedDescription)"
            throw LessonFirebaseError.saveFailed(error)
        }
    }
    
    // Updated to include language parameter
    func deleteLesson(for dayKey: String, language: AppLanguage) async throws {
        guard let userId = currentUserId else {
            throw LessonFirebaseError.notAuthenticated
        }
        
        isLoading = true
        error = nil
        
        defer {
            isLoading = false
        }
        
        do {
            let lessonKey = createLessonKey(dayKey: dayKey, language: language)
            let docRef = db.collection("users")
                .document(userId)
                .collection("lessons")
                .document(lessonKey)
            
            try await docRef.delete()
            
            cachedLessons.removeValue(forKey: lessonKey)
            
        } catch {
            self.error = "Failed to delete lesson: \(error.localizedDescription)"
            throw LessonFirebaseError.deleteFailed(error)
        }
    }
    
    
    
    private func attachLessonsListener() {
        guard let userId = currentUserId else { return }
        
        lessonsListener = db.collection("users")
            .document(userId)
            .collection("lessons")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.error = "Lessons listener error: \(error.localizedDescription)"
                    return
                }
                
                var lessons: [String: CustomLesson] = [:]
                
                for document in snapshot?.documents ?? [] {
                    let documentId = document.documentID
                    if let lesson = try? self.decodeLessonFromFirebase(document.data(), id: documentId) {
                        lessons[documentId] = lesson
                    }
                }
                
                self.cachedLessons = lessons
            }
    }
    
    private func encodeLessonForFirebase(_ lesson: CustomLesson) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(lesson)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard var lessonData = json else {
            throw LessonFirebaseError.encodingFailed
        }
        
        lessonData["createdAt"] = FieldValue.serverTimestamp()
        lessonData["updatedAt"] = FieldValue.serverTimestamp()
        
        return lessonData
    }
    
    private func decodeLessonFromFirebase(_ data: [String: Any], id: String) throws -> CustomLesson {
        guard let sanitized = sanitizeForJSON(data) as? [String: Any] else {
            throw LessonFirebaseError.encodingFailed
        }

        let jsonData = try JSONSerialization.data(withJSONObject: sanitized)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CustomLesson.self, from: jsonData)
    }
    
    private func sanitizeForJSON(_ value: Any) -> Any? {
        switch value {
        case let ts as Timestamp:
            return ISO8601DateFormatter().string(from: ts.dateValue())
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        case let gp as GeoPoint:
            return ["latitude": gp.latitude, "longitude": gp.longitude]
        case let ref as DocumentReference:
            return ref.path
        case is FieldValue:
            return NSNull()
        case let arr as [Any]:
            return arr.compactMap { sanitizeForJSON($0) }
        case let dict as [String: Any]:
            var out: [String: Any] = [:]
            for (k, v) in dict {
                if let s = sanitizeForJSON(v) { out[k] = s }
            }
            return out
        case is NSNull, is String, is NSNumber, is Bool:
            return value
        default:
            return "\(value)"
        }
    }
}
