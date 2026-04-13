//
//  HotelbedsHotelPipeline.swift
//  Innsy
//

import Foundation

/// Orchestrates Content API → Availability → CheckRate → Booking per [Booking API workflow](https://developer.hotelbeds.com/documentation/hotels/booking-api/workflow/).
struct HotelbedsHotelPipeline: Sendable {
    let client: HotelbedsAPIClient

    struct RoomImageMap: Sendable {
        var byRoomCode: [String: [URL]]
        var byRoomName: [String: [URL]]
    }

    /// Fetch static hotel cards for a destination. Uses `hotel-content-api` (avoid high-frequency calls in production; HBX recommends batch/cache).
    func fetchHotelContent(
        destinationCode: String,
        countryCode: String?,
        limit: Int = 40
    ) async throws -> [HotelContentHotel] {
        let dest = destinationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        for attempt in Self.hotelContentQueryAttempts(destinationCode: dest, countryCode: countryCode, limit: limit) {
            let data = try await client.get(
                path: "hotel-content-api/1.0/hotels",
                queryItems: attempt
            )
            let decoded = try JSONDecoder.hotelbeds.decode(HotelContentRoot.self, from: data)
            let list = decoded.hotels
            if list.isEmpty == false { return list }
        }
        return []
    }

    /// Hotel Content `GET .../hotels` uses **`destinationCode`** (singular). In tests, **`destinationCodes`** is ignored and returns the global list (~238k), which made the app think there were "no" Paris hotels after filtering client-side or decoding failed.
    private static func hotelContentQueryAttempts(
        destinationCode: String,
        countryCode: String?,
        limit: Int
    ) -> [[URLQueryItem]] {
        func build(country: String?) -> [URLQueryItem] {
            var items: [URLQueryItem] = [
                URLQueryItem(name: "fields", value: "all"),
                URLQueryItem(name: "language", value: "ENG"),
                URLQueryItem(name: "destinationCode", value: destinationCode),
                URLQueryItem(name: "from", value: "1"),
                URLQueryItem(name: "to", value: "\(limit)"),
            ]
            if let country, country.isEmpty == false {
                items.append(URLQueryItem(name: "countryCode", value: country))
            }
            return items
        }

        let cc = countryCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cc, cc.isEmpty == false {
            return [build(country: cc), build(country: nil)]
        }
        return [build(country: nil)]
    }

    func fetchAvailability(
        intent: BookingIntent,
        hotelCodes: [Int]
    ) async throws -> [AvailabilityHotel] {
        let req = AvailabilityRequest(
            stay: .init(checkIn: intent.checkIn, checkOut: intent.checkOut),
            occupancies: [
                .init(rooms: intent.rooms, adults: intent.adults, children: intent.children),
            ],
            hotels: .init(hotel: hotelCodes)
        )
        let data = try await client.postJSON(path: "hotel-api/1.0/hotels", body: req)
        let decoded = try JSONDecoder.hotelbeds.decode(AvailabilityResponse.self, from: data)
        return decoded.resolvedHotels
    }

    /// Fetches facility code -> human-readable label from Content API type catalog.
    func fetchFacilityTypes() async throws -> [Int: String] {
        let pageSize = 1000
        var from = 1
        var namesByCode: [Int: String] = [:]

        for _ in 0 ..< 30 {
            let to = from + pageSize - 1
            let data = try await client.get(
                path: "hotel-content-api/1.0/types/facilities",
                queryItems: [
                    URLQueryItem(name: "language", value: "ENG"),
                    URLQueryItem(name: "from", value: "\(from)"),
                    URLQueryItem(name: "to", value: "\(to)"),
                ]
            )
            let decoded = try JSONDecoder.hotelbeds.decode(HotelFacilityTypeRoot.self, from: data)
            namesByCode.merge(decoded.facilitiesByCode) { current, _ in current }

            let fetchedCount = decoded.facilitiesByCode.count
            if fetchedCount < pageSize { break }
            if let total = decoded.total, namesByCode.count >= total { break }

            from += pageSize
        }

        return namesByCode
    }

    func recheck(rateKey: String) async throws -> String {
        let data = try await client.postJSON(
            path: "hotel-api/1.0/checkrates",
            body: CheckRatesRequest(rooms: [.init(rateKey: rateKey)])
        )
        if let newKey = Self.extractPreferredRateKey(from: data) {
            return newKey
        }
        throw HotelbedsAPIError.http(status: 422, body: "Could not parse CheckRate response for rateKey.")
    }

    func createBooking(
        rateKey: String,
        holderGiven: String,
        holderFamily: String,
        guestGiven: String,
        guestFamily: String,
        adults: Int,
        clientReference: String
    ) async throws -> BookingResponse {
        var paxes: [BookingRequest.RoomBooking.Pax] = []
        for i in 0 ..< max(adults, 1) {
            paxes.append(
                .init(
                    roomId: 1,
                    type: "AD",
                    name: i == 0 ? guestGiven : "Guest \(i + 1)",
                    surname: guestFamily
                )
            )
        }
        let body = BookingRequest(
            holder: .init(name: holderGiven, surname: holderFamily),
            rooms: [.init(rateKey: rateKey, paxes: paxes)],
            clientReference: clientReference,
            remark: "Innsy integration test booking",
            tolerance: 2.0
        )
        let data = try await client.postJSON(path: "hotel-api/1.0/bookings", body: body)
        return try JSONDecoder.hotelbeds.decode(BookingResponse.self, from: data)
    }

    /// Pulls the first BOOKABLE rateKey from a CheckRate payload, else any rateKey.
    private static func extractPreferredRateKey(from data: Data) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        if let hotelArray = root["hotel"] as? [[String: Any]] {
            for h in hotelArray {
                if let key = digRateKey(in: h, preferBookable: true) { return key }
            }
            for h in hotelArray {
                if let key = digRateKey(in: h, preferBookable: false) { return key }
            }
        }
        if let hotel = root["hotel"] as? [String: Any] {
            if let hotels = hotel["hotels"] as? [[String: Any]] {
                for h in hotels {
                    if let key = digRateKey(in: h, preferBookable: true) { return key }
                }
            }
            return digRateKey(in: hotel, preferBookable: true)
                ?? digRateKey(in: hotel, preferBookable: false)
        }
        return nil
    }

    private static func digRateKey(in dict: [String: Any], preferBookable: Bool) -> String? {
        if let roomsWithRates = extractRates(from: dict) {
            let filtered = preferBookable
                ? roomsWithRates.filter { ($0["rateType"] as? String) == "BOOKABLE" }
                : roomsWithRates
            let pool = filtered.isEmpty ? roomsWithRates : filtered
            return pool.compactMap { $0["rateKey"] as? String }.first
        }
        for (_, value) in dict {
            if let child = value as? [String: Any],
               let key = digRateKey(in: child, preferBookable: preferBookable) {
                return key
            }
            if let arr = value as? [[String: Any]] {
                for child in arr {
                    if let key = digRateKey(in: child, preferBookable: preferBookable) {
                        return key
                    }
                }
            }
        }
        return nil
    }

    private static func extractRates(from hotelDict: [String: Any]) -> [[String: Any]]? {
        guard let rooms = hotelDict["rooms"] as? [[String: Any]] else { return nil }
        var rates: [[String: Any]] = []
        for room in rooms {
            if let rs = room["rates"] as? [[String: Any]] {
                rates.append(contentsOf: rs)
            }
        }
        return rates.isEmpty ? nil : rates
    }

    /// Attempts to load room-level photos from Hotel Content details for one hotel.
    /// If provider payload shape changes, this returns empty maps gracefully.
    func fetchRoomImageMap(hotelCode: Int) async throws -> RoomImageMap {
        let data = try await client.get(
            path: "hotel-content-api/1.0/hotels/\(hotelCode)/details",
            queryItems: [
                URLQueryItem(name: "language", value: "ENG"),
            ]
        )
        return Self.extractRoomImageMap(from: data)
    }

    private static func extractRoomImageMap(from data: Data) -> RoomImageMap {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .init(byRoomCode: [:], byRoomName: [:])
        }
        var byRoomCode: [String: [URL]] = [:]
        var byRoomName: [String: [URL]] = [:]
        collectRooms(in: root, byRoomCode: &byRoomCode, byRoomName: &byRoomName)
        return .init(byRoomCode: byRoomCode, byRoomName: byRoomName)
    }

    private static func collectRooms(
        in node: Any,
        byRoomCode: inout [String: [URL]],
        byRoomName: inout [String: [URL]]
    ) {
        if let dict = node as? [String: Any] {
            if let rooms = dict["rooms"] {
                collectRooms(in: rooms, byRoomCode: &byRoomCode, byRoomName: &byRoomName)
            }
            if let room = dict["room"] {
                collectRooms(in: room, byRoomCode: &byRoomCode, byRoomName: &byRoomName)
            }

            if looksLikeRoomNode(dict) {
                let roomCode = normalizedRoomKey(Self.stringValue(dict["code"]) ?? Self.stringValue(dict["roomCode"]))
                let roomName = normalizedRoomKey(Self.stringValue(dict["name"]) ?? Self.stringValue(dict["roomName"]))
                let urls = extractImageURLs(from: dict)
                if urls.isEmpty == false {
                    if let roomCode, roomCode.isEmpty == false {
                        byRoomCode[roomCode, default: []].append(contentsOf: urls)
                    }
                    if let roomName, roomName.isEmpty == false {
                        byRoomName[roomName, default: []].append(contentsOf: urls)
                    }
                }
            }

            for (_, value) in dict {
                collectRooms(in: value, byRoomCode: &byRoomCode, byRoomName: &byRoomName)
            }
            return
        }

        if let arr = node as? [Any] {
            for value in arr {
                collectRooms(in: value, byRoomCode: &byRoomCode, byRoomName: &byRoomName)
            }
        }
    }

    private static func looksLikeRoomNode(_ dict: [String: Any]) -> Bool {
        dict["code"] != nil || dict["roomCode"] != nil || dict["name"] != nil || dict["roomName"] != nil
    }

    private static func extractImageURLs(from dict: [String: Any]) -> [URL] {
        var urls: [URL] = []
        func appendFromImageArray(_ value: Any?) {
            guard let images = value as? [[String: Any]] else { return }
            for img in images {
                if let p = stringValue(img["path"]),
                   let u = HotelContentHotel.hotelbedsPhotoURL(relativePath: p, size: .bigger) {
                    urls.append(u)
                    continue
                }
                if let p = stringValue(img["url"]), let u = URL(string: p) {
                    urls.append(u)
                }
            }
        }
        appendFromImageArray(dict["images"])
        appendFromImageArray(dict["photos"])
        appendFromImageArray(dict["media"])
        return uniqueURLs(urls)
    }

    private static func normalizedRoomKey(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let key = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return key.isEmpty ? nil : key
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var out: [URL] = []
        for u in urls {
            let key = u.absoluteString
            if seen.insert(key).inserted {
                out.append(u)
            }
        }
        return out
    }
}
