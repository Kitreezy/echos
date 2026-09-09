//
//  RadarView.swift
//  echos
//
//  Created by Artem Rodionov on 13.03.2026.
//

import SwiftUI

/// Радар без радара.
///
/// Было: четыре расходящихся кольца, вращающийся сектор с градиентом и
/// свечение вокруг точки. Стало: круг, точка и одно медленное кольцо —
/// как круг на воде. Движение осталось, потому что экран не должен быть
/// мёртвым, но оно теперь одно, и его можно не замечать.
struct RadarView: View {

    @ObservedObject var state: RadarState

    @State private var rippleScale: CGFloat = 0.2
    @State private var rippleOpacity: Double = 0

    private let diameter: CGFloat = 240

    var body: some View {
        ZStack {
            // Граница слышимости. Одна линия вместо четырёх колец.
            Circle()
                .stroke(Color.hairline, lineWidth: 1)
                .frame(width: diameter, height: diameter)

            if state.isScanning {
                Circle()
                    .stroke(Color.alive, lineWidth: 1)
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(rippleScale)
                    .opacity(rippleOpacity)
            }

            // Ты. Без свечения — точка и есть точка.
            Circle()
                .fill(Color.ink)
                .frame(width: 5, height: 5)
        }
        .frame(width: diameter, height: diameter)
        .task(id: state.isScanning) {
            guard state.isScanning else {
                return
            }
            await breathe()
        }
    }

    /// Один круг на воде каждые четыре секунды.
    private func breathe() async {
        while !Task.isCancelled {
            rippleScale = 0.2
            rippleOpacity = 0.5

            withAnimation(.easeOut(duration: 3.2)) {
                rippleScale = 1
                rippleOpacity = 0
            }

            guard (try? await Task.sleep(for: .seconds(4))) != nil else {
                return
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.surface.ignoresSafeArea()

        let state = RadarState()
        RadarView(state: state)
            .onAppear {
                state.isScanning = true
            }
    }
}
