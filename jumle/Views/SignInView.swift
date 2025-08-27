//
//  SignInView.swift
//  jumle
//
//  Created by Kai Kahar on 2025-08-19.
//

import SwiftUI
import AuthenticationServices

// MARK: - SignInView
struct SignInView: View {
    @EnvironmentObject private var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private var rootVC: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?.rootViewController
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Welcome to Jumle")
                    .font(.title2.weight(.semibold))
                    .padding(.top, 4)

                // --- Google (custom styled to match Apple) ---
                GoogleStyledButton(title: "Sign in with Google") {
                    guard let vc = rootVC else { return }
                    Task {
                        do {
                            try await session.signInWithGoogle(presenting: vc)
                            dismiss()
                        } catch {
                            print("Google sign-in failed:", error.localizedDescription)
                        }
                    }
                }

                // --- Apple (native) ---
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
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text("By continuing you agree to our Terms and Privacy Policy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)

                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
                    .padding(.top, 6)

                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .navigationTitle("Sign in")
        }
    }
}

// MARK: - GoogleStyledButton
/// A Google button that visually matches Apple’s: 50pt height, centered label, leading logo, rounded rect + border.
private struct GoogleStyledButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            ZStack {
                // Centered label
                Text(title)
                    .font(.headline)            // similar weight to Apple’s
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // Leading logo (keeps label perfectly centered)
                HStack {
                    Group {
                        Image("google_logo")
                            .resizable()
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)

                        // Fallback if you don’t have an asset yet:
                        // Image(systemName: "g.circle").imageScale(.large)
                    }
                    Spacer()
                }
                .padding(.leading, 16)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(.plain)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .accessibilityLabel(Text(title))
    }

    private var backgroundColor: Color {
        scheme == .dark ? Color(uiColor: .systemBackground) : .white
    }

    private var borderColor: Color {
        Color.gray.opacity(scheme == .dark ? 0.45 : 0.35)
    }
}
