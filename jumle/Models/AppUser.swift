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
    var provider: String      // "google" or "apple"
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
}
