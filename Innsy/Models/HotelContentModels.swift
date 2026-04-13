//
//  HotelContentModels.swift
//  Innsy
//

import Foundation

struct HotelContentRoot: Decodable, Sendable {
    let hotels: [HotelContentHotel]
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case hotels
        case total
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = Self.decodeTotal(from: c)

        if c.contains(.hotels) {
            if let list = try? c.decode([HotelContentHotel].self, forKey: .hotels) {
                hotels = list
            } else if let bucket = try? c.decode(HotelsEnvelope.self, forKey: .hotels) {
                hotels = bucket.hotels ?? bucket.hotel ?? []
            } else {
                hotels = []
            }
        } else {
            hotels = []
        }
    }

    private struct HotelsEnvelope: Decodable {
        let hotels: [HotelContentHotel]?
        let hotel: [HotelContentHotel]?
    }

    private static func decodeTotal(from c: KeyedDecodingContainer<CodingKeys>) -> Int? {
        if let v = try? c.decode(Int.self, forKey: .total) { return v }
        if let s = try? c.decode(String.self, forKey: .total), let v = Int(s) { return v }
        return nil
    }
}

struct HotelFacilityTypeRoot: Decodable, Sendable {
    let facilitiesByCode: [Int: String]
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case facilities
        case total
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try? c.decode(Int.self, forKey: .total) {
            total = v
        } else if let s = try? c.decode(String.self, forKey: .total), let v = Int(s) {
            total = v
        } else {
            total = nil
        }
        let list: [HotelFacilityType]

        if let flat = try? c.decode([HotelFacilityType].self, forKey: .facilities) {
            list = flat
        } else if let envelope = try? c.decode(HotelFacilityTypeEnvelope.self, forKey: .facilities) {
            list = envelope.facility ?? envelope.facilities ?? []
        } else {
            list = []
        }

        var map: [Int: String] = [:]
        for item in list {
            guard let code = item.facilityCode, let name = item.name, name.isEmpty == false else { continue }
            map[code] = name
        }
        facilitiesByCode = map
    }

    private struct HotelFacilityTypeEnvelope: Decodable {
        let facility: [HotelFacilityType]?
        let facilities: [HotelFacilityType]?
    }
}

struct HotelFacilityType: Decodable, Sendable {
    let facilityCode: Int?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case facilityCode
        case code
        case name
        case description
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        facilityCode = HotelbedsJSONHelpers.decodeIntIfPresent(c, key: .facilityCode)
            ?? HotelbedsJSONHelpers.decodeIntIfPresent(c, key: .code)

        if let plain = try? c.decode(String.self, forKey: .name) {
            name = plain
        } else if let blob = try? c.decode(TextContentBlob.self, forKey: .name) {
            name = blob.content ?? blob.name
        } else if let plain = try? c.decode(String.self, forKey: .description) {
            name = plain
        } else if let blob = try? c.decode(TextContentBlob.self, forKey: .description) {
            name = blob.content ?? blob.name
        } else {
            name = nil
        }
    }

    private struct TextContentBlob: Decodable {
        let content: String?
        let name: String?
    }
}

struct HotelContentHotel: Decodable, Sendable, Identifiable {
    var id: Int { code }

    let code: Int
    let name: String?
    let categoryCode: String?
    let categoryGroupCode: String?
    let destinationCode: String?
    let destinationName: String?
    let countryCode: String?
    let images: [HotelImage]?
    let facilities: [HotelFacility]?
    let ranking: Int?

    enum CodingKeys: String, CodingKey {
        case code, name, categoryCode, categoryGroupCode, destinationCode, destinationName, countryCode
        case images, facilities, ranking
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try HotelbedsJSONHelpers.decodeInt(c, key: .code)
        if let s = try? c.decode(String.self, forKey: .name) {
            name = s
        } else if let blob = try? c.decode(TextContentBlob.self, forKey: .name) {
            name = blob.content
        } else {
            name = nil
        }
        categoryCode = Self.decodeLooseString(c, key: .categoryCode)
        categoryGroupCode = Self.decodeLooseString(c, key: .categoryGroupCode)
        destinationCode = Self.decodeLooseString(c, key: .destinationCode)
        if let s = try? c.decode(String.self, forKey: .destinationName) {
            destinationName = s
        } else if let blob = try? c.decode(TextContentBlob.self, forKey: .destinationName) {
            destinationName = blob.content
        } else {
            destinationName = nil
        }
        countryCode = Self.decodeLooseString(c, key: .countryCode)
        images = try c.decodeIfPresent([HotelImage].self, forKey: .images)
        facilities = (try? c.decode([HotelFacility].self, forKey: .facilities))
            ?? (try? c.decode(FacilityEnvelope.self, forKey: .facilities)).flatMap { $0.facility ?? $0.facilities }
        ranking = HotelbedsJSONHelpers.decodeIntIfPresent(c, key: .ranking)
    }

    private struct FacilityEnvelope: Decodable {
        let facility: [HotelFacility]?
        let facilities: [HotelFacility]?
    }

    /// Content API often returns translatable strings as `{ "content": "..." }`.
    private struct TextContentBlob: Decodable {
        let content: String?
    }

    struct HotelImage: Decodable, Sendable {
        let path: String?
        let imageTypeCode: String?
        let roomCode: String?
        let roomType: String?
        let characteristicCode: String?
        let order: Int?
        let visualOrder: Int?

        enum CodingKeys: String, CodingKey {
            case path
            case roomCode
            case roomType
            case characteristicCode
            case order
            case visualOrder
            case type
        }

        private struct ImageTypeContainer: Decodable {
            let code: String?
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            path = try c.decodeIfPresent(String.self, forKey: .path)
            roomCode = try c.decodeIfPresent(String.self, forKey: .roomCode)
            roomType = try c.decodeIfPresent(String.self, forKey: .roomType)
            characteristicCode = try c.decodeIfPresent(String.self, forKey: .characteristicCode)
            order = HotelbedsJSONHelpers.decodeIntIfPresent(c, key: .order)
            visualOrder = HotelbedsJSONHelpers.decodeIntIfPresent(c, key: .visualOrder)

            if let code = try? c.decodeIfPresent(String.self, forKey: .type) {
                imageTypeCode = code
            } else if let typeBlob = try? c.decodeIfPresent(ImageTypeContainer.self, forKey: .type) {
                imageTypeCode = typeBlob.code
            } else {
                imageTypeCode = nil
            }
        }
    }

    struct HotelFacility: Decodable, Sendable {
        let facilityCode: Int?
        let facilityGroupCode: Int?
        let order: Int?
        let indYesOrNo: Bool?
        let number: Int?
        let voucher: Bool?

        enum CodingKeys: String, CodingKey {
            case facilityCode
            case facilityGroupCode
            case order
            case indYesOrNo
            case number
            case voucher
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            facilityCode = HotelbedsJSONHelpers.decodeIntIfPresent(c, key: .facilityCode)
            facilityGroupCode = HotelbedsJSONHelpers.decodeIntIfPresent(c, key: .facilityGroupCode)
            order = HotelbedsJSONHelpers.decodeIntIfPresent(c, key: .order)
            indYesOrNo = HotelbedsJSONHelpers.decodeBoolIfPresent(c, key: .indYesOrNo)
            number = HotelbedsJSONHelpers.decodeIntIfPresent(c, key: .number)
            voucher = HotelbedsJSONHelpers.decodeBoolIfPresent(c, key: .voucher)
        }
    }

    /// HBX returns a relative `path`; Giata sizes: `small`, `medium` (~117px), `bigger` (~800px), `xl`, `xxl`. See https://developer.hotelbeds.com/documentation/hotels/content-api/photos-images/
    var primaryImageURL: URL? {
        galleryImageURL(displaySlot: 0)
    }

    /// Picks a photo for list UIs. `displaySlot` rotates through the gallery so multiple rate rows for the same hotel don’t all reuse one thumbnail.
    func galleryImageURL(displaySlot: Int) -> URL? {
        let list = (images ?? []).filter { ($0.path?.isEmpty == false) }
        guard list.isEmpty == false else { return nil }
        let sorted = list.sorted { a, b in
            let at = Self.imageTypeSortRank(a.imageTypeCode)
            let bt = Self.imageTypeSortRank(b.imageTypeCode)
            if at != bt { return at < bt }
            let av = a.visualOrder ?? Int.max
            let bv = b.visualOrder ?? Int.max
            if av != bv { return av < bv }
            let ao = a.order ?? 0
            let bo = b.order ?? 0
            return ao < bo
        }
        let idx = displaySlot % sorted.count
        guard let path = sorted[idx].path else { return nil }
        return Self.hotelbedsPhotoURL(relativePath: path, size: .bigger)
    }

    /// Prefer general / exterior shots for the first slots; room-only art later so cards feel less samey.
    private static func imageTypeSortRank(_ code: String?) -> Int {
        switch code?.uppercased() {
        case "GEN", "COM": return 0
        case "RES", "BAR", "TER": return 1
        case "HAB": return 3
        default: return 2
        }
    }

    enum GiataImageSize: String {
        case small = "small"
        case medium = "medium"
        case bigger = "bigger"
        case xl = "xl"
    }

    static func hotelbedsPhotoURL(relativePath: String, size: GiataImageSize = .bigger) -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        if trimmed.lowercased().hasPrefix("http") { return URL(string: trimmed) }
        let path = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        return URL(string: "https://photos.hotelbeds.com/giata/\(size.rawValue)/\(path)")
    }

    func amenityHints(facilityNamesByCode: [Int: String]) -> [String] {
        let labels = facilityLabels(facilityNamesByCode: facilityNamesByCode)
        let amenityKeywords = [
            "pool", "swim", "gym", "fitness", "spa", "sauna", "wifi", "internet",
            "parking", "breakfast", "restaurant", "bar", "pet", "air conditioning",
            "beach", "shuttle", "airport", "family", "accessible",
        ]
        let filtered = labels.filter { label in
            let low = label.lowercased()
            return amenityKeywords.contains { low.contains($0) }
        }
        return (filtered.isEmpty ? labels : filtered)
            .prefix(10)
            .map { $0 }
    }

    func facilityLabels(facilityNamesByCode: [Int: String]) -> [String] {
        facilities?.compactMap { f in
            guard let code = f.facilityCode else { return nil }
            return facilityNamesByCode[code] ?? "Facility \(code)"
        }
        .uniqued()
        .prefix(30)
        .map { $0 } ?? []
    }

    private static func decodeLooseString(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> String? {
        if let s = try? c.decode(String.self, forKey: key) { return s }
        if let i = try? c.decode(Int.self, forKey: key) { return String(i) }
        return nil
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
