//
//  Extensions.swift
//  N4x4
//
//  Created by Jan van Rensburg on 9/12/24.
//
// Extensions.swift

import SwiftUI

extension TimeInterval {
    func formattedTime() -> String {
        let minutes = Int(self) / 60 % 60
        let seconds = Int(self) % 60
        return String(format: "%02i:%02i", minutes, seconds)
    }
}
