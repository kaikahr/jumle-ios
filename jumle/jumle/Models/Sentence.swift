// File: Models/Sentence.swift - Fixed with full Codable conformance
import Foundation

private extension String {
    /// Trim spaces/newlines. If that leaves the string empty, treat it as nil.
    var trimmedOrNil: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// ✅ Changed from Decodable to Codable (which includes both Encodable and Decodable)
struct Sentence: Identifiable, Hashable, Codable {
    let id: Int

    // Language strings straight from JSON
    let english: String?
    let french: String?
    let german: String?
    let turkish: String?
    let ukrainian: String?
    let japanese: String?
    let italian: String?
    let russian: String?
    let spanish: String?

    let level: String?
    let theme: String?
    let audioURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case English, French, German, Turkish, Ukrainian, Japanese, Italian, Russian, Spanish
        case level, theme, audioURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? Int.random(in: 1...Int.max)

        english   = try? c.decode(String.self, forKey: .English)
        french    = try? c.decode(String.self, forKey: .French)
        german    = try? c.decode(String.self, forKey: .German)
        turkish   = try? c.decode(String.self, forKey: .Turkish)
        ukrainian = try? c.decode(String.self, forKey: .Ukrainian)
        japanese  = try? c.decode(String.self, forKey: .Japanese)
        italian   = try? c.decode(String.self, forKey: .Italian)
        russian   = try? c.decode(String.self, forKey: .Russian)
        spanish   = try? c.decode(String.self, forKey: .Spanish)

        level = try? c.decode(String.self, forKey: .level)
        theme = try? c.decode(String.self, forKey: .theme)
        audioURL = try? c.decode(String.self, forKey: .audioURL)
    }

    // ✅ Added custom encoding implementation to match the decoding structure
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        
        try container.encodeIfPresent(english, forKey: .English)
        try container.encodeIfPresent(french, forKey: .French)
        try container.encodeIfPresent(german, forKey: .German)
        try container.encodeIfPresent(turkish, forKey: .Turkish)
        try container.encodeIfPresent(ukrainian, forKey: .Ukrainian)
        try container.encodeIfPresent(japanese, forKey: .Japanese)
        try container.encodeIfPresent(italian, forKey: .Italian)
        try container.encodeIfPresent(russian, forKey: .Russian)
        try container.encodeIfPresent(spanish, forKey: .Spanish)
        
        try container.encodeIfPresent(level, forKey: .level)
        try container.encodeIfPresent(theme, forKey: .theme)
        try container.encodeIfPresent(audioURL, forKey: .audioURL)
    }

    // MARK: Strict accessor — NO fallback
    func text(for lang: AppLanguage) -> String? {
        switch lang {
        case .English:   return english?.trimmedOrNil
        case .French:    return french?.trimmedOrNil
        case .German:    return german?.trimmedOrNil
        case .Turkish:   return turkish?.trimmedOrNil
        case .Ukrainian: return ukrainian?.trimmedOrNil
        case .Japanese:  return japanese?.trimmedOrNil
        case .Italian:   return italian?.trimmedOrNil
        case .Russian:   return russian?.trimmedOrNil
        case .Spanish:   return spanish?.trimmedOrNil
        }
    }

    // Topic chip(s)
    var topics: [String] {
        if let t = theme?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return [t.capitalized]
        }
        return []
    }

    // MARK: Search helpers (unchanged)
    func matches(_ query: String) -> Bool {
        let q = query.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        guard !q.isEmpty else { return true }
        let fields = [english, french, german, turkish, ukrainian, japanese, italian, russian].compactMap { $0?.lowercased() }
        if fields.contains(where: { $0.contains(q) }) { return true }
        if topics.map({ $0.lowercased() }).contains(where: { $0.contains(q) }) { return true }
        return false
    }

    func topicMatches(_ topic: String) -> Bool {
        let t = topic.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        if topics.map({ $0.lowercased() }).contains(where: { $0 == t || $0.contains(t) }) { return true }
        let fields = [english, french, german, turkish, ukrainian, japanese, italian, russian].compactMap { $0?.lowercased() }
        return fields.contains(where: { $0.contains(t) })
    }

    var topicDisplay: String { topics.joined(separator: " • ") }
}
