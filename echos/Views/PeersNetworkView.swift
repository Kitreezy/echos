//
//  PeersNetworkView.swift
//  echos
//
//  Created by Artem Rodionov on 13.03.2026.
//

import SwiftUI

/// Общая картина связей: кто на связи, кто рядом, с кем связь потеряна.
///
/// Было: шапка «EKKO // PEER_NETWORK» с шестерёнкой, секции «ACTIVE
/// TRANSMISSIONS» и «KNOWN FREQUENCY», карточки с цветной полосой, рамкой и
/// иконкой в квадрате, выдуманные подписи «SYNC: 100% // 12M AWAY» и залитая
/// кнопка «START NEW SCAN» во всю ширину.
///
/// Стало: три группы строк с тихими заголовками. Сами строки — те же, что
/// в списке рядом: `PeerRow`.
struct PeersNetworkView: View {

    @Bindable var viewModel: ChatViewModel

    /// Экран живёт в стеке навигации UIKit, поэтому уход с него —
    /// дело вызывающей стороны: `dismiss()` отсюда ничего не закроет.
    var onOpenChat: () -> Void = {}
    var onNewScan: () -> Void = {}

    private var activePeers: [Peer] {
        viewModel.peers.filter { $0.status == .connected }
    }

    private var knownPeers: [Peer] {
        viewModel.peers.filter { $0.status == .notConnected }
    }

    private var lostPeers: [Peer] {
        viewModel.peers.filter { $0.status == .failed }
    }

    var body: some View {
        ZStack {
            Color.surface.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                if viewModel.peers.isEmpty {
                    Spacer()
                    Text("Пока никого рядом")
                        .font(Font(Typography.caption))
                        .foregroundStyle(Color.inkMuted)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    groups
                }

                // Не `action`: Blue 072 — тёмный пантон, на почти чёрном фоне
                // он не читается. Синий ждёт места, где станет заливкой,
                // а не текстом.
                Button("Искать заново", action: onNewScan)
                .font(Font(Typography.caption))
                .foregroundStyle(Color.inkMuted)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.room)
            }
        }
        .navigationTitle("Связи")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Groups

    private var groups: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                group("на связи", peers: activePeers)
                group("рядом", peers: knownPeers)
                group("потеряны", peers: lostPeers)
            }
            .padding(.top, Space.room)
        }
    }

    @ViewBuilder
    private func group(_ title: String, peers: [Peer]) -> some View {
        if !peers.isEmpty {
            Text(title)
                .font(Font(Typography.micro))
                .tracking(Typography.narrow)
                .foregroundStyle(Color.inkMuted)
                .padding(.horizontal, Space.margin)
                .padding(.bottom, Space.tight)

            ForEach(peers) { peer in
                PeerRow(peer: peer)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard peer.status == .connected else {
                            return
                        }
                        openChat(with: peer)
                    }
            }
            .padding(.bottom, Space.room)
        }
    }

    private func openChat(with peer: Peer) {
        Task {
            await viewModel.switchToConversation(with: peer.displayName)
            onOpenChat()
        }
    }
}

#Preview {
    PeersNetworkView(viewModel: ChatViewModel())
}
