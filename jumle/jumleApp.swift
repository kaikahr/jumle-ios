//
//  jumleApp.swift
//  jumle
//
//  Created by Kai Kahar on 2025-08-07.
//

// App.swift
import SwiftUI
import FirebaseCore
import GoogleSignIn


@main
struct JumleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject private var app = AppState()
    @StateObject private var session = SessionViewModel()
    @StateObject private var audio = AudioPlayerService()
    @StateObject private var learned = LearnedStore()
    @StateObject private var streaks = StreakService()

    var body: some Scene {
        WindowGroup {
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
