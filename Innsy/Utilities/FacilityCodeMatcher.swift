//
//  FacilityCodeMatcher.swift
//  Innsy
//

import Foundation

/// Maps free-text (e.g. speech transcript) to Hotelbeds facility codes using the downloaded codebook.
enum FacilityCodeMatcher {
    /// Codes implied by the transcript; use with AND filter over `HotelOfferCard.facilityCodes`.
    static func facilityCodesMentioned(in transcript: String, namesByCode: [Int: String]) -> [Int] {
        let t = normalize(transcript)
        guard t.isEmpty == false, namesByCode.isEmpty == false else { return [] }

        var hits = Set<Int>()
        for (code, rawLabel) in namesByCode {
            let label = normalize(rawLabel)
            guard label.count >= 3 else { continue }

            if t.contains(label) {
                hits.insert(code)
                continue
            }

            let words = label.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { normalize(String($0)) }.filter { $0.count >= 4 }
            if words.count >= 2, words.allSatisfy({ t.contains($0) }) {
                hits.insert(code)
            }
        }

        for rule in Self.spokenToLabelNeedle {
            guard t.contains(rule.spoken) else { continue }
            for (code, raw) in namesByCode where normalize(raw).contains(rule.labelNeedle) {
                hits.insert(code)
            }
        }

        return Array(hits).sorted()
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX")).lowercased()
    }

    /// Spoken token (normalized) → lowercase ASCII fragment expected in a codebook label.
    private struct Rule {
        let spoken: String
        let labelNeedle: String
    }

    private static let spokenToLabelNeedle: [Rule] = [
        Rule(spoken: "pool", labelNeedle: "pool"),
        Rule(spoken: "swim", labelNeedle: "pool"),
        Rule(spoken: "gym", labelNeedle: "fitness"),
        Rule(spoken: "workout", labelNeedle: "fitness"),
        Rule(spoken: "fitness", labelNeedle: "fitness"),
        Rule(spoken: "spa", labelNeedle: "spa"),
        Rule(spoken: "wifi", labelNeedle: "wi-fi"),
        Rule(spoken: "wi-fi", labelNeedle: "wi-fi"),
        Rule(spoken: "internet", labelNeedle: "internet"),
        Rule(spoken: "parking", labelNeedle: "parking"),
        Rule(spoken: "car park", labelNeedle: "park"),
        Rule(spoken: "pet", labelNeedle: "pet"),
        Rule(spoken: "pets", labelNeedle: "pet"),
        Rule(spoken: "cat", labelNeedle: "pet"),
        Rule(spoken: "dog", labelNeedle: "pet"),
        Rule(spoken: "puppy", labelNeedle: "pet"),
        Rule(spoken: "kitty", labelNeedle: "pet"),
        Rule(spoken: "pet-friendly", labelNeedle: "pet"),
        Rule(spoken: "pet friendly", labelNeedle: "pet"),
        Rule(spoken: "animal", labelNeedle: "pet"),
        Rule(spoken: "animals", labelNeedle: "pet"),
        Rule(spoken: "breakfast", labelNeedle: "breakfast"),
        Rule(spoken: "kitchen", labelNeedle: "kitchen"),
        Rule(spoken: "restaurant", labelNeedle: "restaurant"),
    ]
}
