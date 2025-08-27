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
    @StateObject private var session = SessionViewModel() // from below
    @StateObject private var audio = AudioPlayerService()
    @StateObject private var learned = LearnedStore()
    

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                .environmentObject(session)
                .environmentObject(audio)
                .environmentObject(learned)   // ⬅️ provide LearnedStore to the tree
                .onAppear {
                    // Start/stop Firestore listeners when auth changes
                    if let uid = session.currentUser?.uid {
                        learned.start(userId: uid)
                    } else {
                        learned.stop()
                    }
                }
                .onChange(of: session.currentUser?.uid) { _, newUID in
                    if let uid = newUID {
                        learned.start(userId: uid)
                    } else {
                        learned.stop()
                    }
                }
                .sheet(isPresented: $session.showSignInSheet) {
                    SignInView()
                        .environmentObject(session)
                        .presentationDetents([.medium, .large])
                }
        }
    }

}
