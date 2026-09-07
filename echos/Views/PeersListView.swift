//
//  PeersListView.swift
//  echos
//
//  Created by Artem Rodionov on 24.02.2026.
//

import SwiftUI

struct PeersListView: View {
    
    @Bindable var viewModel: ChatViewModel
    
    var body: some View {
        Group {
            if viewModel.peers.isEmpty {
                emptyState
            } else {
                peersList
            }
        }
        .navigationTitle("Устройства рядом")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Peers List
    
    private var peersList: some View {
        List(viewModel.peers) { peer in
            HStack(spacing: 12) {
                Image(systemName: peer.statusIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(peer.statusColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(peer.displayName)
                        .font(.headline)
                    
                    Text(peer.statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if peer.status == .notConnected {
                    Button {
                        connectToPeer(peer)
                    } label: {
                        Text("Подключиться")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                } else if peer.status == .connecting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if peer.status == .connected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    
                    Button {
                        disconnectFromPeer(peer)
                    } label: {
                        Text("Отключиться")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.1))
                            .foregroundStyle(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .listStyle(.insetGrouped)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        ContentUnavailableView {
            Label("Нет устройств", systemImage: "antenna.radiowaves.left.and.right.slash")
        } description: {
            Text("Убедитесь что Bluetooth и Wi-Fi включены.\nДругие устройства с echos появятся здесь автоматически.")
        }
    }
    
    // MARK: Actions
    
    private func connectToPeer(_ peer: Peer) {
        Task {
            do {
                try await viewModel.multipeerService?.connectToPeer(displayName: peer.displayName)
                print("[PeersListView] Sent invite to '\(peer.displayName)'")
            } catch {
                print("[PeersListView] Failed to connect: \(error)")
            }
        }
    }
    
    private func disconnectFromPeer(_ peer: Peer) {
        Task {
            if viewModel.currentConversationPeer == peer.displayName {
                viewModel.disconnectFromCurrentPeer()
            } else {
                viewModel.multipeerService?.disconnect(from: peer.displayName)
            }
            print("[PeersListView] Disconnected from '\(peer.displayName)'")
        }
    }
}

#Preview {
    NavigationStack {
        PeersListView(viewModel: ChatViewModel())
    }
}
