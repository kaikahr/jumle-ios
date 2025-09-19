//
//  ContentView.swift
//  jumle
//
//  Created by Kai Kahar on 2025-08-07.
//

// File: Views/ContentView.swift - Updated to preload saved sentences
import SwiftUI

struct ContentView: View {
    @StateObject private var app = AppState()
    @StateObject private var session = SessionViewModel()
    @StateObject private var audio = AudioPlayerService()

    var body: some View {
        TabView {
            HomeView().tabItem { Label("Home", systemImage: "house.fill") }
            SavedView().tabItem { Label("Saved", systemImage: "bookmark") }
            FlashcardsView().tabItem { Label("Study", systemImage: "rectangle.on.rectangle") }
            ProfileView().tabItem { Label("Profile", systemImage: "person") }
        }
        .environmentObject(app)
        .environmentObject(session)
        .environmentObject(audio)
        .sheet(isPresented: $session.showSignInSheet) {
            SignInView().environmentObject(session)
        }
        .task {
            // ✅ Preload saved sentences on app start
            if !app.saved.isEmpty {
                await app.ensureSavedSentencesLoaded()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(AudioPlayerService())
        .environmentObject(SessionViewModel())
        .environmentObject(LessonCoordinator.shared)
        .environmentObject(LearnedStore()) // 👈 so previews don't crash
}
