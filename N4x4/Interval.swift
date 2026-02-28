// Interval.swift

import Foundation

enum IntervalType: Equatable {
    case warmup
    case highIntensity
    case rest
    case cooldown
}

struct Interval {
    let name: String
    let duration: TimeInterval
    let type: IntervalType
}

