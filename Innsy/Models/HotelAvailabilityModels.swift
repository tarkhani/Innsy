//
//  HotelAvailabilityModels.swift
//  Innsy
//

import Foundation

struct AvailabilityRequest: Encodable, Sendable {
    struct Stay: Encodable, Sendable {
        let checkIn: String
        let checkOut: String
    }
    struct Occupancy: Encodable, Sendable {
        let rooms: Int
        let adults: Int
        let children: Int
    }
    struct HotelCodes: Encodable, Sendable {
        let hotel: [Int]
    }

    let stay: Stay
    let occupancies: [Occupancy]
    let hotels: HotelCodes
}

struct AvailabilityResponse: Decodable, Sendable {
    struct HotelsWrapper: Decodable, Sendable {
        let hotels: [AvailabilityHotel]?
        let hotel: [AvailabilityHotel]?

        var resolved: [AvailabilityHotel] { hotels ?? hotel ?? [] }
    }

    let hotels: HotelsWrapper?

    /// Flattened hotels from either `hotels.hotels` or `hotels.hotel`.
    var resolvedHotels: [AvailabilityHotel] {
        hotels?.resolved ?? []
    }
}

struct AvailabilityHotel: Decodable, Sendable, Identifiable {
    var id: Int { code }

    let code: Int
    let name: String?
    let categoryCode: String?
    let categoryName: String?
    let destinationCode: String?
    let destinationName: String?
    let zoneName: String?
    let minRate: String?
    let maxRate: String?
    let currency: String?
    let latitude: String?
    let longitude: String?
    let rooms: [AvailabilityRoom]?

    enum CodingKeys: String, CodingKey {
        case code, name, categoryCode, categoryName, destinationCode, destinationName, zoneName
        case minRate, maxRate, currency, latitude, longitude, rooms
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try HotelbedsJSONHelpers.decodeInt(c, key: .code)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        categoryCode = try c.decodeIfPresent(String.self, forKey: .categoryCode)
        categoryName = try c.decodeIfPresent(String.self, forKey: .categoryName)
        destinationCode = try c.decodeIfPresent(String.self, forKey: .destinationCode)
        destinationName = try c.decodeIfPresent(String.self, forKey: .destinationName)
        zoneName = try c.decodeIfPresent(String.self, forKey: .zoneName)
        minRate = try c.decodeIfPresent(String.self, forKey: .minRate)
        maxRate = try c.decodeIfPresent(String.self, forKey: .maxRate)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        latitude = try c.decodeIfPresent(String.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(String.self, forKey: .longitude)
        rooms = try? c.decode([AvailabilityRoom].self, forKey: .rooms)
    }

    struct AvailabilityRoom: Decodable, Sendable {
        let code: String?
        let name: String?
        let rates: [AvailabilityRate]?
    }

    struct AvailabilityRate: Decodable, Sendable {
        struct CancellationPolicy: Decodable, Sendable {
            let amount: String?
            let from: String?
        }

        let rateKey: String?
        let rateType: String?
        let net: String?
        let sellingRate: String?
        let boardName: String?
        let allotment: Int?
        let cancellationPolicies: [CancellationPolicy]?

        enum CodingKeys: String, CodingKey {
            case rateKey, rateType, net, sellingRate, boardName, allotment, cancellationPolicies
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            rateKey = try c.decodeIfPresent(String.self, forKey: .rateKey)
            rateType = try c.decodeIfPresent(String.self, forKey: .rateType)
            net = try c.decodeIfPresent(String.self, forKey: .net)
            sellingRate = try c.decodeIfPresent(String.self, forKey: .sellingRate)
            boardName = try c.decodeIfPresent(String.self, forKey: .boardName)
            allotment = HotelbedsJSONHelpers.decodeIntIfPresent(c, key: .allotment)
            cancellationPolicies = try c.decodeIfPresent([CancellationPolicy].self, forKey: .cancellationPolicies)
        }
    }

    func preferredRateForBooking() -> AvailabilityRate? {
        guard let rates = rooms?.compactMap(\.rates).flatMap({ $0 }) else { return nil }
        return rates.first(where: { $0.rateType == "BOOKABLE" })
            ?? rates.first(where: { $0.rateType == "RECHECK" })
            ?? rates.first
    }
}

struct CheckRatesRequest: Encodable, Sendable {
    struct Room: Encodable, Sendable {
        let rateKey: String
    }
    let rooms: [Room]
}

struct CheckRatesResponse: Decodable, Sendable {
    struct HotelWrapper: Decodable, Sendable {
        let hotels: [AvailabilityHotel]?
    }
    let hotel: HotelWrapper?
}

struct BookingRequest: Encodable, Sendable {
    struct Holder: Encodable, Sendable {
        let name: String
        let surname: String
    }
    struct RoomBooking: Encodable, Sendable {
        struct Pax: Encodable, Sendable {
            let roomId: Int
            let type: String
            let name: String
            let surname: String
        }
        let rateKey: String
        let paxes: [Pax]
    }
    let holder: Holder
    let rooms: [RoomBooking]
    let clientReference: String
    let remark: String?
    let tolerance: Double?
}

struct BookingResponse: Decodable, Sendable {
    struct BookingInner: Decodable, Sendable {
        let reference: String?
        let status: String?
    }
    let booking: BookingInner?
}
