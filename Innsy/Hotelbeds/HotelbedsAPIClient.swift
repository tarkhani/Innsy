//
//  HotelbedsAPIClient.swift
//  Innsy
//

import Foundation

struct HotelbedsAPIClient: Sendable {
    let environment: HotelbedsEnvironment
    let apiKey: String
    let secret: String

    func get(path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(
            url: environment.bookingBaseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )!
        if queryItems.isEmpty == false {
            components.queryItems = queryItems
        }
        var request = URLRequest(url: components.url!)
        HotelbedsAuthenticator.signedHeaders(apiKey: apiKey, secret: secret).forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpMethod = "GET"
        HotelbedsAPIDebugLog.logRequest(
            label: "GET \(path)",
            method: "GET",
            url: request.url,
            body: nil,
            queryItems: queryItems
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        HotelbedsAPIDebugLog.logResponse(label: "GET \(path)", url: request.url, response: response, data: data)
        try throwIfNeeded(data: data, response: response)
        return data
    }

    func postJSON(path: String, body: some Encodable) async throws -> Data {
        var request = URLRequest(url: environment.bookingBaseURL.appending(path: path))
        HotelbedsAuthenticator.signedHeaders(apiKey: apiKey, secret: secret).forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpMethod = "POST"
        let bodyData = try JSONEncoder.hotelbeds.encode(body)
        request.httpBody = bodyData
        HotelbedsAPIDebugLog.logRequest(
            label: "POST \(path)",
            method: "POST",
            url: request.url,
            body: bodyData,
            queryItems: nil
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        HotelbedsAPIDebugLog.logResponse(label: "POST \(path)", url: request.url, response: response, data: data)
        try throwIfNeeded(data: data, response: response)
        return data
    }

    private func throwIfNeeded(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200 ..< 300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw HotelbedsAPIError.http(status: http.statusCode, body: body)
        }
    }
}

// MARK: - Request hooks (logging disabled — use breakpoints or OSLog if needed)

private enum HotelbedsAPIDebugLog {
    static func logRequest(
        label: String,
        method: String,
        url: URL?,
        body: Data?,
        queryItems: [URLQueryItem]?
    ) {}

    static func logResponse(label: String, url: URL?, response: URLResponse, data: Data) {}
}

enum HotelbedsAPIError: LocalizedError {
    case http(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case let .http(status, body):
            let snippet = String(body.prefix(500))
            let hint: String =
                switch status {
                case 401:
                    " Use the Hotel suite Api-key and its matching secret from https://developer.hotelbeds.com/dashboard — not the Activities or Transfers key."
                case 403:
                    " Evaluation keys allow about 50 requests per day; 403 often means quota exceeded. In the dashboard, use profile progression / certification for higher limits: https://developer.hotelbeds.com/documentation/getting-started/"
                default:
                    ""
                }
            return "Hotelbeds HTTP \(status): \(snippet)\(hint)"
        }
    }
}

extension JSONEncoder {
    static var hotelbeds: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .useDefaultKeys
        return e
    }
}

extension JSONDecoder {
    static var hotelbeds: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }
}
