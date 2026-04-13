//
//  HotelbedsAuthenticator.swift
//  Innsy
//

import CryptoKit
import Foundation

enum HotelbedsAuthenticator {
    /// Per HBX docs: `X-Signature` = SHA-256 hex digest of `apiKey + secret + unixTimestampSeconds`.
    static func signedHeaders(apiKey: String, secret: String) -> [String: String] {
        let timestamp = Int(Date().timeIntervalSince1970)
        let payload = "\(apiKey)\(secret)\(timestamp)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        let signature = digest.map { String(format: "%02x", $0) }.joined()
        return [
            "Api-key": apiKey,
            "X-Signature": signature,
            "Accept": "application/json",
            "Accept-Encoding": "gzip",
            "Content-Type": "application/json",
        ]
    }
}
