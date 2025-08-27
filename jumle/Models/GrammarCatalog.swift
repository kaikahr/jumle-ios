//
//  GrammarCatalog.swift
//  jumle
//
//  Created by Kai Kahar on 2025-08-22.
//
// File: Models/GrammarCatalog.swift
import Foundation

struct GrammarCatalog {
    static let base = "https://d3bk01zimbieoh.cloudfront.net/text/grammar/"

    // Display name → filename
    static let items: [String: String] = [
        "Articles": "articles.json",
        "Comparative": "comparative.json",
        "Conditional": "conditional.json",
        "Conjunctions & Linking Words": "conjunctions_and_linking_words.json",
        "Future (going to)": "future_going_to.json",
        "Future (will)": "future_will.json",
        "Gerund/Participle (general)": "gerundparticiple_(general).json",
        "Imperative": "imperative.json",
        "Modal Verbs": "modal_verbs.json",
        "Negation": "negation.json",
        "Passive Voice": "passive_voice.json",
        "Past Perfect": "past_perfect.json",
        "Phrasal Verb": "phrasal_verb.json",
        "Politeness Formulas": "politeness_formulas.json",
        "Prepositions": "prepositions.json",
        "Present Perfect": "present_perfect.json",
        "Progressive Aspect": "progressive_aspect.json",
        "Quantifiers & Determiners": "quantifiers_and_determiners.json",
        "Question Form (WH-)": "question_form_wh-question.json",
        "Reassurance Expression": "reassurance_expression.json",
        "Relative Clause": "relative_clause.json",
        "Reported Speech": "reported_speech.json",
        "Superlative": "superlative.json",
        "Tag Question": "tag_question.json",
        "To‑infinitive (general)": "to-infinitive_(general).json",
        "Verb + Gerund": "verb_+_gerund.json",
        "Verb + To‑infinitive": "verb_+_to-infinitive.json"
    ]

    static var allDisplayNames: [String] {
        items.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func urlString(for displayName: String) -> String? {
        guard let file = items[displayName] else { return nil }
        return base + file
    }
}
