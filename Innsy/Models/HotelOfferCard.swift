//
//  HotelOfferCard.swift
//  Innsy
//

import Foundation

struct HotelOfferCard: Identifiable, Sendable {
    /// Stable row identity for SwiftUI (hotel + concrete rate).
    var id: String { "\(hotelCode)|\(rate.rateKey ?? "")" }
    let hotelCode: Int
    let name: String
    let destinationLine: String
    let categoryLabel: String?
    let fromPrice: String?
    let currency: String?
    let boardName: String?
    let imageURL: URL?
    let amenities: [String]
    let facilities: [String]
    /// Human-readable facility label by code.
    let facilityLabelByCode: [Int: String]
    /// Raw Hotelbeds `facilityCode` values (for facility matching / filters).
    let facilityCodes: [Int]
    let preferencesMatched: [String]
    /// Facility labels from structured filters (`requestedFacilityCodes`) that this hotel has, in filter order.
    let facilityFilterMatches: [String]
    /// Lowercased facility labels the user requested and this hotel has (excluded from the Amenities list; shown under Matches).
    let wantedFacilityLabelsMatchedLowercased: Set<String>
    /// Requested facility labels this hotel does not list (red chips).
    let wantedFacilityLabelsMissing: [String]
    /// Same ordered code list as search-time `requiredFacilityCodes` (model + transcript); when non-empty, Matches are driven only by codes.
    let requestedFacilityCodes: [Int]
    let rate: AvailabilityHotel.AvailabilityRate
    let availabilityHotel: AvailabilityHotel
    let contentHotel: HotelContentHotel?

    var rateType: String? { rate.rateType }
    var rateKey: String { rate.rateKey ?? "" }

    /// Gold “Matches”: catalog labels for requested facility codes this hotel has. If there were no requested codes, falls back to fuzzy `preferencesMatched`.
    var displayMatchesOrdered: [String] {
        if requestedFacilityCodes.isEmpty == false {
            return facilityFilterMatches
        }
        var seenLower = Set<String>()
        var out: [String] = []
        for label in preferencesMatched {
            let low = label.lowercased()
            guard seenLower.insert(low).inserted else { continue }
            out.append(label)
        }
        return out
    }

    /// Other facilities and amenity hints only — excludes anything already listed as a structured filter match.
    var mergedAmenitiesDisplayOrdered: [String] {
        let excluded = wantedFacilityLabelsMatchedLowercased
        var seenLower = Set<String>()
        var others: [String] = []

        for tag in facilities + amenities {
            let low = tag.lowercased()
            guard seenLower.insert(low).inserted else { continue }
            guard excluded.contains(low) == false else { continue }
            others.append(tag)
        }
        others.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return others
    }

    static func merge(
        availability: [AvailabilityHotel],
        contentByCode: [Int: HotelContentHotel],
        intent: BookingIntent,
        requestedFacilityCodes: [Int],
        facilityNamesByCode: [Int: String]
    ) -> [HotelOfferCard] {
        let minPrice = intent.minPrice
        let maxPrice = intent.maxPrice
        let currency = intent.currency?.uppercased()
        let prefs = Set(intent.preferences.map { $0.lowercased() })

        var cards: [HotelOfferCard] = []

        var imageSlotByHotelCode: [Int: Int] = [:]

        for hotel in availability {
            let allRates = hotel.rooms?.compactMap(\.rates).flatMap { $0 } ?? []
            let withKeys = allRates.filter { ($0.rateKey ?? "").isEmpty == false }
            let sortedRates = withKeys.sorted { a, b in
                func rank(_ t: String?) -> Int {
                    switch t {
                    case "BOOKABLE": return 0
                    case "RECHECK": return 1
                    default: return 2
                    }
                }
                if rank(a.rateType) != rank(b.rateType) { return rank(a.rateType) < rank(b.rateType) }
                let pa = numericPrice(from: a.sellingRate ?? a.net) ?? .greatestFiniteMagnitude
                let pb = numericPrice(from: b.sellingRate ?? b.net) ?? .greatestFiniteMagnitude
                return pa < pb
            }

            guard let rate = sortedRates.first(where: { rate in
                let price = numericPrice(from: rate.sellingRate ?? rate.net)
                if let minPrice, let price, price < minPrice { return false }
                if let maxPrice, let price, price > maxPrice { return false }
                return true
            }) else {
                continue
            }

            let content = contentByCode[hotel.code]
            var facilityLabelByCode: [Int: String] = [:]
            if let facs = content?.facilities {
                for f in facs {
                    guard let code = f.facilityCode else { continue }
                    let label = facilityNamesByCode[code] ?? "Facility \(code)"
                    if facilityLabelByCode[code] == nil {
                        facilityLabelByCode[code] = label
                    }
                }
            }
            let facilityCodeInts = content?.facilities?.compactMap(\.facilityCode) ?? []
            let facilityStrings = content?.facilityLabels(facilityNamesByCode: facilityNamesByCode) ?? []
            let amenityStrings = content?.amenityHints(facilityNamesByCode: facilityNamesByCode) ?? []
            let matched = intent.preferences.filter { p in
                let low = p.lowercased()
                return amenityStrings.joined(separator: " ").lowercased().contains(low)
                    || (content?.name ?? hotel.name ?? "").lowercased().contains(low)
            }

            let destinationLine = [
                hotel.zoneName,
                hotel.destinationName,
            ]
            .compactMap { $0 }
            .joined(separator: " · ")

            let category = hotel.categoryName ?? content?.categoryCode

            let slot = imageSlotByHotelCode[hotel.code, default: 0]
            imageSlotByHotelCode[hotel.code] = slot + 1
            let photoURL = content?.galleryImageURL(displaySlot: slot)

            let haveSet = Set(facilityCodeInts)
            let reqOrdered = requestedFacilityCodes
            let matchedLabels = reqOrdered.filter { FacilityCodeEquivalence.hotelSatisfies(requestedCode: $0, hotelFacilityCodes: haveSet) }.map { code -> String in
                facilityNamesByCode[code] ?? "Facility \(code)"
            }
            let missingLabels = reqOrdered.filter { !FacilityCodeEquivalence.hotelSatisfies(requestedCode: $0, hotelFacilityCodes: haveSet) }.map { code -> String in
                facilityNamesByCode[code] ?? "Facility \(code)"
            }
            let goldLower = Set(matchedLabels.map { $0.lowercased() })

            cards.append(
                HotelOfferCard(
                    hotelCode: hotel.code,
                    name: hotel.name ?? content?.name ?? "Hotel \(hotel.code)",
                    destinationLine: destinationLine,
                    categoryLabel: category,
                    fromPrice: rate.sellingRate ?? rate.net ?? hotel.minRate,
                    currency: hotel.currency,
                    boardName: rate.boardName,
                    imageURL: photoURL,
                    amenities: amenityStrings,
                    facilities: facilityStrings,
                    facilityLabelByCode: facilityLabelByCode,
                    facilityCodes: facilityCodeInts,
                    preferencesMatched: matched,
                    facilityFilterMatches: matchedLabels,
                    wantedFacilityLabelsMatchedLowercased: goldLower,
                    wantedFacilityLabelsMissing: missingLabels,
                    requestedFacilityCodes: reqOrdered,
                    rate: rate,
                    availabilityHotel: hotel,
                    contentHotel: content
                )
            )
        }

        if requestedFacilityCodes.isEmpty == false {
            cards.sort { a, b in
                if a.wantedFacilityLabelsMissing.count != b.wantedFacilityLabelsMissing.count {
                    return a.wantedFacilityLabelsMissing.count < b.wantedFacilityLabelsMissing.count
                }
                if prefs.isEmpty == false, a.displayMatchesOrdered.count != b.displayMatchesOrdered.count {
                    return a.displayMatchesOrdered.count > b.displayMatchesOrdered.count
                }
                return false
            }
        } else if prefs.isEmpty == false {
            cards.sort { lhs, rhs in
                lhs.displayMatchesOrdered.count > rhs.displayMatchesOrdered.count
            }
        }

        return cards
    }

    private static func numericPrice(from string: String?) -> Double? {
        guard let string else { return nil }
        let filtered = string.filter { "0123456789.".contains($0) }
        return Double(filtered)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var set = Set<Element>()
        var out: [Element] = []
        out.reserveCapacity(count)
        for e in self where set.insert(e).inserted {
            out.append(e)
        }
        return out
    }
}
