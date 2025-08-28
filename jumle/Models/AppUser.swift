//
//  AppUser.swift
//  jumle
//
//  Created by Kai Kahar on 2025-08-19.
//

// Models/AppUser.swift
import Foundation
import FirebaseFirestore

struct AppUser: Codable, Identifiable {
    var id: String { uid }            // uid
    let uid: String
    var email: String?
    var displayName: String?
    var photoURL: String?
    var provider: String      // "google", "apple", or "email"
    var createdAt: Date
    var updatedAt: Date

    init(uid: String, email: String?, displayName: String?, photoURL: String?, provider: String) {
        self.uid = uid
        self.email = email
        self.displayName = displayName
        self.photoURL = photoURL
        self.provider = provider
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }

    static var collection: String { "users" }
    
    // Convenience computed properties
    var isEmailProvider: Bool {
        return provider == "email"
    }
    
    var providerDisplayName: String {
        switch provider {
        case "google":
            return "Google"
        case "apple":
            return "Apple"
        case "email":
            return "Email"
        default:
            return "Unknown"
        }
    }
}
