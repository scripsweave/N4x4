// Interval.swift

import Foundation

enum IntervalType: String, Codable, Equatable {
    case warmup
    case highIntensity
    case rest
    case cooldown
}

struct Interval: Codable, Equatable {
    let name: String
    let duration: TimeInterval
    let type: IntervalType
}

