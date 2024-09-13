// Interval.swift

import Foundation

enum IntervalType {
    case warmup
    case highIntensity
    case rest
}

struct Interval {
    let name: String
    let duration: TimeInterval
    let type: IntervalType
}
