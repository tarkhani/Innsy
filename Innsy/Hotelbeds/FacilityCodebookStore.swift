//
//  FacilityCodebookStore.swift
//  Innsy
//

import Foundation

actor FacilityCodebookStore {
    static let shared = FacilityCodebookStore()

    private var facilityNamesByCode: [Int: String] = [:]
    private var didAttemptLoad = false

    private init() {}

    func preloadIfNeeded(using pipeline: HotelbedsHotelPipeline) async {
        if didAttemptLoad == false {
            await loadFromDiskIfNeeded()
        }
        guard facilityNamesByCode.isEmpty else { return }
        do {
            let fetched = try await pipeline.fetchFacilityTypes()
            guard fetched.isEmpty == false else { return }
            facilityNamesByCode = fetched
            try persistToDisk(fetched)
        } catch {
        }
    }

    func cachedFacilityNamesByCode() async -> [Int: String] {
        if didAttemptLoad == false {
            await loadFromDiskIfNeeded()
        }
        return facilityNamesByCode
    }

    private func loadFromDiskIfNeeded() async {
        didAttemptLoad = true
        let url = Self.storageURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([Int: String].self, from: data)
            facilityNamesByCode = decoded
        } catch {
        }
    }

    private func persistToDisk(_ map: [Int: String]) throws {
        let url = Self.storageURL
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(map)
        try data.write(to: url, options: .atomic)
    }

    private static var storageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("Innsy", isDirectory: true)
            .appendingPathComponent("facility-codebook.json")
    }
}
