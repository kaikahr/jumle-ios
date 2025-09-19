//
//  ProfileView.swift
//  jumle
//
//  Created by Kai Kahar on 2025-08-07.
//
// File: Views/ProfileView.swift - Enhanced with streak tracking
import SwiftUI
import AuthenticationServices
import GoogleSignInSwift

struct ProfileView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var session: SessionViewModel
    @EnvironmentObject private var streaks: StreakService

    var body: some View {
        NavigationStack {
            Form {
                // -------------------
                // Account Section
                // -------------------
                Section("Account") {
                    if session.isSignedIn, let u = session.currentUser {
                        HStack {
                            if let urlString = u.photoURL, let url = URL(string: urlString) {
                                AsyncImage(url: url) { img in
                                    img.resizable()
                                } placeholder: {
                                    Color.gray.opacity(0.2)
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                            }

                            VStack(alignment: .leading) {
                                Text(u.displayName ?? "User").font(.headline)
                                if let email = u.email {
                                    Text(email)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Sign out") { session.signOut() }
                                .buttonStyle(.bordered)
                        }
                    } else {
                        VStack(spacing: 12) {
                            Button {
                                session.showSignInSheet = true
                            } label: {
                                Label("Sign in or create account", systemImage: "person.crop.circle.badge.plus")
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }

                // -------------------
                // Streak Section
                // -------------------
                if session.isSignedIn {
                    Section("Learning Streak") {
                        StreakStatsView(streaks: streaks)
                    }
                    
                    Section {
                        ActivityCalendar()
                            .environmentObject(streaks)
                    } header: {
                        Text("Activity Calendar")
                    }
                }

                // -------------------
                // Languages Section
                // -------------------
                Section("Languages") {
                    Picker("I know", selection: Binding(
                        get: { app.knownLanguage },
                        set: { app.knownLanguage = $0 }
                    )) {
                        ForEach(AppLanguage.allCases, id: \.self) { lang in
                            Text(lang.displayName)
                                .foregroundStyle(lang == app.learningLanguage ? .secondary : .primary)
                                .tag(lang)
                        }
                    }

                    Picker("I'm learning", selection: Binding(
                        get: { app.learningLanguage },
                        set: { app.learningLanguage = $0 }
                    )) {
                        ForEach(AppLanguage.allCases, id: \.self) { lang in
                            Text(lang.displayName)
                                .foregroundStyle(lang == app.knownLanguage ? .secondary : .primary)
                                .tag(lang)
                        }
                    }

                    if app.knownLanguage == app.learningLanguage {
                        Text("Known and learning languages cannot be the same.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                // -------------------
                // Settings Section
                // -------------------
                
            }
            .navigationTitle("Profile")
        }
    }
}

// MARK: - Streak Stats Component

struct StreakStatsView: View {
    @ObservedObject var streaks: StreakService
    
    var body: some View {
        VStack(spacing: 16) {
            // Current streak
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("Current Streak")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(streaks.currentStreak)")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.primary) +
                    Text(" days")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Longest streak
                VStack(alignment: .trailing, spacing: 4) {
                    HStack {
                        Text("Best")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(.yellow)
                    }
                    Text("\(streaks.longestStreak)")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.primary) +
                    Text(" days")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            // Total goals reached
            HStack {
                Image(systemName: "target")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Goals Reached")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(streaks.totalGoalsReached)")
                        .font(.title2.weight(.semibold))
                }
                Spacer()
            }
        }
        .padding(.vertical, 8)
    }
}
