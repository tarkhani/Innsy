//
//  FacilityCodebookPromptFormatter.swift
//  Innsy
//

import Foundation

/// Turns the Hotelbeds facility type map into a single prompt block for the LLM (one code per line).
enum FacilityCodebookPromptFormatter {
    /// `code=description` per line, sorted by code. Empty if `map` is empty.
    static func promptCatalogText(from map: [Int: String]) -> String {
        guard map.isEmpty == false else { return "" }
        var lines: [String] = []
        lines.reserveCapacity(map.count)
        for code in map.keys.sorted() {
            guard let raw = map[code] else { continue }
            let name = sanitizeDescription(raw)
            lines.append("\(code)=\(name)")
        }
        return lines.joined(separator: "\n")
    }

    private static func sanitizeDescription(_ s: String) -> String {
        s
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: "")
    }
}
