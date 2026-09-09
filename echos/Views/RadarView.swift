//
//  RadarView.swift
//  echos
//
//  Created by Artem Rodionov on 13.03.2026.
//

import SwiftUI

struct RadarView: View {
    
    @ObservedObject var state: RadarState
    @State private var rotation: Double = 0
    @State private var ping1Scale: CGFloat = 1.0
    @State private var ping1Opacity: Double = 1.0
    @State private var ping2Scale: CGFloat = 1.0
    @State private var ping2Opacity: Double = 1.0
    @State private var ping3Scale: CGFloat = 1.0
    @State private var ping3Opacity: Double = 1.0
    @State private var ping4Scale: CGFloat = 1.0
    @State private var ping4Opacity: Double = 1.0
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.alive.opacity(0.6), lineWidth: 1)
                .frame(width: 64, height: 64)
                .scaleEffect(ping1Scale)
                .opacity(ping1Opacity)
            
            Circle()
                .stroke(Color.alive.opacity(0.4), lineWidth: 1)
                .frame(width: 128, height: 128)
                .scaleEffect(ping2Scale)
                .opacity(ping2Opacity)
            
            Circle()
                .stroke(Color.alive.opacity(0.2), lineWidth: 1)
                .frame(width: 192, height: 192)
                .scaleEffect(ping3Scale)
                .opacity(ping3Opacity)
            
            Circle()
                .stroke(Color.alive.opacity(0.1), lineWidth: 1)
                .frame(width: 256, height: 256)
                .scaleEffect(ping4Scale)
                .opacity(ping4Opacity)
            
            if state.isScanning {
                // Sector gradient
                Circle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.alive.opacity(0.5), location: 0.0),
                                .init(color: Color.alive.opacity(0.2), location: 0.15),
                                .init(color: .clear, location: 0.25)
                            ]),
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        )
                    )
                    .frame(width: 256, height: 256)
                    .rotationEffect(.degrees(rotation))
                    .blendMode(.plusLighter)
                    .onAppear {
                        withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                        startPingAnimation()
                    }
            }
            
            Circle()
                .fill(Color.alive)
                .frame(width: 12, height: 12)
                .shadow(color: Color.alive, radius: 15, x: 0, y: 0)
                .zIndex(10)
        }
        .frame(width: 256, height: 256)
    }
    
    private func startPingAnimation() {
        // Ring 1: 0s delay
        withAnimation(.easeOut(duration: 3).repeatForever(autoreverses: false)) {
            ping1Scale = 1.5
            ping1Opacity = 0
        }
        
        // Ring 2: 0.75s delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            withAnimation(.easeOut(duration: 3).repeatForever(autoreverses: false)) {
                ping2Scale = 1.5
                ping2Opacity = 0
            }
        }
        
        // Ring 3: 1.5s delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 3).repeatForever(autoreverses: false)) {
                ping3Scale = 1.5
                ping3Opacity = 0
            }
        }
        
        // Ring 4: 2.25s delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.25) {
            withAnimation(.easeOut(duration: 3).repeatForever(autoreverses: false)) {
                ping4Scale = 1.5
                ping4Opacity = 0
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
