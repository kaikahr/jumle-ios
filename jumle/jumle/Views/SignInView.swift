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
    
    @State private var showEmailSignIn = false

    private var rootVC: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?.rootViewController
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Welcome to Jumle")
                    .font(.title2.weight(.semibold))
                    .padding(.top, 4)

                VStack(spacing: 16) {
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

                    // --- Email/Password ---
                    EmailStyledButton(title: "Sign in with Email") {
                        showEmailSignIn = true
                    }
                }

                // Divider with "or"
                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.gray.opacity(0.3))
                    Text("or")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.gray.opacity(0.3))
                }
                .padding(.horizontal)

                Text("By continuing you agree to our Terms and Privacy Policy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)

                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .navigationTitle("Sign in")
        }
        .sheet(isPresented: $showEmailSignIn) {
            EmailSignInView()
                .environmentObject(session)
        }
    }
}

// MARK: - EmailSignInView (Optimized)
struct EmailSignInView: View {
    @EnvironmentObject private var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isSignUp = false
    @State private var showForgotPassword = false
    
    // Debounce timer for error clearing
    @State private var errorClearTimer: Timer?
    
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case email, password, displayName
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(isSignUp ? "Create Account" : "Sign In")
                    .font(.title2.weight(.semibold))
                
                VStack(spacing: 16) {
                    // Email field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.subheadline.weight(.medium))
                        TextField("Enter your email", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled(true) // Prevent autocorrect lag
                            .focused($focusedField, equals: .email)
                    }
                    
                    // Display name field (only for sign up)
                    if isSignUp {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name (optional)")
                                .font(.subheadline.weight(.medium))
                            TextField("Enter your name", text: $displayName)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.name)
                                .autocorrectionDisabled(true)
                                .focused($focusedField, equals: .displayName)
                        }
                    }
                    
                    // Password field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.subheadline.weight(.medium))
                        SecureField("Enter your password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(isSignUp ? .newPassword : .password)
                            .focused($focusedField, equals: .password)
                    }
                }
                
                // Error message
                if let error = session.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .animation(.easeInOut(duration: 0.2), value: error) // Smooth error transitions
                }
                
                VStack(spacing: 12) {
                    // Main action button
                    Button {
                        handleMainAction()
                    } label: {
                        HStack {
                            if session.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(isSignUp ? "Create Account" : "Sign In")
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(session.isLoading || email.isEmpty || password.isEmpty)
                    
                    // Toggle between sign in/sign up
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isSignUp.toggle()
                        }
                        clearErrorWithDelay()
                    } label: {
                        Text(isSignUp ? "Already have an account? Sign in" : "Don't have an account? Sign up")
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                    }
                    
                    // Forgot password (only show when signing in)
                    if !isSignUp {
                        Button("Forgot Password?") {
                            showForgotPassword = true
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            focusedField = nil
                        }
                    }
                }
            }
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordView()
                    .environmentObject(session)
            }
        }
        .onAppear {
            session.clearError()
        }
        // Debounced error clearing to reduce UI updates
        .onChange(of: email) { _, _ in
            clearErrorWithDelay()
        }
        .onChange(of: password) { _, _ in
            clearErrorWithDelay()
        }
        .onDisappear {
            errorClearTimer?.invalidate()
        }
    }
    
    private func clearErrorWithDelay() {
        errorClearTimer?.invalidate()
        errorClearTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            session.clearError()
        }
    }
    
    private func handleMainAction() {
        focusedField = nil
        errorClearTimer?.invalidate() // Cancel any pending error clear
        
        Task {
            do {
                if isSignUp {
                    try await session.signUpWithEmail(
                        email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: password,
                        displayName: displayName.isEmpty ? nil : displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                } else {
                    try await session.signInWithEmail(
                        email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: password
                    )
                }
                dismiss()
            } catch {
                // Error is already handled in SessionViewModel
            }
        }
    }
}

// MARK: - ForgotPasswordView
struct ForgotPasswordView: View {
    @EnvironmentObject private var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var email = ""
    @State private var showSuccess = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Reset Password")
                    .font(.title2.weight(.semibold))
                
                Text("Enter your email address and we'll send you a link to reset your password.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.subheadline.weight(.medium))
                    TextField("Enter your email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }
                
                if let error = session.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
                
                if showSuccess {
                    Text("Password reset email sent! Check your inbox.")
                        .font(.caption)
                        .foregroundColor(.green)
                        .multilineTextAlignment(.center)
                }
                
                Button {
                    handleResetPassword()
                } label: {
                    HStack {
                        if session.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text("Send Reset Email")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(session.isLoading || email.isEmpty)
                
                Spacer()
            }
            .padding(.horizontal)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            session.clearError()
            showSuccess = false
        }
        .onChange(of: email) { _, _ in
            // Debounce the error clearing
            Task { @MainActor in
                session.clearError()
                showSuccess = false
            }
        }
    }
    
    private func handleResetPassword() {
        Task {
            do {
                try await session.resetPassword(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
                showSuccess = true
            } catch {
                // Error is already handled in SessionViewModel
            }
        }
    }
}

// MARK: - EmailStyledButton
private struct EmailStyledButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            ZStack {
                // Centered label
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // Leading icon
                HStack {
                    Image(systemName: "envelope.fill")
                        .imageScale(.large)
                        .accessibilityHidden(true)
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

// MARK: - GoogleStyledButton (unchanged)
private struct GoogleStyledButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            ZStack {
                // Centered label
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // Leading logo
                HStack {
                    Group {
                        Image("google_logo")
                            .resizable()
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)

                        // Fallback if you don't have an asset yet:
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
