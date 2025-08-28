//
//  jumleApp.swift
//  jumle
//
//  Updated with launch loading animation
//

import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct JumleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var launchManager = AppLaunchManager()
    
    // Your existing state objects
    @StateObject private var app = AppState()
    @StateObject private var session = SessionViewModel()
    @StateObject private var audio = AudioPlayerService()
    @StateObject private var learned = LearnedStore()
    @StateObject private var streaks = StreakService()

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
                    .onAppear {
                        setupServices()
                    }
                    .onChange(of: session.currentUser?.uid) { _, newUID in
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
                // Start the launch sequence when the app appears
                if launchManager.isLaunching {
                    launchManager.startLaunchSequence()
                }
            }
            .task {
                // Ensure services are set up after launch completes
                if !launchManager.isLaunching {
                    setupServices()
                }
            }
        }
    }
    
    private func setupServices() {
        if let uid = session.currentUser?.uid {
            learned.start(userId: uid)
            streaks.start(userId: uid)
        } else {
            learned.stop()
            streaks.stop()
        }
    }
}
