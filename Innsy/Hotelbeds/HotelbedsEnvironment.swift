//
//  HotelbedsEnvironment.swift
//  Innsy
//

import Foundation

struct HotelbedsEnvironment: Sendable {
    let useTestHosts: Bool

    var host: String {
        useTestHosts ? "api.test.hotelbeds.com" : "api.hotelbeds.com"
    }

    var bookingBaseURL: URL {
        URL(string: "https://\(host)")!
    }
}
