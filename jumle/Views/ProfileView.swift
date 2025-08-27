//
//  ProfileView.swift
//  jumle
//
//  Created by Kai Kahar on 2025-08-07.
//
// File: Views/ProfileView.swift


import SwiftUI
import AuthenticationServices
import GoogleSignInSwift

struct ProfileView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var session: SessionViewModel

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
                Section("Settings") {
                    Toggle(isOn: .constant(true)) { Text("Dark Mode (sample)") }
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $session.showSignInSheet) {
                SignInSheet()
                    .environmentObject(session)
            }
        }
    }
}

// -------------------
// Sign-In Sheet
// -------------------
struct SignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Sign in to jumle")
                    .font(.title2)
                    .bold()
                    .padding(.top, 40)

                // Google
                GoogleSignInButton {
                    if let rootVC = UIApplication.shared.connectedScenes
                        .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
                        .first {
                        Task {
                            do {
                                try await session.signInWithGoogle(presenting: rootVC)
                                dismiss()
                            } catch {
                                print("Google sign-in failed:", error.localizedDescription)
                            }
                        }
                    }
                }
                .frame(height: 48)
                .padding(.horizontal)

                // Apple
                SignInWithAppleButton(.signIn, onRequest: { request in
                    let req = session.startSignInWithApple()
                    request.requestedScopes = req.requestedScopes
                    request.nonce = req.nonce
                }, onCompletion: { result in
                    Task {
                        do {
                            try await session.handleAppleCompletion(result)
                            dismiss()
                        } catch {
                            print("Apple sign-in failed:", error.localizedDescription)
                        }
                    }
                })
                .frame(height: 48)
                .padding(.horizontal)

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
