//
//  HotelbedsJSONHelpers.swift
//  Innsy
//

import Foundation

enum HotelbedsJSONHelpers {
    static func decodeInt<K: CodingKey>(_ c: KeyedDecodingContainer<K>, key: K) throws -> Int {
        if let v = try? c.decode(Int.self, forKey: key) { return v }
        if let v = try? c.decode(String.self, forKey: key), let i = Int(v) { return i }
        if let v = try? c.decode(Double.self, forKey: key) { return Int(v) }
        throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Expected Int-compatible value.")
    }

    static func decodeIntIfPresent<K: CodingKey>(_ c: KeyedDecodingContainer<K>, key: K) -> Int? {
        if let v = try? c.decode(Int.self, forKey: key) { return v }
        if let v = try? c.decode(String.self, forKey: key), let i = Int(v) { return i }
        if let v = try? c.decode(Double.self, forKey: key) { return Int(v) }
        return nil
    }

    static func decodeBoolIfPresent<K: CodingKey>(_ c: KeyedDecodingContainer<K>, key: K) -> Bool? {
        if let v = try? c.decode(Bool.self, forKey: key) { return v }
        if let v = try? c.decode(String.self, forKey: key) {
            switch v.uppercased() {
            case "Y", "YES", "TRUE", "1": return true
            case "N", "NO", "FALSE", "0": return false
            default: return nil
            }
        }
        if let i = try? c.decode(Int.self, forKey: key) { return i != 0 }
        return nil
    }
}
