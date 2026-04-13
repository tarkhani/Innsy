//
//  BookingIntent.swift
//  Innsy
//

import Foundation

/// Structured output expected from the multimodal LLM (see `BookingIntent.systemInstruction`; amenity lines come from `GemmaFacilityAllowlist.json`). The model may return `explicitAmenityCodes` and `inferredAmenityCodes`; they are merged into `facilityCodes` for search and UI.
struct BookingIntent: Decodable, Sendable {
    var destinationName: String?
    /// HBX destination code when inferable (e.g. BCN, LON, NYC, PAR).
    var hotelbedsDestinationCode: String?
    /// ISO 3166-1 alpha-2 country code when inferable (e.g. ES, GB, US, FR).
    var countryCode: String?
    var checkIn: String
    var checkOut: String
    var rooms: Int
    var adults: Int
    var children: Int
    var minPrice: Double?
    var maxPrice: Double?
    var currency: String?
    var preferences: [String]
    /// Hotelbeds facility type codes the model believes match the dream trip (used with availability/content filters).
    var facilityCodes: [Int]
    /// Plain-language summary of what the model inferred (voice, text, and image). Alias JSON key: `inferenceExplanation`.
    var gemmaInferenceExplanation: String?

    enum CodingKeys: String, CodingKey {
        case destinationName
        case hotelbedsDestinationCode
        case countryCode
        case checkIn
        case checkOut
        case rooms
        case adults
        case children
        case minPrice
        case maxPrice
        case currency
        case preferences
        case facilityCodes
        case explicitAmenityCodes
        case inferredAmenityCodes
        case gemmaInferenceExplanation
        case inferenceExplanation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        destinationName = try c.decodeIfPresent(String.self, forKey: .destinationName)
        hotelbedsDestinationCode = try c.decodeIfPresent(String.self, forKey: .hotelbedsDestinationCode)
        countryCode = try c.decodeIfPresent(String.self, forKey: .countryCode)
        checkIn = try c.decodeIfPresent(String.self, forKey: .checkIn) ?? ""
        checkOut = try c.decodeIfPresent(String.self, forKey: .checkOut) ?? ""
        rooms = Self.flexInt(c, .rooms) ?? 1
        adults = Self.flexInt(c, .adults) ?? 2
        children = Self.flexInt(c, .children) ?? 0
        let directMinPrice = Self.flexDouble(c, .minPrice)
        let aliasMinPrice = Self.decodeBudgetAliases(from: decoder, kind: .min)
        minPrice = directMinPrice ?? aliasMinPrice
        let directMaxPrice = Self.flexDouble(c, .maxPrice)
        let aliasMaxPrice = Self.decodeBudgetAliases(from: decoder, kind: .max)
        maxPrice = directMaxPrice ?? aliasMaxPrice
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        preferences = try c.decodeIfPresent([String].self, forKey: .preferences) ?? []
        facilityCodes = try Self.decodeFacilityCodeArray(c)
        let explanationPrimary = try c.decodeIfPresent(String.self, forKey: .gemmaInferenceExplanation)
        let explanationFallback = try c.decodeIfPresent(String.self, forKey: .inferenceExplanation)
        gemmaInferenceExplanation = explanationPrimary ?? explanationFallback
    }

    /// Legacy `facilityCodes` only, when the model does not send split amenity arrays.
    private static func decodeLegacyFacilityCodes(_ c: KeyedDecodingContainer<CodingKeys>) throws -> [Int] {
        if let ints = try c.decodeIfPresent([Int].self, forKey: .facilityCodes) {
            return ints
        }
        if let strs = try? c.decode([String].self, forKey: .facilityCodes) {
            return strs.compactMap { s in
                let digits = s.filter { $0.isNumber }
                return Int(digits)
            }
        }
        if let single = try? c.decode(Int.self, forKey: .facilityCodes) {
            return [single]
        }
        if let singleStr = try? c.decode(String.self, forKey: .facilityCodes),
           let v = Int(singleStr.filter { $0.isNumber }) {
            return [v]
        }
        return []
    }

    private static func decodeFlexibleIntList(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> [Int] {
        if let ints = try c.decodeIfPresent([Int].self, forKey: key) {
            return ints
        }
        if let strs = try c.decodeIfPresent([String].self, forKey: key) {
            return strs.compactMap { s in
                let digits = s.filter { $0.isNumber }
                return Int(digits)
            }
        }
        if let single = try c.decodeIfPresent(Int.self, forKey: key) {
            return [single]
        }
        if let singleStr = try c.decodeIfPresent(String.self, forKey: key),
           let v = Int(singleStr.filter { $0.isNumber }) {
            return [v]
        }
        return []
    }

    /// Prefers `explicitAmenityCodes` + `inferredAmenityCodes` when either key exists; otherwise uses `facilityCodes`.
    private static func decodeFacilityCodeArray(_ c: KeyedDecodingContainer<CodingKeys>) throws -> [Int] {
        let legacy = try decodeLegacyFacilityCodes(c)
        let hasSplitAmenities = c.contains(.explicitAmenityCodes) || c.contains(.inferredAmenityCodes)
        guard hasSplitAmenities else { return legacy }
        let explicit = try decodeFlexibleIntList(c, .explicitAmenityCodes)
        let inferred = try decodeFlexibleIntList(c, .inferredAmenityCodes)
        var seen = Set<Int>()
        var merged: [Int] = []
        for code in explicit + inferred where seen.insert(code).inserted {
            merged.append(code)
        }
        return merged.isEmpty ? legacy : merged
    }

    private static func flexInt(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        HotelbedsJSONHelpers.decodeIntIfPresent(c, key: key)
    }

    private static func flexDouble(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let v = try? c.decode(Double.self, forKey: key) { return v }
        if let v = try? c.decode(Int.self, forKey: key) { return Double(v) }
        if let s = try? c.decode(String.self, forKey: key) {
            let filtered = s.filter { "0123456789.-".contains($0) }
            return Double(filtered)
        }
        return nil
    }

    private enum BudgetAliasKeys: String, CodingKey {
        case amx
        case amin
        case min_value
        case minValue
        case minBudget
        case budgetMin
        case priceMin
        case max_value
        case maxValue
        case maxBudget
        case budgetMax
        case budget
        case budgetLimit
        case priceMax
    }

    private enum BudgetKind {
        case min
        case max
    }

    private static func decodeBudgetAliases(from decoder: Decoder, kind: BudgetKind) -> Double? {
        guard let c = try? decoder.container(keyedBy: BudgetAliasKeys.self) else { return nil }
        let keys: [BudgetAliasKeys] = switch kind {
        case .min:
            [.amin, .min_value, .minValue, .minBudget, .budgetMin, .priceMin]
        case .max:
            [.amx, .max_value, .maxValue, .maxBudget, .budgetMax, .budget, .budgetLimit, .priceMax]
        }
        for key in keys {
            if let v = decodeFlexibleDouble(c, key: key) {
                return v
            }
        }
        return nil
    }

    private static func decodeFlexibleDouble<K: CodingKey>(_ c: KeyedDecodingContainer<K>, key: K) -> Double? {
        if let v = try? c.decode(Double.self, forKey: key) { return v }
        if let v = try? c.decode(Int.self, forKey: key) { return Double(v) }
        if let s = try? c.decode(String.self, forKey: key) {
            let filtered = s.filter { "0123456789.-".contains($0) }
            return Double(filtered)
        }
        return nil
    }

    static func systemInstruction(facilityCatalogBlock: String, hasReferenceImage: Bool = false) -> String {
        let trimmedCatalog = facilityCatalogBlock.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageSection: String
        if hasReferenceImage {
            imageSection = """

            REFERENCE IMAGE: Use the photo to infer **inferredAmenityCodes** (and vibe) only when it **does not conflict** with the user’s text. Do **not** use the photo to choose **country, region, or city** when the user’s words already specify where they want to stay (e.g. “UK”, “United Kingdom”, “England”, “London”, “Britain”, “Scotland”). If the picture looks tropical but the user said UK, output UK (`countryCode` GB) and a real UK destination—never override spoken geography with the image’s apparent location.
            TEXT VS IMAGE (critical): If the **transcript or typed text contradicts** the photo—destination, budget, dates, party, or amenities (e.g. “no pool”, “budget hotel”, “I need a gym” vs a resort pool photo)—**follow the text**. Omit conflicting codes from `inferredAmenityCodes` (and do not put them in `explicitAmenityCodes` unless the user asked). When text and image align, add image-suggested catalog codes to `inferredAmenityCodes`.
            POOL / OUTDOOR: If the image shows a pool, barbecue, spa, sea view, etc., and the user does **not** rule those out, you may add matching catalog codes to `inferredAmenityCodes`.
            In `gemmaInferenceExplanation`, use **human-readable amenity names** (not numeric codes) when you describe what you chose, including both explicit and inferred amenities.
            """
        } else {
            imageSection = """

            There is **no** reference image: set `inferredAmenityCodes` to [].
            """
        }

        let catalogSection: String
        if trimmedCatalog.isEmpty {
            catalogSection = """

            No curated amenity code list is bundled for this build. Set `explicitAmenityCodes` and `inferredAmenityCodes` to [] (both). The app cannot match amenity chips without a catalog.
            """
        } else {
            catalogSection = """

            AMENITY CATALOG (required): The lines between CATALOG_BEGIN and CATALOG_END are the **only** amenity codes you may use. There is no other catalog—do not guess codes from memory. Each line is `<integer_code>=<description>` (ENG).
            - Put codes for what the user **said in text** in `explicitAmenityCodes` only.
            - Put codes you infer **from the reference image** in `inferredAmenityCodes` only (use [] when there is no image or nothing to infer). Never put image-only guesses in `explicitAmenityCodes`.
            - Output **only** integers that appear in that list. Never invent codes. If nothing matches, use [] for that array.
            PETS: Phrases like **pet-friendly**, **bring my cat/dog**, **traveling with a pet**, **animals**, or **pets allowed** → add **all** applicable catalog lines whose descriptions mention **pet** or **pets** to `explicitAmenityCodes`.
            GYM / FITNESS: Words like **gym**, **workout**, **fitness**, **exercise room** → map to catalog lines for **Fitness** / **Fitness room** in `explicitAmenityCodes` when applicable; if the user says they do **not** want a gym, omit those codes even if the image shows a gym.
            UI MATCHING: For each hotel, **gold “Matches”** = a requested code the hotel lists; **red “not available”** = a requested code the hotel lacks. Put **every** amenity the user (or App UI context) cares about into the appropriate array whenever it maps to this catalog so the UI can mark present vs missing.

            CATALOG_BEGIN
            \(trimmedCatalog)
            CATALOG_END
            """
        }

        return """
        You extract structured hotel booking parameters from a user’s “dream trip” description. Input may include typed text and optionally a reference image.

        Map the user’s request (text and image) into:
        - Destination (country, region, city)
        - Dates
        - Budget
        - Party size
        - Amenities

        Always prioritize **user text** over the **image** if there is any conflict (destination, dates, budget, party size, amenities). If they name a **country or city** (UK, United Kingdom, England, London, France, Paris, …), set `countryCode` and destination fields from their words—not from scenery in the photo. Only when the user gives **no** location clue may you infer destination from the image and context.

        AMENITIES RULES:
        You must return two types of amenities:

        1. Explicit amenities
        Amenities clearly mentioned by the user in the text → `explicitAmenityCodes`.

        2. Inferred amenities
        Amenities you infer from the reference image → `inferredAmenityCodes` (use [] if there is no image or nothing to infer).
        Example: If the image shows a pool or barbecue area, you may infer pool or barbecue **codes** in `inferredAmenityCodes` when the user did not forbid them.

        You will be provided with an amenities code list (catalog).
        - Only use amenities that exist in this list
        - Return amenity codes (not names) in the JSON arrays
        - Do not invent new amenities or codes
        \(imageSection)\(catalogSection)

        OUTPUT FORMAT (STRICT):
        Return JSON only (no markdown, no extra text).

        Required keys:

        destinationName (string)
        City or main resort area.
        If only a country is given, choose a sensible default city (e.g. UK → London).
        If nothing is given, infer from context and/or image.

        hotelbedsDestinationCode (string)
        3-letter HBX destination code (e.g. PAR, BCN, LON, NYC).
        Never use country codes here (FR, GB, etc.).

        countryCode (string)
        ISO 3166-1 alpha-2 (e.g. GB, FR, ES).
        Must match the user-stated country if provided.

        checkIn (YYYY-MM-DD)
        checkOut (YYYY-MM-DD)

        rooms (int, default 1)
        adults (int, default 2)
        children (int, default 0)

        minPrice (number or null)
        maxPrice (number or null)
        currency (3-letter ISO or null)

        explicitAmenityCodes (array of integers)
        Amenity codes explicitly requested by the user in text.

        inferredAmenityCodes (array of integers)
        Amenity codes inferred from the image ([] when no image).

        gemmaInferenceExplanation (string, REQUIRED)
        2–5 sentences explaining:
        - How the destination was chosen (especially if inferred)
        - How dates were interpreted
        - Party size assumptions
        - Budget extraction
        - How the image influenced inferred amenities (if any)
        - Why amenities were selected (explicit vs inferred)
        In this field use the **names** of amenities (and places), not numeric codes.

        Optional compatibility: you may also include `preferences` (string array) for extra free-text hints; the app does not require it.

        If the user mentions a max budget ("under 200", "max 300 dollars"), set maxPrice.
        If the user mentions a minimum budget ("at least 150", "from 120 per night"), set minPrice.
        For compatibility, you may include `amx` for max and `amin` for min with the same numeric values as maxPrice/minPrice.

        If dates are relative (e.g. "next Friday"), use reasonable future calendar dates using the **today** date given in the user message (app-provided).

        ADDITIONAL RULES:
        - Use reasonable defaults when information is missing
        - Do not leave required fields empty if they can be inferred
        - Ensure checkOut is after checkIn
        - Ensure outputs are valid for hotel search APIs
        - Always prioritize user text over the image if there is any conflict
        """
    }
}

