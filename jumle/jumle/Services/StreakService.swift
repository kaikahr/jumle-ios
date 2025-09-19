//
//  StreakService.swift
//  jumle
//
//  Created by Kai Kahar on 2025-08-27.
//

//
//  StreakService.swift
//  jumle
//
//  Tracks daily goal completion and streaks
//

import Foundation
import FirebaseFirestore

struct DailyGoalEntry: Codable {
    let date: String
    let completedCount: Int
    let goalTarget: Int
    let timestamp: Date
    let isGoalReached: Bool
    // Add new fields for different activity types
    let quizzesCompleted: Int
    let flashcardsRemembered: Int
    
    init(date: String, completedCount: Int, goalTarget: Int, timestamp: Date, isGoalReached: Bool, quizzesCompleted: Int = 0, flashcardsRemembered: Int = 0) {
            self.date = date
            self.completedCount = completedCount
            self.goalTarget = goalTarget
            self.timestamp = timestamp
            self.isGoalReached = isGoalReached
            self.quizzesCompleted = quizzesCompleted
            self.flashcardsRemembered = flashcardsRemembered
        }
        
    var dateComponents: DateComponents? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: self.date) else { return nil }
        return Calendar.current.dateComponents([.year, .month, .day], from: date)
    }
}

@MainActor
final class StreakService: ObservableObject {
    @Published private(set) var currentStreak: Int = 0
    @Published private(set) var longestStreak: Int = 0
    @Published private(set) var totalGoalsReached: Int = 0
    @Published private(set) var dailyEntries: [String: DailyGoalEntry] = [:] // date -> entry
    
    private let db = Firestore.firestore()
    private var streakListener: ListenerRegistration?
    private var uid: String?
    
    func start(userId: String) {
        stop()
        uid = userId
        attachListener()
    }
    
    func stop() {
        streakListener?.remove()
        streakListener = nil
        uid = nil
        currentStreak = 0
        longestStreak = 0
        totalGoalsReached = 0
        dailyEntries = [:]
    }
    
    deinit {
        streakListener?.remove()
    }
    
    private func attachListener() {
        guard let uid else { return }
        
        // Listen to all streak entries for this user
        streakListener = db.collection("users").document(uid).collection("streaks")
            .order(by: "date", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                
                if let error {
                    print("Streak listener error:", error)
                    return
                }
                
                var entries: [String: DailyGoalEntry] = [:]
                
                for doc in snapshot?.documents ?? [] {
                    let data = doc.data()
                    guard let date = data["date"] as? String,
                          let completedCount = data["completedCount"] as? Int,
                          let goalTarget = data["goalTarget"] as? Int,
                          let timestamp = (data["timestamp"] as? Timestamp)?.dateValue(),
                          let isGoalReached = data["isGoalReached"] as? Bool else {
                        continue
                    }
                    
                    // ✅ FIXED: Handle the new fields with defaults
                    let quizzesCompleted = data["quizzesCompleted"] as? Int ?? 0
                    let flashcardsRemembered = data["flashcardsRemembered"] as? Int ?? 0
                    
                    let entry = DailyGoalEntry(
                        date: date,
                        completedCount: completedCount,
                        goalTarget: goalTarget,
                        timestamp: timestamp,
                        isGoalReached: isGoalReached,
                        quizzesCompleted: quizzesCompleted,
                        flashcardsRemembered: flashcardsRemembered
                    )
                    entries[date] = entry
                }
                
                self.dailyEntries = entries
                self.calculateStreaks()
            }
    }
    
    // Call this when user reaches daily goal
    func recordDailyGoalReached(count: Int, goal: Int) async {
        guard let uid else { return }
        
        let today = todayDateString()
        
        // Don't record if already recorded today
        if let existing = dailyEntries[today], existing.isGoalReached {
            return
        }
        
        let entry = DailyGoalEntry(
            date: today,
            completedCount: count,
            goalTarget: goal,
            timestamp: Date(),
            isGoalReached: count >= goal
        )
        
        let docRef = db.collection("users").document(uid).collection("streaks").document(today)
        
        do {
            try await docRef.setData([
                "date": entry.date,
                "completedCount": entry.completedCount,
                "goalTarget": entry.goalTarget,
                "timestamp": FieldValue.serverTimestamp(),
                "isGoalReached": entry.isGoalReached
            ])
        } catch {
            print("Failed to record daily goal:", error)
        }
    }
    // Track quiz completion
    // Add these methods to StreakService if they're missing:
    func recordQuizCompleted() async {
        guard let uid else { return }
        let today = todayDateString()
        
        // Get current entry or create new one
        let currentEntry = dailyEntries[today]
        let quizValue = 5
        let newQuizCount = (currentEntry?.quizzesCompleted ?? 0) + quizValue
        let learnedCount = currentEntry?.completedCount ?? 0
        let flashcardCount = currentEntry?.flashcardsRemembered ?? 0
        let totalProgress = learnedCount + newQuizCount + flashcardCount
        
        let entry = DailyGoalEntry(
            date: today,
            completedCount: learnedCount,
            goalTarget: currentEntry?.goalTarget ?? 5,
            timestamp: Date(),
            isGoalReached: totalProgress >= (currentEntry?.goalTarget ?? 5),
            quizzesCompleted: newQuizCount,
            flashcardsRemembered: flashcardCount
        )
        // DEBUG: Print what we're about to store
       print("🔍 About to store entry:")
       print("  - Date: \(entry.date)")
       print("  - Learned: \(entry.completedCount)")
       print("  - Quizzes: \(entry.quizzesCompleted)")
       print("  - Flashcards: \(entry.flashcardsRemembered)")
       print("  - Goal reached: \(entry.isGoalReached)")
       
       // UPDATE LOCAL STATE IMMEDIATELY
       dailyEntries[today] = entry
       calculateStreaks()
           
           // Debug right after updating
           print("🔍 After storing, dailyEntries has \(dailyEntries.count) entries")
           debugTodayStats()
           
        dailyEntries[today] = entry
            
        // Also trigger streak recalculation
        calculateStreaks()
        
        let docRef = db.collection("users").document(uid).collection("streaks").document(today)
        
        do {
            try await docRef.setData([
                "date": entry.date,
                "completedCount": entry.completedCount,
                "goalTarget": entry.goalTarget,
                "timestamp": FieldValue.serverTimestamp(),
                "isGoalReached": entry.isGoalReached,
                "quizzesCompleted": entry.quizzesCompleted,
                "flashcardsRemembered": entry.flashcardsRemembered
            ])
            print("✅ Quiz completion recorded: \(newQuizCount) quizzes today")
        } catch {
            print("❌ Failed to record quiz completion:", error)
        }
    }

    // Track flashcard progress (call this when user marks 3 flashcards as remembered)
    func recordFlashcardMilestone() async {
        guard let uid else { return }
        let today = todayDateString()
        
        let currentEntry = dailyEntries[today]
        let newFlashcardCount = (currentEntry?.flashcardsRemembered ?? 0) + 1
        let learnedCount = currentEntry?.completedCount ?? 0
        let quizCount = currentEntry?.quizzesCompleted ?? 0
        let totalProgress = learnedCount + quizCount + newFlashcardCount
        
        let entry = DailyGoalEntry(
            date: today,
            completedCount: learnedCount,
            goalTarget: currentEntry?.goalTarget ?? 5,
            timestamp: Date(),
            isGoalReached: totalProgress >= (currentEntry?.goalTarget ?? 5),
            quizzesCompleted: quizCount,
            flashcardsRemembered: newFlashcardCount
        )
        
        // ✅ UPDATE LOCAL STATE IMMEDIATELY
        dailyEntries[today] = entry
        calculateStreaks()
        
        // Then save to Firestore...
        let docRef = db.collection("users").document(uid).collection("streaks").document(today)
        
        do {
            try await docRef.setData([
                "date": entry.date,
                "completedCount": entry.completedCount,
                "goalTarget": entry.goalTarget,
                "timestamp": FieldValue.serverTimestamp(),
                "isGoalReached": entry.isGoalReached,
                "quizzesCompleted": entry.quizzesCompleted,
                "flashcardsRemembered": entry.flashcardsRemembered
            ])
        } catch {
            print("❌ Failed to record flashcard milestone:", error)
        }
    }

    private func updateDailyEntry(for date: String, updateBlock: (DailyGoalEntry?) -> DailyGoalEntry) async {
        guard let uid else { return }
        
        let docRef = db.collection("users").document(uid).collection("streaks").document(date)
        let newEntry = updateBlock(dailyEntries[date])
        
        do {
            try await docRef.setData([
                "date": newEntry.date,
                "completedCount": newEntry.completedCount,
                "goalTarget": newEntry.goalTarget,
                "timestamp": FieldValue.serverTimestamp(),
                "isGoalReached": newEntry.isGoalReached,
                "quizzesCompleted": newEntry.quizzesCompleted,
                "flashcardsRemembered": newEntry.flashcardsRemembered
            ])
        } catch {
            print("Failed to update daily entry:", error)
        }
    }
    
    private func calculateStreaks() {
        let sortedEntries = dailyEntries.values
            .filter { $0.isGoalReached }
            .sorted { $0.date > $1.date } // Most recent first
        
        totalGoalsReached = sortedEntries.count
        
        guard !sortedEntries.isEmpty else {
            currentStreak = 0
            longestStreak = 0
            return
        }
        
        // Calculate current streak
        currentStreak = calculateCurrentStreak(from: sortedEntries)
        
        // Calculate longest streak
        longestStreak = calculateLongestStreak(from: sortedEntries)
    }
    
    private func calculateCurrentStreak(from entries: [DailyGoalEntry]) -> Int {
        guard !entries.isEmpty else { return 0 }
        
        let calendar = Calendar.current
        let today = Date()
        var streak = 0
        var checkDate = today
        
        // Check each day backwards from today
        for _ in 0..<365 {
            let dateString = formatDate(checkDate)
            
            if let entry = dailyEntries[dateString] {
                // Calculate total progress for this day
                let totalProgress = entry.completedCount + entry.quizzesCompleted + entry.flashcardsRemembered
                let goalReached = totalProgress >= entry.goalTarget
                
                if goalReached {
                    streak += 1
                } else if streak == 0 && (calendar.isDateInToday(checkDate) || calendar.isDateInYesterday(checkDate)) {
                    // Allow today or yesterday to not break streak if we haven't started counting yet
                } else {
                    break
                }
            } else if streak == 0 && (calendar.isDateInToday(checkDate) || calendar.isDateInYesterday(checkDate)) {
                // No entry for today/yesterday but haven't started counting - continue
            } else {
                break
            }
            
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }
        
        return streak
    }
    
    func debugTodayStats() {
        let today = todayDateString()
        if let entry = dailyEntries[today] {
            print("📊 Today's stats:")
            print("  - Learned: \(entry.completedCount)")
            print("  - Quizzes: \(entry.quizzesCompleted)")
            print("  - Flashcards: \(entry.flashcardsRemembered)")
            print("  - Total: \(entry.completedCount + entry.quizzesCompleted + entry.flashcardsRemembered)")
            print("  - Goal: \(entry.goalTarget)")
            print("  - Goal reached: \(entry.isGoalReached)")
        } else {
            print("📊 No entry for today yet")
        }
    }
    
    private func calculateLongestStreak(from entries: [DailyGoalEntry]) -> Int {
        guard !entries.isEmpty else { return 0 }
        
        let sortedByDate = entries.sorted { $0.date < $1.date }
        let calendar = Calendar.current
        
        var longestStreak = 0
        var currentStreak = 0
        var previousDate: Date?
        
        for entry in sortedByDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            guard let entryDate = formatter.date(from: entry.date) else { continue }
            
            if let prevDate = previousDate {
                let daysDiff = calendar.dateComponents([.day], from: prevDate, to: entryDate).day ?? 0
                
                if daysDiff == 1 {
                    // Consecutive day
                    currentStreak += 1
                } else {
                    // Break in streak
                    longestStreak = max(longestStreak, currentStreak)
                    currentStreak = 1
                }
            } else {
                // First entry
                currentStreak = 1
            }
            
            previousDate = entryDate
        }
        
        // Check final streak
        longestStreak = max(longestStreak, currentStreak)
        
        return longestStreak
    }
    
    // Helper methods
    private func todayDateString() -> String {
        formatDate(Date())
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    // Public helper for UI
    func hasGoalToday() -> Bool {
        let today = todayDateString()
        return dailyEntries[today]?.isGoalReached ?? false
    }
    
    func getActivityLevel(for date: Date) -> ActivityLevel {
        let dateString = formatDate(date)
        guard let entry = dailyEntries[dateString] else { return .none }
        
        if entry.isGoalReached {
            return .high
        } else if entry.completedCount > 0 {
            return .low
        } else {
            return .none
        }
    }
    
    enum ActivityLevel {
        case none, low, high
        
        var color: String {
            switch self {
            case .none: return "secondary"
            case .low: return "orange"
            case .high: return "green"
            }
        }
        
        var opacity: Double {
            switch self {
            case .none: return 0.1
            case .low: return 0.5
            case .high: return 1.0
            }
        }
    }
}
