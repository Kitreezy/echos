//
//  RadarState.swift
//  echos
//
//  Created by Artem Rodionov on 13.03.2026.
//

import SwiftUI

final class RadarState: ObservableObject {
    
    @Published var isScanning: Bool = false

    /// Сколько человек вокруг. Радар рисует их точками — это тот же счётчик,
    /// только видимый, а не прочитанный.
    @Published var nearbyCount: Int = 0
}
