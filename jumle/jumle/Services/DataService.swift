//
//  DataService.swift
//  jumle
//
//  Created by Kai Kahar on 2025-08-07.
//
// File: Services/DataService.swift
import Foundation

enum DataService {
    static func fetchSentences(from url: URL) async throws -> [Sentence] {
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([Sentence].self, from: data)
    }

    static func fetchSentences(from urlString: String) async throws -> [Sentence] {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        return try await fetchSentences(from: url)
    }
}
