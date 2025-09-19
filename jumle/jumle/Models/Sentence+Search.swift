//
//  Sentence+Search.swift
//  jumle
//
// File: Models/Sentence+Search.swift
import Foundation

extension Sentence {
    fileprivate func norm(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }

    var allTexts: [String] {
        [english, french, german, turkish, ukrainian, japanese, italian, russian].compactMap { $0 }
    }

    var normalizedCorpus: (texts: [String], topics: [String]) {
        (allTexts.map { norm($0) }, topics.map { norm($0) })
    }
}
