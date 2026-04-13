//
//  FacilityCodeEquivalence.swift
//  Innsy
//

import Foundation

/// Hotelbeds content often lists a different but equivalent facility code than the model or user picks (e.g. 295 “Fitness” vs 308 “Fitness room”).
/// Gold/red chips use this so we do not mark a hotel as missing when it lists a sibling code for the same amenity.
enum FacilityCodeEquivalence {
    private static let groups: [[Int]] = [
        [295, 308],
        [306, 313, 362, 365, 326, 573, 385],
        [535, 536, 541],
    ]

    private static let codeToGroupIndex: [Int: Int] = {
        var m: [Int: Int] = [:]
        for (i, g) in groups.enumerated() {
            for c in g { m[c] = i }
        }
        return m
    }()

    static func hotelSatisfies(requestedCode: Int, hotelFacilityCodes: Set<Int>) -> Bool {
        if hotelFacilityCodes.contains(requestedCode) { return true }
        guard let gi = codeToGroupIndex[requestedCode] else { return false }
        for h in hotelFacilityCodes where codeToGroupIndex[h] == gi {
            return true
        }
        return false
    }
}
