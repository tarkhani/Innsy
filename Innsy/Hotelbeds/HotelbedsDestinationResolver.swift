//
//  HotelbedsDestinationResolver.swift
//  Innsy
//
//  Maps spoken cities and fixes common LLM mistakes (e.g. using ISO country FR instead of HBX PAR for Paris).
//

import Foundation

enum HotelbedsDestinationResolver {
    /// ISO 3166-1 alpha-2 codes — never use alone as `destinationCode` for Content API hotel search.
    private static let isoCountryAlpha2: Set<String> = [
        "AD", "AE", "AF", "AG", "AI", "AL", "AM", "AO", "AQ", "AR", "AS", "AT", "AU", "AW", "AX", "AZ",
        "BA", "BB", "BD", "BE", "BF", "BG", "BH", "BI", "BJ", "BL", "BM", "BN", "BO", "BQ", "BR", "BS", "BT", "BV", "BW", "BY", "BZ",
        "CA", "CC", "CD", "CF", "CG", "CH", "CI", "CK", "CL", "CM", "CN", "CO", "CR", "CU", "CV", "CW", "CX", "CY", "CZ",
        "DE", "DJ", "DK", "DM", "DO", "DZ", "EC", "EE", "EG", "EH", "ER", "ES", "ET", "FI", "FJ", "FK", "FM", "FO", "FR",
        "GA", "GB", "GD", "GE", "GF", "GG", "GH", "GI", "GL", "GM", "GN", "GP", "GQ", "GR", "GS", "GT", "GU", "GW", "GY",
        "HK", "HM", "HN", "HR", "HT", "HU", "ID", "IE", "IL", "IM", "IN", "IO", "IQ", "IR", "IS", "IT",
        "JE", "JM", "JO", "JP", "KE", "KG", "KH", "KI", "KM", "KN", "KP", "KR", "KW", "KY", "KZ",
        "LA", "LB", "LC", "LI", "LK", "LR", "LS", "LT", "LU", "LV", "LY", "MA", "MC", "MD", "ME", "MF", "MG", "MH", "MK", "ML", "MM", "MN", "MO", "MP", "MQ", "MR", "MS", "MT", "MU", "MV", "MW", "MX", "MY", "MZ",
        "NA", "NC", "NE", "NF", "NG", "NI", "NL", "NO", "NP", "NR", "NU", "NZ", "OM", "PA", "PE", "PF", "PG", "PH", "PK", "PL", "PM", "PN", "PR", "PS", "PT", "PW", "PY",
        "QA", "RE", "RO", "RS", "RU", "RW", "SA", "SB", "SC", "SD", "SE", "SG", "SH", "SI", "SJ", "SK", "SL", "SM", "SN", "SO", "SR", "SS", "ST", "SV", "SX", "SY", "SZ",
        "TC", "TD", "TF", "TG", "TH", "TJ", "TK", "TL", "TM", "TN", "TO", "TR", "TT", "TV", "TW", "TZ",
        "UA", "UG", "UM", "US", "UY", "UZ", "VA", "VC", "VE", "VG", "VI", "VN", "VU", "WF", "WS", "YE", "YT", "ZA", "ZM", "ZW",
    ]

    /// English / common tourism names → typical HBX destination codes (see Content API destinations portfolio).
    private static let cityToHBX: [String: String] = [
        "paris": "PAR",
        "lyon": "LYS",
        "nice": "NCE",
        "marseille": "MRS",
        "toulouse": "TLS",
        "bordeaux": "BOD",
        "barcelona": "BCN",
        "madrid": "MAD",
        "seville": "SVQ",
        "malaga": "AGP",
        "valencia": "VLC",
        "london": "LON",
        "manchester": "MAN",
        "edinburgh": "EDI",
        "rome": "ROM",
        "milan": "MIL",
        "venice": "VCE",
        "florence": "FLR",
        "naples": "NAP",
        "berlin": "BER",
        "munich": "MUC",
        "frankfurt": "FRA",
        "hamburg": "HAM",
        "amsterdam": "AMS",
        "brussels": "BRU",
        "vienna": "VIE",
        "zurich": "ZRH",
        "lisbon": "LIS",
        "porto": "OPO",
        "dublin": "DUB",
        "prague": "PRG",
        "warsaw": "WAW",
        "krakow": "KRK",
        "budapest": "BUD",
        "athens": "ATH",
        "istanbul": "IST",
        "dubai": "DXB",
        "new york": "NYC",
        "los angeles": "LAX",
        "miami": "MIA",
        "san francisco": "SFO",
        "chicago": "CHI",
        "boston": "BOS",
        "toronto": "YTO",
        "vancouver": "YVR",
        "sydney": "SYD",
        "melbourne": "MEL",
        "tokyo": "TYO",
        "singapore": "SIN",
        "bangkok": "BKK",
    ]

    /// Returns a 3-letter HBX destination code when possible.
    static func resolveCode(for intent: BookingIntent) -> String? {
        let country = intent.countryCode?.uppercased()
        let nameNorm = normalizeCityName(intent.destinationName ?? "")

        if let fromCity = codeFromCityName(nameNorm) { return fromCity }

        let raw = intent.hotelbedsDestinationCode?
            .uppercased()
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if raw.count == 2, isoCountryAlpha2.contains(raw) {
            return codeFromCityName(nameNorm)
        }

        if raw.count == 2, let country, raw == country {
            return codeFromCityName(nameNorm)
        }

        if raw.count == 3, raw.allSatisfy(\.isLetter), isoCountryAlpha2.contains(raw) == false {
            return raw
        }

        return codeFromCityName(nameNorm)
    }

    private static func normalizeCityName(_ s: String) -> String {
        let folded = s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let first = folded.components(separatedBy: ",").first ?? folded
        return first.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func codeFromCityName(_ nameNorm: String) -> String? {
        if nameNorm.isEmpty { return nil }
        if let c = cityToHBX[nameNorm] { return c }
        for (city, code) in cityToHBX where nameNorm.contains(city) || city.contains(nameNorm) {
            if nameNorm.count >= 3 { return code }
        }
        return nil
    }
}
