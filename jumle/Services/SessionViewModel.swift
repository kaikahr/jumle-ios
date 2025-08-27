//
//  SessionViewModel.swift
//  jumle
//
//  Created by Kai Kahar on 2025-08-19.
//

// Services/SessionViewModel.swift
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseCore
import AuthenticationServices
import GoogleSignIn
import GoogleSignInSwift
import CryptoKit

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var currentUser: AppUser?
    @Published var isSignedIn: Bool = false
    @Published var showSignInSheet: Bool = false

    private let db = Firestore.firestore()
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?

    init() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { await self?.refreshUser(user) }
        }
    }

    deinit {
        if let h = authStateHandle { Auth.auth().removeStateDidChangeListener(h) }
    }

    // MARK: - Firestore sync
    private func upsertUser(_ authUser: User, provider: String) async throws {
        let ref = db.collection(AppUser.collection).document(authUser.uid)
        let snap = try await ref.getDocument()
        let now = Timestamp(date: Date())

        var data: [String: Any] = [
            "id": authUser.uid,
            "email": authUser.email as Any,
            "displayName": authUser.displayName as Any,
            "photoURL": authUser.photoURL?.absoluteString as Any,
            "provider": provider,
            "updatedAt": now
        ]

        if !snap.exists {
            data["createdAt"] = now
        }
        try await ref.setData(data, merge: true)
    }

    private func loadUserModel(_ authUser: User?) async {
        guard let u = authUser else {
            currentUser = nil
            isSignedIn = false
            return
        }
        let ref = db.collection(AppUser.collection).document(u.uid)
        if let snap = try? await ref.getDocument(), let dict = snap.data() {
            let user = AppUser(
                uid: dict["id"] as? String ?? u.uid,
                email: dict["email"] as? String ?? u.email,
                displayName: dict["displayName"] as? String ?? u.displayName,
                photoURL: dict["photoURL"] as? String,
                provider: dict["provider"] as? String ?? "unknown"
            )
            currentUser = user
            isSignedIn = true
        } else {
            currentUser = AppUser(
                uid: u.uid,
                email: u.email,
                displayName: u.displayName,
                photoURL: u.photoURL?.absoluteString,
                provider: "unknown"
            )
            isSignedIn = true
        }
    }

    private func refreshUser(_ user: User?) async {
        await loadUserModel(user)
    }

    // MARK: - Google Sign-In
    func signInWithGoogle(presenting: UIViewController) async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw NSError(domain: "app", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Google client ID"])
        }

        // Optional with latest SDKs; safe to keep
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        let signInResult = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<GIDSignInResult, Error>) in
            GIDSignIn.sharedInstance.signIn(withPresenting: presenting) { result, error in
                if let error { cont.resume(throwing: error) }
                else if let result { cont.resume(returning: result) }
                else {
                    cont.resume(throwing: NSError(domain: "app", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unknown Google Sign-In error"]))
                }
            }
        }

        guard let idToken = signInResult.user.idToken?.tokenString else {
            throw NSError(domain: "app", code: -3, userInfo: [NSLocalizedDescriptionKey: "Missing Google ID token"])
        }
        let accessToken = signInResult.user.accessToken.tokenString

        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
        let authResult = try await Auth.auth().signIn(with: credential)

        try await upsertUser(authResult.user, provider: "google")
        await refreshUser(authResult.user)          // ✅ fixed name
        showSignInSheet = false
    }

    // MARK: - Sign in with Apple
    func startSignInWithApple() -> ASAuthorizationAppleIDRequest {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let nonce = randomNonceString()
        currentNonce = nonce
        request.nonce = sha256(nonce)
        return request
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async throws {
        switch result {
        case .success(let auth):
            guard
                let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let tokenString = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                throw NSError(domain: "app", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid Apple credential"])
            }

            // ✅ Use AppleAuthProvider in modern FirebaseAuth
            let appleCred = OAuthProvider.appleCredential(
                withIDToken: tokenString,
                rawNonce: nonce,
                fullName: credential.fullName
            )


            let authResult = try await Auth.auth().signIn(with: appleCred)
            try await upsertUser(authResult.user, provider: "apple")
            await refreshUser(authResult.user)
            showSignInSheet = false

        case .failure(let error):
            throw error
        }
    }

    // MARK: - Helpers
    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            // no-op: leaving as non-fatal
        }
        self.currentUser = nil
        self.isSignedIn = false
    }

    /// Returns true if signed in; otherwise opens the Sign-In sheet and returns false.
    @discardableResult
    func ensureSignedIn() -> Bool {
        if isSignedIn { return true }
        showSignInSheet = true
        return false
    }

    // Nonce helpers
    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var random: UInt8 = 0
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if errorCode != errSecSuccess { fatalError("Unable to generate nonce.") }
            if random < charset.count {
                result.append(charset[Int(random)])
                remainingLength -= 1
            }
        }
        return result
    }
}
