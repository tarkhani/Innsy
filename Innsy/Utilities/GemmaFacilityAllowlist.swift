//
//  GemmaFacilityAllowlist.swift
//  Innsy
//

import Foundation

/// Sole source of facility codes and labels sent to Gemma (Hugging Face) for mapping user requests (`GemmaFacilityAllowlist.json` in the app target).
/// The downloaded Hotelbeds codebook is used elsewhere (validation, hotel cards), not embedded in model prompts.
enum GemmaFacilityAllowlist {
    private struct Entry: Codable {
        let code: Int
        let name: String
    }

    private static var cachedNamesByCode: [Int: String]?

    static func namesByCode() -> [Int: String] {
        if let cached = cachedNamesByCode { return cached }
        let loaded = loadFromBundle()
        cachedNamesByCode = loaded
        return loaded
    }

    static func allowedCodes() -> Set<Int> {
        Set(namesByCode().keys)
    }

    /// True when the bundled list has at least one entry (pipeline may restrict model + transcript codes to this set).
    static var isActive: Bool {
        namesByCode().isEmpty == false
    }

    static func promptCatalogText() -> String {
        FacilityCodebookPromptFormatter.promptCatalogText(from: namesByCode())
    }

    private static func loadFromBundle() -> [Int: String] {
        guard let url = Bundle.main.url(forResource: "GemmaFacilityAllowlist", withExtension: "json") else {
            return [:]
        }
        guard let data = try? Data(contentsOf: url) else { return [:] }
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [:] }
        var map: [Int: String] = [:]
        map.reserveCapacity(entries.count)
        for e in entries {
            map[e.code] = e.name
        }
        return map
    }
}
