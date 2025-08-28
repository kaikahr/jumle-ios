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
    let date: String // "YYYY-MM-DD" format
    let completedCount: Int
    let goalTarget: Int
    let timestamp: Date
    let isGoalReached: Bool
    
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
                    
                    let entry = DailyGoalEntry(
                        date: date,
                        completedCount: completedCount,
                        goalTarget: goalTarget,
                        timestamp: timestamp,
                        isGoalReached: isGoalReached
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
        for _ in 0..<365 { // Max reasonable streak to check
            let dateString = formatDate(checkDate)
            
            if dailyEntries[dateString]?.isGoalReached == true {
                streak += 1
            } else {
                // If we're checking today or yesterday and no entry, continue
                // (user might not have reached goal today yet)
                if streak == 0 && calendar.isDateInToday(checkDate) {
                    // Today - continue checking
                } else if streak == 0 && calendar.isDateInYesterday(checkDate) {
                    // Yesterday - continue checking
                } else {
                    // Found a break in the streak
                    break
                }
            }
            
            // Move to previous day
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }
        
        return streak
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
