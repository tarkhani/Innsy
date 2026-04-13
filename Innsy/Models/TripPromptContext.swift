//
//  TripPromptContext.swift
//  Innsy
//

import Foundation

/// Values chosen in the trip filter sheets; folded into the LLM prompt only (not shown in the chat field).
struct TripPromptContext: Sendable {
    var checkIn: Date
    var checkOut: Date
    /// Treated as adult count for the model (`adults`); rooms default in instruction text.
    var guests: Int
    var minBudget: String
    var maxBudget: String

    /// Multiline block suitable to append after `BookingIntent.systemInstruction(facilityCatalogBlock:hasReferenceImage:)`.
    func llmAppendix(timeZone: TimeZone = .current) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = timeZone
        df.dateFormat = "yyyy-MM-dd"

        var lines: [String] = []
        lines.append("Check-in (YYYY-MM-DD): \(df.string(from: checkIn))")
        lines.append("Check-out (YYYY-MM-DD): \(df.string(from: checkOut))")
        lines.append("Guests from UI: \(guests) adult(s). Assume rooms=1 and children=0 unless the user says otherwise.")
        let minT = minBudget.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxT = maxBudget.trimmingCharacters(in: .whitespacesAndNewlines)
        if minT.isEmpty == false || maxT.isEmpty == false {
            if minT.isEmpty == false, maxT.isEmpty == false {
                lines.append("Budget hints from UI: minimum \(minT), maximum \(maxT) (infer currency from speech/text if not stated).")
            } else if maxT.isEmpty == false {
                lines.append("Budget hint from UI: maximum \(maxT).")
            } else {
                lines.append("Budget hint from UI: minimum \(minT).")
            }
        }
        return lines.joined(separator: "\n")
    }
}
