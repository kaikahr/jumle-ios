//
//  SubscriptionManager.swift
//  jumle
//
//  Created by Kai Kahar on 2025-09-08.


//  Complete subscription management system
//

import SwiftUI
import StoreKit
import Combine

// MARK: - Subscription Product IDs
enum SubscriptionProduct: String, CaseIterable {
    case monthly = "ai.jumle.premium.monthly"
    case annual = "ai.jumle.premium.annual"
    
    var displayName: String {
        switch self {
        case .monthly: return "Monthly"
        case .annual: return "Annual"
        }
    }
    
    var price: String {
        switch self {
        case .monthly: return "$9.99"
        case .annual: return "$79.99"
        }
    }
    
    var savings: String? {
        switch self {
        case .monthly: return nil
        case .annual: return "Save 33%"
        }
    }
}

// MARK: - Subscription Status
enum SubscriptionStatus {
    case free
    case premium
    case loading
    case error(String)
}

// MARK: - Usage Tracking
struct DailyUsage: Codable {
    let date: String
    var savedSentences: Int = 0
    var quizzesTaken: Int = 0
    var aiLessonsGenerated: Int = 0
    
    static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

// MARK: - Subscription Manager
@MainActor
final class SubscriptionManager: ObservableObject {
    @Published var subscriptionStatus: SubscriptionStatus = .loading
    @Published var showPaywall = false
    @Published var dailyUsage: DailyUsage = DailyUsage(date: DailyUsage.todayKey())
    @Published var availableProducts: [Product] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Usage limits for free users
    static let maxDailySaved = 8
    static let maxDailyQuizzes = 5
    static let maxDailyAILessons = 3 // For premium users
    
    private var updateListenerTask: Task<Void, Error>?
    private let userDefaults = UserDefaults.standard
    
    var isPremium: Bool {
        if case .premium = subscriptionStatus {
            return true
        }
        return false
    }
    
    init() {
        loadDailyUsage()
        updateListenerTask = listenForTransactions()
        
        Task {
            await requestProducts()
            await updateSubscriptionStatus()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - Usage Tracking
    
    private func loadDailyUsage() {
        let today = DailyUsage.todayKey()
        if let data = userDefaults.data(forKey: "dailyUsage_\(today)"),
           let usage = try? JSONDecoder().decode(DailyUsage.self, from: data) {
            dailyUsage = usage
        } else {
            dailyUsage = DailyUsage(date: today)
        }
    }
    
    private func saveDailyUsage() {
        let today = DailyUsage.todayKey()
        if let data = try? JSONEncoder().encode(dailyUsage) {
            userDefaults.set(data, forKey: "dailyUsage_\(today)")
        }
    }
    
    // MARK: - Feature Access Control
    
    func canSaveSentence() -> Bool {
        if isPremium { return true }
        return dailyUsage.savedSentences < Self.maxDailySaved
    }
    
    func canTakeQuiz() -> Bool {
        if isPremium { return true }
        return dailyUsage.quizzesTaken < Self.maxDailyQuizzes
    }
    
    func canUseAIFeatures() -> Bool {
        return isPremium
    }
    
    func canGenerateAILesson() -> Bool {
        if !isPremium { return false }
        return dailyUsage.aiLessonsGenerated < Self.maxDailyAILessons
    }
    
    // MARK: - Usage Recording
    
    func recordSentenceSaved() {
        dailyUsage.savedSentences += 1
        saveDailyUsage()
    }
    
    func recordQuizTaken() {
        dailyUsage.quizzesTaken += 1
        saveDailyUsage()
    }
    
    func recordAILessonGenerated() {
        dailyUsage.aiLessonsGenerated += 1
        saveDailyUsage()
    }
    
    // MARK: - Subscription Management
    
    func requestProducts() async {
        do {
            availableProducts = try await Product.products(for: SubscriptionProduct.allCases.map { $0.rawValue })
        } catch {
            print("Failed to load products: \(error)")
            errorMessage = "Failed to load subscription options"
        }
    }
    
    func purchase(_ product: Product) async throws {
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                await updateSubscriptionStatus()
            case .unverified:
                throw SubscriptionError.unverifiedTransaction
            }
        case .userCancelled:
            break
        case .pending:
            throw SubscriptionError.transactionPending
        @unknown default:
            throw SubscriptionError.unknown
        }
    }
    
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        try? await AppStore.sync()
        await updateSubscriptionStatus()
    }
    
    private func updateSubscriptionStatus() async {
        var hasActiveSubscription = false
        
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if SubscriptionProduct.allCases.map({ $0.rawValue }).contains(transaction.productID) {
                    hasActiveSubscription = true
                    break
                }
            case .unverified:
                break
            }
        }
        
        subscriptionStatus = hasActiveSubscription ? .premium : .free
    }
    
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    await transaction.finish()
                    await self.updateSubscriptionStatus()
                case .unverified:
                    break
                }
            }
        }
    }
    
    // MARK: - Paywall Helpers
    
    func showPaywallForFeature(_ feature: String) {
        showPaywall = true
    }
    
    func getUsageStatus(for feature: String) -> String {
        switch feature {
        case "save":
            if isPremium { return "Unlimited" }
            return "\(dailyUsage.savedSentences)/\(Self.maxDailySaved) today"
        case "quiz":
            if isPremium { return "Unlimited" }
            return "\(dailyUsage.quizzesTaken)/\(Self.maxDailyQuizzes) today"
        case "ai_lesson":
            if !isPremium { return "Premium feature" }
            return "\(dailyUsage.aiLessonsGenerated)/\(Self.maxDailyAILessons) today"
        default:
            return ""
        }
    }
}

// MARK: - Subscription Errors
enum SubscriptionError: LocalizedError {
    case unverifiedTransaction
    case transactionPending
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .unverifiedTransaction:
            return "Transaction could not be verified"
        case .transactionPending:
            return "Transaction is pending approval"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}
