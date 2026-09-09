//
//  PeersListView.swift
//  echos
//
//  Created by Artem Rodionov on 24.02.2026.
//

import SwiftUI

/// Список тех, кто рядом.
///
/// Был системный `List` в стиле `.insetGrouped` с синими и красными кнопками-
/// плашками и `ContentUnavailableView` — то есть внешний вид по умолчанию,
/// не имеющий отношения к остальному приложению. Строки здесь устроены так же,
/// как на экране поиска: точка, имя, слово, волосяная линия.
struct PeersListView: View {

    @Bindable var viewModel: ChatViewModel

    var body: some View {
        ZStack {
            Color.surface.ignoresSafeArea()

            if viewModel.peers.isEmpty {
                Text("Пока никого рядом")
                    .font(Font(Typography.caption))
                    .foregroundStyle(Color.inkMuted)
            } else {
                peersList
            }
        }
        .navigationTitle("Рядом")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - List

    private var peersList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.peers) { peer in
                    PeerRow(peer: peer) {
                        disconnect(from: peer)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard peer.status == .notConnected else {
                            return
                        }
                        connect(to: peer)
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func connect(to peer: Peer) {
        Task {
            do {
                try await viewModel.multipeerService?.connectToPeer(displayName: peer.displayName)
                print("[PeersListView] Sent invite to '\(peer.displayName)'")
            } catch {
                print("[PeersListView] Failed to connect: \(error)")
            }
        }
    }

    private func disconnect(from peer: Peer) {
        if viewModel.currentConversationPeer == peer.displayName {
            viewModel.disconnectFromCurrentPeer()
        } else {
            viewModel.multipeerService?.disconnect(from: peer.displayName)
        }
        print("[PeersListView] Disconnected from '\(peer.displayName)'")
    }
}

// MARK: - Row

/// Строка собеседника. Та же анатомия, что у `PeerDiscoveryCell` в UIKit:
/// цветная точка, имя, состояние словом.
struct PeerRow: View {

    let peer: Peer
    var onDisconnect: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Space.step) {
                Circle()
                    .fill(peer.statusColor)
                    .frame(width: 5, height: 5)
                    .padding(.top, 10)

                VStack(alignment: .leading, spacing: Space.tight) {
                    Text(peer.displayName)
                        .font(Font(Typography.title))
                        .tracking(Typography.narrow)
                        .foregroundStyle(Color.ink)

                    Text(peer.statusLabel)
                        .font(Font(Typography.caption))
                        .foregroundStyle(Color.inkMuted)
                }

                Spacer(minLength: Space.step)

                // Единственное действие, и то без плашки: подключение
                // происходит нажатием на строку.
                if peer.status == .connected, let onDisconnect {
                    Button("Отключиться", action: onDisconnect)
                        .font(Font(Typography.caption))
                        .foregroundStyle(Color.inkMuted)
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.room)

            Rectangle()
                .fill(Color.hairline)
                .frame(height: 1)
                .padding(.horizontal, Space.margin)
        }
        .opacity(peer.status == .failed ? 0.4 : 1)
    }
}

#Preview {
    NavigationStack {
        PeersListView(viewModel: ChatViewModel())
    }
}
