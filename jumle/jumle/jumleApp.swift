//
//  jumleApp.swift
//  jumle
//
//  Updated with launch loading animation + SubscriptionManager injection
//

import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct JumleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var launchManager = AppLaunchManager()
    
    // Core app state objects
    @StateObject private var app = AppState()
    @StateObject private var session = SessionViewModel()
    @StateObject private var audio = AudioPlayerService()
    @StateObject private var learned = LearnedStore()
    @StateObject private var streaks = StreakService()
    @StateObject private var subscriptionManager = SubscriptionManager()   // ⬅️ NEW

    // AI Lesson system
    @StateObject private var lessonCoordinator = LessonCoordinator.shared

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Main app content
                ContentView()
                    .environmentObject(app)
                    .environmentObject(session)
                    .environmentObject(audio)
                    .environmentObject(learned)
                    .environmentObject(streaks)
                    .environmentObject(lessonCoordinator)
                    .environmentObject(subscriptionManager)                // ⬅️ NEW
                    .onAppear { setupServices() }
                    .onChange(of: session.currentUser?.uid) { _, _ in
                        setupServices()
                    }
                    .onChange(of: learned.todayCount) { oldCount, newCount in
                        // Check if daily goal was just reached
                        if newCount >= learned.dailyGoal && oldCount < learned.dailyGoal {
                            Task {
                                await streaks.recordDailyGoalReached(count: newCount, goal: learned.dailyGoal)
                            }
                        }
                    }
                    .sheet(isPresented: $session.showSignInSheet) {
                        SignInView()
                            .environmentObject(session)
                            .environmentObject(subscriptionManager)        // (propagate just in case)
                            .presentationDetents([.medium, .large])
                    }
                    .opacity(launchManager.isLaunching ? 0 : 1)
                    .animation(.easeInOut(duration: 0.6), value: launchManager.isLaunching)
                
                // Launch loading overlay
                if launchManager.isLaunching {
                    LaunchLoadingView()
                        .transition(.opacity.combined(with: .scale(scale: 1.1)))
                        .zIndex(1)
                }
            }
            .onAppear {
                if launchManager.isLaunching {
                    launchManager.startLaunchSequence()
                }
            }
            .task {
                if !launchManager.isLaunching {
                    setupServices()
                }
            }
        }
    }
    
    private func setupServices() {
        if let uid = session.currentUser?.uid {
            // Start user-dependent services
            learned.start(userId: uid)
            streaks.start(userId: uid)
            lessonCoordinator.setupServices(userId: uid)
        } else {
            // Stop services when user is not signed in
            learned.stop()
            streaks.stop()
            lessonCoordinator.setupServices(userId: nil)
        }
    }
}
