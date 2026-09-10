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

            // Остальные. Расстояний у нас нет — ни через релей, ни у
            // Multipeer без калибровки, — поэтому точки стоят ровно по кругу,
            // а не «где-то там». Показывать вымышленное расстояние честнее
            // не показывать вовсе.
            ForEach(0..<state.nearbyCount, id: \.self) { index in
                Circle()
                    .fill(Color.other)
                    .frame(width: 5, height: 5)
                    .offset(offset(of: index))
            }
            .animation(.easeInOut(duration: 0.4), value: state.nearbyCount)

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

    /// Место точки на круге. Первая — сверху, дальше по часовой.
    private func offset(of index: Int) -> CGSize {
        let radius = diameter * 0.34
        let step = 2 * Double.pi / Double(max(state.nearbyCount, 1))
        let angle = -Double.pi / 2 + step * Double(index)

        return CGSize(width: radius * cos(angle), height: radius * sin(angle))
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
