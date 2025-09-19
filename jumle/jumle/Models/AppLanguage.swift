//
//  AppLanguage.swift
//  jumle
//
//  Created by Kai Kahar on 2025-08-07.
//
// File: Models/AppLanguage.swift - Verified with correct audio mappings
import Foundation

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case English, French, German, Turkish, Ukrainian, Japanese, Italian, Russian, Spanish

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .English:   return "English"
        case .French:    return "French"
        case .German:    return "German"
        case .Turkish:   return "Turkish"
        case .Ukrainian: return "Ukrainian"
        case .Japanese:  return "Japanese"
        case .Italian:   return "Italian"
        case .Russian:   return "Russian"
        case .Spanish:  return "Spanish"
        }
    }
}

extension AppLanguage {
    /// Audio folder name based on your screenshot
    var audioFolder: String {
        switch self {
        case .English:   return "audio_en"
        case .French:    return "audio_fr"
        case .German:    return "audio_de"
        case .Turkish:   return "audio_tr"
        case .Ukrainian: return "audio_uk"
        case .Japanese:  return "audio_jp"
        case .Italian:   return "audio_it"
        case .Russian:   return "audio_ru"
        case .Spanish:  return "audio_es"
        }
    }

    /// File name prefix before "-<id>.mp3"
    var audioPrefix: String {
        switch self {
        case .English:   return "English"
        case .French:    return "French"
        case .German:    return "German"
        case .Turkish:   return "Turkish"
        case .Ukrainian: return "Ukrainian"
        case .Japanese:  return "Japanese"
        case .Italian:   return "Italian"
        case .Russian:   return "Russian"
        case .Spanish:  return "Spanish"
        }
    }
}
